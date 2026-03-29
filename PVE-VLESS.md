# PVE 宿主机接入 VLESS Reality 节点指南

这份文档基于外部节点部署材料重新整理，但只保留**适合本仓库长期维护**的消费端部分：

- 保留：VLESS Reality 节点的必要字段、PVE 接入步骤、BBR 与排障建议
- 丢弃：供应商专有信息、住宅 IP 营销描述、3X-UI 面板点击路径、以及不够稳妥的旧配置写法

因此，**不建议把原始 PDF 直接收纳进仓库**。更合适的做法是拆成两份 Markdown：

- [`VPS-VLESS.md`](./VPS-VLESS.md)：新 VPS 上如何部署服务端节点
- 本文档：PVE 宿主机如何消费这个节点

如果你是通过 OpenCode / agent 交互式推进，推荐顺序是：

1. 先让它阅读 [`AGENTS.md`](./AGENTS.md)
2. 明确告诉它当前机器角色是 `pve-xray` 或 `pve-tproxy`
3. 再由它调用底层脚本，或用 `setup.sh` 作为可选命令分发器

---

## 适用范围

本仓库解决的是：

1. 你已经有一个可用的 VLESS Reality 节点
2. 你希望让 **PVE 宿主机** 先连上它
3. 然后再用 `pve_tproxy_setup.sh` 把 **宿主机 + LXC** 的流量统一导入透明代理

也就是说：这份文档默认讨论的是 **PVE 消费端角色**，不是服务端节点角色。

本仓库脚本**不负责**：

- 自动部署远端 VLESS 服务器（手工部署文档见 [`VPS-VLESS.md`](./VPS-VLESS.md)）
- 自动安装 / 管理 3X-UI 面板
- 保存任何真实 UUID、公钥、Short ID 或完整分享链接

如果你使用的是 3X-UI、x-ui 或其他控制面板，也没问题；只要最终能提供一条**完整的 VLESS Reality 分享链接**，本仓库就能消费。

如果你还没有把服务端节点建出来，请先看 [`VPS-VLESS.md`](./VPS-VLESS.md)。

如果你已经明确当前场景是 `pve-xray`，可以直接运行：

```bash
VLESS_LINK='vless://...' bash setup.sh pve-xray
```

但对 OpenCode 来说，更推荐的思路仍然是：先明确角色，再执行命令。

---

## 节点要求（服务端侧）

远端节点至少应满足以下条件：

| 项目 | 建议值 | 说明 |
|------|--------|------|
| 协议 | `vless` | 与仓库脚本兼容 |
| 传输 | `tcp` | `pve_xray_setup.sh` 当前只支持 TCP |
| 安全层 | `reality` | 当前仓库只支持 VLESS Reality |
| Flow | `xtls-rprx-vision` | 与仓库文档和脚本保持一致 |
| 端口 | 优先 `443` | 不是脚本硬要求，但通常更像正常 HTTPS 流量 |
| SNI | 真实存在的大站域名 | 例如 `www.microsoft.com` |
| 指纹 | `chrome` | 本仓库默认按现代 Chrome 指纹处理 |

### 服务端优化建议

以下内容不由仓库脚本自动完成，但值得在远端节点侧检查：

#### 1. BBR（可选，但推荐）

```bash
uname -r
sysctl net.ipv4.tcp_congestion_control

cat > /etc/sysctl.d/99-bbr.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

sysctl --system
lsmod | grep bbr
```

如果系统已经显示 `bbr`，就不必重复配置。

#### 2. 保持客户端版本较新

较新的 Xray 版本会持续调整 REALITY / TLS 指纹相关实现；若你遇到握手失败、`client hello` 异常，先确认客户端和服务端都不是过旧版本。

#### 3. 不要把字段写错层级

原始 PDF 中提到的某些写法不适合直接照搬。对本仓库来说，最重要的是：

- `encryption: "none"` 属于 **VLESS 用户配置层**
- `publicKey` / `shortId` / `serverName` / `fingerprint` 属于 **Reality 配置层**
- 不要把不属于 `realitySettings` 的字段硬塞进去

---

## 分享链接需要包含哪些字段

`pve_xray_setup.sh` 会从 VLESS 分享链接中读取以下字段：

| 字段 | 是否需要 | 说明 |
|------|----------|------|
| `UUID` | 必需 | 用户 ID |
| `host` | 必需 | 服务端地址 |
| `port` | 必需 | 服务端端口 |
| `security=reality` | 必需 | 当前脚本只接受 Reality |
| `type=tcp` | 必需 | 当前脚本只接受 TCP |
| `sni` / `serverName` | 必需 | Reality 握手域名 |
| `pbk` / `publicKey` | 必需 | Reality 公钥 |
| `flow=xtls-rprx-vision` | 必需 | 当前仓库固定为 Vision |
| `sid` / `shortId` | 可选 | 若服务端允许空 shortId，则可为空；非空时建议 8 或 16 位十六进制 |
| `fp` / `fingerprint` / `client-fingerprint` | 可选 | 默认按 `chrome` 处理 |

### 参考格式

```text
vless://<UUID>@<SERVER_HOST>:443?security=reality&type=tcp&sni=www.microsoft.com&fp=chrome&pbk=<PUBLIC_KEY>&sid=<SHORT_ID>&flow=xtls-rprx-vision#pve-reality
```

### 当前脚本的行为

- 如果 `security` 不是 `reality`，脚本会直接报错
- 如果 `type` 不是 `tcp`，脚本会直接报错
- 如果缺少 `sni` 或 `pbk/publicKey`，脚本会直接报错
- 如果 `flow` 不是 `xtls-rprx-vision`，脚本会直接报错
- `shortId` 可以为空；`fingerprint` 缺失时默认使用 `chrome`

### 新版面板 / 官方文档兼容提示

- 较新的官方 JSON 文档可能把客户端侧 `publicKey` 写成 `password`；而面板和分享链接仍常见 `pbk` / `publicKey`。对当前仓库来说，它们本质上指向同一个客户端要持有的 Reality 值
- 最新官方文档里配置文件可能把 TCP 传输写成 `network: "raw"`；但当前仓库在分享链接层仍按 `type=tcp` 解析和生成，不要手工改成 `type=raw`
- 如果分享链接里带了 `spx` / `spiderX`、`alpn`、`allowInsecure` 等额外参数，`pve_xray_setup.sh` 当前会忽略它们，只抓取生成最小可用配置所需的字段
- 如果 `shortId` 非空，尽量保证它是偶数长度十六进制；推荐 8 位或 16 位。奇数长度值往往不会在脚本解析阶段暴露，而会在 `xray.service` 启动或握手时失败
- 如果面板导出的 `flow` 不是 `xtls-rprx-vision`（例如 `xtls-rprx-vision-udp443`），当前脚本会拒绝；这是仓库当前的兼容边界，不是链接“看起来像 Reality”就一定能直接消费

这样做是为了避免脚本静默降级成错误配置。

---

## PVE 宿主机接入步骤

### 1. 手动安装 xray 二进制

如果 GitHub 无法直连，可先在 Mac 上下载，再传到 PVE：

```bash
# Mac
curl -L "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip" \
    -o /tmp/xray-linux-64.zip
scp /tmp/xray-linux-64.zip root@<PVE_IP>:/tmp/

# PVE
cd /tmp
unzip xray-linux-64.zip
install -m 755 xray /usr/local/bin/xray
```

确认二进制已就位：

```bash
xray version
```

### 2. 生成基础客户端配置

```bash
bash pve_xray_setup.sh
```

脚本会：

- 解析分享链接中的 `UUID / host / port / sni / pbk / sid / fp / flow`
- 生成 `/etc/xray/config.json`
- 注册并启动 `xray.service`
- 配置 apt 使用本地 HTTP 代理 `127.0.0.1:1081`

### 3. 验证基础代理是否正常

```bash
systemctl status xray
journalctl -u xray -f
curl --proxy http://127.0.0.1:1081 https://www.google.com -I
```

默认监听端口：

- SOCKS5：`0.0.0.0:1080`（宿主机本地可用 `127.0.0.1:1080`）
- HTTP：`0.0.0.0:1081`（宿主机本地可用 `127.0.0.1:1081`）

如果你的 PVE 宿主机有公网暴露面，请额外确认防火墙不会把 `1080/1081` 暴露给不可信网络；
当前监听 `0.0.0.0` 的主要目的，是让同一宿主机上的 LXC 也能复用这组代理端口。

### 4. 升级为透明代理（可选，但推荐）

如果你希望让宿主机和 LXC 都自动走代理，再执行：

```bash
bash pve_tproxy_setup.sh
```

它会：

- 给现有 xray 配置追加 `dokodemo-door` tproxy 入站（端口 `12345`）
- 写入 `/etc/xray/iptables.sh` 与 `/etc/xray/iptables-clean.sh`
- 注册 `xray-iptables.service`
- 固定 `resolv.conf`，避免 DNS 泄漏

验证命令：

```bash
systemctl status xray-iptables
systemctl status xray
curl -fsSL --max-time 10 https://ifconfig.me
```

---

## 脚本会写入哪些文件

| 路径 | 来源脚本 | 作用 |
|------|----------|------|
| `/etc/xray/config.json` | `pve_xray_setup.sh` | xray 客户端主配置 |
| `/etc/systemd/system/xray.service` | `pve_xray_setup.sh` / `pve_tproxy_setup.sh` | xray systemd 服务 |
| `/etc/apt/apt.conf.d/99proxy` | `pve_xray_setup.sh` | apt 通过本地 HTTP 代理出站 |
| `/etc/xray/iptables.sh` | `pve_tproxy_setup.sh` | tproxy / mangle / 白名单规则 |
| `/etc/xray/iptables-clean.sh` | `pve_tproxy_setup.sh` | 清理透明代理规则 |
| `/etc/systemd/system/xray-iptables.service` | `pve_tproxy_setup.sh` | 开机自动加载 iptables 规则 |
| `/etc/resolv.conf` | `pve_tproxy_setup.sh` | 固定 DNS，避免被 DHCP 覆盖 |

---

## 常见问题与排障

### 1. 脚本一开始就拒绝分享链接

优先检查这些字段是否存在：

- `security=reality`
- `type=tcp`
- `sni=` 或 `serverName=`
- `pbk=` 或 `publicKey=`
- `flow=xtls-rprx-vision`

如果服务商导出的链接不完整，先在面板里补齐字段，再重新复制分享链接。

### 2. `xray.service` 启动失败

```bash
systemctl status xray
journalctl -u xray -n 50
```

常见原因：

- 公钥、SNI、Short ID 与服务端不匹配
- 服务端实际不是 Reality / Vision 配置
- 本地 `xray` 二进制版本过旧

### 3. 基础代理正常，但透明代理不生效

```bash
systemctl status xray-iptables
journalctl -u xray -n 50
iptables -t mangle -S XRAY
iptables -t mangle -S XRAY_SELF
```

另外检查：

- `/etc/xray/iptables.sh` 中的 `WHITELIST_IPS` 是否误放了目标地址
- LXC 默认网关是否正确指向 `10.10.10.1`
- 是否在改完白名单后执行了 `systemctl restart xray-iptables`

### 4. 额外的客户端侧排障（非仓库脚本范围）

以下建议主要用于吸收原始 PDF 中仍有价值的经验，但它们不属于本仓库脚本的自动化范围：

- 优先使用较新的客户端与浏览器版本
- 不要把“关闭 QUIC”当作默认配置；只在排障时临时尝试
- 如果你关心浏览器真实出口泄漏，额外检查 WebRTC 行为
- 对 IP 信誉敏感的站点，尽量避免频繁切换不同节点

---

## 安全注意事项

- `/etc/xray/config.json` 含敏感信息，不提交到仓库
- 不要把真实分享链接、UUID、公钥、Short ID 直接写进 Markdown
- 如果需要收纳示例，请始终使用占位符
- 基础代理默认监听 `0.0.0.0:1080/1081`；如不需要给 LXC 复用，可改成更严格的监听地址，或用防火墙限制来源

---

## 推荐阅读顺序

1. [`README.md`](./README.md)：仓库总览
2. [`PVE.md`](./PVE.md)：PVE 网络与实验室结构
3. 本文档：VLESS Reality 节点接入与排障
4. `pve_xray_setup.sh` / `pve_tproxy_setup.sh`：最终以脚本为准
