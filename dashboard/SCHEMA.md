# Dashboard 存储 Schema

SQLite，单文件 `/var/lib/dashboard/dashboard.db`，WAL 模式。
两张表 + 一组配置文件。

## 1. PRAGMA / 启动初始化

```sql
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;        -- WAL 下足够安全
PRAGMA foreign_keys = ON;
PRAGMA busy_timeout = 5000;         -- 5s
```

Server 启动时执行 `schema.sql`（幂等，全部 `CREATE ... IF NOT EXISTS`）。

---

## 2. `messages`：所有 ingest 进来的消息

```sql
CREATE TABLE IF NOT EXISTS messages (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  source      TEXT    NOT NULL,
  kind        TEXT    NOT NULL CHECK (kind IN ('briefing','status','alert','link')),
  title       TEXT,
  body        TEXT    NOT NULL,
  severity    TEXT    CHECK (severity IN ('info','warn','error')),
  client_ts   TEXT,                                -- RFC3339, 可空
  server_ts   TEXT    NOT NULL,                    -- RFC3339, server 写入时填
  dedup_key   TEXT,
  meta_json   TEXT                                  -- 原样 JSON 字符串
);

-- Feed: 每个 source 取最新一条
CREATE INDEX IF NOT EXISTS ix_messages_source_server_ts
  ON messages (source, server_ts DESC);

-- 历史按时间倒序翻页
CREATE INDEX IF NOT EXISTS ix_messages_server_ts
  ON messages (server_ts DESC);

-- Dedup upsert：(source, dedup_key) 唯一，但 dedup_key 为空时不约束
CREATE UNIQUE INDEX IF NOT EXISTS uq_messages_source_dedup
  ON messages (source, dedup_key)
  WHERE dedup_key IS NOT NULL;
```

### Upsert 语义（Ingest 实现）

```sql
INSERT INTO messages (source, kind, title, body, severity, client_ts, server_ts, dedup_key, meta_json)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT (source, dedup_key) WHERE dedup_key IS NOT NULL
DO UPDATE SET
  kind      = excluded.kind,
  title     = excluded.title,
  body      = excluded.body,
  severity  = excluded.severity,
  client_ts = excluded.client_ts,
  server_ts = excluded.server_ts,
  meta_json = excluded.meta_json
RETURNING id, server_ts, (xmax = 0) AS inserted;  -- pseudocode
```

> SQLite 没有 `xmax`；实际实现里通过事务前后比较 `last_insert_rowid()` 或
> `changes()` 判断是 INSERT 还是 UPDATE，再返回 `deduped: bool`。

### Feed 查询

```sql
-- 每个 source 最新一条
SELECT m.*
FROM messages m
JOIN (
  SELECT source, MAX(server_ts) AS max_ts
  FROM messages
  WHERE kind IN (:kinds)         -- 缺省时省略
  GROUP BY source
) latest ON m.source = latest.source AND m.server_ts = latest.max_ts
ORDER BY m.server_ts DESC
LIMIT :limit;
```

`history_count` 旁路查询：

```sql
SELECT source, COUNT(*) AS n FROM messages GROUP BY source;
```

可在内存里组装；本量级直接两次查询即可，不必 window function。

---

## 3. `node_status`：Server 主动 ping 的结果

```sql
CREATE TABLE IF NOT EXISTS node_status (
  node            TEXT PRIMARY KEY,        -- 同 nodes.toml 里的 key
  alive           INTEGER NOT NULL,        -- 0 / 1
  last_seen       TEXT,                    -- 最后一次 ping 成功的 RFC3339
  last_check_ts   TEXT NOT NULL,           -- 最近一次尝试的时间
  ping_ms         REAL,                    -- 最近一次成功的 RTT
  consecutive_fail INTEGER NOT NULL DEFAULT 0
);
```

### 后台 ping 任务伪代码

```python
async def ping_loop():
    while True:
        for node in load_nodes_toml():
            ok, rtt = await probe(node.tailscale_name, node.method)
            now = utcnow_iso()
            if ok:
                db.execute("""
                    INSERT INTO node_status (node, alive, last_seen, last_check_ts, ping_ms, consecutive_fail)
                    VALUES (?, 1, ?, ?, ?, 0)
                    ON CONFLICT(node) DO UPDATE SET
                      alive=1, last_seen=excluded.last_seen,
                      last_check_ts=excluded.last_check_ts,
                      ping_ms=excluded.ping_ms, consecutive_fail=0
                """, (node.id, now, now, rtt))
            else:
                db.execute("""
                    INSERT INTO node_status (node, alive, last_seen, last_check_ts, ping_ms, consecutive_fail)
                    VALUES (?, 0, NULL, ?, NULL, 1)
                    ON CONFLICT(node) DO UPDATE SET
                      last_check_ts=excluded.last_check_ts,
                      consecutive_fail=consecutive_fail+1,
                      alive = CASE WHEN consecutive_fail+1 >= 2 THEN 0 ELSE alive END
                """, (node.id, now))
        await asyncio.sleep(30)
```

阈值（`>= 2` 次失败才翻为 down）避免单次抖动误报红灯。

### Nodes 端点查询

```sql
-- node_status 是判活；indicators 来自 messages 里最近一条 kind=status
SELECT n.node, n.alive, n.last_seen, n.ping_ms,
       m.meta_json AS metrics_json, m.server_ts AS metrics_ts
FROM node_status n
LEFT JOIN messages m
       ON m.source = n.node
      AND m.kind   = 'status'
      AND m.id     = (
        SELECT id FROM messages
         WHERE source = n.node AND kind = 'status'
         ORDER BY server_ts DESC LIMIT 1
      );
```

---

## 4. 保留策略

每 24h 触发一次：

```sql
-- 1) 计算每个 source 的最新 id（保护它们不被删）
WITH latest AS (
  SELECT source, MAX(id) AS keep_id FROM messages GROUP BY source
)
DELETE FROM messages
 WHERE server_ts < datetime('now', printf('-%d days', :retain_days))
   AND id NOT IN (SELECT keep_id FROM latest);

-- 2) WAL checkpoint
PRAGMA wal_checkpoint(TRUNCATE);
```

每月 1 号额外：

```sql
VACUUM;
```

`:retain_days` 由 `server.toml.retain_days` 提供，默认 90。

---

## 5. 容量估算

假设：
- 10 个 source，每个每分钟 1 条 status + 每天 5 条 briefing
- status body 平均 200 B，briefing 800 B

每天 messages 行数 ≈ 10 × (60×24 + 5) = 14,450
每天字节 ≈ 10 × (1440 × 200 + 5 × 800) ≈ 2.92 MB
90 天 ≈ 263 MB

完全在 SQLite 舒适区。如果 status 频率拉到 10s 一次，量级×6，仍 < 2 GB / 90 天，
可接受。如果未来想压缩，可以把老 `kind=status` 的 `meta_json` 里数值序列单独抽到
时序表（暂不规划）。

---

## 6. 配置文件

### 6.1 `/etc/dashboard/server.toml`

```toml
[server]
bind          = "100.64.0.1"        # tailscale0 IP；服务启动时 fail-fast 校验
port          = 8787
tls_certfile  = "/etc/dashboard/tls/cert.pem"
tls_keyfile   = "/etc/dashboard/tls/key.pem"

[storage]
db_path       = "/var/lib/dashboard/dashboard.db"
retain_days   = 90

[ingest]
body_max_bytes        = 65536
rate_limit_per_minute = 60

[read]
require_token = false              # 切到 true 时启用 X-Read-Token
read_token_hash = ""               # sha256(token), 空则禁用
```

### 6.2 `/etc/dashboard/sources.toml`

```toml
# source_id 即 X-Source-Id；token_hash = sha256(明文 token)
[sources.gcp-ai-workstation]
display_name = "GCP AI Workstation"
token_hash   = "9f86d081884c7d659a2feaa0c55ad015..."

[sources.vps-hk-01]
display_name = "Hong Kong VPS"
token_hash   = "2c26b46b68ffc68ff99b453c1d304134..."

[sources.openclaw-daily]
display_name = "OpenClaw 每日简报"
token_hash   = "..."
```

热加载：Server 收到 `SIGHUP` 时重新读取 `sources.toml` / `nodes.toml`，
**不需要重启**。

### 6.3 `/etc/dashboard/nodes.toml`

```toml
[nodes.pve-homelab]
label          = "PVE 家庭主机"
tailscale_name = "pve-homelab"
method         = "icmp"           # icmp | tcp
tcp_port       = 0                 # 仅 method=tcp 时使用

[nodes.gcp-ai-workstation]
label          = "GCP AI Workstation"
tailscale_name = "gcp-ai-workstation"
method         = "tcp"
tcp_port       = 22

[nodes.vps-hk-01]
label          = "Hong Kong VPS"
tailscale_name = "vps-hk-01"
method         = "icmp"
```

> `nodes.toml` 与 `sources.toml` 是**两份独立清单**：
> - 只想 Server 主动判活的节点，只在 `nodes.toml` 注册；
> - 想推简报 / 状态的数据源，只在 `sources.toml` 注册；
> - 两者都要的节点，在两边都登记，且建议 ID 一致。

---

## 7. 备份（暂不实现）

预留方案：每日 03:00 触发
```bash
sqlite3 /var/lib/dashboard/dashboard.db ".backup '/var/lib/dashboard/backup/$(date +%F).db'"
```
保留 7 份。等业务真有价值再加进 Server 后台 task。
