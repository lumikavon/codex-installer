#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Codex One-Click Installer
# 支持系统: Ubuntu, OpenEuler, RockyLinux, CentOS, Debian, Fedora 等
# 功能: 一键安装 Node.js 和 Codex，包括配置 MCP Servers
# ============================================================================

# Simple logging helpers
_now() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
show_step() { printf "\n==> %s\n" "$1"; }
log_info() { printf "%s [INFO] %s\n" "$(_now)" "$1"; }
log_warning() { printf "%s [WARN] %s\n" "$(_now)" "$1"; }
log_error() { printf "%s [ERROR] %s\n" "$(_now)" "$1"; }
log_success() { printf "%s [OK] %s\n" "$(_now)" "$1"; }

die() { log_error "$1"; exit 1; }
command_exists() { command -v "$1" >/dev/null 2>&1; }

# ============================================================================
# System Detection
# ============================================================================

detect_os() {
    if [ -f /etc/os-release ]; then
        # source /etc/os-release may have issues with some bash settings
        . /etc/os-release
        OS="${ID:-unknown}"
        OS_VERSION="${VERSION_ID:-}"
    elif [ -f /etc/redhat-release ]; then
        OS="rhel"
        OS_VERSION=""
    elif [ -f /etc/debian_version ]; then
        OS="debian"
        OS_VERSION=""
    else
        OS="unknown"
        OS_VERSION=""
    fi

    case "${OS,,}" in
        ubuntu|debian|raspbian)
            OS_FAMILY="debian"
            ;;
        fedora|rhel|rocky|centos|openeuler|almalinux)
            OS_FAMILY="redhat"
            ;;
        *)
            OS_FAMILY="unknown"
            ;;
    esac

    log_info "检测到系统: ${OS} (${OS_VERSION:-unknown})"
}

# ============================================================================
# System-specific package installation
# ============================================================================

install_system_dependencies() {
    show_step "安装系统依赖"

    case "${OS_FAMILY}" in
        debian)
            log_info "使用 apt 安装依赖"
            sudo apt-get update -qq || log_warning "apt-get update 失败，继续执行"
            sudo apt-get install -y -qq \
                curl wget git ca-certificates \
                xz-utils tar gzip \
                build-essential python3 \
                jq \
                2>/dev/null || log_warning "部分依赖安装失败，继续执行"
            ;;
        redhat)
            log_info "使用 yum/dnf 安装依赖"
            if command_exists dnf; then
                sudo dnf install -y \
                    curl wget git ca-certificates \
                    xz tar gzip \
                    gcc gcc-c++ make python3 \
                    jq \
                    2>/dev/null || log_warning "部分依赖安装失败，继续执行"
            else
                sudo yum install -y \
                    curl wget git ca-certificates \
                    xz tar gzip \
                    gcc gcc-c++ make python3 \
                    jq \
                    2>/dev/null || log_warning "部分依赖安装失败，继续执行"
            fi
            ;;
        *)
            log_warning "未识别的系统族: ${OS_FAMILY}，跳过系统依赖安装"
            ;;
    esac

    log_success "系统依赖安装步骤完成"
}

# ============================================================================
# Node.js Installation
# ============================================================================

get_node_download_url() {
    local arch
    arch="$(uname -m)"
    
    case "${arch}" in
        x86_64)
            echo "https://nodejs.org/dist/v22.18.0/node-v22.18.0-linux-x64.tar.xz"
            ;;
        aarch64|arm64)
            echo "https://nodejs.org/dist/v22.18.0/node-v22.18.0-linux-arm64.tar.xz"
            ;;
        armv7l)
            echo "https://nodejs.org/dist/v22.18.0/node-v22.18.0-linux-armv7l.tar.xz"
            ;;
        *)
            log_warning "不支持的架构: ${arch}，将使用 x64"
            echo "https://nodejs.org/dist/v22.18.0/node-v22.18.0-linux-x64.tar.xz"
            ;;
    esac
}

install_nodejs_from_source_archive() {
    show_step "安装 Node.js"

    local install_base="$HOME/.local"
    local node_version="v22.18.0"
    local node_dir_name="node-${node_version}-linux-$(uname -m)"
    local target_dir="$install_base/${node_dir_name}"
    local node_link="$install_base/node"
    local bashrc="$HOME/.bashrc"

    mkdir -p "$install_base" "$HOME/.local/bin"

    if [ -d "$target_dir" ]; then
        log_info "检测到已安装的 Node.js，跳过下载"
    else
        local download_url
        download_url="$(get_node_download_url)"
        local node_tar="${install_base}/${node_dir_name}.tar.xz"

        log_info "下载 Node.js 从: ${download_url}"
        if ! curl -fsSL -o "$node_tar" "$download_url"; then
            die "Node.js 下载失败: ${download_url}"
        fi

        log_info "解压 Node.js 到 ${install_base} ..."
        tar -xJf "$node_tar" -C "$install_base" || die "Node.js 解压失败"
        rm -f "$node_tar"
    fi

    ln -sfn "$target_dir" "$node_link"

    # 配置 PATH
    touch "$bashrc"
    # 清理旧配置
    sed -i '/# node environment (managed by initializer)/d' "$bashrc" 2>/dev/null || true
    sed -i '/export NODE_HOME=/d' "$bashrc" 2>/dev/null || true
    sed -i '/export PATH=.*NODE_HOME/d' "$bashrc" 2>/dev/null || true
    
    cat >> "$bashrc" <<'EOF_NODE'
# node environment (managed by initializer)
export NODE_HOME="$HOME/.local/node"
export PATH="$NODE_HOME/bin:$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"
EOF_NODE

    # 立刻生效当前会话
    export NODE_HOME="$node_link"
    export PATH="$NODE_HOME/bin:$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"

    log_info "Node 版本: $(node -v 2>/dev/null || echo 未知)"
    log_info "NPM  版本: $(npm -v 2>/dev/null || echo 未知)"

    # 配置 npm 镜像源
    log_info "配置 npm 镜像为 https://registry.npmmirror.com ..."
    npm config set registry https://registry.npmmirror.com --location=global 2>/dev/null || \
    npm config set registry https://registry.npmmirror.com -g 2>/dev/null || true

    log_success "Node.js 安装完成"
}

configure_npm_global() {
    show_step "配置 npm 全局环境"

    local prefix
    prefix="$(npm prefix -g 2>/dev/null || true)"
    if [ -z "${prefix}" ]; then
        log_warning "无法获取 npm 全局 prefix，将使用 ~/.npm-global"
        prefix="$HOME/.npm-global"
    fi

    if [ ! -w "${prefix}" ]; then
        log_info "当前 npm prefix 不可写: ${prefix}"
        log_info "将 npm prefix 切换为: $HOME/.npm-global"
        mkdir -p "$HOME/.npm-global" "$HOME/.npm-global/bin"
        npm config set prefix "$HOME/.npm-global" --location=user >/dev/null 2>&1 || \
        npm config set prefix "$HOME/.npm-global" >/dev/null 2>&1 || true
        export PATH="$HOME/.npm-global/bin:$PATH"
    fi

    local bashrc="$HOME/.bashrc"
    touch "$bashrc"
    if ! grep -q "\.npm-global/bin" "$bashrc" 2>/dev/null; then
        cat >>"$bashrc" <<'EOF_PATH'
# npm global bin (managed by initializer)
export PATH="$HOME/.npm-global/bin:$PATH"
EOF_PATH
        log_info "已配置 ~/.npm-global 到 ~/.bashrc"
    fi

    log_success "npm 全局环境配置完成"
}

install_package_managers() {
    show_step "安装 Yarn 和 Pnpm"

    log_info "全局安装 Yarn 和 Pnpm ..."
    npm install -g yarn pnpm --registry=https://registry.npmmirror.com || \
        log_warning "Yarn/Pnpm 安装失败，继续执行"

    # 配置 yarn 镜像
    if command_exists yarn; then
        yarn config set npmRegistryServer https://registry.npmmirror.com -H >/dev/null 2>&1 || \
        yarn config set registry https://registry.npmmirror.com >/dev/null 2>&1 || true
        log_info "Yarn 版本: $(yarn -v 2>/dev/null || echo 未知)"
    else
        log_warning "Yarn 未安装或未在 PATH 中"
    fi

    # 配置 pnpm 镜像
    if command_exists pnpm; then
        pnpm config set registry https://registry.npmmirror.com --global >/dev/null 2>&1 || true
        log_info "pnpm 版本: $(pnpm -v 2>/dev/null || echo 未知)"
    else
        log_warning "pnpm 未安装或未在 PATH 中"
    fi

    log_success "包管理器安装配置完成"
}

# ============================================================================
# Codex Installation
# ============================================================================

OPENAI_BASE_URL_DEFAULT="https://api.aicodemirror.com/api/codex/backend-api/codex"

sanitize_api_key() {
    local key="$1"
    key="${key//$'\r'/}"
    key="${key//$'\n'/}"
    key="$(printf '%s' "$key" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

    if printf '%s' "$key" | LC_ALL=C grep -q '[[:cntrl:]]'; then
        die "OPENAI_API_KEY 包含控制字符，请重新复制后再输入（不要包含换行/空字符）"
    fi

    printf '%s' "$key"
}

install_codex() {
    show_step "安装 Codex (@openai/codex)"

    if command_exists codex; then
        log_info "检测到已安装 codex: $(codex -V 2>/dev/null || echo unknown)"
        log_info "将尝试更新到最新版本"
    fi

    if command_exists npm; then
        npm install -g @openai/codex --registry=https://registry.npmmirror.com || \
            log_warning "Codex npm 安装失败，尝试备选方案"
        return 0
    fi

    if command_exists brew; then
        log_info "未检测到 npm，尝试使用 brew 安装 codex"
        brew install codex
        return 0
    fi

    die "未检测到 npm 或 brew，无法安装 codex。"
}

get_api_key() {
    local api_key="${1:-}"
    api_key="$(printf '%s' "$api_key" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if [ -n "${api_key}" ]; then
        sanitize_api_key "${api_key}"
        return 0
    fi

    api_key="${OPENAI_API_KEY:-}"
    api_key="$(printf '%s' "$api_key" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if [ -n "${api_key}" ]; then
        sanitize_api_key "${api_key}"
        return 0
    fi

    if [ -t 0 ]; then
        read -rp "请输入 OPENAI_API_KEY (将写入 ~/.codex/auth.json): " api_key
        api_key="$(printf '%s' "$api_key" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        echo
    fi

    if [ -z "${api_key}" ]; then
        die "未提供 OPENAI_API_KEY。请设置环境变量 OPENAI_API_KEY 或传参 --api-key。"
    fi

    sanitize_api_key "${api_key}"
}

write_codex_config() {
    show_step "写入 Codex 配置 (~/.codex)"

    local api_key="${1:-}"
    if [ -z "${api_key}" ]; then
        die "未提供 OPENAI_API_KEY。"
    fi

    local codex_dir="$HOME/.codex"

    rm -rf "${codex_dir}"
    mkdir -p "${codex_dir}"

    # auth.json
    rm -f "${codex_dir}/auth.json"
    if command_exists jq; then
        jq -n --arg key "${api_key}" '{OPENAI_API_KEY: $key}' >"${codex_dir}/auth.json"
    else
        local escaped_key
        escaped_key="${api_key//\\/\\\\}"
        escaped_key="${escaped_key//\"/\\\"}"
        printf '{\n  "OPENAI_API_KEY": "%s"\n}\n' "${escaped_key}" >"${codex_dir}/auth.json"
    fi

    # config.toml
    rm -f "${codex_dir}/config.toml"
    cat >"${codex_dir}/config.toml" <<'EOF'
model_provider = "aicodemirror"
model = "gpt-5.2"
model_reasoning_effort = "high"
disable_response_storage = true
preferred_auth_method = "apikey"

[model_providers.aicodemirror]
name = "aicodemirror"
base_url = "https://api.aicodemirror.com/api/codex/backend-api/codex"
wire_api = "responses"
EOF

    chmod 700 "${codex_dir}" || true
    chmod 600 "${codex_dir}/auth.json" "${codex_dir}/config.toml" || true

    log_success "已生成: ${codex_dir}/auth.json, ${codex_dir}/config.toml"
}

write_openai_env_to_bashrc() {
    show_step "写入 OpenAI 环境变量到 ~/.bashrc"

    local api_key="${1:-}"
    if [ -z "${api_key}" ]; then
        die "未提供 OPENAI_API_KEY。"
    fi

    api_key="$(sanitize_api_key "${api_key}")"

    local bashrc="$HOME/.bashrc"
    local begin_marker="# OPENAI Environment Variables (managed by initializer) - begin"
    local end_marker="# OPENAI Environment Variables (managed by initializer) - end"

    touch "$bashrc"

    local tmpfile
    tmpfile="$(mktemp)"
    awk -v begin="$begin_marker" -v end="$end_marker" '
        $0 == begin { skipping = 1; next }
        skipping && $0 == end { skipping = 0; next }
        !skipping { print }
    ' "$bashrc" >"$tmpfile" && mv "$tmpfile" "$bashrc" || rm -f "$tmpfile"

    {
        printf '%s\n' "${begin_marker}"
        printf 'export OPENAI_BASE_URL=%q\n' "${OPENAI_BASE_URL_DEFAULT}"
        printf 'export OPENAI_API_KEY=%q\n' "${api_key}"
        printf '%s\n' "${end_marker}"
    } >>"$bashrc"

    log_success "已写入 ~/.bashrc（新终端会生效）"
}

verify_codex() {
    show_step "验证 Codex 安装"

    if ! command_exists codex; then
        log_error "未找到 codex 命令。请运行: source ~/.bashrc"
        log_error "然后重新验证: codex -V"
        die "Codex 验证失败"
    fi

    codex -V
    log_success "Codex 验证成功"
}

configure_codex_mcp_servers() {
    show_step "配置 Codex MCP Servers"

    if ! command_exists codex; then
        log_warning "未找到 codex 命令，跳过 MCP 配置"
        return 0
    fi

    if ! command_exists npx; then
        log_warning "未找到 npx 命令，跳过基于 npx 的 MCP Server 配置"
        return 0
    fi

    # mcp-server-fetch（依赖 uvx）
    if command_exists uvx; then
        codex mcp add fetch -- uvx mcp-server-fetch || true
    else
        log_info "uvx 未安装，跳过 mcp-server-fetch"
    fi

    # Context7 MCP 服务器
    codex mcp add context7 -- npx -y @upstash/context7-mcp || true
    codex mcp add sequential-thinking -- npx -y @modelcontextprotocol/server-sequential-thinking || true
    codex mcp add playwright -- npx -y @playwright/mcp@latest || true
    codex mcp add chrome-devtools -- npx -y chrome-devtools-mcp@latest || true

    log_success "MCP Servers 配置步骤已执行"
}

# ============================================================================
# Help & Main
# ============================================================================

print_help() {
    cat <<'EOF'
用法: codex.install.sh [OPTIONS]

说明：
  一键安装 Node.js 和 Codex，支持多个 Linux 系统
  
选项：
  --api-key <key>     设置 OpenAI API Key（也可使用环境变量 OPENAI_API_KEY）
  --skip-nodejs       跳过 Node.js 安装
  --skip-codex        跳过 Codex 安装
  --skip-mcp          跳过 MCP Servers 配置
  -h, --help          显示本帮助

示例：
  # 完整安装
  ./codex.install.sh --api-key <your-api-key>

  # 使用环境变量
  export OPENAI_API_KEY=<your-api-key>
  ./codex.install.sh

  # 跳过某些步骤
  ./codex.install.sh --skip-mcp --api-key <your-api-key>
EOF
}

main() {
    local api_key="${OPENAI_API_KEY:-}"
    local skip_nodejs=false
    local skip_codex=false
    local skip_mcp=false
    local show_help=false

    while [ $# -gt 0 ]; do
        case "$1" in
            --api-key)
                shift || true
                api_key="${1:-}"
                ;;
            --skip-nodejs)
                skip_nodejs=true
                ;;
            --skip-codex)
                skip_codex=true
                ;;
            --skip-mcp)
                skip_mcp=true
                ;;
            -h|--help)
                show_help=true
                ;;
            *)
                ;;
        esac
        shift || true
    done

    if [ "${show_help}" = true ]; then
        print_help
        exit 0
    fi

    show_step "Codex 一键安装程序"
    log_info "系统: $(uname -s) $(uname -m)"

    detect_os
    install_system_dependencies

    if [ "${skip_nodejs}" = false ]; then
        install_nodejs_from_source_archive
        configure_npm_global
        install_package_managers
    else
        log_info "跳过 Node.js 安装（--skip-nodejs）"
    fi

    if [ "${skip_codex}" = false ]; then
        install_codex

        local resolved_api_key
        resolved_api_key="$(get_api_key "${api_key}")"
        write_codex_config "${resolved_api_key}"
        write_openai_env_to_bashrc "${resolved_api_key}"
        verify_codex

        if [ "${skip_mcp}" = false ]; then
            configure_codex_mcp_servers
        else
            log_info "跳过 MCP Servers 配置（--skip-mcp）"
        fi
    else
        log_info "跳过 Codex 安装（--skip-codex）"
    fi

    show_step "安装完成"
    log_success "请运行以下命令使环境变量生效："
    log_success "source ~/.bashrc"
    log_success ""
    log_success "然后在项目目录运行: codex"
}

# 支持通过管道执行（curl | bash）和直接运行
# 避免在 set -u 下读取未绑定的 BASH_SOURCE 数组元素
if (return 0 2>/dev/null); then
    : # sourced; do not run main
else
    main "$@"
fi
