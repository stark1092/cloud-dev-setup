# 新 VPS 部署 VLESS Reality 服务端指南

这份文档从外部 PDF 中提炼出**适合本仓库长期保存**的服务端部署部分，目标是：

1. 在一台全新的 Linux VPS 上部署一个可用的 VLESS Reality 节点
2. 导出可供客户端 / `pve_xray_setup.sh` 使用的分享链接
3. 保留对后续维护真正有帮助的检查项和排障思路

如果你的目标是让 **OpenCode 在 fresh server 上接管安装**，更合理的流程是：

1. 先让它阅读 [`AGENTS.md`](./AGENTS.md)
2. 你明确告诉它当前机器就是 `vps-vless` 角色
3. 再由它选择调用 `bash setup.sh vps-vless` 或直接调用脚本

如果你已经明确要走 VPS 服务端路径，那么最方便的命令是：

```bash
bash setup.sh vps-vless
```

这会直接执行 [`vps_vless_setup.sh`](./vps_vless_setup.sh)，自动完成：

- 基础依赖安装
- BBR 配置（默认开启，可用 `ENABLE_BBR=0` 关闭）
- xray 安装
- Reality 服务端配置生成
- `xray.service` 启动
- 分享链接输出与落盘

如果 GitHub 下载不通，也可以预先放好本地 xray 二进制，再执行：

```bash
XRAY_LOCAL_BINARY=/root/xray bash setup.sh vps-vless
```

也就是说：对于 AI agent，**AGENTS.md + 脚本入口** 比模板更有价值；模板更适合人工对照修改，而 agent 更适合在明确角色后直接执行脚本。

它适合收纳到本仓库，因为这本来就是一份 **VPS / PVE 环境配置集合**。
`PVE-VLESS.md` 负责“PVE 如何消费一个已有节点”，而本文负责“如何先把这个节点建出来”。

---

## 适用范围

本文解决的是：

- 一台全新的 VPS 作为 **VLESS Reality 服务端**
- 面向个人使用或家庭实验室，不追求多租户复杂运营
- 最终产出一条可导入客户端、也可喂给 `pve_xray_setup.sh` 的 VLESS Reality 分享链接

本文不解决的是：

- 面板自动化备份 / 多用户限速 / 商业化运营
- 将敏感配置直接提交进仓库
- 所有客户端的细枝末节适配

如果你不想让脚本自动生成默认值，也可以通过环境变量覆盖：

```bash
SERVER_ADDRESS=1.2.3.4 \
VLESS_PORT=443 \
REALITY_DEST=www.microsoft.com:443 \
REALITY_SERVER_NAME=www.microsoft.com \
VLESS_UUID='11111111-1111-1111-1111-111111111111' \
VLESS_SHORT_ID='aabbccdd' \
NODE_REMARK='my-vps-node' \
bash setup.sh vps-vless
```

如果你后续要让 PVE 宿主机消费这个节点，请继续看 [`PVE-VLESS.md`](./PVE-VLESS.md)。

---

## 服务端最低配置建议

| 项目 | 建议 |
|------|------|
| 系统 | Debian 12 / Ubuntu 22.04+ |
| 协议 | `vless` |
| 传输 | `tcp` |
| 安全层 | `reality` |
| Flow | `xtls-rprx-vision` |
| 端口 | 优先 `443` |
| 指纹 | `chrome` |

说明：

- `443` 不是绝对硬性要求，但通常最符合 HTTPS 流量外观
- Reality 当前仍以 TCP 场景为主，和仓库现有文档 / 脚本约定一致
- 如果你打算把这个节点交给 `pve_xray_setup.sh` 使用，请保持 `flow=xtls-rprx-vision`

---

## 初始系统准备

如果你采用脚本入口，上面的系统准备会由 `vps_vless_setup.sh` 直接完成；本节主要用于解释脚本背后的步骤与默认值。

### 1. 更新系统并安装基础工具

```bash
apt update
apt upgrade -y
apt install -y curl wget socat tar unzip jq
```

如果系统启用了 UFW / 云防火墙，记得放行你实际使用的管理端口与服务端口。

### 2. BBR（可选，但推荐）

原始 PDF 把这一步写得很重，我保留它，但把表述收敛为“推荐优化项”，而不是“缺了就不能用”。

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

如果输出已经显示 `bbr`，说明系统已启用，无需重复配置。

---

## 先准备好这些值

无论你最终使用面板还是手工配置，先理解并准备这些字段会更稳：

| 字段 | 用途 | 备注 |
|------|------|------|
| `UUID` | 客户端身份 ID | 每个节点 / 用户至少一组 |
| `privateKey` | Reality 服务端私钥 | 只留在服务端，绝不进仓库 |
| `publicKey` | 客户端要使用的公钥 | 需要出现在分享链接里 |
| `shortId` | Reality 辅助标识 | 可为空，也可用简短十六进制 |
| `serverName` / `SNI` | 握手域名 | 需与 `dest` 逻辑一致 |
| `dest` | Reality 目标站点 | 常见写法如 `www.microsoft.com:443` |

### 生成 UUID

```bash
cat /proc/sys/kernel/random/uuid
```

### 生成 Reality 密钥对

如果已经安装了 xray，可直接生成：

```bash
xray x25519
```

典型输出会包含：

- `Private key`
- `Public key`

其中：

- `Private key` 只保留在服务端配置里
- `Public key` 需要提供给客户端 / 分享链接

---

## 选择控制面

本仓库不强制你用某个控制面，但从 PDF 实际内容出发，最贴近原文的方式是：

1. **使用 3X-UI / x-ui 等面板** 来创建 Reality 入站
2. 然后导出分享链接
3. 最终把分享链接交给客户端或 `pve_xray_setup.sh`

这也是为什么服务端部署部分值得纳入仓库：

- PDF 讲的是“如何把节点建起来”
- 现有 `PVE-VLESS.md` 讲的是“如何把节点用起来”

### 关于 3X-UI 的边界

我保留“可用 3X-UI 部署”的思路，但不原样保留 PDF 中的所有面板细节，因为：

- 面板版本变化快，截图 / 点击路径容易过时
- 原文中有一条关于在 `realitySettings` 中插 `decryption` / `encryption` 的说法，不适合直接照搬

因此，仓库里只保留**字段级约束**，不把面板点击路径写死成唯一真理。

### 一个足够务实的落地方式

如果你就是想在一台新 VPS 上尽快把节点跑起来，推荐路径可以简化为：

1. 更新系统并安装基础工具
2. 安装一个你熟悉且还在维护的 xray 面板（例如 3X-UI）
3. 创建一条 `vless + reality + xtls-rprx-vision` 入站
4. 导出分享链接
5. 用客户端验证，再交给 `pve_xray_setup.sh`

### 面板安装入口（示例）

原始 PDF 使用了面板方案，因此这里保留“面板入口”这个层级，但不把每一步点击路径写死。

```bash
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
```

说明：

- 这是为了保留“新 VPS 上快速起服务端”的可执行路径
- 真正长期可靠的是下面的**字段约束**与**导出分享链接字段检查**
- 如果面板后续版本改了菜单路径，不影响本仓库文档主体

---

## 使用面板创建 VLESS Reality 入站

无论你使用 3X-UI 还是类似面板，最终需要确保入站配置满足这些字段：

| 项目 | 建议值 | 说明 |
|------|--------|------|
| 协议 | `vless` | 当前主流方案 |
| 端口 | `443` 或其他可用端口 | `443` 更接近标准 HTTPS |
| 传输 | `tcp` | Reality 走 TCP |
| Flow | `xtls-rprx-vision` | 与仓库现有脚本保持一致 |
| Security | `reality` | 核心安全层 |
| Fingerprint | `chrome` | 与当前客户端兼容性最好 |
| Dest | 类似 `www.microsoft.com:443` | 用作外观伪装 |
| SNI | 例如 `www.microsoft.com` | 握手域名，应和目标一致 |
| Short ID | 8~16 位十六进制或留空 | 与客户端保持一致 |

面板里如果还有这些概念，也要保持一致：

- `UUID`
- `Public Key`
- `Private Key`（通常由面板 / xray 自动生成后展示或写入）
- `serverNames`
- `dest`

你还需要记录或导出这些值：

- 服务器地址
- 服务器端口
- UUID
- Public Key
- Short ID
- SNI / serverName
- Flow
- Fingerprint

---

## 关于 Xray / Reality 配置的几个关键点

### 1. `xtls-rprx-vision` 仍然值得保留

这和当前仓库脚本、PVE 文档保持一致，也是 PDF 中最有价值的一条字段约束。

### 2. `443` 值得优先考虑

不是唯一可选端口，但若无特别原因，优先使用 `443` 更符合 Reality 的流量外观目标。

### 3. 不要照搬 PDF 中那条 `realitySettings` 修改建议

PDF 提到在 `realitySettings` 里手工插入：

```json
"decryption": "none",
"encryption": "none"
```

这类写法不应直接照搬进仓库指南。你真正需要记住的是：

- `encryption: "none"` 是 VLESS 用户配置层的概念
- `publicKey` / `shortId` / `serverName` / `fingerprint` 才属于 Reality 相关字段

如果你使用面板，优先让它生成正确配置；如果你手改 JSON，请先确认字段归属没写错。

### 4. 对“PQC / ML-KEM 导致全部客户端异常”的说法要保守看待

原始 PDF 把这件事写得过于绝对。更稳妥的说法是：

- 新版 Xray 会持续调整相关实现
- 如果个别客户端握手失败，优先排查客户端版本、指纹、Reality 字段是否完整
- 不要把某个版本问题当成永久结论写死在仓库里

---

## 最低限度的服务端运维检查

### 1. 端口与防火墙

如果你使用的是 `ufw`，至少确认：

```bash
ufw allow 22/tcp
ufw allow 443/tcp
ufw status
```

如果你实际节点不跑在 `443`，按实际端口替换。

同时检查云服务商控制台里的安全组 / 防火墙规则是否同步放行。

### 2. 服务监听

```bash
ss -tuln | grep 443
```

### 3. 服务状态

```bash
systemctl status xray
journalctl -u xray -n 50
```

如果你使用的是面板方案，也可以同时检查面板服务是否正常。

---

## 导出分享链接并交给客户端 / PVE

你最终需要拿到的，应该是一条类似这样的分享链接：

```text
vless://<UUID>@<SERVER_HOST>:443?security=reality&type=tcp&sni=www.microsoft.com&fp=chrome&pbk=<PUBLIC_KEY>&sid=<SHORT_ID>&flow=xtls-rprx-vision#my-vps-node
```

这条链接可以用于：

- 手机 / 桌面客户端直接导入
- 交给 [`PVE-VLESS.md`](./PVE-VLESS.md) 中的 `pve_xray_setup.sh`

如果你打算给 PVE 用，至少确认以下字段齐全：

- `security=reality`
- `type=tcp`
- `sni=` 或 `serverName=`
- `pbk=` 或 `publicKey=`
- `flow=xtls-rprx-vision`

如果导出的链接字段不完整，不要急着在客户端里盲试，先回到面板确认 Reality 入站字段是否真的都创建成功。

---

## 基础验证

### 1. 先在普通客户端导入分享链接

优先用一个你熟悉的客户端先验证节点本身是否能用，再接给 PVE。

### 2. 服务端端口是否监听

```bash
ss -tuln | grep 443
```

如果你用的不是 `443`，替换成实际端口即可。

### 3. 面板 / xray 服务是否正常

```bash
systemctl status xray
journalctl -u xray -n 50
```

如果你使用的是面板式安装，服务名可能因面板而不同，但排查思路是一样的：

- 先看服务是否存活
- 再看最近日志里是否有 Reality / TLS / inbound 初始化错误

### 4. 客户端连通性验证

导入分享链接后，优先做最简单的出站检查：

```bash
curl https://ifconfig.me
```

如果出口 IP 已切成你的 VPS，说明基础链路已通。

---

## 常见问题与排障

### 1. 客户端导入后无法连接

优先核对：

- `UUID`
- `Public Key`
- `Short ID`
- `SNI`
- 端口
- `flow=xtls-rprx-vision`

其中任一项不一致，都可能直接导致握手失败。

### 2. 端口已开，但仍无法连通

检查：

- 云服务商安全组 / 防火墙是否已放行
- 面板监听端口和 Reality 入站端口是否搞混
- VPS 上是否还有其他服务占用了同一端口

### 3. 个别客户端表现不稳定

这类问题优先从“版本 / 指纹 / 字段完整性”排查，而不是先假设协议本身有问题：

- 优先使用较新的客户端版本
- 保持 `fingerprint=chrome`
- 不要随意改动 `flow`
- 如遇特定浏览器场景异常，再临时测试 QUIC / WebRTC 相关影响

### 4. 需要长期维护哪些内容

建议长期关注：

- Xray / 面板版本更新后是否影响 Reality 字段导出
- 你的分享链接字段是否仍完整
- 服务端端口、SNI、Short ID 是否发生过变更

如果你给多个环境复用同一个节点，建议至少保存一份**脱敏后的字段清单**，避免后续只剩一条黑盒分享链接而不知道其中各字段含义。

---

## 安全注意事项

- 不要把真实 UUID、Private Key、Public Key、Short ID 提交到仓库
- 如果只是个人节点，也要限制 SSH 暴露面和面板管理入口
- 面板管理端口不要使用默认弱口令，最好配合来源限制或反向代理防护
- 如果未来你把服务端完整 JSON 配置也文档化，只保留占位符模板，不保留真实值

---

## 与仓库其他文档的关系

- [`VPS-VLESS.md`](./VPS-VLESS.md)：新 VPS 上部署服务端节点
- [`PVE-VLESS.md`](./PVE-VLESS.md)：PVE 宿主机如何消费这个节点
- [`PVE.md`](./PVE.md)：PVE 家庭实验室网络结构与透明代理落地

推荐阅读顺序：

1. 本文档：先把 VPS 节点搭起来
2. [`PVE-VLESS.md`](./PVE-VLESS.md)：再把节点接入 PVE
3. [`PVE.md`](./PVE.md)：最后看整体实验室流量架构
