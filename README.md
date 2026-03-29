# VPS-ENV

服务器和虚拟化环境配置脚本集合，涵盖 GCP Ubuntu 工作站初始化、VPS 代理节点部署、PVE 家庭实验室代理接入，以及常用运维文档。

## 目录结构

```
VPS-ENV/
├── AGENTS.md             # Canonical agent entry for OpenCode / Claude Code
├── CLAUDE.md             # Claude Code compatibility shim (points back to AGENTS.md)
├── setup.sh              # 统一入口：按场景分发到对应安装脚本
├── gcp_provision.sh     # GCP Ubuntu 工作站一键配置（tmux/zsh/docker/mise 等）
├── proxy_toggle.sh      # 代理切换工具（source 后使用 proxy on/off/status）
├── VPS-VLESS.md         # 新 VPS 部署 VLESS Reality 服务端指南
├── vps_vless_setup.sh   # 新 VPS：自动安装 VLESS Reality 服务端并输出分享链接
├── PVE-TAILSCALE.md     # PVE 宿主机接入 Tailscale（含子网路由与后续 LXC 策略）
├── pve_tailscale_setup.sh # PVE 宿主机：安装 Tailscale 并广播 LXC 子网
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
| VPS 节点服务端部署 | `setup.sh vps-vless` | 自动安装 VLESS Reality 服务端并生成分享链接 |
| PVE Tailscale 接入 | `pve_tailscale_setup.sh` | 为 PVE 宿主机安装 Tailscale，并广播 `10.10.10.0/24` LXC 子网 |
| PVE 基础代理接入 | `pve_xray_setup.sh` | 读取 VLESS Reality 分享链接，生成 `/etc/xray/config.json` |
| PVE 透明代理 | `pve_tproxy_setup.sh` | 为 PVE 宿主机与 LXC 流量启用 tproxy + DNS 防泄漏 |
| PVE 实操记录 | `PVE.md` | 记录网络拓扑、LXC 约定、服务管理方法 |
| PVE Tailscale 文档 | `PVE-TAILSCALE.md` | 从零账号起步接入 tailnet，并规划后续开发 LXC 访问 |
| 节点接入指南 | `PVE-VLESS.md` | 收纳节点要求、分享链接字段、排障与补充说明 |
| 命令与工具 | `COMMANDS.md` / `TOOLS.md` | 日常运维命令与工具教程 |

## 快速开始

### Agent 文档分层

- `README.md`：给人类看的仓库总览
- `AGENTS.md`：给 OpenCode / Claude Code 共用的**唯一 canonical agent 入口**
- `CLAUDE.md`：仅保留 Claude Code 兼容发现能力的薄封装，避免与 `AGENTS.md` 双份维护

所以对于同时使用 Claude Code 和 OpenCode 的用户，推荐结构不是维护两份完整 agent 手册，而是：

- 把真实规范收敛到 `AGENTS.md`
- 保留 `CLAUDE.md`，但只做跳转和极少量 Claude 特定说明
- 让角色文档（`VPS-VLESS.md`、`PVE-VLESS.md`、`PVE.md`）继续承载场景知识

### Claude Code / OpenCode 交互式入口

如果你的目标是：

1. 新服务器先安装好 OpenCode
2. `git clone` 这个仓库
3. 然后让 OpenCode 基于你的选择开始部署与调试

推荐流程不是“让 agent 自动判断机器角色”，而是：

1. 先让 agent 读 [`AGENTS.md`](./AGENTS.md)
2. 你明确告诉它这台机器的角色（GCP / VPS VLESS / PVE Tailscale / PVE xray / PVE tproxy）
3. 再由它决定直接调用底层脚本，或使用 `setup.sh` 这个便捷分发器

也就是说，`AGENTS.md` 是 **Claude Code / OpenCode 共用的主入口说明**，`setup.sh` 是 **可选命令助手**。

当角色已经明确时，可以用 `setup.sh` 快速执行：

```bash
# 新 VPS：安装 VLESS Reality 服务端
bash setup.sh vps-vless

# PVE 宿主机：安装 Tailscale 并广播 LXC 子网
TAILSCALE_HOSTNAME='pve-homelab' bash setup.sh pve-tailscale

# PVE 宿主机：接入一个现成的 VLESS Reality 节点
VLESS_LINK='vless://...' bash setup.sh pve-xray

# PVE 宿主机：升级为透明代理
bash setup.sh pve-tproxy

# GCP Ubuntu 工作站
bash setup.sh gcp
```

相比只给一个配置模板，这种做法的优势是：

- OpenCode 有明确文档入口和可执行脚本入口
- 敏感值可以由脚本自动生成或通过环境变量注入
- 最终状态会落成真实系统配置，而不是停留在“待你手工套模板”

如果你是通过 Claude Code 或 OpenCode 交互式推进，优先让它先读 [`AGENTS.md`](./AGENTS.md)。

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
# 1. 在新 VPS 上部署一个可用的 VLESS Reality 服务端
bash setup.sh vps-vless

# 2. 记下脚本输出的分享链接，或读取 /root/.vps-env/vless-share-link.txt

# 2. 在 PVE 宿主机安装 xray 二进制（见 PVE-VLESS.md）

# 3. 生成基础 xray 客户端配置
VLESS_LINK='vless://...' bash setup.sh pve-xray

# 4. 如需让宿主机 / LXC 全流量走代理，再执行
bash setup.sh pve-tproxy
```

### PVE 宿主机接入 Tailscale

如果你希望把 PVE 宿主机作为远程管理入口，并把 `10.10.10.0/24` 这段 LXC 子网暴露给 tailnet：

```bash
# 1. 从 0 开始时，先在浏览器创建 Tailscale 账号，并让本地管理设备先加入 tailnet

# 2. 在 PVE 宿主机安装 Tailscale，并广播 LXC 子网
TAILSCALE_HOSTNAME='pve-homelab' bash setup.sh pve-tailscale

# 3. 如果你已经准备好 auth key，也可以无交互登录
TAILSCALE_AUTH_KEY='tskey-auth-xxxxx' \
TAILSCALE_HOSTNAME='pve-homelab' \
bash setup.sh pve-tailscale
```

更多细节见 [`PVE-TAILSCALE.md`](./PVE-TAILSCALE.md)。

## 文档索引

- [VPS-VLESS.md](./VPS-VLESS.md)：新 VPS 上部署 VLESS Reality 服务端节点
- [vps_vless_setup.sh](./vps_vless_setup.sh)：新 VPS 上的可执行安装脚本
- [AGENTS.md](./AGENTS.md)：OpenCode / agent 执行入口与约束说明
- [CLAUDE.md](./CLAUDE.md)：Claude Code 兼容 shim，真实规范仍以 AGENTS.md 为准
- [PVE-TAILSCALE.md](./PVE-TAILSCALE.md)：PVE 宿主机从零接入 Tailscale 与后续 LXC 访问策略
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

# PVE Tailscale（执行 pve_tailscale_setup.sh 后）
tailscale status
tailscale ip -4
tailscale netcheck

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
