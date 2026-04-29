# Dashboard Client 契约

Client 是单文件 Python 脚本，stdlib only，无后台进程。
部署到任何能访问 Server（Tailscale 内）的节点。

## 1. 设计契约

| 维度 | 选择 |
|------|------|
| 语言 / 运行时 | Python 3.9+，stdlib only（`urllib`, `json`, `os`, `pathlib`, `argparse`, `socket`, `time`）|
| 部署位置 | `/usr/local/bin/dashboard-push`（chmod +x）|
| 配置位置 | `/etc/dashboard-client.env` |
| 持久状态 | 仅 spool 文件 `/var/lib/dashboard-client/spool.jsonl` |
| 触发方式 | cron / OpenClaw / systemd timer，**不**自带 daemon |
| 失败语义 | 网络/HTTP 失败时把 payload 追加到 spool（ring 200 行）；下次启动尝试 flush 一次 |
| 退出码 | 0 = 投递成功（含 spool flush 成功）；2 = 投递失败（已落 spool）；3 = 配置或参数错误 |

输入由命令行 + stdin 决定，**不依赖任何环境变量以外的全局状态**。
这样 cron 行最自然（`echo ... | dashboard-push briefing`）。

---

## 2. 配置文件 `/etc/dashboard-client.env`

```bash
# 必填
SOURCE_ID=gcp-ai-workstation
SOURCE_TOKEN=<plain token, 这台机器的密钥>
SERVER_URL=https://dashboard.<tailnet>.ts.net:8787

# 可选
SPOOL_PATH=/var/lib/dashboard-client/spool.jsonl
SPOOL_MAX=200
TIMEOUT_S=5
TLS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt   # 留空走系统默认
```

权限建议：`chmod 600 /etc/dashboard-client.env`，owner = root（或专属用户）。

---

## 3. 新增数据源 onboarding

5 步，全部可被脚本化：

```bash
# 在 Server 那台 LXC 上：
SOURCE_ID="vps-hk-02"
TOKEN="$(openssl rand -hex 32)"
HASH="$(printf %s "$TOKEN" | sha256sum | awk '{print $1}')"
# 将下面块追加到 /etc/dashboard/sources.toml 然后 SIGHUP server
cat >> /etc/dashboard/sources.toml <<EOF

[sources.${SOURCE_ID}]
display_name = "Hong Kong VPS #2"
token_hash   = "${HASH}"
EOF
systemctl reload dashboard   # 或 OpenRC: rc-service dashboard reload

# 把 $TOKEN 安全地传到目标节点（一次性即可），然后在目标节点上：
install -m 755 client.py /usr/local/bin/dashboard-push
install -d -m 750 /var/lib/dashboard-client
cat > /etc/dashboard-client.env <<EOF
SOURCE_ID=${SOURCE_ID}
SOURCE_TOKEN=${TOKEN}
SERVER_URL=https://dashboard.<tailnet>.ts.net:8787
EOF
chmod 600 /etc/dashboard-client.env

# 烟雾测试
echo "hello from $(hostname)" | dashboard-push briefing --title "smoke test"
```

如果不想推指标，到这里就完了。如果想让节点出现在"服务器状态"卡片：

```bash
# 在 Server LXC 上，往 /etc/dashboard/nodes.toml 也加一段（见 SCHEMA.md §6.3）
# 并加 cron 让 client 推 status：
cat > /etc/cron.d/dashboard-status <<'EOF'
* * * * * root /usr/local/bin/dashboard-push status --collect-host >/dev/null 2>&1
EOF
```

---

## 4. 命令行接口

```text
dashboard-push <kind> [options]

kind:
  briefing | status | alert | link

options:
  --title TEXT             # 卡片标题；缺省取 body 第一行
  --body TEXT              # 与 --body-file / stdin 三选一
  --body-file PATH
  --severity {info,warn,error}
  --dedup-key TEXT
  --meta JSON              # 例：--meta '{"build":42}'
  --collect-host           # status 专用：自动采集 uptime/load/mem/disk 写入 meta
  --client-ts RFC3339      # 测试用；缺省 = 当前 UTC
  --dry-run                # 打印将发送的 JSON，不发起请求

stdin: 当未给 --body / --body-file 时，从 stdin 读 body
```

### 退出码

| code | 含义 |
|------|------|
| 0 | 投递成功 |
| 2 | 投递失败，已写入 spool |
| 3 | 配置 / 参数错误（不会写 spool） |

---

## 5. Spool 行为

```
/var/lib/dashboard-client/spool.jsonl
```

每行一个 JSON 对象，等同 ingest body 但额外带 `__queued_at`：

```json
{"kind":"alert","body":"disk 95%","severity":"warn","__queued_at":"2026-04-29T10:00:00Z"}
```

**写入**：HTTP 失败（连不上 / 5xx / 超时）时 append。超过 `SPOOL_MAX` 行
（默认 200）从头截断（保留尾部最新）。

**flush**：每次进程启动时**先尝试一次**：
1. 如果 spool 不存在或为空，跳过；
2. 否则按行投递，全部成功就 truncate；
3. 任意一行失败就**整体放弃 flush**，等下次启动；不在本次进程内重试。

理由：cron 总会再触发一次，没必要在脚本里写循环；写了循环反而会卡 cron worker。

**4xx 不入 spool**：4xx 是契约错误（token 错、kind 非法、body 太大），重发没用，
直接打到 stderr 让 cron 邮件 / 日志带出。

---

## 6. 参考实现骨架（伪代码）

```python
#!/usr/bin/env python3
"""dashboard-push: minimal stdlib client for the home lab dashboard."""
import argparse, json, os, sys, ssl, socket, time, urllib.request, urllib.error
from pathlib import Path

KINDS = {"briefing", "status", "alert", "link"}
SEVERITIES = {"info", "warn", "error"}

def load_env(path="/etc/dashboard-client.env"):
    env = {}
    for line in Path(path).read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip().strip('"').strip("'")
    for k in ("SOURCE_ID", "SOURCE_TOKEN", "SERVER_URL"):
        if k not in env:
            sys.exit(f"missing {k} in {path}")
    return env

def collect_host_metrics():
    import shutil
    with open("/proc/uptime") as f:
        uptime_s = float(f.read().split()[0])
    with open("/proc/loadavg") as f:
        load_1 = float(f.read().split()[0])
    with open("/proc/meminfo") as f:
        mi = dict(line.split(":", 1) for line in f if ":" in line)
    total = int(mi["MemTotal"].strip().split()[0])
    avail = int(mi["MemAvailable"].strip().split()[0])
    mem_used_pct = round((total - avail) / total * 100, 1)
    du = shutil.disk_usage("/")
    disk_root_pct = round(du.used / du.total * 100, 1)
    return {
        "uptime_s": int(uptime_s),
        "load_1": load_1,
        "mem_used_pct": mem_used_pct,
        "disk_root_pct": disk_root_pct,
        "metrics_ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }

def post(env, payload, timeout):
    req = urllib.request.Request(
        env["SERVER_URL"].rstrip("/") + "/api/v1/ingest",
        data=json.dumps(payload).encode(),
        headers={
            "Content-Type": "application/json",
            "X-Source-Id": env["SOURCE_ID"],
            "X-Source-Token": env["SOURCE_TOKEN"],
        },
        method="POST",
    )
    ctx = ssl.create_default_context(cafile=env.get("TLS_CA_BUNDLE") or None)
    with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
        return r.status, r.read()

def append_spool(env, payload):
    spool = Path(env.get("SPOOL_PATH", "/var/lib/dashboard-client/spool.jsonl"))
    spool.parent.mkdir(parents=True, exist_ok=True)
    payload = {**payload, "__queued_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    spool.touch(exist_ok=True)
    lines = spool.read_text().splitlines() if spool.stat().st_size else []
    lines.append(json.dumps(payload, ensure_ascii=False))
    cap = int(env.get("SPOOL_MAX", 200))
    lines = lines[-cap:]
    spool.write_text("\n".join(lines) + "\n")

def flush_spool(env, timeout):
    spool = Path(env.get("SPOOL_PATH", "/var/lib/dashboard-client/spool.jsonl"))
    if not spool.exists() or spool.stat().st_size == 0:
        return
    try:
        for line in spool.read_text().splitlines():
            obj = json.loads(line)
            obj.pop("__queued_at", None)
            post(env, obj, timeout)
        spool.write_text("")  # truncate on full success
    except Exception:
        pass  # leave spool for next invocation

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("kind", choices=sorted(KINDS))
    ap.add_argument("--title")
    ap.add_argument("--body")
    ap.add_argument("--body-file")
    ap.add_argument("--severity", choices=sorted(SEVERITIES))
    ap.add_argument("--dedup-key")
    ap.add_argument("--meta")
    ap.add_argument("--collect-host", action="store_true")
    ap.add_argument("--client-ts")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    env = load_env()
    timeout = float(env.get("TIMEOUT_S", 5))

    if args.body_file:
        body = Path(args.body_file).read_text()
    elif args.body is not None:
        body = args.body
    else:
        body = sys.stdin.read()

    payload = {"kind": args.kind, "body": body}
    if args.title: payload["title"] = args.title
    if args.severity: payload["severity"] = args.severity
    if args.dedup_key: payload["dedup_key"] = args.dedup_key
    if args.client_ts: payload["client_ts"] = args.client_ts
    meta = json.loads(args.meta) if args.meta else {}
    if args.collect_host and args.kind == "status":
        meta.update(collect_host_metrics())
    if meta:
        payload["meta"] = meta

    if args.dry_run:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return 0

    flush_spool(env, timeout)

    try:
        post(env, payload, timeout)
        return 0
    except urllib.error.HTTPError as e:
        if 400 <= e.code < 500:
            sys.stderr.write(f"contract error {e.code}: {e.read().decode(errors='replace')}\n")
            return 3
        append_spool(env, payload)
        return 2
    except (urllib.error.URLError, socket.timeout, OSError):
        append_spool(env, payload)
        return 2

if __name__ == "__main__":
    sys.exit(main())
```

> 这是骨架 + 行为契约，落地实现时按此结构补齐。stdlib 限制让二进制依赖为零，
> 适配从 Alpine 到 Ubuntu 的所有目标节点。

---

## 7. 典型 cron 行

```cron
# 每分钟推一次状态指标（搭配 nodes.toml 的判活）
* * * * * root /usr/local/bin/dashboard-push status --collect-host >/dev/null 2>&1

# 每天 03:00 推 daily build summary
0 3 * * * root /opt/scripts/build_summary.sh | /usr/local/bin/dashboard-push briefing --title "Daily build" --dedup-key "daily-build-$(date +\%F)"

# 任何脚本里检测到异常时
df -h / | awk 'NR==2 && $5+0>=90 {print}' | grep -q . \
  && echo "root disk 90%+" | dashboard-push alert --severity warn --dedup-key "disk-root-$(date +\%F)"
```

---

## 8. 不做的事

- **不做**长连接 / 双向通道：客户端只 push，不接受 Server 指令
- **不做**自更新：Client 升级 = scp 覆盖 + 改 cron
- **不做**多实例多 source：一台机器一份 `/etc/dashboard-client.env`，
  对应一个 `SOURCE_ID`。如果同台机器要发不同 source，复制一份脚本到不同路径
  + 不同 env 文件即可（成本极低，没必要把多 source 烤进配置）。
