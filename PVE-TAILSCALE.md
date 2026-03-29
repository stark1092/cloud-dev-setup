# PVE 宿主机接入 Tailscale（从 0 开始）

这份文档面向当前仓库里的 **PVE 家庭实验室场景**，目标是把 Tailscale 作为远程管理平面接入进来，并为后续开发用 LXC 做好入口。

本文聚焦三件事：

1. 从 **还没有 Tailscale 账号** 的状态开始创建 tailnet
2. 让 **PVE 宿主机** 先加入 tailnet，作为远程入口和 subnet router
3. 让你后续可以先通过 `10.10.10.0/24` 访问 LXC，再按需给开发机 LXC 单独安装 Tailscale

如果你是通过 OpenCode / agent 推进，推荐顺序是：

1. 先让它阅读 [`AGENTS.md`](./AGENTS.md)
2. 明确告诉它当前机器角色是 `pve-tailscale`
3. 再由它调用底层脚本，或使用 `setup.sh` 这个便捷分发器

---

## 适用范围

本文解决的是：

- 你的 PVE 宿主机已经可用
- 你希望从公网外稳定进入 PVE 管理面
- 你希望未来从本地开发机远程连进 **PVE 上的开发 LXC**
- 你当前还没有 Tailscale 账号，需要从零开始

本文不解决的是：

- 自建 DERP / relay / peer relay 优化
- 把 AWS / VPS 立刻改造成 Tailscale exit node
- 多团队、多管理员的复杂 ACL 设计
- 每个 LXC 的精细化 Tailscale 自动化安装

当前阶段，更合理的路径是：

1. 先把 **本地管理设备 + PVE 宿主机** 拉进同一个 tailnet
2. 让 PVE 广播 `10.10.10.0/24` 这段 LXC 子网
3. 先通过子网路由访问开发 LXC
4. 只有当某个 LXC 确定要长期作为开发机时，再让它自己成为一个独立的 Tailscale 节点

---

## 为什么当前仓库适合先做 PVE 宿主机接入

本仓库已有这些前提：

- `PVE.md` 已固定 LXC 子网为 `10.10.10.0/24`
- `vmbr1` 作为 PVE 内部桥接，网关为 `10.10.10.1`
- `pve_tproxy_setup.sh` 已把 `100.64.0.0/10`（Tailscale 网段）列入直连白名单

这意味着：

- **Tailscale 管理流量** 不会被误送进现有代理链路
- PVE 很适合先作为 **subnet router**，把 `10.10.10.0/24` 暴露给 tailnet
- 你后续访问 LXC 时，不必先给每个容器都立即安装 Tailscale

---

## 推荐顺序

### 第 1 步：创建 Tailscale 账号与 tailnet

在你的本地浏览器中完成：

1. 打开 <https://tailscale.com/>
2. 选择 **Get started**
3. 用你方便长期使用的身份提供商登录（例如 Google / GitHub）
4. 创建你的第一个 tailnet

个人家庭实验室场景，用个人账号起步即可；如果你用的是公开邮箱域名（例如 Gmail），默认会落到个人计划。

### 第 2 步：先把你的本地管理设备接入 tailnet

建议先把你当前这台本地开发机 / Mac 作为**第一个已登录设备**接入。

原因很简单：

- 后面 PVE 登录时，需要你在本地浏览器里完成授权
- 后续验证 `tailscale ping`、Web UI、SSH，都会从这台本地机发起

完成后，你应该已经能在 Tailscale admin console 看到你的本地设备。

### 第 3 步：在 PVE 宿主机安装并登录 Tailscale

当前仓库新增了：

- [`pve_tailscale_setup.sh`](./pve_tailscale_setup.sh)
- `bash setup.sh pve-tailscale`

最基础的命令是：

```bash
bash setup.sh pve-tailscale
```

更推荐给 PVE 一个稳定机器名：

```bash
TAILSCALE_HOSTNAME='pve-homelab' bash setup.sh pve-tailscale
```

默认行为：

- 安装 Tailscale
- 启动 `tailscaled`
- 将 `10.10.10.0/24` 作为 subnet route 广播
- 默认使用 `--accept-dns=false`，避免和当前仓库里的 DNS / xray 逻辑打架

如果你已经提前创建了 auth key，也可以无交互登录：

```bash
TAILSCALE_AUTH_KEY='tskey-auth-xxxxx' \
TAILSCALE_HOSTNAME='pve-homelab' \
bash setup.sh pve-tailscale
```

但从 0 开始时，通常更简单的是**先不用 auth key**，直接让脚本输出登录链接，然后在本地浏览器里点开完成登录。

---

## 脚本会做什么

`pve_tailscale_setup.sh` 会：

1. 安装 `tailscale` 客户端
2. 启动并设置 `tailscaled` 开机自启
3. 在需要广播子网时开启 IP forwarding
4. 执行 `tailscale up`
5. 将以下行为固化为默认值：

| 项目 | 默认值 | 原因 |
|------|--------|------|
| `TAILSCALE_ADVERTISE_ROUTES` | `10.10.10.0/24` | 与仓库现有 LXC 子网约定一致 |
| `TAILSCALE_ACCEPT_DNS` | `false` | 避免覆盖当前 PVE / xray DNS 处理 |
| `TAILSCALE_ENABLE_SSH` | `0` | 先把网络打通，再决定是否启用 Tailscale SSH |

如果你想同时启用 Tailscale SSH，可以显式加上：

```bash
TAILSCALE_ENABLE_SSH=1 \
TAILSCALE_HOSTNAME='pve-homelab' \
bash setup.sh pve-tailscale
```

注意：Tailscale SSH 只接管 **来自 tailnet 的 22 端口连接**，不会替换普通公网 SSH 的整体配置。

---

## 第一次登录后你还需要做什么

### 1. 在 Tailscale admin console 批准子网路由

脚本广播了 `10.10.10.0/24` 之后，还需要在网页管理台批准该 route：

1. 打开 <https://login.tailscale.com/admin/machines>
2. 找到你的 `pve-homelab`（或默认主机名）
3. 进入 **Edit route settings**
4. 批准 `10.10.10.0/24`

如果不批准，PVE 虽然已经进 tailnet，但远端设备还不能通过它访问 LXC 子网。

### 2. 保持 MagicDNS 开启

MagicDNS 默认是启用的，建议保持开启。这样你后面访问 PVE 宿主机时，不必记 Tailscale IP，可以直接用机器名。

例如：

- `https://pve-homelab:8006`
- `ssh root@pve-homelab`

---

## 验证步骤

### 在 PVE 宿主机上

```bash
tailscale status
tailscale ip -4
tailscale netcheck
```

如果你想确认当前连接是直连还是经 DERP：

```bash
tailscale ping <your-local-device-name>
```

### 在本地管理设备上

1. 访问 PVE Web UI：

```text
https://pve-homelab:8006
```

2. 通过 Tailscale SSH / 普通 SSH 访问宿主机：

```bash
ssh root@pve-homelab
```

3. 在批准子网路由后，测试访问一个 LXC：

```bash
ssh user@10.10.10.101
```

---

## 后续开发机 LXC 应该怎么接入

### 阶段 A：先通过 subnet router 访问

在开发 LXC 刚建出来时，先按 [`PVE.md`](./PVE.md) 的标准配置：

- 网桥：`vmbr1`
- IP：`10.10.10.x/24`
- 网关：`10.10.10.1`
- DNS：`8.8.8.8`

此时只要 PVE 的 Tailscale 子网路由已经批准，你就能从本地直接访问它：

```bash
ssh user@10.10.10.101
```

这适合：

- 先验证容器可达性
- 先做轻量维护
- 先搭开发环境

### 阶段 B：当它成为长期开发机时，再让它自己接入 Tailscale

如果某个 LXC 后续会长期承担：

- VS Code Remote SSH
- JetBrains Gateway
- 长时间 SSH 会话
- 单独的 ACL / 审计 / 身份边界

那更好的方式是：**让这个 LXC 自己加入 tailnet**。

这样做的好处是：

- 它拥有自己的 Tailscale 身份
- 可以直接用 MagicDNS 名称连接它
- SSH / IDE 连接路径更干净
- 不依赖 PVE 作为跳板或 subnet router 才能连上

当前仓库先把 **PVE 宿主机侧** 固化下来；开发 LXC 侧可以在你把第一台开发容器建出来后，再按实际发行版与权限模型单独补脚本。

---

## 常见问题

### 1. 我没有 auth key，脚本还能用吗？

可以。

脚本会调用 `tailscale up`。如果当前机器还没登录，它会输出一个登录链接。你只需要在本地浏览器打开这个链接，完成登录后再继续验证即可。

### 2. 我需要先准备一台 VPS 给 Tailscale 做加速节点吗？

不需要。

起步阶段直接使用 Tailscale 默认的直连 / DERP 机制即可。只有你后面实际观察到跨网络延迟或中继瓶颈，再考虑进一步优化。

### 3. 为什么默认 `--accept-dns=false`？

因为当前仓库里，PVE 宿主机可能已经使用 xray/tproxy 并改写过 DNS 相关行为。`--accept-dns=false` 更稳，不容易和现有网络栈互相覆盖。

### 4. 我需要现在就启用 Tailscale SSH 吗？

不需要。

先把 tailnet 打通、子网路由批准、PVE / LXC 连通性验证通过，再决定要不要启用 `tailscale set --ssh` 或 `TAILSCALE_ENABLE_SSH=1`。

---

## 安全注意事项

- 不要把 `TAILSCALE_AUTH_KEY` 提交进仓库
- 不要把 tailnet policy、机器截图、登录链接直接收纳到公开文档
- `/var/lib/tailscale/` 属于本机状态目录，视为敏感本地状态
- 如果你已经把 PVE Web UI 暴露给公网，Tailscale 不是替代防火墙的理由；公网面仍应单独限制

---

## 推荐阅读顺序

1. [`README.md`](./README.md)：仓库总览
2. [`PVE.md`](./PVE.md)：PVE 网络与 LXC 约定
3. 本文档：PVE 宿主机如何接入 Tailscale
4. 后续需要代理链路时再看 [`PVE-VLESS.md`](./PVE-VLESS.md)
