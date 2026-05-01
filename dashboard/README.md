# Dashboard

家庭实验室聚合简报 + 节点状态看板，三层架构：

```
[各数据源] → [轻量 Client] → [Dashboard Server] → [前端 PWA]
```

只在 Tailscale 网络内可达，桌面 / 手机加到主屏即可使用。

## 文档导航

| 文件 | 内容 |
|------|------|
| [DESIGN.md](./DESIGN.md) | 原方案 review、修订点、最终架构与决策表 |
| [API.md](./API.md) | HTTP 接口契约、请求 / 响应示例 |
| [SCHEMA.md](./SCHEMA.md) | SQLite 表结构、索引、保留策略、节点清单格式 |
| [CLIENT.md](./CLIENT.md) | Client 契约、配置、新增数据源流程、参考实现 |
| [server/](./server/) | FastAPI 服务端代码（DESIGN.md §6 S1）|
| [client/](./client/) | `dashboard-push` 单文件 stdlib 客户端 |

## 状态

| Session | 范围 | 状态 |
|---------|------|------|
| S1 | Server 骨架 + ingest + feed + history + health + 一个 Client | ✅ 已落地，14 个 smoke 测试 + e2e 跑通 |
| S2 | 后台 ping + retention + `/api/v1/nodes` + SIGHUP 热加载 | ✅ 已落地，27 个测试全绿 + e2e 跑通 |
| S3 | PWA 前端（三块布局 + 历史瀑布流 + 30s 轮询）| 待启动 |
| S4 | TLS（tailscale cert）+ manifest + service worker | 待启动 |
| S5 | 集成进 `setup.sh dashboard` role | 待启动 |

## 与本仓库其他角色的关系

未来可作为 `bash setup.sh dashboard` 的新 role 接入 [`AGENTS.md`](../AGENTS.md)，
部署位置预计为 PVE 上的一个 Alpine LXC。Client 脚本可分发到任意数据源节点
（GCP 工作站、VPS、其他 LXC 等），由 cron / OpenClaw 调度。
