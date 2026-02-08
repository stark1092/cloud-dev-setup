#!/bin/bash
# ============================================
# 代理切换脚本 - proxy_toggle.sh
# 用法: source 后使用 proxy on/off/status/set
# ============================================

PROXY_CONFIG_FILE="$HOME/.proxy_config"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 加载保存的代理配置
_load_proxy_config() {
    if [[ -f "$PROXY_CONFIG_FILE" ]]; then
        source "$PROXY_CONFIG_FILE"
    fi
}

# 保存代理配置
_save_proxy_config() {
    echo "SAVED_PROXY_URL=\"$1\"" > "$PROXY_CONFIG_FILE"
}

# 显示当前代理状态
proxy_status() {
    echo -e "${BLUE}=== 代理状态 ===${NC}"
    if [[ -n "$HTTP_PROXY" ]]; then
        echo -e "${GREEN}✓ 代理已开启${NC}"
        echo -e "  HTTP_PROXY:  $HTTP_PROXY"
        echo -e "  HTTPS_PROXY: $HTTPS_PROXY"
        [[ -n "$NO_PROXY" ]] && echo -e "  NO_PROXY:    $NO_PROXY"
    else
        echo -e "${YELLOW}✗ 代理已关闭${NC}"
    fi
    
    _load_proxy_config
    if [[ -n "$SAVED_PROXY_URL" ]]; then
        echo -e "${BLUE}  已保存的代理地址: $SAVED_PROXY_URL${NC}"
    fi
}

# 开启代理
proxy_on() {
    _load_proxy_config
    local proxy_url="${1:-$SAVED_PROXY_URL}"
    
    if [[ -z "$proxy_url" ]]; then
        echo -e "${RED}错误: 未设置代理地址${NC}"
        echo -e "请先运行: ${YELLOW}proxy set http://your-proxy:port${NC}"
        return 1
    fi
    
    export HTTP_PROXY="$proxy_url"
    export HTTPS_PROXY="$proxy_url"
    export http_proxy="$proxy_url"
    export https_proxy="$proxy_url"
    export NO_PROXY="localhost,127.0.0.1,::1"
    export no_proxy="localhost,127.0.0.1,::1"
    
    echo -e "${GREEN}✓ 代理已开启: $proxy_url${NC}"
}

# 关闭代理
proxy_off() {
    unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy
    unset NO_PROXY no_proxy
    
    echo -e "${YELLOW}✗ 代理已关闭${NC}"
}

# 设置代理地址
proxy_set() {
    if [[ -z "$1" ]]; then
        echo -e "${RED}错误: 请提供代理地址${NC}"
        echo -e "用法: ${YELLOW}proxy set http://your-proxy:port${NC}"
        return 1
    fi
    
    _save_proxy_config "$1"
    echo -e "${GREEN}✓ 代理地址已保存: $1${NC}"
    echo -e "使用 ${YELLOW}proxy on${NC} 开启代理"
}

# 主函数
proxy() {
    case "$1" in
        on)
            proxy_on "$2"
            ;;
        off)
            proxy_off
            ;;
        status|st)
            proxy_status
            ;;
        set)
            proxy_set "$2"
            ;;
        *)
            echo -e "${BLUE}代理切换工具${NC}"
            echo "用法:"
            echo -e "  ${YELLOW}proxy on${NC}              开启代理 (使用已保存地址)"
            echo -e "  ${YELLOW}proxy on <url>${NC}        开启代理 (指定地址)"
            echo -e "  ${YELLOW}proxy off${NC}             关闭代理"
            echo -e "  ${YELLOW}proxy status${NC}          查看当前状态"
            echo -e "  ${YELLOW}proxy set <url>${NC}       保存代理地址"
            echo ""
            echo "示例:"
            echo -e "  ${YELLOW}proxy set http://127.0.0.1:7890${NC}"
            echo -e "  ${YELLOW}proxy on${NC}"
            ;;
    esac
}

# 如果直接执行脚本，显示帮助
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "此脚本需要被 source 加载后使用"
    echo "请将以下行添加到 ~/.zshrc 或 ~/.bashrc:"
    echo ""
    echo "  source ~/.local/bin/proxy_toggle.sh"
    echo ""
    echo "然后使用 'proxy' 命令"
fi
