# GCP AI 开发工作站

Ubuntu 24.04 LTS 自动化配置脚本，为 OpenClaw 和 Claude Code 提供完整开发环境。

## 快速开始

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

## 安装内容

| 类别 | 工具 |
|------|------|
| 终端 | tmux (TPM + 插件), Zsh (Oh My Zsh) |
| 搜索 | fzf, ripgrep, zoxide |
| 容器 | Docker, Docker Compose |
| 版本管理 | mise (Python/Node.js) |
| 工具 | btop, jq, tree, git, curl |

## 文件说明

```
VPS-ENV/
├── gcp_provision.sh     # 主安装脚本
├── .tmux.conf           # Tmux 配置
├── proxy_toggle.sh      # 代理切换脚本
├── TOOLS.md             # 工具使用教程
└── README.md            # 本文档
```

## 安装后验证

```bash
tmux                    # 测试 tmux
docker run hello-world  # 测试 Docker
proxy status            # 测试代理脚本
mise --version          # 测试 mise
rg --version            # 测试 ripgrep
```

## 工具使用

详细的工具使用教程请参阅 [TOOLS.md](./TOOLS.md)。

常用命令速查：

| 工具 | 常用命令 |
|------|----------|
| Tmux | `tmux` 启动, `tmux a` 连接, `Ctrl-a d` 分离 |
| 代理 | `proxy on/off/status` |
| 版本 | `mise use python@3.12` / `mise use node@22` |

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
