# 工具使用教程

本文档包含开发工作站中各工具的详细使用说明。

---

## Tmux 终端复用器

Tmux 让你在断开 SSH 后保持程序运行，并支持多窗格布局。

### 会话管理

```bash
tmux                       # 启动新会话
tmux new -s work           # 创建名为 "work" 的会话
tmux ls                    # 列出所有会话
tmux a                     # 连接到最近的会话
tmux a -t work             # 连接到指定会话
tmux kill-session -t work  # 删除会话

# 退出会话
exit                       # 或 Ctrl-d，退出并关闭当前会话
Ctrl-a d                   # 分离会话 (后台保留运行)
```

### 窗格操作 (前缀键: `Ctrl-a`)

| 快捷键 | 功能 |
|--------|------|
| `Ctrl-a d` | 分离会话 (后台运行) |
| `Ctrl-a \|` | 垂直分割 (左右) |
| `Ctrl-a -` | 水平分割 (上下) |
| `Ctrl-a h/j/k/l` | 切换窗格 (vim 风格) |
| `Ctrl-a x` | 关闭当前窗格 |
| `Ctrl-a z` | 最大化/还原窗格 |
| `Ctrl-a {` / `}` | 交换窗格位置 |

### 窗口操作

| 快捷键 | 功能 |
|--------|------|
| `Ctrl-a c` | 新建窗口 |
| `Ctrl-a ,` | 重命名窗口 |
| `Ctrl-a n` / `p` | 下/上一个窗口 |
| `Ctrl-a 0-9` | 切换到指定窗口 |
| `Ctrl-a &` | 关闭当前窗口 |

### 其他

| 快捷键 | 功能 |
|--------|------|
| `Ctrl-a I` | 安装 TPM 插件 |
| `Ctrl-a r` | 重载配置 |
| `Ctrl-a [` | 进入复制模式 (可滚动) |
| `q` | 退出复制模式 |

---

## fzf 模糊搜索

```bash
Ctrl-t              # 在命令行中插入文件路径
Ctrl-r              # 模糊搜索历史命令
Alt-c               # 模糊搜索并进入目录

vim $(fzf)          # 用 fzf 选择文件并打开
cat file.txt | fzf  # 从输入中模糊选择
```

---

## zoxide 智能目录跳转

```bash
z foo           # 跳转到最常访问的包含 "foo" 的目录
z foo bar       # 跳转到包含多个关键词的目录
zi              # 交互式选择目录
z -             # 返回上一个目录
```

---

## mise 版本管理

```bash
# 安装语言版本
mise use python@3.12      # 安装并使用 Python 3.12
mise use node@22          # 安装并使用 Node.js 22
mise use node@lts         # 使用 LTS 版本

# 查看版本
mise list                 # 查看已安装版本
mise list python          # 查看已安装的 Python 版本

# 全局 vs 项目级
mise use -g python@3.12   # 全局默认
mise use python@3.11      # 当前目录 (创建 .mise.toml)

# 维护
mise outdated             # 检查过时版本
mise upgrade              # 升级所有工具
```

---

## Docker

```bash
# 容器操作
docker ps              # 查看运行中的容器
docker ps -a           # 查看所有容器
docker run -d nginx    # 后台运行容器
docker stop <id>       # 停止容器
docker rm <id>         # 删除容器

# 镜像操作
docker images          # 列出镜像
docker pull nginx      # 拉取镜像
docker rmi <image>     # 删除镜像

# 别名 (已配置)
dc up -d               # docker compose up -d
dc down                # docker compose down
dc logs -f             # docker compose logs -f
dps                    # docker ps
dimg                   # docker images
```

---

## ripgrep 代码搜索

```bash
rg "pattern"           # 递归搜索当前目录
rg "pattern" src/      # 搜索指定目录
rg -i "pattern"        # 忽略大小写
rg -t py "import"      # 只搜索 Python 文件
rg -l "pattern"        # 只显示文件名
rg -C 3 "pattern"      # 显示上下文 3 行
```

---

## 代理切换

```bash
proxy set http://127.0.0.1:7890   # 保存代理地址
proxy on                          # 开启代理
proxy off                         # 关闭代理
proxy status                      # 查看状态
```
