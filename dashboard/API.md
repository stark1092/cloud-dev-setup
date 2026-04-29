# Dashboard HTTP API

Base: `https://dashboard.<tailnet>.ts.net:8787`
Version prefix: `/api/v1`
Encoding: JSON UTF-8。所有时间戳 RFC3339（`2026-04-29T10:30:00Z`）。

## 1. 认证

| 端点类 | 机制 | Header |
|--------|------|--------|
| Ingest | per-source token | `X-Source-Id`, `X-Source-Token` |
| Read   | 默认无认证（tailnet 边界）；可选开启 | `X-Read-Token`（如启用） |
| Health | 无 | – |

Server 用 `hmac.compare_digest` 比对 token 哈希；任何一个字段缺失或不匹配
统一返回 `401`，不区分错误原因（避免枚举攻击，虽然在 tailnet 内意义不大，
但成本几乎为零）。

---

## 2. POST /api/v1/ingest

Client 上报一条消息。

### Request

```http
POST /api/v1/ingest HTTP/1.1
Content-Type: application/json
X-Source-Id: gcp-ai-workstation
X-Source-Token: <token>

{
  "kind": "briefing",
  "title": "Daily build summary",
  "body": "- 12 commits\n- all tests green\n- 2 new images pushed",
  "severity": "info",
  "client_ts": "2026-04-29T03:00:00Z",
  "dedup_key": "daily-build-2026-04-29",
  "meta": { "build_id": 1452, "duration_s": 187 }
}
```

字段语义详见 [DESIGN.md §1.2 R4](./DESIGN.md#r4-数据模型不清--落实成枚举)。

注意：`source` 不在 body 里，**强制从 `X-Source-Id` 取**，避免 Client
互相伪造。

### Response

成功（新插入）：
```http
HTTP/1.1 201 Created
{ "id": 18293, "server_ts": "2026-04-29T03:00:01.234Z", "deduped": false }
```

成功（dedup 命中、覆盖）：
```http
HTTP/1.1 200 OK
{ "id": 18290, "server_ts": "2026-04-29T03:00:01.234Z", "deduped": true }
```

错误：
| 状态 | 含义 |
|------|------|
| 400 | JSON 解析失败 / 必填字段缺失 / kind 非法 / body 超长 |
| 401 | source 或 token 不匹配 |
| 413 | body > 64 KiB（hard limit） |
| 429 | 单 source 速率超限（默认 60/min，可配） |
| 500 | DB 不可写 |

---

## 3. GET /api/v1/feed

返回每个 source 的最新一条消息，按 `server_ts` 倒序。前端简报区直接渲染。

### Request

```http
GET /api/v1/feed?kinds=briefing,alert HTTP/1.1
```

| Query | 默认 | 说明 |
|-------|------|------|
| `kinds` | 全部 | 逗号分隔的 kind 过滤；`status` 默认**不**返回（它走 `/nodes`）|
| `limit` | 50 | 最多返回多少 source 卡片 |

### Response

```http
HTTP/1.1 200 OK
{
  "items": [
    {
      "id": 18293,
      "source": "gcp-ai-workstation",
      "source_label": "GCP AI Workstation",
      "kind": "briefing",
      "title": "Daily build summary",
      "body": "- 12 commits\n- all tests green\n- 2 new images pushed",
      "severity": "info",
      "client_ts": "2026-04-29T03:00:00Z",
      "server_ts": "2026-04-29T03:00:01.234Z",
      "history_count": 47
    },
    ...
  ],
  "generated_at": "2026-04-29T10:31:02.001Z"
}
```

`source_label` 来自 `sources.toml` 的 `display_name`，前端用它做卡片标题。
`history_count` 让前端决定是否显示"展开历史"按钮。

---

## 4. GET /api/v1/feed/{source}/history

某个 source 的历史，瀑布流展开用。

### Request

```http
GET /api/v1/feed/gcp-ai-workstation/history?before=2026-04-29T03:00:01Z&limit=20
```

| Query | 默认 | 说明 |
|-------|------|------|
| `before` | 当前时间 | 拉取 `server_ts < before` 的记录 |
| `limit` | 20 | 单次返回上限 100 |
| `kinds` | 全部 | 同 `/feed` |

游标用 `before` 而不是 offset，避免新数据插入导致翻页错乱。

### Response

```http
HTTP/1.1 200 OK
{
  "source": "gcp-ai-workstation",
  "items": [ /* 同 /feed 的 item 形态，但去掉 history_count */ ],
  "next_before": "2026-04-28T03:00:01.500Z"   // null 表示已到末尾
}
```

---

## 5. GET /api/v1/nodes

服务器状态卡片数据。来源是 Server 后台 ping 写入的 `node_status` 表，
JOIN `nodes.toml` 静态信息，再可选 JOIN 该 source 最近一次 `kind=status`
的 `meta`（CPU / 内存 / 磁盘）。

### Request

```http
GET /api/v1/nodes HTTP/1.1
```

无 query。

### Response

```http
HTTP/1.1 200 OK
{
  "items": [
    {
      "node": "pve-homelab",
      "label": "PVE 家庭主机",
      "tailscale_name": "pve-homelab",
      "alive": true,
      "last_seen": "2026-04-29T10:30:58Z",
      "ping_ms": 1.2,
      "metrics": {
        "uptime_s": 1843200,
        "load_1": 0.42,
        "mem_used_pct": 38.1,
        "disk_root_pct": 71.4,
        "metrics_ts": "2026-04-29T10:30:00Z"
      }
    },
    {
      "node": "vps-hk-01",
      "label": "Hong Kong VPS",
      "tailscale_name": "vps-hk-01",
      "alive": false,
      "last_seen": "2026-04-29T10:24:00Z",
      "ping_ms": null,
      "metrics": null
    }
  ],
  "generated_at": "2026-04-29T10:31:02.001Z"
}
```

`alive` 由 Server ping 决定（默认连续 2 次失败 → false）。
`metrics` 来自 Client 推的 `kind=status` 消息，如果该 node 没有对应 source
（即只 ping 不推指标），则为 `null`，前端只显示判活信息。

`node` 字段和 ingest 的 `source` **可以重名也可以不重名**：
- 如果某个节点既被 ping 又自己推指标，建议两边用同一个 ID；
- 如果只 ping 不推（例如路由器），`nodes.toml` 配置一个 ID 即可，无需 source。

---

## 6. GET /api/v1/health

健康检查，无认证。

### Response

```http
HTTP/1.1 200 OK
{
  "status": "ok",
  "version": "0.1.0",
  "db_ok": true,
  "uptime_s": 7321,
  "now": "2026-04-29T10:31:02.001Z"
}
```

---

## 7. 速率与限制

| 项 | 值 | 来源 |
|----|----|------|
| body 最大 | 64 KiB | hard，超出 413 |
| ingest 单 source 速率 | 60 / 分钟 | 滑动窗口，超出 429 |
| feed limit | 50 | 默认；上限 200 |
| history limit | 20 | 默认；上限 100 |
| meta JSON 深度 | 4 层 | 防止误塞大对象 |

---

## 8. 错误响应格式

非 2xx 一律：
```json
{ "error": "<machine_code>", "detail": "<human readable>" }
```

`error` 用 snake_case，前端可据此切换文案 / 重试策略。例：
- `invalid_kind`
- `body_too_large`
- `rate_limited`
- `unknown_source`
- `bad_token`
- `db_unavailable`

---

## 9. curl 速查

```bash
# Ingest 一条简报
curl -sS -X POST https://dashboard.<tailnet>.ts.net:8787/api/v1/ingest \
  -H "Content-Type: application/json" \
  -H "X-Source-Id: gcp-ai-workstation" \
  -H "X-Source-Token: $TOKEN" \
  -d '{"kind":"briefing","body":"hello"}'

# 查最新 feed
curl -sS https://dashboard.<tailnet>.ts.net:8787/api/v1/feed | jq

# 查某 source 的历史
curl -sS "https://dashboard.<tailnet>.ts.net:8787/api/v1/feed/gcp-ai-workstation/history?limit=5" | jq

# 查节点状态
curl -sS https://dashboard.<tailnet>.ts.net:8787/api/v1/nodes | jq
```
