# 常用命令收纳

本文档用于收集和保存各类常用命令，方便跨平台迁移和快速查阅。

---

## OpenClaw

用于管理和监控 OpenClaw 服务的命令。

```bash
# 检验模型状态
openclaw models status --probe
```

---

## SSH 隧道

建立本地与 VPS 之间的端口转发隧道。

```bash
# 使用 ssh config 别名 (推荐)
ssh -L 18789:localhost:18789 gcp-dev

# 完整命令 (备用)
ssh -L 18789:localhost:18789 zihang@34.63.165.167

# 后台运行隧道 (-f 后台, -N 不执行命令)
ssh -fNL 18789:localhost:18789 gcp-dev

# 多端口转发
ssh -L 18789:localhost:18789 -L 8080:localhost:8080 gcp-dev
```

> **提示**: 本地 `~/.ssh/config` 中配置了 `Host gcp-dev`，可直接使用别名代替 `user@ip`

---

## 服务管理

### systemd 服务

```bash
sudo systemctl status <service>    # 查看服务状态
sudo systemctl start <service>     # 启动服务
sudo systemctl stop <service>      # 停止服务
sudo systemctl restart <service>   # 重启服务
sudo systemctl enable <service>    # 开机自启
sudo systemctl disable <service>   # 取消自启

journalctl -u <service> -f         # 查看服务日志 (实时)
journalctl -u <service> --since today  # 今日日志
```

---

## 网络诊断

```bash
curl -I https://example.com        # 获取 HTTP 响应头
curl -sS https://example.com       # 静默请求
wget --spider https://example.com  # 测试链接可达性

ping -c 4 example.com              # ping 测试
traceroute example.com             # 路由追踪
dig example.com                    # DNS 查询
nslookup example.com               # DNS 查询 (备选)

ss -tuln                           # 查看监听端口
netstat -tuln                      # 查看监听端口 (传统)
lsof -i :8080                      # 查看端口占用
```

---

## 文件与磁盘

```bash
df -h                              # 磁盘使用情况
du -sh *                           # 当前目录各文件/夹大小
du -sh .                           # 当前目录总大小
ncdu                               # 交互式磁盘分析 (需安装)

find . -name "*.log" -mtime +7 -delete  # 删除 7 天前的日志
```

---

## 进程管理

```bash
htop                               # 交互式进程管理
ps aux | grep <name>               # 搜索进程
kill <pid>                         # 终止进程
kill -9 <pid>                      # 强制终止
pkill -f <pattern>                 # 按名称终止
```

---

## Git

```bash
git log --oneline -10              # 简洁日志
git diff --stat HEAD~1             # 上次提交的改动统计
git stash                          # 暂存修改
git stash pop                      # 恢复暂存
git reset --hard HEAD~1            # 回退一次提交 (慎用)
```

---

## 快速添加新命令

在对应分类下添加新命令，或创建新分类。格式参考：

```bash
# 命令说明
command --with --options
```
