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

**协议参数：**
- 传输：TCP + TLS Reality
- Flow：xtls-rprx-vision
- SNI：www.microsoft.com / Fingerprint：chrome

**本地端口（备用手动代理）：**
- SOCKS5：127.0.0.1:1080
- HTTP：127.0.0.1:1081
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

**安装脚本：** `pve_tproxy_setup.sh`（在 PVE 宿主机以 root 执行）
