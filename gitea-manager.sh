#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                    Gitea Tools Manager v1.0.0                                ║
# ║         一键部署 Gitea + Gitea Actions + PostgreSQL                           ║
# ║         自动检测更新 · 多架构支持 · 全自动配置                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
set -euo pipefail

# ─── 全局变量 ───────────────────────────────────────────────────────────────────
VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/gitea-manager.conf"
LOG_FILE="${SCRIPT_DIR}/gitea-manager.log"

# 颜色定义
declare -A C=(
    [R]='\033[0;31m'     # Red
    [G]='\033[0;32m'     # Green
    [Y]='\033[0;33m'     # Yellow
    [B]='\033[0;34m'     # Blue
    [P]='\033[0;35m'     # Purple
    [C]='\033[0;36m'     # Cyan
    [W]='\033[0;37m'     # White
    [RD]='\033[1;31m'    # Bold Red
    [GD]='\033[1;32m'    # Bold Green
    [YD]='\033[1;33m'    # Bold Yellow
    [BD]='\033[1;34m'    # Bold Blue
    [PD]='\033[1;35m'    # Bold Purple
    [CD]='\033[1;36m'    # Bold Cyan
    [WD]='\033[1;37m'    # Bold White
    [BG_R]='\033[41m'    # BG Red
    [BG_G]='\033[42m'    # BG Green
    [BG_B]='\033[44m'    # BG Blue
    [BG_P]='\033[45m'    # BG Purple
    [NC]='\033[0m'       # No Color
)

# 默认配置
GITEA_VERSION="latest"
GITEA_USER="gitea"
GITEA_HOME="/var/lib/gitea"
GITEA_BIN="/usr/local/bin/gitea"
GITEA_WORK_DIR="/var/lib/gitea"
GITEA_CUSTOM="/var/lib/gitea/custom"
GITEA_CONFIG="/etc/gitea/app.ini"
GITEA_HTTP_PORT="3000"
GITEA_SSH_PORT="22"
GITEA_DOMAIN="$(hostname -I 2>/dev/null | awk '{print $1}' || echo 'localhost')"
GITEA_ROOT_URL="http://${GITEA_DOMAIN}:${GITEA_HTTP_PORT}/"
GITEA_DB_TYPE="postgres"
GITEA_DB_HOST="127.0.0.1:5432"
GITEA_DB_NAME="gitea"
GITEA_DB_USER="gitea"
GITEA_DB_PASSWORD=""
GITEA_ADMIN_USER="gitea_admin"
GITEA_ADMIN_PASSWORD=""
GITEA_ADMIN_EMAIL="admin@${GITEA_DOMAIN}"

# Actions Runner
ACTIONS_RUNNER_ENABLED="true"
ACTIONS_RUNNER_VERSION="latest"
ACTIONS_RUNNER_LABELS="ubuntu-latest:docker://node:20-bullseye,ubuntu-22.04:docker://catthehacker/ubuntu:act-22.04"

# PostgreSQL
PG_VERSION=""
PG_DATA_DIR="/var/lib/postgresql/data"
PG_CONF_DIR="/etc/postgresql"

# 系统信息
ARCH=""
OS=""
OS_ID=""
OS_VERSION=""
TOTAL_STEPS=12
CURRENT_STEP=0

# ─── 工具函数 ───────────────────────────────────────────────────────────────────

# 日志写入
_log() {
    local level="$1" msg="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] ${msg}" >> "$LOG_FILE"
}

# ══════════════════════════════════════════════════════════════════════════════════
# 输出美化函数
# ══════════════════════════════════════════════════════════════════════════════════

banner() {
    clear 2>/dev/null || true
    echo -e "${C[BD]}"
    echo "  ██████╗ ██╗████████╗███████╗ █████╗ "
    echo " ██╔════╝ ██║╚══██╔══╝██╔════╝██╔══██╗"
    echo " ██║  ███╗██║   ██║   █████╗  ███████║"
    echo " ██║   ██║██║   ██║   ██╔══╝  ██╔══██║"
    echo " ╚██████╔╝██║   ██║   ███████╗██║  ██║"
    echo "  ╚═════╝ ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝"
    echo -e "${C[NC]}"
    echo -e "${C[CD]}  Tools Manager ${C[W]}v${VERSION}"
    echo -e "${C[CD]}  Gitea + Actions Runner + PostgreSQL 一键部署"
    echo -e "${C[NC]}"
    draw_line "="
}

draw_line() {
    local char="${1:-─}"
    printf '%*s\n' "$(tput cols 2>/dev/null || echo 80)" | tr ' ' "$char"
}

draw_box_top() {
    local width=70
    printf "  ${C[BD]}╔%s╗${C[NC]}\n" "$(printf '%*s' "$width" | tr ' ' '═')"
}

draw_box_bottom() {
    local width=70
    printf "  ${C[BD]}╚%s╝${C[NC]}\n" "$(printf '%*s' "$width" | tr ' ' '═')"
}

draw_box_line() {
    local text="$1" color="${2:-${C[W]}}"
    printf "  ${C[BD]}║${C[NC]} ${color}%-67s${C[NC]} ${C[BD]}║${C[NC]}\n" "$text"
}

step_header() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo ""
    echo -e "${C[BD]}┌─ Step ${CURRENT_STEP}/${TOTAL_STEPS} ──────────────────────────────────────────────────────┐${C[NC]}"
    echo -e "${C[BD]}│${C[NC]} ${C[YD]}▶ $1${C[NC]}"
    echo -e "${C[BD]}└──────────────────────────────────────────────────────────────────────┘${C[NC]}"
}

ok() {
    echo -e "  ${C[G]}✔${C[NC]} ${C[W]}$1${C[NC]}"
}

info() {
    echo -e "  ${C[C]}ℹ${C[NC]} ${C[W]}$1${C[NC]}"
}

warn() {
    echo -e "  ${C[Y]}⚠${C[NC]} ${C[Y]}$1${C[NC]}"
}

error() {
    echo -e "  ${C[R]}✘${C[NC]} ${C[RD]}$1${C[NC]}"
}

progress() {
    local current="$1" total="$2" label="$3"
    local percent=$(( current * 100 / total ))
    local filled=$(( percent / 2 ))
    local empty=$(( 50 - filled ))
    printf "  ${C[C]}%-20s${C[NC]} ${C[BD]}[%s%s]${C[NC]} ${C[YD]}%3d%%${C[NC]}\r" \
        "$label" \
        "$(printf '%*s' "$filled" | tr ' ' '█')" \
        "$(printf '%*s' "$empty" | tr ' ' '░')" \
        "$percent"
    if [ "$current" -eq "$total" ]; then
        echo ""
    fi
}

# 显示表格
print_table_header() {
    printf "  ${C[BD]}%-30s │ %s${C[NC]}\n" "$1" "$2"
    printf "  %-30s─┼─%s\n" "$(printf '%*s' 30 | tr ' ' '─')" "$(printf '%*s' 38 | tr ' ' '─')"
}

print_table_row() {
    printf "  ${C[W]}%-30s${C[NC]} │ ${C[CD]}%s${C[NC]}\n" "$1" "$2"
}

# ─── 系统检测 ───────────────────────────────────────────────────────────────────

detect_os() {
    step_header "检测操作系统与架构"

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="$ID"
        OS_VERSION="$VERSION_ID"
        case "$ID" in
            ubuntu|debian)     OS="debian" ;;
            centos|rhel|rocky|almalinux|fedora|oracle) OS="rhel" ;;
            arch|manjaro)      OS="arch" ;;
            alpine)            OS="alpine" ;;
            opensuse*)         OS="suse" ;;
            *)                 OS="unknown" ;;
        esac
    elif [ "$(uname)" = "Darwin" ]; then
        OS="macos"
        OS_ID="macos"
    else
        OS="unknown"
        OS_ID="unknown"
    fi

    local machine
    machine="$(uname -m)"
    case "$machine" in
        x86_64|amd64)   ARCH="amd64" ;;
        aarch64|arm64)  ARCH="arm64" ;;
        armv7l)         ARCH="arm-5" ;;
        armv6l)         ARCH="arm-6" ;;
        i386|i686)      ARCH="386" ;;
        riscv64)        ARCH="riscv64" ;;
        loongarch64)    ARCH="loong64" ;;
        *)              ARCH="amd64"; warn "未知架构: $machine，默认使用 amd64" ;;
    esac

    ok "操作系统: ${OS_ID} ${OS_VERSION}  (${OS})"
    ok "CPU 架构:  ${ARCH}"
    _log "INFO" "Detected OS=${OS_ID}:${OS_VERSION} ARCH=${ARCH}"
}

detect_gpg_keyring() {
    # 检测可用的 GPG keyring 路径 (Gitea 用于验证签名)
    local paths=(
        "/usr/share/keyrings/gitea-archive-keyring.gpg"
        "/etc/apt/keyrings/gitea-archive-keyring.gpg"
    )
    for p in "${paths[@]}"; do
        local dir; dir="$(dirname "$p")"
        if [ -d "$dir" ]; then
            echo "$p"
            return 0
        fi
    done
    echo "/usr/share/keyrings/gitea-archive-keyring.gpg"
}

# ─── 依赖检查 ───────────────────────────────────────────────────────────────────

install_dependencies() {
    step_header "安装系统依赖"

    local deps="curl wget tar gzip git gnupg openssl"

    case "$OS" in
        debian)
            info "更新 apt 源..."
            apt-get update -qq 2>/dev/null
            info "安装依赖包..."
            apt-get install -y -qq $deps ca-certificates 2>/dev/null
            ;;
        rhel)
            if command -v dnf &>/dev/null; then
                dnf install -y -q $deps ca-certificates 2>/dev/null
            else
                yum install -y -q $deps ca-certificates 2>/dev/null
            fi
            ;;
        arch)
            pacman -S --noconfirm --needed $deps ca-certificates 2>/dev/null
            ;;
        *)
            warn "未知系统，请手动安装依赖: $deps"
            ;;
    esac

    ok "依赖安装完成"
}

# ─── PostgreSQL 安装 ─────────────────────────────────────────────────────────────

install_postgresql() {
    step_header "安装与配置 PostgreSQL"

    if command -v psql &>/dev/null; then
        ok "PostgreSQL 已安装: $(psql --version 2>/dev/null | head -1)"
        return 0
    fi

    case "$OS" in
        debian)
            info "从 apt 仓库安装 PostgreSQL..."
            apt-get install -y -qq postgresql postgresql-client 2>/dev/null
            ;;
        rhel)
            info "从 dnf 仓库安装 PostgreSQL..."
            dnf install -y -q postgresql-server postgresql 2>/dev/null || \
                yum install -y -q postgresql-server postgresql 2>/dev/null
            # 初始化数据库
            postgresql-setup --initdb 2>/dev/null || true
            ;;
        arch)
            pacman -S --noconfirm --needed postgresql 2>/dev/null
            # 初始化
            if [ ! -d "$PG_DATA_DIR" ]; then
                info "初始化 PostgreSQL 数据目录..."
                mkdir -p "$PG_DATA_DIR"
                chown postgres:postgres "$PG_DATA_DIR"
                su - postgres -c "initdb -D ${PG_DATA_DIR}" 2>/dev/null || true
            fi
            ;;
        *)
            error "不支持的发行版，请手动安装 PostgreSQL"
            return 1
            ;;
    esac

    # 启动服务
    info "启动 PostgreSQL 服务..."
    if command -v systemctl &>/dev/null; then
        systemctl enable postgresql 2>/dev/null || true
        systemctl start postgresql 2>/dev/null || \
            systemctl start postgresql-15 2>/dev/null || \
            systemctl start postgresql-16 2>/dev/null || true
    else
        service postgresql start 2>/dev/null || true
    fi

    ok "PostgreSQL $(psql --version 2>/dev/null | grep -oP '\d+\.\d+' || echo '?') 安装完成"
}

configure_postgresql() {
    step_header "配置 PostgreSQL 数据库与用户"

    # 生成随机密码
    if [ -z "$GITEA_DB_PASSWORD" ]; then
        GITEA_DB_PASSWORD="$(openssl rand -base64 24 | tr -d '/+=')"
    fi

    info "创建数据库用户: ${GITEA_DB_USER}"
    info "数据库名称:     ${GITEA_DB_NAME}"

    # 切换为 postgres 用户执行 SQL
    su - postgres -c "psql -tc \"SELECT 1 FROM pg_roles WHERE rolname='${GITEA_DB_USER}'\" 2>/dev/null" \
        | grep -q 1 || {
        su - postgres -c "psql -c \"CREATE ROLE ${GITEA_DB_USER} WITH LOGIN PASSWORD '${GITEA_DB_PASSWORD}';\""
    }

    # 创建数据库
    su - postgres -c "psql -tc \"SELECT 1 FROM pg_database WHERE datname='${GITEA_DB_NAME}'\" 2>/dev/null" \
        | grep -q 1 || {
        su - postgres -c "psql -c \"CREATE DATABASE ${GITEA_DB_NAME} OWNER ${GITEA_DB_USER} ENCODING 'UTF8' LC_COLLATE='en_US.UTF-8' LC_CTYPE='en_US.UTF-8' TEMPLATE=template0;\""
    }

    # 授权
    su - postgres -c "psql -c \"GRANT ALL PRIVILEGES ON DATABASE ${GITEA_DB_NAME} TO ${GITEA_DB_USER};\""
    su - postgres -c "psql -c \"GRANT ALL ON SCHEMA public TO ${GITEA_DB_USER};\" -d ${GITEA_DB_NAME}" 2>/dev/null || true

    # 确保 pg_hba.conf 使用 md5 认证
    local pg_hba
    pg_hba="$(su - postgres -c "psql -t -c 'SHOW hba_file;'" 2>/dev/null | tr -d ' ')" || true
    if [ -n "$pg_hba" ] && [ -f "$pg_hba" ]; then
        if ! grep -q "gitea" "$pg_hba" 2>/dev/null; then
            info "更新 pg_hba.conf 认证策略..."
            echo "# Gitea access" >> "$pg_hba"
            echo "host    ${GITEA_DB_NAME}    ${GITEA_DB_USER}    127.0.0.1/32    md5" >> "$pg_hba"
            echo "host    ${GITEA_DB_NAME}    ${GITEA_DB_USER}    ::1/128         md5" >> "$pg_hba"
            systemctl reload postgresql 2>/dev/null || \
                su - postgres -c "pg_ctl reload -D ${PG_DATA_DIR}" 2>/dev/null || true
        fi
    fi

    # 测试连接
    if PGPASSWORD="$GITEA_DB_PASSWORD" psql -h 127.0.0.1 -U "$GITEA_DB_USER" -d "$GITEA_DB_NAME" -c "SELECT 1;" &>/dev/null; then
        ok "数据库连接测试通过"
    else
        warn "数据库连接测试失败，但将继续配置"
    fi

    # 保存密码到配置文件
    save_config
}

# ─── Gitea 安装 ─────────────────────────────────────────────────────────────────

fetch_gitea_version() {
    # 获取最新版本号
    if [ "$GITEA_VERSION" = "latest" ]; then
        info "获取 Gitea 最新版本..."
        GITEA_VERSION=$(curl -sSL https://api.github.com/repos/go-gitea/gitea/releases/latest \
            | grep -oP '"tag_name":\s*"\K[^"]+' | sed 's/^v//')
        if [ -z "$GITEA_VERSION" ]; then
            error "无法获取最新版本号，使用默认版本 1.22.0"
            GITEA_VERSION="1.22.0"
        fi
    fi
    info "Gitea 版本: v${GITEA_VERSION}"
}

download_gitea() {
    step_header "下载 Gitea v${GITEA_VERSION}"

    local base_url="https://dl.gitea.com/gitea/${GITEA_VERSION}"
    local binary_name="gitea-${GITEA_VERSION}-${OS_ID}-${ARCH}"
    local gpg_url="${base_url}/${binary_name}.asc"
    local checksum_url="${base_url}/gitea-${GITEA_VERSION}-${OS_ID}-${ARCH}.sha256"
    local download_url="${base_url}/${binary_name}"

    # 某些旧版本用 linux 前缀
    if ! curl -sI "$download_url" 2>/dev/null | grep -q "200 OK"; then
        download_url="${base_url}/gitea-${GITEA_VERSION}-linux-${ARCH}"
        gpg_url="${base_url}/gitea-${GITEA_VERSION}-linux-${ARCH}.asc"
    fi

    info "下载地址: ${download_url}"
    info "保存位置: ${GITEA_BIN}"

    # 下载
    curl -fSL# -o "${GITEA_BIN}.tmp" "$download_url" || {
        error "下载失败!"
        return 1
    }

    # 验证（可选）
    if curl -fsSL "${checksum_url}" -o "/tmp/gitea-sha256" 2>/dev/null; then
        local expected
        expected=$(awk '{print $1}' /tmp/gitea-sha256)
        local actual
        actual=$(sha256sum "${GITEA_BIN}.tmp" | awk '{print $1}')
        if [ "$expected" = "$actual" ]; then
            ok "SHA256 校验通过"
        else
            warn "SHA256 校验失败，但仍继续"
        fi
        rm -f /tmp/gitea-sha256
    fi

    # 安装
    chmod +x "${GITEA_BIN}.tmp"
    mv "${GITEA_BIN}.tmp" "$GITEA_BIN"

    ok "Gitea v${GITEA_VERSION} 下载安装完成"
}

setup_gitea_user() {
    step_header "创建 Gitea 系统用户"

    if id "$GITEA_USER" &>/dev/null; then
        ok "用户 ${GITEA_USER} 已存在"
        return 0
    fi

    case "$OS" in
        debian|rhel|arch)
            useradd --system --create-home --home-dir "$GITEA_HOME" \
                --shell /bin/bash --comment "Gitea user" "$GITEA_USER" 2>/dev/null || \
                adduser --system --home "$GITEA_HOME" --group "$GITEA_USER" 2>/dev/null
            ;;
        *)
            adduser --system --home "$GITEA_HOME" --group "$GITEA_USER" 2>/dev/null || true
            ;;
    esac

    ok "用户 ${GITEA_USER} 创建完成"
}

setup_directories() {
    step_header "创建 Gitea 目录结构"

    mkdir -p "${GITEA_HOME}/custom" \
             "${GITEA_HOME}/data" \
             "${GITEA_HOME}/log" \
             "${GITEA_HOME}/repositories" \
             "${GITEA_HOME}/gitea-repositories" \
             "${GITEA_CUSTOM}/conf" \
             /etc/gitea

    chown -R "${GITEA_USER}:${GITEA_USER}" "$GITEA_HOME" /etc/gitea
    chmod 750 "$GITEA_HOME"

    ok "目录结构创建完成"
}

generate_gitea_config() {
    step_header "生成 Gitea 配置文件"

    local secret_key
    secret_key="$(openssl rand -base64 48 | tr -d '/+=')"

    cat > "$GITEA_CONFIG" << EOF
; ════════════════════════════════════════════════
;  Gitea Configuration — Generated by Tools Manager
;  Version: ${GITEA_VERSION}
;  Date:     $(date '+%Y-%m-%d %H:%M:%S')
; ════════════════════════════════════════════════

[APP_NAME]
APP_NAME        = Gitea: Git with a cup of tea
RUN_USER        = ${GITEA_USER}
RUN_MODE        = prod

[repository]
ROOT            = ${GITEA_HOME}/repositories
DEFAULT_BRANCH  = main

[repository.local]
LOCAL_COPY_PATH = ${GITEA_HOME}/gitea-repositories

[server]
PROTOCOL        = http
DOMAIN          = ${GITEA_DOMAIN}
ROOT_URL        = ${GITEA_ROOT_URL}
HTTP_ADDR       = 0.0.0.0
HTTP_PORT       = ${GITEA_HTTP_PORT}
SSH_DOMAIN      = ${GITEA_DOMAIN}
SSH_PORT        = ${GITEA_SSH_PORT}
SSH_LISTEN_PORT = ${GITEA_SSH_PORT}
START_SSH_SERVER = true
OFFLINE_MODE     = false
LANDING_PAGE     = explore

[database]
DB_TYPE         = postgres
HOST            = ${GITEA_DB_HOST}
NAME            = ${GITEA_DB_NAME}
USER            = ${GITEA_DB_USER}
PASSWD          = ${GITEA_DB_PASSWORD}
SSL_MODE        = disable
LOG_SQL         = false

[security]
INSTALL_LOCK          = true
SECRET_KEY            = ${secret_key}
INTERNAL_TOKEN        = $(openssl rand -base64 36 | tr -d '/+=')
PASSWORD_HASH_ALGO    = pbkdf2
MIN_PASSWORD_LENGTH   = 8

[service]
DISABLE_REGISTRATION  = false
REQUIRE_SIGNIN_VIEW   = false
REGISTER_EMAIL_CONFIRM = false
ENABLE_NOTIFY_MAIL    = false
DEFAULT_KEEP_EMAIL_PRIVATE = false
NO_REPLY_ADDRESS      = noreply.${GITEA_DOMAIN}

[mailer]
ENABLED         = false

[session]
PROVIDER        = db

[picture]
DISABLE_GRAVATAR        = false
ENABLE_FEDERATED_AVATAR = true

[log]
MODE            = file
LEVEL           = Info
ROOT_PATH       = ${GITEA_HOME}/log

[actions]
ENABLED         = true
DEFAULT_ACTIONS_URL = https://github.com

[other]
SHOW_FOOTER_VERSION = true
EOF

    chown "${GITEA_USER}:${GITEA_USER}" "$GITEA_CONFIG"
    chmod 640 "$GITEA_CONFIG"

    ok "配置文件已生成: ${GITEA_CONFIG}"
}

create_systemd_service() {
    step_header "创建 Systemd 服务"

    cat > /etc/systemd/system/gitea.service << EOF
[Unit]
Description=Gitea (Git with a cup of tea)
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=${GITEA_USER}
Group=${GITEA_USER}
WorkingDirectory=${GITEA_WORK_DIR}
ExecStart=${GITEA_BIN} web --config ${GITEA_CONFIG}
Restart=always
RestartSec=5
Environment=USER=${GITEA_USER}
Environment=HOME=${GITEA_HOME}
Environment=GITEA_WORK_DIR=${GITEA_WORK_DIR}
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable gitea 2>/dev/null || true

    ok "Systemd 服务已创建: gitea.service"
}

# ─── Gitea Actions Runner ────────────────────────────────────────────────────────

setup_actions_runner() {
    step_header "配置 Gitea Actions Runner"

    if [ "$ACTIONS_RUNNER_ENABLED" != "true" ]; then
        info "Actions Runner 已禁用，跳过"
        return 0
    fi

    # 安装 Docker (Actions Runner 需要)
    if ! command -v docker &>/dev/null; then
        info "安装 Docker..."
        case "$OS" in
            debian)
                apt-get install -y -qq docker.io docker-compose 2>/dev/null || \
                    curl -fsSL https://get.docker.com | bash -s
                ;;
            rhel)
                dnf install -y -q docker docker-compose 2>/dev/null || \
                    curl -fsSL https://get.docker.com | bash -s
                ;;
            arch)
                pacman -S --noconfirm --needed docker docker-compose 2>/dev/null
                ;;
            *)
                curl -fsSL https://get.docker.com | bash -s 2>/dev/null
                ;;
        esac
        systemctl enable docker 2>/dev/null || true
        systemctl start docker 2>/dev/null || true
        ok "Docker 安装完成"
    else
        ok "Docker 已安装"
    fi

    # 将 gitea 用户加入 docker 组
    usermod -aG docker "$GITEA_USER" 2>/dev/null || true

    # 下载并安装 act_runner
    info "下载 Gitea Actions Runner..."
    local runner_arch="$ARCH"
    local runner_version="$ACTIONS_RUNNER_VERSION"

    if [ "$runner_version" = "latest" ]; then
        runner_version=$(curl -sSL https://gitea.com/api/v1/repos/gitea/act_runner/releases/latest \
            | grep -oP '"tag_name":\s*"\K[^"]+' | sed 's/^v//')
        [ -z "$runner_version" ] && runner_version="0.2.11"
    fi

    # 架构映射
    case "$runner_arch" in
        amd64)  runner_arch="amd64" ;;
        arm64)  runner_arch="arm64" ;;
        arm-5)  runner_arch="armv5" ;;
        arm-6)  runner_arch="armv6" ;;
        *)      runner_arch="amd64" ;;
    esac

    local runner_url="https://gitea.com/gitea/act_runner/releases/download/v${runner_version}/act_runner-${runner_version}-linux-${runner_arch}"
    curl -fsSL -o /usr/local/bin/act_runner "$runner_url" 2>/dev/null || {
        # 尝试备用地址
        curl -fsSL -o /usr/local/bin/act_runner \
            "https://dl.gitea.com/act_runner/${runner_version}/act_runner-${runner_version}-linux-${runner_arch}" 2>/dev/null || true
    }
    chmod +x /usr/local/bin/act_runner 2>/dev/null || true

    if [ -x /usr/local/bin/act_runner ]; then
        ok "Actions Runner v${runner_version} 安装完成"
    else
        warn "Actions Runner 下载失败，请稍后手动安装"
        return 0
    fi

    # 生成 runner 配置
    local runner_config="${GITEA_HOME}/.runner"
    mkdir -p "$runner_config"

    # 注册 Runner（需要在 Gitea 运行后执行）
    # 创建注册脚本
    cat > "${GITEA_HOME}/register-runner.sh" << 'REGISTER'
#!/usr/bin/env bash
# Gitea Runner 注册脚本
# 在 Gitea 启动后运行此脚本获取 Runner Token 并注册

set -euo pipefail

GITEA_URL="http://localhost:${GITEA_HTTP_PORT:-3000}"
RUNNER_CONFIG="/var/lib/gitea/.runner"
RUNNER_LABELS="${ACTIONS_RUNNER_LABELS:-ubuntu-latest:docker://node:20-bullseye}"

echo "请在 Gitea 管理后台获取 Runner Token:"
echo "  Site Administration → Actions → Runners → Create new Runner"
echo ""
read -rp "请输入 Runner Registration Token: " TOKEN

if [ -z "$TOKEN" ]; then
    echo "错误: Token 不能为空"
    exit 1
fi

/usr/local/bin/act_runner register \
    --no-interactive \
    --instance "$GITEA_URL" \
    --token "$TOKEN" \
    --name "gitea-runner-$(hostname)" \
    --labels "$RUNNER_LABELS" \
    --config "${RUNNER_CONFIG}/config.yaml"

echo "Runner 注册成功!"
echo "配置文件: ${RUNNER_CONFIG}/config.yaml"
REGISTER

    chmod +x "${GITEA_HOME}/register-runner.sh"
    chown "${GITEA_USER}:${GITEA_USER}" -R "$runner_config"

    # 创建 Runner systemd 服务（延迟启动，等 Gitea 注册完）
    cat > /etc/systemd/system/gitea-actions-runner.service << EOF
[Unit]
Description=Gitea Actions Runner
After=gitea.service docker.service
Wants=gitea.service docker.service

[Service]
Type=simple
User=${GITEA_USER}
Group=${GITEA_USER}
WorkingDirectory=${GITEA_HOME}
ExecStart=/usr/local/bin/act_runner daemon --config ${GITEA_HOME}/.runner/config.yaml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    ok "Actions Runner 配置完成 (待注册)"
    info "安装后运行: ${GITEA_HOME}/register-runner.sh"
}

# ─── Gitea 管理用户 ──────────────────────────────────────────────────────────────

create_admin_user() {
    step_header "创建 Gitea 管理员用户"

    if [ -z "$GITEA_ADMIN_PASSWORD" ]; then
        GITEA_ADMIN_PASSWORD="$(openssl rand -base64 16 | tr -d '/+=')"
    fi

    info "管理员: ${GITEA_ADMIN_USER}"
    info "邮箱:    ${GITEA_ADMIN_EMAIL}"

    # 使用 gitea CLI 创建管理员
    su - "$GITEA_USER" -c "GITEA_WORK_DIR=${GITEA_WORK_DIR} ${GITEA_BIN} admin user create \
        --admin \
        --username '${GITEA_ADMIN_USER}' \
        --password '${GITEA_ADMIN_PASSWORD}' \
        --email '${GITEA_ADMIN_EMAIL}' \
        --config '${GITEA_CONFIG}' \
        --must-change-password=false" 2>/dev/null || {
        warn "管理员可能已存在，跳过创建"
        return 0
    }

    ok "管理员用户创建完成"
}

# ─── 启动服务 ───────────────────────────────────────────────────────────────────

start_services() {
    step_header "启动 Gitea 服务"

    info "启动 Gitea..."
    systemctl restart gitea

    # 等待服务就绪
    local max_retry=30
    local retry=0
    info "等待 Gitea 启动..."
    while [ $retry -lt $max_retry ]; do
        if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${GITEA_HTTP_PORT}" 2>/dev/null \
            | grep -qE "2[0-9][0-9]|3[0-9][0-9]|401|404"; then
            ok "Gitea 服务已就绪 (http://localhost:${GITEA_HTTP_PORT})"
            return 0
        fi
        sleep 2
        retry=$((retry + 1))
        progress "$retry" "$max_retry" "等待启动"
    done

    warn "Gitea 启动超时，请检查日志: journalctl -u gitea -f"
}

# ─── 配置持久化 ─────────────────────────────────────────────────────────────────

save_config() {
    cat > "$CONFIG_FILE" << EOF
# ════════════════════════════════════════════════
# Gitea Tools Manager Configuration
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
# ════════════════════════════════════════════════

GITEA_VERSION=${GITEA_VERSION}
GITEA_USER=${GITEA_USER}
GITEA_HOME=${GITEA_HOME}
GITEA_BIN=${GITEA_BIN}
GITEA_CONFIG=${GITEA_CONFIG}
GITEA_HTTP_PORT=${GITEA_HTTP_PORT}
GITEA_DOMAIN=${GITEA_DOMAIN}
GITEA_ROOT_URL=${GITEA_ROOT_URL}

GITEA_DB_TYPE=${GITEA_DB_TYPE}
GITEA_DB_HOST=${GITEA_DB_HOST}
GITEA_DB_NAME=${GITEA_DB_NAME}
GITEA_DB_USER=${GITEA_DB_USER}
GITEA_DB_PASSWORD=${GITEA_DB_PASSWORD}

GITEA_ADMIN_USER=${GITEA_ADMIN_USER}
GITEA_ADMIN_PASSWORD=${GITEA_ADMIN_PASSWORD}
GITEA_ADMIN_EMAIL=${GITEA_ADMIN_EMAIL}

ACTIONS_RUNNER_ENABLED=${ACTIONS_RUNNER_ENABLED}
ACTIONS_RUNNER_VERSION=${ACTIONS_RUNNER_VERSION}
EOF

    chmod 600 "$CONFIG_FILE"
}

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
    fi
}

# ─── 状态显示 ───────────────────────────────────────────────────────────────────

show_status() {
    echo ""
    draw_box_top
    draw_box_line "📊 Gitea 服务状态" "${C[YD]}"
    draw_box_line "$(printf '%*s' 67 | tr ' ' '-')"

    # Gitea 状态
    local gitea_status="未运行"
    if systemctl is-active --quiet gitea 2>/dev/null; then
        gitea_status="${C[G]}● 运行中${C[W]}"
    else
        gitea_status="${C[R]}○ 已停止${C[W]}"
    fi
    draw_box_line "Gitea:          ${gitea_status}"

    # PostgreSQL 状态
    local pg_status="未运行"
    if systemctl is-active --quiet postgresql 2>/dev/null || \
       systemctl is-active --quiet postgresql-* 2>/dev/null; then
        pg_status="${C[G]}● 运行中${C[W]}"
    else
        pg_status="${C[R]}○ 已停止${C[W]}"
    fi
    draw_box_line "PostgreSQL:     ${pg_status}"

    # Gitea 版本
    local installed_ver="$(${GITEA_BIN} --version 2>/dev/null | head -1 || echo 'N/A')"
    draw_box_line "Gitea 版本:     ${C[CD]}${installed_ver}${C[W]}"

    # Actions Runner
    local runner_status="未安装"
    if [ -x /usr/local/bin/act_runner ]; then
        runner_status="${C[G]}● 已安装${C[W]}"
    fi
    draw_box_line "Actions Runner: ${runner_status}"

    # 访问地址
    draw_box_line ""
    draw_box_line "访问地址: ${C[YD]}http://${GITEA_DOMAIN}:${GITEA_HTTP_PORT}/${C[W]}"

    draw_box_bottom
}

show_admin_info() {
    echo ""
    echo -e "  ${C[YD]}┌─────────────────────────────────────────────────────────────────────┐${C[NC]}"
    echo -e "  ${C[YD]}│                         🔐 管理员凭据                              │${C[NC]}"
    echo -e "  ${C[YD]}├─────────────────────────────────────────────────────────────────────┤${C[NC]}"
    echo -e "  ${C[YD]}│${C[NC]}  用户名: ${C[WD]}${GITEA_ADMIN_USER}${C[NC]}"
    echo -e "  ${C[YD]}│${C[NC]}  密码:   ${C[WD]}${GITEA_ADMIN_PASSWORD}${C[NC]}"
    echo -e "  ${C[YD]}│${C[NC]}  邮箱:   ${C[W]}${GITEA_ADMIN_EMAIL}${C[NC]}"
    echo -e "  ${C[YD]}│${C[NC]}                                                                    "
    echo -e "  ${C[YD]}│${C[NC]}  ${C[R]}⚠  请立即登录修改密码!${C[NC]}"
    echo -e "  ${C[YD]}│${C[NC]}  ${C[W]}配置文件: ${CONFIG_FILE}${C[NC]}"
    echo -e "  ${C[YD]}└─────────────────────────────────────────────────────────────────────┘${C[NC]}"
}

# ─── 更新功能 ───────────────────────────────────────────────────────────────────

check_update() {
    step_header "检查 Gitea 更新"

    info "当前安装版本: v$(load_config 2>/dev/null; echo "${GITEA_VERSION:-unknown}")"

    local latest
    latest=$(curl -sSL https://api.github.com/repos/go-gitea/gitea/releases/latest 2>/dev/null \
        | grep -oP '"tag_name":\s*"\K[^"]+' | sed 's/^v//')

    if [ -z "$latest" ]; then
        error "无法获取最新版本信息"
        return 1
    fi

    local current
    current=$("$GITEA_BIN" --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "0.0.0")

    echo ""
    print_table_header "项目" "版本"
    print_table_row "当前版本" "v${current}"
    print_table_row "最新版本" "v${latest}"

    if [ "$current" = "$latest" ]; then
        echo ""
        ok "已是最新版本! 🎉"
        return 0
    fi

    # 版本比较
    local newer
    newer=$(printf '%s\n%s\n' "$current" "$latest" | sort -V | tail -1)
    if [ "$newer" = "$latest" ] && [ "$current" != "$latest" ]; then
        echo ""
        echo -e "  ${C[YD]}┌─────────────────────────────────────────────────────────────────────┐${C[NC]}"
        echo -e "  ${C[YD]}│  ${C[RD]}🎯 发现新版本! v${current} → v${latest}${C[NC]}"
        echo -e "  ${C[YD]}│${C[NC]}  ${C[W]}运行 ${C[CD]}./gitea-manager.sh update${C[W]} 执行更新${C[NC]}"
        echo -e "  ${C[YD]}└─────────────────────────────────────────────────────────────────────┘${C[NC]}"
        return 2
    fi
}

do_update() {
    load_config 2>/dev/null

    echo -e "${C[BD]}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║       🔄 Gitea 自动更新程序              ║"
    echo "  ╚══════════════════════════════════════════╝"
    echo -e "${C[NC]}"

    # 设置新版本
    GITEA_VERSION="latest"
    fetch_gitea_version

    local old_version
    old_version=$("$GITEA_BIN" --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "?")

    if [ "$old_version" = "$GITEA_VERSION" ]; then
        ok "已是最新版 v${GITEA_VERSION}，无需更新"
        return 0
    fi

    info "更新: v${old_version} → v${GITEA_VERSION}"

    # 停止服务
    info "停止 Gitea 服务..."
    systemctl stop gitea 2>/dev/null || true

    # 备份
    info "备份配置文件..."
    cp "$GITEA_CONFIG" "${GITEA_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"

    # 下载新版本
    download_gitea

    # 更新版本号
    save_config

    # 启动服务
    info "启动 Gitea 服务..."
    systemctl start gitea

    # 等待就绪
    sleep 5
    local new_ver
    new_ver=$("$GITEA_BIN" --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "?")

    echo ""
    echo -e "  ${C[G]}┌─────────────────────────────────────────────────────────────────────┐${C[NC]}"
    echo -e "  ${C[G]}│                        ✅ 更新完成                                  │${C[NC]}"
    echo -e "  ${C[G]}├─────────────────────────────────────────────────────────────────────┤${C[NC]}"
    echo -e "  ${C[G]}│${C[NC]}  旧版本: v${old_version}"
    echo -e "  ${C[G]}│${C[NC]}  新版本: v${new_ver}"
    printf "  ${C[G]}│${C[NC]}  备份:   %s\n" "${GITEA_CONFIG}.bak.*"
    echo -e "  ${C[G]}└─────────────────────────────────────────────────────────────────────┘${C[NC]}"

    show_status
}

# ══════════════════════════════════════════════════════════════════════════════════
# 主安装流程
# ══════════════════════════════════════════════════════════════════════════════════

full_install() {
    banner

    # 检查 root
    if [ "$(id -u)" -ne 0 ]; then
        error "请以 root 权限运行此脚本!"
        echo "  sudo bash $0 install"
        exit 1
    fi

    echo ""
    echo -e "  ${C[YD]}即将开始一键部署:${C[NC]}"
    echo -e "  ${C[W]}  • Gitea (Git 服务)${C[NC]}"
    echo -e "  ${C[W]}  • PostgreSQL (数据库)${C[NC]}"
    echo -e "  ${C[W]}  • Gitea Actions Runner${C[NC]}"
    echo -e "  ${C[W]}  • Docker (Actions Runner 依赖)${C[NC]}"
    echo ""

    # 加载已有配置
    load_config 2>/dev/null || true

    # 检测
    detect_os

    # 检查是否已安装
    if [ -f "$GITEA_BIN" ]; then
        warn "检测到 Gitea 已安装"
        local cur_ver
        cur_ver=$("$GITEA_BIN" --version 2>/dev/null | head -1 || echo "unknown")
        info "当前版本: $cur_ver"
        read -rp $'  \033[1;33m是否重新安装/覆盖? [y/N]: \033[0m' confirm
        if [ "${confirm,,}" != "y" ] && [ "${confirm,,}" != "yes" ]; then
            info "已取消安装"
            show_status
            exit 0
        fi
    fi

    # 按顺序执行安装步骤
    install_dependencies
    install_postgresql
    configure_postgresql
    fetch_gitea_version
    setup_gitea_user
    setup_directories
    generate_gitea_config
    download_gitea
    create_systemd_service
    start_services
    create_admin_user
    setup_actions_runner

    save_config

    # ─── 完成 ──────────────────────────────────────────────────────
    echo ""
    echo -e "${C[GD]}"
    echo "  ╔══════════════════════════════════════════════════════════════╗"
    echo "  ║                                                              ║"
    echo "  ║              ✅ 安装全部完成!                                ║"
    echo "  ║                                                              ║"
    echo "  ╚══════════════════════════════════════════════════════════════╝"
    echo -e "${C[NC]}"

    show_status
    show_admin_info

    echo ""
    draw_line "─"
    echo -e "  ${C[W]}常用命令:${C[NC]}"
    echo -e "  ${C[CD]}systemctl status gitea${C[NC]}        查看 Gitea 状态"
    echo -e "  ${C[CD]}journalctl -u gitea -f${C[NC]}         查看 Gitea 日志"
    echo -e "  ${C[CD]}${GITEA_HOME}/register-runner.sh${C[NC]}    注册 Actions Runner"
    echo -e "  ${C[CD]}$0 check${C[NC]}                       检查更新"
    echo -e "  ${C[CD]}$0 update${C[NC]}                       更新到最新版本"
    echo -e "  ${C[CD]}$0 status${C[NC]}                       查看服务状态"
    draw_line "─"
    echo ""
    _log "INFO" "Installation completed successfully"
}

# ─── 后台更新守护 ───────────────────────────────────────────────────────────────

daemon_check() {
    # 后台定时检查更新（配合 cron 使用）
    local interval="${1:-86400}"  # 默认每天检查一次

    banner
    echo -e "  ${C[C]}📡 更新监控已启动 (间隔: ${interval}s)${C[NC]}"
    echo ""

    while true; do
        local latest current
        latest=$(curl -sSL https://api.github.com/repos/go-gitea/gitea/releases/latest 2>/dev/null \
            | grep -oP '"tag_name":\s*"\K[^"]+' | sed 's/^v//')
        current=$("$GITEA_BIN" --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "0.0.0")

        if [ -n "$latest" ] && [ "$current" != "$latest" ]; then
            echo -e "  ${C[YD]}$(date '+%Y-%m-%d %H:%M:%S') | 发现更新: v${current} → v${latest}${C[NC]}"
            _log "UPDATE" "New version available: v${current} → v${latest}"

            # 可选：自动更新
            # do_update
        else
            echo -e "  ${C[G]}$(date '+%Y-%m-%d %H:%M:%S') | 已是最新 v${current}${C[NC]}"
        fi

        sleep "$interval"
    done
}

# ══════════════════════════════════════════════════════════════════════════════════
# 命令路由
# ══════════════════════════════════════════════════════════════════════════════════

usage() {
    echo ""
    echo -e "${C[BD]}Gitea Tools Manager v${VERSION}${C[NC]}"
    echo ""
    echo -e "${C[YD]}用法:${C[NC]} $0 <命令> [选项]"
    echo ""
    echo -e "${C[WD]}命令:${C[NC]}"
    echo -e "  ${C[CD]}install${C[NC]}    一键安装 Gitea + PostgreSQL + Actions Runner"
    echo -e "  ${C[CD]}update${C[NC]}     更新 Gitea 到最新版本"
    echo -e "  ${C[CD]}check${C[NC]}      检查是否有新版本"
    echo -e "  ${C[CD]}status${C[NC]}     查看服务运行状态"
    echo -e "  ${C[CD]}config${C[NC]}     显示当前配置信息"
    echo -e "  ${C[CD]}watch${C[NC]}      后台监控更新 (可选参数: 检查间隔秒数)"
    echo -e "  ${C[CD]}uninstall${C[NC]}  卸载 Gitea 及相关服务"
    echo ""
    echo -e "${C[WD]}示例:${C[NC]}"
    echo -e "  sudo $0 install              # 完整安装"
    echo -e "  $0 check                     # 检查更新"
    echo -e "  $0 watch 43200               # 每12小时检查一次更新"
    echo ""
}

# 卸载
do_uninstall() {
    echo -e "${C[RD]}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║        ⚠  卸载 Gitea 所有组件           ║"
    echo "  ╚══════════════════════════════════════════╝"
    echo -e "${C[NC]}"
    echo ""
    echo -e "  ${C[R]}此操作将删除 Gitea、配置文件和数据库!${C[NC]}"
    read -rp "  请输入 'DELETE' 确认卸载: " confirm
    if [ "$confirm" != "DELETE" ]; then
        info "已取消"
        exit 0
    fi

    systemctl stop gitea 2>/dev/null || true
    systemctl stop gitea-actions-runner 2>/dev/null || true
    systemctl disable gitea 2>/dev/null || true
    systemctl disable gitea-actions-runner 2>/dev/null || true
    rm -f /etc/systemd/system/gitea.service
    rm -f /etc/systemd/system/gitea-actions-runner.service
    systemctl daemon-reload

    rm -f "$GITEA_BIN"
    rm -f /usr/local/bin/act_runner
    rm -rf "$GITEA_HOME"
    rm -rf /etc/gitea
    rm -f "$CONFIG_FILE"

    # 删除数据库
    su - postgres -c "psql -c 'DROP DATABASE IF EXISTS ${GITEA_DB_NAME};'" 2>/dev/null || true
    su - postgres -c "psql -c 'DROP ROLE IF EXISTS ${GITEA_DB_USER};'" 2>/dev/null || true

    userdel -r "$GITEA_USER" 2>/dev/null || true

    ok "卸载完成"
}

show_config() {
    load_config 2>/dev/null || true
    echo ""
    draw_box_top
    draw_box_line "📋 当前配置" "${C[YD]}"
    draw_box_line "$(printf '%*s' 67 | tr ' ' '-')"
    draw_box_line "Gitea 版本:    ${GITEA_VERSION:-N/A}"
    draw_box_line "域名:          ${GITEA_DOMAIN:-N/A}"
    draw_box_line "HTTP 端口:     ${GITEA_HTTP_PORT:-3000}"
    draw_box_line "数据库类型:    ${GITEA_DB_TYPE:-postgres}"
    draw_box_line "数据库主机:    ${GITEA_DB_HOST:-127.0.0.1}"
    draw_box_line "数据库名称:    ${GITEA_DB_NAME:-gitea}"
    draw_box_line "数据库用户:    ${GITEA_DB_USER:-gitea}"
    draw_box_line "管理员:        ${GITEA_ADMIN_USER:-N/A}"
    draw_box_line "Actions Runner: ${ACTIONS_RUNNER_ENABLED:-true}"
    draw_box_line "配置文件:      ${CONFIG_FILE}"
    draw_box_bottom
    echo ""
}

# ─── 主入口 ─────────────────────────────────────────────────────────────────────

main() {
    case "${1:-}" in
        install)
            full_install
            ;;
        update)
            do_update
            ;;
        check)
            load_config 2>/dev/null || true
            check_update
            ;;
        status)
            load_config 2>/dev/null || true
            banner
            show_status
            ;;
        config)
            banner
            show_config
            ;;
        watch)
            daemon_check "${2:-86400}"
            ;;
        uninstall)
            load_config 2>/dev/null || true
            do_uninstall
            ;;
        -h|--help|help|"")
            usage
            ;;
        *)
            echo -e "${C[R]}未知命令: $1${C[NC]}"
            usage
            exit 1
            ;;
    esac
}

main "$@"
