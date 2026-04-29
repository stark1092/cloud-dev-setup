# Dashboard 架构设计

## 0. TL;DR

推送式简报聚合 + Server 端判活 + PWA 看板，全程在 Tailscale 内。
SQLite 单文件存储，FastAPI 单进程，Alpine.js 单 HTML。

```
OpenClaw / cron ─┐
VPS 状态        ─┼─ POST /api/v1/ingest ─→ FastAPI ─┬─ SQLite
其他简报源       ─┘                                 │
                                                    ├─ 后台 ping (judge live)
                                                    └─ 后台保留策略 (purge)
                                       PWA ←── GET /api/v1/{feed,nodes}
                                       (Tailscale + tailscale cert TLS)
```

---

## 1. Review：原方案哪里好，哪里需要改

### 1.1 保留的设计

- **推送式 ingest**：Client 极简，cron 友好，节点之间互不影响 ✓
- **SQLite 单文件**：本场景写入并发极低（每分钟个位数），完全够用 ✓
- **Tailscale + API Key**：信任边界已经收缩到 tailnet，再叠 mTLS 是过度工程 ✓
- **Alpine.js 单文件 + 30s 轮询**：零构建，省心；WebSocket 在这个量级不值得 ✓
- **快捷面板视为可选**：本质上是另一种 `kind=link` 的简报，不必单独抽象 ✓

### 1.2 需要修订（按优先级）

#### R1. 认证粒度：单 API Key → 每源 Token

**问题**：一个全局 API Key 共享给所有 Client，泄漏后只能整体轮换，无法精准撤销。
节点跨主机分布、随时增删，全局 Key 既不易管理也不易审计。

**改法**：`source_id` + `source_token` 配对。Server 配置文件里维护
`{source_id: token_hash}` 字典；Client 配置里持有 `source_id` 和明文 token。
ingest 时 Header 带两者，Server 只接受匹配的组合，constant-time 比对。

**成本**：一行 dict 查找 + 一次 `hmac.compare_digest`。换来按源撤销 / 审计能力。

#### R2. Client 静默丢弃 → 一次性本地 spool

**问题**：原方案"失败静默丢弃"对状态心跳无所谓，但对 `kind=alert` 类
（例如证书快过期、磁盘满）就是事故。但完整重试队列 + 后台进程又违背"轻量"目标。

**改法**：失败时把 payload 追加到 `/var/lib/dashboard-client/spool.jsonl`，
ring file 形式，超过 N 行（默认 200）自动从头截断。每次 Client 启动时**先尝试一次**
flush spool（只一次，不循环），成功就清空。无后台进程、无定时器、无重试退避。

**成本**：约 30 行 Python，stdlib only。换来网络抖动时的零丢失。

#### R3. Server 主动采集 → 拆成"判活由 Server，指标由 Client"

**问题**：原方案说"服务器状态由 Server 主动采集"。但要采 CPU / 内存 / 磁盘，
Server 要么 SSH 进去（每节点都要装 key、开端口），要么节点上跑
`node_exporter` / `cadvisor`。结果还是"每个节点装东西"，与"加一个新数据源
只复制一个脚本"矛盾。

**改法**：分两层。
- **判活（liveness）由 Server 主动**：仅 ICMP / TCP ping 到 Tailscale 名字，
  每 30s 一次，不需要节点配合。结果写 `node_status` 表。
- **详细指标由 Client 推**：复用同一个 `client.py`，加 `kind=status`，
  cron 每分钟跑一次，把 `uptime` / `loadavg` / `df` / `free` 拼成 JSON 推上来。

这样真正满足"新增节点 = 复制一个脚本改两行配置"，且节点只需要出方向 HTTPS，
不需要被 Server 入向访问私有端口。

#### R4. 数据模型不清 → 落实成枚举

原文 "source 名称 + 类型标签 + 正文" 太松。明确成：

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `source` | str | ✓ | 稳定 ID，例如 `gcp-ai-workstation`、`vps-hk-01` |
| `kind` | enum | ✓ | `briefing` / `status` / `alert` / `link` |
| `title` | str | – | 卡片一行标题；缺省时取 body 第一行 |
| `body` | str | ✓ | 纯文本或 Markdown |
| `severity` | enum | – | `info` / `warn` / `error`，决定卡片颜色 |
| `client_ts` | RFC3339 | – | Client 时钟，缺省时 Server 填 |
| `dedup_key` | str | – | 见 R6 |
| `meta` | object | – | 任意结构化补充字段（JSON） |

详见 [API.md](./API.md) 与 [SCHEMA.md](./SCHEMA.md)。

#### R5. 时钟漂移 → client_ts + server_ts 双时间戳

Client 跑在多台机器上，时钟可能不同步。Server 同时记录 `client_ts`（Client 自报）
和 `server_ts`（Server 接收时填）。**前端排序、保留策略一律用 `server_ts`**；
`client_ts` 仅展示。

#### R6. 重复投递 → 可选 dedup_key

cron 重叠 / Client retry spool 都可能让同一逻辑事件投递两次。Ingest 增加可选
`dedup_key`：

- 若 `dedup_key` 缺省，正常 INSERT；
- 若 `dedup_key` 存在，按 `(source, dedup_key)` upsert（后到的覆盖先到的）。

例如证书检查脚本可以用 `dedup_key="cert-foo.example-2026-04-29"`，今天再跑就
覆盖而不是堆叠。

#### R7. 保留策略 → 后台清理 + 不丢"每源最新"

SQLite 不会自己变小。Server 内置一个 24h 周期任务：

1. 删除 `server_ts < now() - 90d` 的记录，**但保留每个 `source` 当前最新一条**
   （这样即使某个源静默 1 年，前端 Feed 仍能显示它最后一次说了什么）。
2. WAL checkpoint。
3. 每月 1 号执行一次 `VACUUM`。

阈值可由 env 配置：`RETAIN_DAYS`（默认 90）。

#### R8. PWA 可安装 → 走 Tailscale 证书

Service Worker 强制 HTTPS（除 localhost）。Tailscale 内网原生支持
`tailscale cert dashboard.<tailnet>.ts.net`，拿到合法 LE 证书。Server 直接用这张
证书起 HTTPS（uvicorn 自带 SSL 参数即可），不引入 Caddy / Nginx。详见
[deploy 章节](#5-部署形态)。

### 1.3 可推迟（明确不做）

- **WebSocket 推送**：30s 轮询足够，等真出现"延迟感人"再说
- **小程序 / 原生 App**：先 PWA 验证使用频率
- **多用户 / 权限**：单人使用，没必要

---

## 2. 修订后的最终架构

### 2.1 三层职责

```
┌─────────────────────────────────────────────────────────────────┐
│ Client（每个数据源一份）                                         │
│  - python3 stdlib only，单文件 ~150 行                           │
│  - 配置：/etc/dashboard-client.env (SOURCE_ID/TOKEN/SERVER_URL) │
│  - 入口：dashboard-push <kind> [--title ...] [--body-file ...]  │
│  - 失败 spool：/var/lib/dashboard-client/spool.jsonl (ring 200) │
│  - 不带后台进程，cron / OpenClaw 调度                            │
└─────────────────────────────────────────────────────────────────┘
                              │  HTTPS POST /api/v1/ingest
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ Server（PVE 上一个 Alpine LXC）                                  │
│  - FastAPI + uvicorn，监听 tailscale0 的 IP，端口 8787           │
│  - SQLite WAL，/var/lib/dashboard/dashboard.db                  │
│  - 静态托管前端 (/static)                                        │
│  - 后台 task 1：每 30s ping nodes.toml 列表，写 node_status      │
│  - 后台 task 2：每 24h 跑一次保留策略                             │
│  - 配置：/etc/dashboard/server.toml + sources.toml + nodes.toml │
└─────────────────────────────────────────────────────────────────┘
                              │  HTTPS GET /api/v1/{feed,nodes}
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ Frontend PWA                                                    │
│  - 单 index.html + manifest.webmanifest + sw.js (~30 行)        │
│  - Alpine.js + Tailwind play CDN                                │
│  - 三块布局：简报 Feed / 服务器状态 / 快捷面板                    │
│  - 30s setInterval 轮询，pull-to-refresh 手动刷新                 │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 数据流

```
1. ingest:    Client → POST /api/v1/ingest → INSERT/UPSERT messages
2. liveness:  Server background → ping nodes.toml → UPSERT node_status
3. read:      PWA → GET /api/v1/feed       → 每个 source 最新一条
              PWA → GET /api/v1/nodes      → node_status JOIN nodes.toml
              PWA → GET /api/v1/feed/{src}/history → 瀑布流展开
4. retain:    Server background → 删除过期 messages（保留每源最新）
```

### 2.3 信任边界

- **网络层**：Server 仅 bind Tailscale IP，公网无法触达。
- **传输层**：Tailscale 自带 WireGuard 加密；额外 `tailscale cert` 拿 TLS
  仅为 PWA 可安装性，不做信任根。
- **应用层**：
  - Ingest：`(source_id, source_token)` 配对，token 在 Server 配置以哈希存储。
  - Read：默认无认证（tailnet 即权限边界）；可选 `READ_TOKEN` env 启用。

---

## 3. 决策对比表

| 维度 | 原方案 | 修订后 | 原因 |
|------|--------|--------|------|
| 认证 | 单 API Key | per-source token | 撤销粒度、审计能力 |
| Client 失败处理 | 静默丢弃 | 一次性本地 spool | 告警类不可丢，但避免后台进程 |
| 服务器指标采集 | Server 主动采集（含 CPU/内存）| Server 只 ping，指标由 Client 推 | 真正不在节点装 agent |
| 类型标签 | 字符串 | 枚举 `briefing/status/alert/link` | 前端样式可预测 |
| 时间戳 | 单一 | `client_ts` + `server_ts` | 时钟漂移 |
| 去重 | 无 | 可选 `dedup_key` upsert | cron 重叠场景 |
| 保留 | 无 | 90 天 + 保留每源最新 | DB 不膨胀但不丢"最后一次发声" |
| 前端 HTTPS | 未提 | `tailscale cert` | PWA 可安装 |
| 推送通道 | HTTP | HTTP（30s 轮询）| 量级不值得 WS |

---

## 4. 配置文件总览

> 详细字段见 [SCHEMA.md §6](./SCHEMA.md#6-配置文件)

```
/etc/dashboard/
├── server.toml      # 端口、bind IP、retain days、tls cert path
├── sources.toml     # source_id → token_hash + 显示名称
└── nodes.toml       # 待 ping 的节点清单（tailscale name + 探测方式）
```

```
/etc/dashboard-client.env  # SOURCE_ID / SOURCE_TOKEN / SERVER_URL
```

---

## 5. 部署形态

- **Server LXC**：Alpine，最小化。`apk add python3 py3-pip`，venv 装 FastAPI/uvicorn/httpx。
  OpenRC 管理 `dashboard` 服务。`/var/lib/dashboard/` 持久化。
- **TLS**：在 PVE 宿主或 LXC 内执行 `tailscale cert dashboard.<tailnet>.ts.net`，
  把 cert/key 路径写到 `server.toml`，uvicorn `--ssl-certfile/--ssl-keyfile` 即可。
- **Client 安装**：scp `client.py` 到 `/usr/local/bin/dashboard-push`，
  `chmod +x`，写一个 `/etc/dashboard-client.env`，加一行 cron。完。
- **新增数据源 onboarding**：详见 [CLIENT.md §3](./CLIENT.md#3-新增数据源-onboarding)。

---

## 6. 实现路线图

按 session 切分，每个 session 都能独立 ship：

| Session | 范围 | Definition of Done |
|---------|------|-------------------|
| S1 | Server 骨架 + ingest + feed API + SQLite schema + 一个 Client | curl 推一条，curl 拉到 |
| S2 | 后台 ping + retention + sources/nodes 配置加载 | `nodes` 端点能反映节点 up/down |
| S3 | 前端 PWA（三块布局 + 历史瀑布流 + 30s 轮询）| 桌面浏览器可用 |
| S4 | TLS（tailscale cert）+ manifest + sw.js | iOS / Android 加桌面 |
| S5 | 集成进 `setup.sh dashboard` role | 一键在新 LXC 起服务 |

---

## 7. 已知风险与未决

- **iOS PWA 推送**：Apple 限制较多，目前不规划 push notification，靠 PWA 主动打开。
- **Client 时钟严重漂移**：极端情况下 `client_ts` 可能"未来"。前端展示用
  `server_ts`，`client_ts` 仅作 debug 字段。
- **SQLite 单文件备份**：每日 `sqlite3 .backup` 到一个独立路径，加进
  Server 后台 task；目前先不做，等数据真有价值再加。
