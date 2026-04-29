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

## 状态

设计阶段。代码尚未落地。

## 与本仓库其他角色的关系

未来可作为 `bash setup.sh dashboard` 的新 role 接入 [`AGENTS.md`](../AGENTS.md)，
部署位置预计为 PVE 上的一个 Alpine LXC。Client 脚本可分发到任意数据源节点
（GCP 工作站、VPS、其他 LXC 等），由 cron / OpenClaw 调度。
