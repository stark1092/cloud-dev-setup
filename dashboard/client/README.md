# dashboard-push

stdlib-only Python 3.9+ 单文件，把简报 / 状态 / 告警 POST 给 dashboard-server。
契约详见 [`../CLIENT.md`](../CLIENT.md)。

## 安装到目标节点

```bash
sudo install -m 755 dashboard-push /usr/local/bin/dashboard-push
sudo install -d -m 750 /var/lib/dashboard-client
sudo install -m 600 examples/dashboard-client.env /etc/dashboard-client.env
sudo $EDITOR /etc/dashboard-client.env       # 填 SOURCE_ID / SOURCE_TOKEN / SERVER_URL
```

## 用法

```bash
# 简报（body 可来自 stdin）
echo "12 commits, all green" | dashboard-push briefing --title "Daily build"

# 主机状态指标
dashboard-push status --body "host metrics" --collect-host \
  --dedup-key "status-$(hostname)"

# 告警，幂等 dedup
df -h / | awk 'NR==2 && $5+0>=90' | grep -q . \
  && echo "root disk 90%+" | dashboard-push alert --severity warn \
       --dedup-key "disk-root-$(date +%F)"

# Dry run（看不发请求时 payload 长啥样）
dashboard-push briefing --body "demo" --dry-run
```

## 退出码

| 0 | 投递成功（含 spool flush）|
| 2 | 投递失败，已 spool（cron 下次会再尝试 flush）|
| 3 | 配置 / 参数 / 4xx 契约错误（不 spool）|

## 测试连通

```bash
DASHBOARD_CLIENT_ENV=./examples/dashboard-client.env \
  ./dashboard-push briefing --body "smoke" --dry-run
```
