# VPS-ENV

服务器和虚拟化环境配置脚本集合，涵盖 GCP Ubuntu 工作站初始化、PVE 家庭实验室代理接入，以及常用运维文档。

## 目录结构

```
VPS-ENV/
├── gcp_provision.sh     # GCP Ubuntu 工作站一键配置（tmux/zsh/docker/mise 等）
├── proxy_toggle.sh      # 代理切换工具（source 后使用 proxy on/off/status）
├── pve_xray_setup.sh    # PVE 宿主机：接入 VLESS Reality 节点，生成 xray 客户端配置
├── pve_tproxy_setup.sh  # PVE 宿主机：升级为透明代理（tproxy + DNS 防泄漏）
├── PVE.md               # PVE 家庭实验室完整配置记录
├── PVE-VLESS.md         # VLESS Reality 节点接入与排障指南（适配本仓库）
├── COMMANDS.md          # 常用命令速查
├── TOOLS.md             # 工具使用教程
└── README.md            # 本文档
```

## 场景总览

| 场景 | 入口 | 说明 |
|------|------|------|
| GCP 开发工作站 | `gcp_provision.sh` | Ubuntu 24.04 一键配置 tmux / zsh / Docker / mise 等环境 |
| PVE 基础代理接入 | `pve_xray_setup.sh` | 读取 VLESS Reality 分享链接，生成 `/etc/xray/config.json` |
| PVE 透明代理 | `pve_tproxy_setup.sh` | 为 PVE 宿主机与 LXC 流量启用 tproxy + DNS 防泄漏 |
| PVE 实操记录 | `PVE.md` | 记录网络拓扑、LXC 约定、服务管理方法 |
| 节点接入指南 | `PVE-VLESS.md` | 收纳节点要求、分享链接字段、排障与补充说明 |
| 命令与工具 | `COMMANDS.md` / `TOOLS.md` | 日常运维命令与工具教程 |

## 快速开始

### GCP Ubuntu 工作站

```bash
# 1. 上传文件到 GCP 实例
scp -r ./ username@your-gcp-ip:~/setup/

# 2. SSH 连入实例
ssh username@your-gcp-ip

# 3. 运行配置脚本
cd ~/setup
chmod +x gcp_provision.sh
./gcp_provision.sh

# 4. 重新登录使配置生效
exit
ssh username@your-gcp-ip
```

GCP 脚本会安装以下常用组件：

| 类别 | 工具 |
|------|------|
| 终端 | tmux (TPM + 插件), Zsh (Oh My Zsh) |
| 搜索 | fzf, ripgrep, zoxide |
| 容器 | Docker, Docker Compose |
| 版本管理 | mise (Python/Node.js) |
| 工具 | btop, jq, tree, git, curl |

### PVE 宿主机接入 VLESS Reality 节点

```bash
# 1. 在远端服务端准备一个可用的 VLESS Reality 节点
# 2. 在 PVE 宿主机安装 xray 二进制（见 PVE-VLESS.md）

# 3. 生成基础 xray 客户端配置
bash pve_xray_setup.sh

# 4. 如需让宿主机 / LXC 全流量走代理，再执行
bash pve_tproxy_setup.sh
```

## 文档索引

- [PVE.md](./PVE.md)：PVE 家庭实验室的硬件、网络与服务布局说明
- [PVE-VLESS.md](./PVE-VLESS.md)：VLESS Reality 节点要求、接入步骤与排障建议
- [COMMANDS.md](./COMMANDS.md)：常用命令速查
- [TOOLS.md](./TOOLS.md)：工具使用教程

## 安装后验证

```bash
# GCP 工作站
tmux
docker run hello-world
proxy status
mise --version
rg --version

# PVE 基础代理（执行 pve_xray_setup.sh 后）
systemctl status xray
curl --proxy http://127.0.0.1:1081 https://www.google.com -I

# PVE 透明代理（执行 pve_tproxy_setup.sh 后）
systemctl status xray-iptables
curl -fsSL --max-time 10 https://ifconfig.me
```

## 本地 Mac SSH 配置 (可选)

在 `~/.ssh/config` 添加:

```
Host gcp-dev
    HostName <your-gcp-ip>
    User <username>
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

然后直接使用 `ssh gcp-dev` 连接。
