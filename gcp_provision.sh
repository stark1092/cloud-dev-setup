#!/bin/bash
# ============================================
# GCP AI 开发工作站 - 自动化配置脚本
# 目标系统: Ubuntu 24.04 LTS
# ============================================

set -e  # 遇到错误立即退出

# === 颜色定义 ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# === 日志函数 ===
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "\n${PURPLE}==>${NC} ${PURPLE}$1${NC}"; }

# === 幂等检查函数 ===
command_exists() {
    command -v "$1" &> /dev/null
}

# === 前置检查 ===
preflight_check() {
    log_step "运行前置检查..."
    
    # 检查是否为 Ubuntu
    if [[ ! -f /etc/os-release ]]; then
        log_error "无法检测操作系统"
        exit 1
    fi
    
    source /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        log_warning "检测到非 Ubuntu 系统: $ID，脚本可能无法正常工作"
    else
        log_info "检测到 Ubuntu $VERSION_ID"
    fi
    
    # 检查 sudo 权限
    if ! sudo -v &> /dev/null; then
        log_error "需要 sudo 权限"
        exit 1
    fi
    log_success "前置检查通过"
}

# === Locale 配置 ===
setup_locale() {
    log_step "配置 Locale (UTF-8)..."
    
    if locale -a 2>/dev/null | grep -q "en_US.utf8"; then
        log_info "en_US.UTF-8 已存在"
    else
        sudo locale-gen en_US.UTF-8
    fi
    
    if locale -a 2>/dev/null | grep -q "zh_CN.utf8"; then
        log_info "zh_CN.UTF-8 已存在"
    else
        sudo locale-gen zh_CN.UTF-8 || log_warning "zh_CN.UTF-8 生成失败，继续执行"
    fi
    
    sudo update-locale LANG=en_US.UTF-8
    log_success "Locale 配置完成"
}

# === 系统更新 ===
system_update() {
    log_step "更新系统包..."
    sudo apt-get update -qq
    sudo apt-get upgrade -y -qq
    log_success "系统更新完成"
}

# === 安装基础包 ===
install_base_packages() {
    log_step "安装基础软件包..."
    
    local packages=(
        tmux
        zsh
        git
        curl
        wget
        build-essential
        btop
        jq
        tree
        ripgrep
        ca-certificates
        gnupg
        lsb-release
        unzip
    )
    
    sudo apt-get install -y -qq "${packages[@]}"
    log_success "基础包安装完成"
}

# === 安装 fzf ===
install_fzf() {
    log_step "安装 fzf..."
    
    if command_exists fzf; then
        log_info "fzf 已安装，跳过"
        return 0
    fi
    
    if [[ -d "$HOME/.fzf" ]]; then
        log_info "fzf 目录已存在，更新中..."
        cd "$HOME/.fzf" && git pull --quiet
    else
        git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
    fi
    
    "$HOME/.fzf/install" --all --no-bash --no-fish --key-bindings --completion --update-rc
    log_success "fzf 安装完成"
}

# === 安装 zoxide ===
install_zoxide() {
    log_step "安装 zoxide..."
    
    if command_exists zoxide; then
        log_info "zoxide 已安装，跳过"
        return 0
    fi
    
    curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
    log_success "zoxide 安装完成"
}

# === 安装 Docker ===
install_docker() {
    log_step "安装 Docker..."
    
    if command_exists docker; then
        log_info "Docker 已安装，跳过"
    else
        # 添加 Docker GPG 密钥
        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null || true
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
        
        # 添加 Docker 仓库
        echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
            $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
            sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        # 安装 Docker
        sudo apt-get update -qq
        sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        
        log_success "Docker 安装完成"
    fi
    
    # 添加用户到 docker 组
    if ! groups "$USER" | grep -q docker; then
        sudo usermod -aG docker "$USER"
        log_info "已将用户 $USER 添加到 docker 组 (需要重新登录生效)"
    fi
    
    # 启用 Docker 服务
    sudo systemctl enable docker --now 2>/dev/null || true
}

# === 安装 mise ===
install_mise() {
    log_step "安装 mise (多语言版本管理)..."
    
    if command_exists mise; then
        log_info "mise 已安装，跳过"
        return 0
    fi
    
    curl https://mise.run | sh
    
    # 确保 mise 在 PATH 中
    export PATH="$HOME/.local/bin:$PATH"
    
    log_success "mise 安装完成"
    log_info "使用示例: mise use python@3.12 / mise use node@22"
}

# === 安装 Oh My Zsh ===
install_ohmyzsh() {
    log_step "安装 Oh My Zsh..."
    
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        log_info "Oh My Zsh 已安装，跳过"
        return 0
    fi
    
    # 非交互式安装
    RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    
    log_success "Oh My Zsh 安装完成"
}

# === 安装 TPM (Tmux Plugin Manager) ===
install_tpm() {
    log_step "安装 TPM (Tmux Plugin Manager)..."
    
    local tpm_dir="$HOME/.tmux/plugins/tpm"
    
    if [[ -d "$tpm_dir" ]]; then
        log_info "TPM 已安装，更新中..."
        cd "$tpm_dir" && git pull --quiet
    else
        git clone https://github.com/tmux-plugins/tpm "$tpm_dir"
    fi
    
    log_success "TPM 安装完成"
    log_info "首次启动 tmux 后按 Ctrl-a + I 安装插件"
}

# === 部署配置文件 ===
deploy_configs() {
    log_step "部署配置文件..."
    
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # 部署 .tmux.conf
    if [[ -f "$script_dir/.tmux.conf" ]]; then
        cp "$script_dir/.tmux.conf" "$HOME/.tmux.conf"
        log_info "已部署 .tmux.conf"
    else
        log_warning "未找到 .tmux.conf，请手动创建"
    fi
    
    # 部署 proxy_toggle.sh
    mkdir -p "$HOME/.local/bin"
    if [[ -f "$script_dir/proxy_toggle.sh" ]]; then
        cp "$script_dir/proxy_toggle.sh" "$HOME/.local/bin/proxy_toggle.sh"
        chmod +x "$HOME/.local/bin/proxy_toggle.sh"
        log_info "已部署 proxy_toggle.sh"
    else
        log_warning "未找到 proxy_toggle.sh，请手动创建"
    fi
}

# === 配置 .zshrc ===
configure_zshrc() {
    log_step "配置 .zshrc..."
    
    local zshrc="$HOME/.zshrc"
    
    # 备份原有配置
    if [[ -f "$zshrc" ]]; then
        cp "$zshrc" "$zshrc.backup.$(date +%Y%m%d%H%M%S)"
    fi
    
    # 确保插件配置
    if grep -q "^plugins=" "$zshrc" 2>/dev/null; then
        sed -i 's/^plugins=.*/plugins=(git fzf zoxide)/' "$zshrc"
    fi
    
    # 添加自定义配置块
    local marker="# === GCP Workstation Config ==="
    if ! grep -q "$marker" "$zshrc" 2>/dev/null; then
        cat >> "$zshrc" << 'EOF'

# === GCP Workstation Config ===
# 修复 Ghostty 等新终端的兼容性（terminfo 缺失问题）
if [[ "$TERM" == "xterm-ghostty" ]] && ! infocmp "$TERM" &>/dev/null; then
    export TERM=xterm-256color
fi

# PATH
export PATH="$HOME/.local/bin:$PATH"

# mise 初始化
if command -v mise &> /dev/null; then
    eval "$(mise activate zsh)"
fi

# zoxide 初始化
if command -v zoxide &> /dev/null; then
    eval "$(zoxide init zsh)"
fi

# fzf 配置
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# 代理切换脚本
[ -f ~/.local/bin/proxy_toggle.sh ] && source ~/.local/bin/proxy_toggle.sh

# 修复删除键/退格键
bindkey "^[[3~" delete-char       # Delete 键
bindkey "^?" backward-delete-char  # Backspace 键
bindkey "^H" backward-delete-char  # Ctrl+H

# 别名
alias ll='ls -alh'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'

# Docker 别名
alias dc='docker compose'
alias dps='docker ps'
alias dimg='docker images'
# === End GCP Workstation Config ===
EOF
        log_info "已添加自定义配置到 .zshrc"
    else
        log_info ".zshrc 已包含自定义配置"
    fi
    
    log_success ".zshrc 配置完成"
}

# === SSH 保活配置 ===
configure_ssh_keepalive() {
    log_step "配置 SSH 保活..."
    
    local sshd_config="/etc/ssh/sshd_config"
    
    # 检查并添加 ClientAliveInterval
    if ! grep -q "^ClientAliveInterval" "$sshd_config" 2>/dev/null; then
        echo "ClientAliveInterval 60" | sudo tee -a "$sshd_config" > /dev/null
        echo "ClientAliveCountMax 3" | sudo tee -a "$sshd_config" > /dev/null
        sudo systemctl reload sshd 2>/dev/null || sudo systemctl reload ssh 2>/dev/null || true
        log_info "SSH 保活配置已添加"
    else
        log_info "SSH 保活已配置"
    fi
    
    log_success "SSH 配置完成"
}

# === 创建参考模板 ===
create_templates() {
    log_step "创建参考模板..."
    
    mkdir -p "$HOME/templates"
    
    # OpenClaw 模板
    cat > "$HOME/templates/openclaw.env" << 'EOF'
# OpenClaw 环境变量参考模板
# 实际配置请参考 OpenClaw 官方文档

ANTHROPIC_API_KEY=your_api_key_here
MODEL=claude-3-5-sonnet-20241022
MAX_TOKENS=8192

# 代理已通过 proxy_toggle.sh 全局管理
# 无需在此配置 HTTP_PROXY/HTTPS_PROXY
EOF

    # Claude Code 模板
    cat > "$HOME/templates/claude-code.env" << 'EOF'
# Claude Code 环境变量参考模板
# 实际配置请参考 Claude Code 官方文档

ANTHROPIC_API_KEY=your_api_key_here
CLAUDE_MODEL=claude-3-5-sonnet-20241022

# 代理已通过 proxy_toggle.sh 全局管理
# 无需在此配置 HTTP_PROXY/HTTPS_PROXY
EOF

    # README
    cat > "$HOME/templates/README.md" << 'EOF'
# 环境变量参考模板

此目录包含 AI Agent 的环境变量参考模板。

## 注意事项

1. **代理配置**: 已通过 `proxy_toggle.sh` 全局管理，无需在 `.env` 中重复配置
2. **实际路径**: 
   - OpenClaw: `~/.openclaw/.env` 或官方文档指定路径
   - Claude Code: 参见官方文档

## 使用方法

```bash
# 开启代理
proxy on

# 关闭代理  
proxy off

# 查看状态
proxy status
```
EOF

    log_success "参考模板创建完成: ~/templates/"
}

# === 设置默认 Shell ===
set_default_shell() {
    log_step "设置 Zsh 为默认 Shell..."
    
    local zsh_path=$(which zsh)
    
    if [[ "$SHELL" == "$zsh_path" ]]; then
        log_info "Zsh 已是默认 Shell"
        return 0
    fi
    
    # 确保 zsh 在 /etc/shells 中
    if ! grep -q "$zsh_path" /etc/shells; then
        echo "$zsh_path" | sudo tee -a /etc/shells > /dev/null
    fi
    
    chsh -s "$zsh_path"
    log_success "Zsh 已设为默认 Shell (重新登录后生效)"
}

# === 验证安装 ===
verify_installation() {
    log_step "验证安装..."
    
    local all_ok=true
    
    echo ""
    echo "组件状态检查:"
    echo "─────────────────────────────"
    
    for cmd in tmux zsh git curl docker btop fzf jq rg tree mise; do
        if command_exists "$cmd"; then
            echo -e "  ${GREEN}✓${NC} $cmd"
        else
            echo -e "  ${RED}✗${NC} $cmd"
            all_ok=false
        fi
    done
    
    # 检查 zoxide (可能在 ~/.local/bin)
    if command_exists zoxide || [[ -f "$HOME/.local/bin/zoxide" ]]; then
        echo -e "  ${GREEN}✓${NC} zoxide"
    else
        echo -e "  ${RED}✗${NC} zoxide"
        all_ok=false
    fi
    
    echo "─────────────────────────────"
    
    # 检查配置文件
    echo ""
    echo "配置文件检查:"
    echo "─────────────────────────────"
    
    for file in "$HOME/.tmux.conf" "$HOME/.local/bin/proxy_toggle.sh" "$HOME/.oh-my-zsh"; do
        if [[ -e "$file" ]]; then
            echo -e "  ${GREEN}✓${NC} $(basename $file)"
        else
            echo -e "  ${RED}✗${NC} $(basename $file)"
            all_ok=false
        fi
    done
    
    if [[ -d "$HOME/.tmux/plugins/tpm" ]]; then
        echo -e "  ${GREEN}✓${NC} TPM"
    else
        echo -e "  ${RED}✗${NC} TPM"
        all_ok=false
    fi
    
    echo "─────────────────────────────"
    
    if $all_ok; then
        log_success "所有组件安装成功!"
    else
        log_warning "部分组件安装可能存在问题"
    fi
}

# === 显示后续步骤 ===
show_next_steps() {
    echo ""
    echo -e "${PURPLE}════════════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}   安装完成! 后续步骤:${NC}"
    echo -e "${PURPLE}════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "1. ${YELLOW}重新登录${NC} 以使 Zsh 和 docker 组生效"
    echo ""
    echo -e "2. 首次启动 tmux 后，按 ${YELLOW}Ctrl-a + I${NC} 安装插件"
    echo ""
    echo -e "3. 配置代理 (如需要):"
    echo -e "   ${YELLOW}proxy set http://your-proxy:port${NC}"
    echo -e "   ${YELLOW}proxy on${NC}"
    echo ""
    echo -e "4. 安装 Python/Node.js 版本:"
    echo -e "   ${YELLOW}mise use python@3.12${NC}"
    echo -e "   ${YELLOW}mise use node@22${NC}"
    echo ""
    echo -e "📝 ${BLUE}建议配置 Git 身份:${NC}"
    echo -e "   git config --global user.name 'Your Name'"
    echo -e "   git config --global user.email 'your@email.com'"
    echo ""
    
    if [[ ! -f "$HOME/.ssh/id_ed25519" ]]; then
        echo -e "💡 ${BLUE}建议生成 SSH 密钥用于 GitHub:${NC}"
        echo -e "   ssh-keygen -t ed25519 -C 'your@email.com'"
        echo ""
    fi
    
    echo -e "${PURPLE}════════════════════════════════════════════════════════${NC}"
}

# === 主函数 ===
main() {
    echo ""
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║   GCP AI 开发工作站 - 自动化配置脚本                 ║${NC}"
    echo -e "${PURPLE}║   目标: Ubuntu 24.04 LTS                             ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    preflight_check
    setup_locale
    system_update
    install_base_packages
    install_fzf
    install_zoxide
    install_docker
    install_mise
    install_ohmyzsh
    install_tpm
    deploy_configs
    configure_zshrc
    configure_ssh_keepalive
    create_templates
    set_default_shell
    verify_installation
    show_next_steps
}

# 运行主函数
main "$@"
