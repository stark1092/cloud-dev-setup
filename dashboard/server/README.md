# dashboard-server

已落地：S1（ingest + feed + history + health）+ S2（后台 ping、保留策略、
`/api/v1/nodes`、SIGHUP 热加载）。TLS 终结、PWA 静态托管留给 S4。

## 开发

```bash
cd dashboard/server
python3 -m venv .venv
.venv/bin/pip install -r requirements-dev.txt
.venv/bin/pytest tests/ -v
```

## 本地起服务

```bash
mkdir -p /tmp/dash && cd /tmp/dash

TOKEN=$(python3 -c 'import secrets; print(secrets.token_hex(16))')
HASH=$(printf %s "$TOKEN" | sha256sum | awk '{print $1}')

cat > server.toml <<EOF
[server]
bind = "127.0.0.1"
port = 18787
[storage]
db_path = "/tmp/dash/dashboard.db"
EOF

cat > sources.toml <<EOF
[sources.local]
display_name = "Local"
token_hash   = "$HASH"
EOF

# 起服务（venv 在 dashboard/server/.venv）
cd /path/to/dashboard/server
.venv/bin/python -m dashboard_server \
  --server-toml /tmp/dash/server.toml \
  --sources-toml /tmp/dash/sources.toml
```

另开一个 shell：

```bash
export DASHBOARD_CLIENT_ENV=/tmp/dash/client.env
cat > $DASHBOARD_CLIENT_ENV <<EOF
SOURCE_ID=local
SOURCE_TOKEN=$TOKEN
SERVER_URL=http://127.0.0.1:18787
SPOOL_PATH=/tmp/dash/spool.jsonl
EOF

../client/dashboard-push briefing --title "hello" --body "world"
curl -s http://127.0.0.1:18787/api/v1/feed | python3 -m json.tool
```

## 文件布局

```
dashboard/server/
├── README.md
├── requirements.txt
├── requirements-dev.txt
├── examples/                       # 配置样例
│   ├── server.toml
│   ├── sources.toml
│   └── nodes.toml
├── dashboard_server/
│   ├── __init__.py
│   ├── __main__.py                 # python -m dashboard_server
│   ├── app.py                      # FastAPI 工厂 + lifespan + SIGHUP
│   ├── config.py                   # TOML 加载（server / sources / nodes）
│   ├── auth.py                     # per-source token 校验
│   ├── db.py                       # SQLite 连接 + schema 初始化
│   ├── schema.sql                  # 见 ../SCHEMA.md
│   ├── models.py                   # Pydantic 模型
│   ├── ingest.py                   # POST /api/v1/ingest
│   ├── feed.py                     # GET /api/v1/feed{,/.../history}
│   ├── nodes.py                    # GET /api/v1/nodes
│   ├── liveness.py                 # 后台 ping 任务（icmp / tcp）
│   ├── retention.py                # 后台清理任务 + 月度 VACUUM
│   ├── reload.py                   # SIGHUP 触发的配置热加载
│   └── health.py                   # GET /api/v1/health
└── tests/
    ├── conftest.py
    └── test_smoke.py
```

接口契约见 [`../API.md`](../API.md)，存储 schema 见 [`../SCHEMA.md`](../SCHEMA.md)。
