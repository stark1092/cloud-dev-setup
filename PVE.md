# PVE 家庭实验室配置记录

## 硬件
- CPU: AMD Ryzen 7 7840HS
- 系统: Proxmox VE 9.1.6 (基于 Debian Trixie)

## 初始配置

### 1. APT 源配置
PVE 默认企业源需要订阅，个人使用切换为免费源。

在 PVE 控制台 **节点 → 存储库** 中确认以下源已启用：
- `http://ftp.debian.org/debian` trixie (main contrib)
- `http://ftp.debian.org/debian` trixie-updates
- `http://security.debian.org/debian-security` trixie-security
- `http://download.proxmox.com/debian/pve` trixie pve-no-subscription

并在 Shell 中执行：
```bash
apt update && apt dist-upgrade -y
```

### 2. 存储
- `local`: 存放 ISO 镜像和 CT 模板
- `local-lvm`: 存放容器/虚拟机磁盘

---

## 脚本执行顺序

如果你还没有可用的 VLESS Reality 服务端节点，先看 [`VPS-VLESS.md`](./VPS-VLESS.md)。

如果你通过 OpenCode / agent 操作这台机器，先让它阅读 [`AGENTS.md`](./AGENTS.md)，并明确告诉它当前角色是 `pve-xray` 或 `pve-tproxy`。

1. `pve_xray_setup.sh`
   - 粘贴完整的 VLESS Reality 分享链接
   - 生成 `/etc/xray/config.json`
   - 监听 `0.0.0.0:1080/1081`（宿主机本地可直接用 `127.0.0.1`，LXC 可用宿主机 IP 复用）
2. `pve_tproxy_setup.sh`
   - 在现有 xray 配置上追加 tproxy 入站
   - 写入 iptables / policy routing / DNS 防泄漏规则
3. 字段说明、节点要求、排障建议见 [`PVE-VLESS.md`](./PVE-VLESS.md)

---

## 网络架构

```
LXC (10.10.10.0/24)
    │
    └─► vmbr1 (PVE 内部桥接，10.10.10.1/24，无物理端口)
            │
            └─► PVE 路由层 → iptables tproxy → xray → VLESS 服务器
```

- 所有 LXC 统一使用 vmbr1，流量经 PVE 路由层管控
- NAT 规则写在 `/etc/network/interfaces` 的 vmbr1 post-up/post-down 中
- tproxy 自动拦截所有出站流量，DNS 也通过代理解析（防泄漏）
- 白名单直连：127.0.0.0/8、10.0.0.0/8、192.168.0.0/16、172.16.0.0/12、100.64.0.0/10（Tailscale）

**新建 LXC 标准配置：**
- 网桥：vmbr1
- IP：10.10.10.x/24（静态）
- 网关：10.10.10.1
- DNS：8.8.8.8

### PVE 中文界面字段对照（LXC / CT）

PVE 文档和英文资料经常使用英文选项名，但你在中文界面里看到的字段名可能不同。这里记录一份常用对照，避免以后 agent 只给英文导致在 UI 里找不到。

| 英文项 | 中文界面常见名称 | 说明 / 当前建议 |
|--------|------------------|-----------------|
| Unprivileged container | 无特权容器 / 无特权的容器 | **建议开启**。PVE 新建 CT 默认通常也是开启的 |
| Nesting | 嵌套 | **先不开**。只有明确要在 LXC 里跑 Docker 等嵌套场景时再开 |
| On boot | 开机启动 / 随系统启动 / 启动时运行 | **建议开启**。很多版本是在创建后 `CT -> 选项` 里设置，不一定在创建向导里出现 |
| DNS server / nameserver | DNS 服务器 | 填 `8.8.8.8` |
| DNS domain / searchdomain | DNS 域 / 搜索域 | 当前可以**留空** |
| Start at boot | 开机启动 | 和 On boot 基本是同一类设置 |

### 创建时你如果看不到某些选项，怎么理解

- **无特权容器**：通常在创建向导的“常规 / General”页；如果你没主动改，默认大概率已经是开启状态
- **嵌套**：通常也在“常规 / General”页，或者创建后在 `CT -> 选项 / Features` 中调整
- **开机启动**：很多时候不是创建时就暴露出来，而是在创建完成后到 `CT -> 选项` 里启用
- **DNS 域** 和 **DNS 服务器**：这两个在创建向导里经常同时出现；当前只需要填 DNS 服务器，DNS 域留空即可

### 第一台开发机 LXC 的推荐填写（中文界面口径）

- 模板：Ubuntu 24.04 LTS（没有就用 Ubuntu 22.04 LTS）
- CPU 核心：4
- 内存：8192 MB
- Swap：2048 MB
- 磁盘：80 GB（后续可扩容）
- 网桥：vmbr1
- IPv4 / IP 地址：10.10.10.101/24
- 网关：10.10.10.1
- DNS 服务器：8.8.8.8
- DNS 域：留空
- 无特权容器：开启
- 嵌套：先不开
- 开机启动：创建后到 `CT -> 选项` 中开启

### 当前落地进度（2026-03）

以下事项已经验证通过：

- PVE 宿主机已接入 Tailscale，机器名使用 `pve-homelab`
- Tailscale 子网路由 `10.10.10.0/24` 已可用
- 本地 Mac 已能通过 `ssh root@pve-homelab` 访问 PVE 宿主机
- `vmbr1` 已确认配置为 `10.10.10.1/24`
- 本地 Mac 已能通过子网路由直接访问开发用 LXC
- 第一台开发机 LXC 已创建，并已通过预置的 Mac SSH 公钥实现免密登录

当前策略：

- **先不为开发 LXC 单独安装 Tailscale**
- 继续通过 `PVE 宿主机 + subnet router` 访问 `10.10.10.0/24` 下的容器
- 只有当某个 LXC 需要独立身份、ACL、MagicDNS 名称或长期稳定的独立远程开发入口时，再考虑给它单独接入 Tailscale

下一步待办：

1. 在开发 LXC 内完成基础系统初始化（`apt update && apt upgrade -y`）
2. 安装常用开发工具（如 `git` / `curl` / `zsh` / `tmux`）
3. 视需求决定是否启用 Docker in LXC（届时再开启 `嵌套`，必要时补 `keyctl`）
4. 等开发负载稳定后，再评估是否需要给开发 LXC 单独接入 Tailscale

---

## LXC 容器

### lambda-builder
用途: 为 AWS Lambda 打包 Python 依赖（Linux 环境，x86_64）

| 配置项 | 值 |
|--------|-----|
| 模板 | Ubuntu 22.04 LTS |
| Python | 3.10（系统自带，与 Lambda runtime 对齐） |
| 磁盘 | 8 GB |
| CPU | 1 核 |
| 内存 | 512 MB |
| 网桥 | vmbr1 |
| IP | 10.10.10.100/24（静态） |
| 网关 | 10.10.10.1 |
| DNS | 8.8.8.8 |

**创建后操作：**
```bash
apt update && apt upgrade -y
```

**用途说明：**
在 macOS 上 pip install 会生成 darwin `.so` 文件，无法在 Lambda（Linux）运行。
在此容器内打包可直接生成 Linux 兼容的 zip。

---

## 代理配置

### 方案：xray 透明代理（VLESS + Reality + XTLS Vision）

所有出站流量自动走代理，无需显式指定 `--proxy`。DNS 也通过代理解析，防止泄漏。

如果你手头只有服务商 / 面板生成的 VLESS 分享链接，先看 [`PVE-VLESS.md`](./PVE-VLESS.md)。
如果你还没有把服务端节点建出来，先看 [`VPS-VLESS.md`](./VPS-VLESS.md)。
本仓库当前约定的客户端参数为：`security=reality` + `type=tcp` + `flow=xtls-rprx-vision`。

**协议参数：**
- 传输：TCP + TLS Reality
- Flow：xtls-rprx-vision
- SNI：www.microsoft.com / Fingerprint：chrome

**默认监听端口：**
- SOCKS5：0.0.0.0:1080（宿主机本地可用 `127.0.0.1:1080`）
- HTTP：0.0.0.0:1081（宿主机本地可用 `127.0.0.1:1081`）
- tproxy（透明）：127.0.0.1:12345

**白名单（直连，不走代理）：**
- 127.0.0.0/8 本地
- 10.0.0.0/8 / 192.168.0.0/16 / 172.16.0.0/12 私有网段
- 100.64.0.0/10 Tailscale
- 自定义 IP：编辑 `/etc/xray/iptables.sh` 中的 `WHITELIST_IPS` 数组

**服务管理：**
```bash
systemctl status xray
systemctl status xray-iptables
journalctl -u xray -f

# 修改白名单后重载规则
systemctl restart xray-iptables
```

**相关文档与脚本：**
- [`PVE-VLESS.md`](./PVE-VLESS.md)：节点要求、分享链接字段、PVE 接入步骤、排障建议
- `pve_xray_setup.sh`：生成基础 xray Reality 客户端配置
- `pve_tproxy_setup.sh`：升级为透明代理（在 PVE 宿主机以 root 执行）
