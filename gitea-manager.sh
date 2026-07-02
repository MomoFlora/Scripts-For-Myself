#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                         Gitea Tools Manager  v1.1.0                          ║
# ║          Gitea · Caddy · PostgreSQL · Actions Runner  —  一键部署             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# 架构: Linux amd64 | arm64 | armv7 | riscv64 | loong64
# 发行版: Debian | Ubuntu | RHEL | Rocky | Alma | Fedora | Arch
# 依赖: curl git wget gnupg openssl docker
#
set -euo pipefail
shopt -s extglob

# ──────────────────────────────────────────────────────────────────────────────
# 常量 & 默认值
# ──────────────────────────────────────────────────────────────────────────────
readonly SCRIPT_VERSION="1.1.0"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly CONFIG_FILE="${SCRIPT_DIR}/gitea-manager.conf"
readonly LOG_FILE="${SCRIPT_DIR}/gitea-manager.log"

# Gitea
GITEA_VERSION="${GITEA_VERSION:-latest}"
GITEA_USER="${GITEA_USER:-gitea}"
GITEA_HOME="${GITEA_HOME:-/var/lib/gitea}"
GITEA_BIN="${GITEA_BIN:-/usr/local/bin/gitea}"
GITEA_CONF="${GITEA_CONF:-/etc/gitea/app.ini}"
GITEA_LISTEN="${GITEA_LISTEN:-3000}"

# PostgreSQL
PG_HOST="${PG_HOST:-127.0.0.1}"
PG_PORT="${PG_PORT:-5432}"
PG_NAME="${PG_NAME:-gitea}"
PG_USER="${PG_USER:-gitea}"
PG_PASS="${PG_PASS:-}"

# Caddy
CADDY_ENABLE="${CADDY_ENABLE:-}"
CADDY_DOMAIN="${CADDY_DOMAIN:-}"

# Admin
ADMIN_USER="${ADMIN_USER:-gitea_admin}"
ADMIN_PASS="${ADMIN_PASS:-}"
ADMIN_MAIL="${ADMIN_MAIL:-}"

# Actions Runner
RUNNER_ENABLE="${RUNNER_ENABLE:-true}"

# 运行时
OS_ID=""; OS_VER=""; ARCH=""; TOTAL_STEPS=0; STEP=0
readonly WIDTH=64

# ──────────────────────────────────────────────────────────────
# ANSI 颜色 — 克制、专业的调色板
# ──────────────────────────────────────────────────────────────
C_RST=$'\033[0m'
C_DIM=$'\033[2m'
C_RED=$'\033[0;31m'
C_GRN=$'\033[0;32m'
C_YEL=$'\033[0;33m'
C_BLU=$'\033[0;34m'
C_CYN=$'\033[0;36m'
C_WHT=$'\033[0;37m'
C_BLD=$'\033[1m'
C_BRD=$'\033[1;31m'
C_BGN=$'\033[1;32m'
C_BYL=$'\033[1;33m'
C_BCY=$'\033[1;36m'
C_BWT=$'\033[1;37m'

# ──────────────────────────────────────────────────────────────
# 基础工具
# ──────────────────────────────────────────────────────────────
_log() { printf "[%(%F %T)T] %-7s %s\n" -1 "$1" "$2" >> "$LOG_FILE"; }

_hr() { printf "${C_DIM}%*s${C_RST}\n" "$WIDTH" "" | tr ' ' '-'; }

_title() { printf "\n${C_BCY}  %s${C_RST}\n" "$*"; _hr; }

_ok()   { printf "  ${C_GRN}✓${C_RST} %s\n" "$*"; }

_err()  { printf "  ${C_BRD}✗${C_RST} %s\n" "$*" >&2; }

_info() { printf "  ${C_DIM}→${C_RST} %s\n" "$*"; }

_warn() { printf "  ${C_BYL}!${C_RST} ${C_YEL}%s${C_RST}\n" "$*"; }

_step() {
    STEP=$((STEP + 1))
    printf "\n${C_BCY}  [%02d/%02d]${C_RST} ${C_BLD}%s${C_RST}\n" "$STEP" "$TOTAL_STEPS" "$*"
    _hr
}

# 交互式读取 (curl|bash safe)
_ask() {
    local prompt="$1" default="$2" input
    printf "%b" "$prompt" > /dev/tty 2>/dev/null || { printf '%s' "$default"; return 0; }
    read -r input < /dev/tty 2>/dev/null || { printf '%s' "$default"; return 0; }
    if [ -z "$input" ]; then input="$default"; fi
    printf '%s' "$input"
}

# 校验域名格式
_valid_domain() { [[ "$1" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; }

# ──────────────────────────────────────────────────────────────
# 系统探测
# ──────────────────────────────────────────────────────────────
detect_system() {
    _step "检测系统环境"

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="$ID"; OS_VER="${VERSION_ID:-}"
        case "$ID" in
            ubuntu|debian)             OS="debian" ;;
            centos|rhel|rocky|almalinux|fedora|oracle) OS="rhel" ;;
            arch|manjaro)              OS="arch" ;;
            *)                         OS="unknown" ;;
        esac
    else
        OS="unknown"; OS_ID="unknown"
    fi

    local machine; machine="$(uname -m)"
    case "$machine" in
        x86_64|amd64)  ARCH="amd64"  ;;
        aarch64|arm64) ARCH="arm64"  ;;
        armv7l)        ARCH="arm-6"  ;;
        armv6l)        ARCH="arm-6"  ;;
        riscv64)       ARCH="riscv64";;
        loongarch64)   ARCH="loong64";;
        *)             ARCH="amd64"; _warn "未知架构 $machine，回退到 amd64" ;;
    esac

    _ok "系统: ${OS_ID} ${OS_VER} · 架构: ${ARCH} · 内核: $(uname -r)"
    _log INFO "detect: OS=${OS_ID}:${OS_VER} ARCH=${ARCH}"
}

# ──────────────────────────────────────────────────────────────
# 依赖安装 (curl git docker ...)
# ──────────────────────────────────────────────────────────────
install_deps() {
    _step "安装系统依赖"

    local pkgs="curl wget ca-certificates git gnupg openssl"

    case "$OS" in
        debian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq 2>/dev/null || true
            apt-get install -y -qq -o Dpkg::Use-Pty=0 $pkgs 2>/dev/null
            if ! command -v docker &>/dev/null; then
                _info "安装 Docker..."
                apt-get install -y -qq -o Dpkg::Use-Pty=0 docker.io docker-compose-v2 2>/dev/null || \
                    curl -fsSL https://get.docker.com | bash -s 2>/dev/null
            fi
            ;;
        rhel)
            dnf install -y -q $pkgs 2>/dev/null || yum install -y -q $pkgs 2>/dev/null
            if ! command -v docker &>/dev/null; then
                dnf install -y -q docker docker-compose 2>/dev/null || \
                    curl -fsSL https://get.docker.com | bash -s 2>/dev/null
            fi
            ;;
        arch)
            pacman -S --noconfirm --needed $pkgs docker docker-compose 2>/dev/null
            ;;
        *)
            _warn "未知发行版，请手动安装: $pkgs docker"
            ;;
    esac

    # 启动 Docker
    if command -v docker &>/dev/null; then
        systemctl enable docker 2>/dev/null || true
        systemctl start docker 2>/dev/null || true
        _ok "Docker $(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',') 已就绪"
    fi

    _ok "系统依赖安装完成"
    _log INFO "deps installed"
}

# ──────────────────────────────────────────────────────────────
# Gitea 安装
# ──────────────────────────────────────────────────────────────
fetch_gitea_version() {
    if [ "$GITEA_VERSION" = "latest" ]; then
        GITEA_VERSION="$(curl -sSL https://api.github.com/repos/go-gitea/gitea/releases/latest \
            | grep -oP '"tag_name":\s*"\K[^"]+' | sed 's/^v//')"
        [ -z "$GITEA_VERSION" ] && { _warn "无法获取最新版本，使用 1.22.0"; GITEA_VERSION="1.22.0"; }
    fi
}

install_gitea() {
    _step "安装 Gitea"

    # ── 获取版本 ──
    fetch_gitea_version
    _info "目标版本: ${C_BCY}v${GITEA_VERSION}${C_RST}"

    # ── 下载二进制 ──
    local url="https://dl.gitea.com/gitea/${GITEA_VERSION}/gitea-${GITEA_VERSION}-linux-${ARCH}"
    _info "下载 ${url}"
    curl -fsSL -o "${GITEA_BIN}.tmp" "$url" || {
        _err "下载失败!"
        return 1
    }

    # SHA256 校验
    local sha_url="https://dl.gitea.com/gitea/${GITEA_VERSION}/gitea-${GITEA_VERSION}-linux-${ARCH}.sha256"
    if curl -fsSL "$sha_url" -o /tmp/gitea.sha256 2>/dev/null; then
        local expected; expected="$(awk '{print $1}' /tmp/gitea.sha256)"
        local actual; actual="$(sha256sum "${GITEA_BIN}.tmp" | awk '{print $1}')"
        if [ "$expected" = "$actual" ]; then
            _ok "SHA256 校验通过"
        else
            _warn "SHA256 不匹配，继续使用"
        fi
        rm -f /tmp/gitea.sha256
    fi

    chmod +x "${GITEA_BIN}.tmp"
    mv "${GITEA_BIN}.tmp" "$GITEA_BIN"
    _ok "Gitea 二进制安装到 ${GITEA_BIN}"

    # ── 创建系统用户 ──
    if ! id "$GITEA_USER" &>/dev/null; then
        useradd --system --home-dir "$GITEA_HOME" --shell /bin/bash --comment "Gitea" "$GITEA_USER" 2>/dev/null || \
            adduser --system --home "$GITEA_HOME" --group "$GITEA_USER" 2>/dev/null
        _ok "系统用户 ${GITEA_USER} 已创建"
    else
        _info "用户 ${GITEA_USER} 已存在"
    fi

    # ── 目录结构 ──
    mkdir -p "${GITEA_HOME}"/{custom/conf,data,log,repositories} /etc/gitea
    chown -R "${GITEA_USER}:${GITEA_USER}" "$GITEA_HOME" /etc/gitea
    chmod 750 "$GITEA_HOME"
    _ok "目录结构就绪"

    # ── systemd 服务 ──
    cat > /etc/systemd/system/gitea.service << SYSTEMD
[Unit]
Description=Gitea (Git Service)
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=${GITEA_USER}
Group=${GITEA_USER}
WorkingDirectory=${GITEA_HOME}
ExecStart=${GITEA_BIN} web --config ${GITEA_CONF}
Restart=always
RestartSec=5s
Environment=USER=${GITEA_USER}
Environment=HOME=${GITEA_HOME}
Environment=GITEA_WORK_DIR=${GITEA_HOME}
LimitNOFILE=65536
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
SYSTEMD
    systemctl daemon-reload
    systemctl enable gitea 2>/dev/null || true
    _ok "systemd 服务 gitea.service 已创建"

    _log INFO "gitea ${GITEA_VERSION} installed"
}

# ──────────────────────────────────────────────────────────────
# PostgreSQL 安装
# ──────────────────────────────────────────────────────────────
install_postgresql() {
    _step "安装 PostgreSQL 数据库"

    if command -v psql &>/dev/null; then
        _info "PostgreSQL 已安装: $(psql --version 2>/dev/null | head -1)"
    else
        case "$OS" in
            debian)
                apt-get install -y -qq -o Dpkg::Use-Pty=0 postgresql postgresql-client 2>/dev/null ;;
            rhel)
                dnf install -y -q postgresql-server postgresql 2>/dev/null || \
                    yum install -y -q postgresql-server postgresql 2>/dev/null
                postgresql-setup --initdb 2>/dev/null || true ;;
            arch)
                pacman -S --noconfirm --needed postgresql 2>/dev/null
                if [ ! -d /var/lib/postgres/data ]; then
                    su - postgres -c "initdb -D /var/lib/postgres/data" 2>/dev/null || true
                fi ;;
        esac
        _ok "PostgreSQL 安装完成"
    fi

    # 启动
    systemctl enable postgresql 2>/dev/null || true
    systemctl start postgresql 2>/dev/null || {
        # 尝试特定版本的服务名
        local svc; svc="$(systemctl list-units --type=service --all 2>/dev/null \
            | grep -oP 'postgresql.*\.service' | head -1 || true)"
        [ -n "$svc" ] && systemctl start "$svc" 2>/dev/null || true
    }
    _ok "PostgreSQL 服务已启动"

    # ── 生成密码 ──
    if [ -z "$PG_PASS" ]; then
        PG_PASS="$(openssl rand -base64 24 | tr -d '/+=')"
    fi

    # ── 创建角色 ──
    _info "创建数据库用户 ${PG_USER} ..."
    su - postgres -c "psql -tc \"SELECT 1 FROM pg_roles WHERE rolname='${PG_USER}'\"" 2>/dev/null \
        | grep -q 1 || {
        su - postgres -c "psql -q -c \"SET password_encryption='scram-sha-256'; CREATE ROLE ${PG_USER} LOGIN PASSWORD '${PG_PASS}';\""
    }

    # ── 创建数据库 ──
    _info "创建数据库 ${PG_NAME} ..."
    su - postgres -c "psql -tc \"SELECT 1 FROM pg_database WHERE datname='${PG_NAME}'\"" 2>/dev/null \
        | grep -q 1 || {
        su - postgres -c "psql -q -c \"CREATE DATABASE ${PG_NAME} OWNER ${PG_USER} ENCODING 'UTF8' LC_COLLATE='en_US.UTF-8' LC_CTYPE='en_US.UTF-8' TEMPLATE template0;\""
    }

    su - postgres -c "psql -c 'GRANT ALL PRIVILEGES ON DATABASE ${PG_NAME} TO ${PG_USER};'" >/dev/null
    su - postgres -c "psql -c 'GRANT ALL ON SCHEMA public TO ${PG_USER};' -d ${PG_NAME}" >/dev/null 2>&1 || true

    # ── pg_hba.conf — 插入到文件顶部 (PostgreSQL 用 first-match 策略) ──
    local hba; hba="$(su - postgres -c "psql -t -c 'SHOW hba_file;'" 2>/dev/null | tr -d ' ')" || true
    if [ -n "$hba" ] && [ -f "$hba" ]; then
        if ! grep -qF "gitea" "$hba" 2>/dev/null; then
            _info "配置 pg_hba.conf (scram-sha-256)..."
            # 备份原文件
            cp "$hba" "${hba}.bak.$(date +%Y%m%d%H%M%S)"
            # 插入到第一行 — 确保优先级高于任何 catch-all 规则
            sed -i "1i\
# Gitea — managed by gitea-manager\n\
host    ${PG_NAME}    ${PG_USER}    127.0.0.1/32    scram-sha-256\n\
host    ${PG_NAME}    ${PG_USER}    ::1/128         scram-sha-256\n\
" "$hba"
            systemctl reload postgresql 2>/dev/null || \
                su - postgres -c "pg_ctl reload -D /var/lib/postgresql/*/main/" 2>/dev/null || true
            sleep 1
            _ok "pg_hba.conf 已更新 (行首插入)"
        else
            _info "pg_hba.conf 已有 gitea 规则"
        fi
    fi

    # ── 连接测试 ──
    if PGPASSWORD="$PG_PASS" psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_NAME" -c "SELECT 1;" &>/dev/null; then
        _ok "数据库连接测试通过"
    else
        _err "数据库连接失败! pg_hba.conf 可能仍使用了错误的认证方式"
        _info "当前 pg_hba.conf 前 5 行:"
        if [ -n "$hba" ]; then head -5 "$hba" | while IFS= read -r l; do printf "    ${C_DIM}%s${C_RST}\n" "$l"; done; fi
        _info "手动修复: 确保 scram-sha-256 规则在 pg_hba.conf 的第一条有效行"
        _info "然后执行: systemctl reload postgresql"
    fi

    _log INFO "postgresql configured: ${PG_USER}@${PG_HOST}:${PG_PORT}/${PG_NAME}"
}

# ──────────────────────────────────────────────────────────────
# Gitea 配置生成
# ──────────────────────────────────────────────────────────────
write_gitea_config() {
    _step "生成 Gitea 配置文件"

    local secret; secret="$(openssl rand -base64 48 | tr -d '/+=')"
    local itoken; itoken="$(openssl rand -base64 36 | tr -d '/+=')"
    local domain root_url
    if [ "$CADDY_ENABLE" = "true" ] && [ -n "$CADDY_DOMAIN" ]; then
        domain="$CADDY_DOMAIN"
        root_url="https://${CADDY_DOMAIN}/"
    else
        domain="$(hostname -I 2>/dev/null | awk '{print $1}' || echo 'localhost')"
        root_url="http://${domain}:${GITEA_LISTEN}/"
    fi
    ADMIN_MAIL="${ADMIN_MAIL:-admin@${domain}}"

    cat > "$GITEA_CONF" << EOF
; ───────────────────────────────────────────────────
;  Gitea Configuration — Gitea Tools Manager v${SCRIPT_VERSION}
;  Generated: $(date '+%F %T')
; ───────────────────────────────────────────────────

APP_NAME   = Gitea: Git with a cup of tea
RUN_USER   = ${GITEA_USER}
RUN_MODE   = prod

[repository]
ROOT           = ${GITEA_HOME}/repositories
DEFAULT_BRANCH = main

[server]
PROTOCOL         = http
DOMAIN           = ${domain}
ROOT_URL         = ${root_url}
HTTP_ADDR        = 0.0.0.0
HTTP_PORT        = ${GITEA_LISTEN}
SSH_DOMAIN       = ${domain}
SSH_PORT         = 22
SSH_LISTEN_PORT  = 22
START_SSH_SERVER = true
LANDING_PAGE     = explore

[database]
DB_TYPE  = postgres
HOST     = ${PG_HOST}:${PG_PORT}
NAME     = ${PG_NAME}
USER     = ${PG_USER}
PASSWD   = ${PG_PASS}
SSL_MODE = disable
LOG_SQL  = false

[security]
INSTALL_LOCK       = true
SECRET_KEY         = ${secret}
INTERNAL_TOKEN     = ${itoken}
PASSWORD_HASH_ALGO = pbkdf2

[service]
DISABLE_REGISTRATION       = false
REQUIRE_SIGNIN_VIEW        = false
REGISTER_EMAIL_CONFIRM     = false
ENABLE_NOTIFY_MAIL         = false
DEFAULT_KEEP_EMAIL_PRIVATE = false

[session]
PROVIDER = db

[log]
MODE      = file
LEVEL     = Info
ROOT_PATH = ${GITEA_HOME}/log

[actions]
ENABLED = true
DEFAULT_ACTIONS_URL = github

[other]
SHOW_FOOTER_VERSION = true
EOF

    chown "${GITEA_USER}:${GITEA_USER}" "$GITEA_CONF"
    chmod 640 "$GITEA_CONF"
    _ok "配置文件 → ${GITEA_CONF}"
    _log INFO "gitea config written"
}

# ──────────────────────────────────────────────────────────────
# Caddy 安装 & 反代配置
# ──────────────────────────────────────────────────────────────
prompt_domain() {
    _step "域名配置"

    printf "\n  ${C_WHT}是否需要通过 Caddy 配置 HTTPS 反向代理？${C_RST}\n"
    printf "  ${C_DIM}Caddy 将自动申请 Let's Encrypt SSL 证书，实现 HTTPS 安全访问。${C_RST}\n"
    printf "  ${C_DIM}确保域名 DNS 已解析到此服务器 IP。${C_RST}\n\n"

    CADDY_DOMAIN="$(_ask "  ${C_BCY}域名 (留空跳过):${C_RST} " "")"

    if [ -z "$CADDY_DOMAIN" ]; then
        _info "跳过反向代理 — Gitea 将通过 HTTP 端口 ${GITEA_LISTEN} 访问"
        CADDY_ENABLE="false"
        return 0
    fi

    if ! _valid_domain "$CADDY_DOMAIN"; then
        _err "域名格式无效: ${CADDY_DOMAIN}"
        CADDY_DOMAIN=""
        CADDY_ENABLE="false"
        return 0
    fi

    CADDY_ENABLE="true"
    printf "\n"
    printf "  ${C_WHT}域名:${C_RST}    ${C_BCY}%s${C_RST}\n" "$CADDY_DOMAIN"
    printf "  ${C_WHT}访问地址:${C_RST}  ${C_BCY}https://%s${C_RST}\n" "$CADDY_DOMAIN"
    printf "  ${C_WHT}SSL 证书:${C_RST}  ${C_DIM}Let's Encrypt 自动管理${C_RST}\n"
    printf "\n"

    local confirm; confirm="$(_ask "  ${C_WHT}确认?${C_RST} ${C_DIM}[Y/n]${C_RST} " "y")"
    if [ "${confirm,,}" = "n" ]; then
        CADDY_ENABLE="false"; CADDY_DOMAIN=""
        _info "已取消域名配置"
        return 0
    fi

    _ok "域名配置完成: ${CADDY_DOMAIN}"
    _log INFO "domain: ${CADDY_DOMAIN}"
}

install_caddy() {
    _step "安装 Caddy 反向代理"

    if [ "$CADDY_ENABLE" != "true" ]; then
        _info "未配置域名，跳过"
        return 0
    fi

    if command -v caddy &>/dev/null; then
        _info "Caddy 已安装: $(caddy version 2>/dev/null | head -1)"
    else
        case "$OS" in
            debian)
                curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' 2>/dev/null \
                    | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null
                curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' 2>/dev/null \
                    > /etc/apt/sources.list.d/caddy-stable.list
                apt-get update -qq 2>/dev/null
                apt-get install -y -qq -o Dpkg::Use-Pty=0 caddy 2>/dev/null
                ;;
            rhel)
                dnf install -y -q 'dnf-command(copr)' 2>/dev/null || true
                dnf copr enable -y @caddy/caddy 2>/dev/null || true
                dnf install -y -q caddy 2>/dev/null
                ;;
            arch)
                pacman -S --noconfirm --needed caddy 2>/dev/null
                ;;
        esac
        _ok "Caddy 安装完成"
    fi

    # Caddyfile
    cat > /etc/caddy/Caddyfile << CADDYFILE
# ───────────────────────────────────────────────
#  Gitea reverse proxy — generated by gitea-manager
# ───────────────────────────────────────────────

${CADDY_DOMAIN} {
    log {
        output file /var/log/caddy/gitea.log
        level INFO
    }

    reverse_proxy localhost:${GITEA_LISTEN} {
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto https
        header_up X-Forwarded-Host ${CADDY_DOMAIN}
        header_up Connection {http.request.header.Connection}
    }

    header {
        X-Frame-Options "SAMEORIGIN"
        X-Content-Type-Options "nosniff"
        -Server
    }

    request_body {
        max_size 500MB
    }

    tls ${ADMIN_MAIL}
}
CADDYFILE
    _ok "Caddyfile → /etc/caddy/Caddyfile"

    # 验证配置
    if caddy validate --config /etc/caddy/Caddyfile &>/dev/null; then
        _ok "Caddy 配置验证通过"
    else
        _warn "Caddy 配置验证警告 (检查域名 DNS)"
    fi

    # 防火墙
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
        ufw allow 80/tcp comment "Caddy HTTP" 2>/dev/null || true
        ufw allow 443/tcp comment "Caddy HTTPS" 2>/dev/null || true
        _ok "UFW 防火墙已开放 80/443"
    elif command -v firewall-cmd &>/dev/null && firewall-cmd --state 2>/dev/null | grep -q "running"; then
        firewall-cmd --permanent --add-service=http --add-service=https 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
        _ok "Firewalld 已开放 HTTP/HTTPS"
    fi

    systemctl daemon-reload
    systemctl enable caddy 2>/dev/null || true
    _log INFO "caddy configured for ${CADDY_DOMAIN}"
}

# ──────────────────────────────────────────────────────────────
# 启动服务
# ──────────────────────────────────────────────────────────────
start_all_services() {
    _step "启动服务"

    # PostgreSQL (应该已在运行)
    systemctl is-active --quiet postgresql 2>/dev/null || \
        systemctl is-active --quiet postgresql-* 2>/dev/null || {
        _info "启动 PostgreSQL..."
        systemctl start postgresql 2>/dev/null || true
    }

    # Gitea
    _info "启动 Gitea..."
    systemctl restart gitea

    # 健康检查
    local retry=0 max=15
    while [ $retry -lt $max ]; do
        if curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${GITEA_LISTEN}" 2>/dev/null \
            | grep -qE "2[0-9]{2}|3[0-9]{2}|40[134]"; then
            _ok "Gitea 就绪 → http://127.0.0.1:${GITEA_LISTEN}"
            break
        fi
        retry=$((retry + 1))
        [ $retry -eq $max ] && {
            _err "Gitea 未能在 ${max}x2 秒内启动"
            _info "运行诊断..."
            printf "  ${C_DIM}"
            timeout 5 su -s /bin/bash "$GITEA_USER" -c "GITEA_WORK_DIR=${GITEA_HOME} ${GITEA_BIN} web --config ${GITEA_CONF}" 2>&1 | tail -15 || true
            printf "${C_RST}"
        }
        sleep 2
    done

    # Caddy
    if [ "$CADDY_ENABLE" = "true" ]; then
        _info "启动 Caddy..."
        systemctl restart caddy 2>/dev/null || true
        sleep 2
        if systemctl is-active --quiet caddy 2>/dev/null; then
            _ok "Caddy 就绪 → https://${CADDY_DOMAIN}"
        else
            _warn "Caddy 启动失败: journalctl -u caddy -n 10"
        fi
    fi
}

# ──────────────────────────────────────────────────────────────
# 管理员 & Runner
# ──────────────────────────────────────────────────────────────
create_admin() {
    _step "创建管理员账户"

    if [ -z "$ADMIN_PASS" ]; then
        ADMIN_PASS="$(openssl rand -base64 12 | tr -d '/+=')"
    fi

    _info "管理员: ${ADMIN_USER} / ${ADMIN_MAIL}"

    su - "$GITEA_USER" -c "GITEA_WORK_DIR=${GITEA_HOME} ${GITEA_BIN} admin user create \
        --admin --username '${ADMIN_USER}' --password '${ADMIN_PASS}' \
        --email '${ADMIN_MAIL}' --config '${GITEA_CONF}' \
        --must-change-password=false" 2>/dev/null && {
        _ok "管理员 ${ADMIN_USER} 创建成功"
    } || {
        _warn "管理员可能已存在，跳过"
    }

    _log INFO "admin: ${ADMIN_USER} / ${ADMIN_MAIL}"
}

setup_actions_runner() {
    _step "配置 Actions Runner"

    if [ "$RUNNER_ENABLE" != "true" ]; then
        _info "已禁用，跳过"
        return 0
    fi

    if ! command -v docker &>/dev/null; then
        _warn "Docker 未安装，跳过 Runner 配置"
        return 0
    fi

    usermod -aG docker "$GITEA_USER" 2>/dev/null || true

    # 下载 act_runner
    local runner_ver; runner_ver="$(curl -sSL https://gitea.com/api/v1/repos/gitea/act_runner/releases/latest 2>/dev/null \
        | grep -oP '"tag_name":\s*"\K[^"]+' | sed 's/^v//')"
    if [ -z "$runner_ver" ]; then runner_ver="0.2.11"; fi

    local rarch="$ARCH"
    case "$rarch" in amd64|arm64) ;; arm-6) rarch="armv6" ;; *) rarch="amd64" ;; esac

    local runner_url="https://gitea.com/gitea/act_runner/releases/download/v${runner_ver}/act_runner-${runner_ver}-linux-${rarch}"
    curl -fsSL -o /usr/local/bin/act_runner "$runner_url" 2>/dev/null && {
        chmod +x /usr/local/bin/act_runner
        _ok "act_runner v${runner_ver} 已安装"
    } || {
        _warn "act_runner 下载失败，可稍后手动安装"
        return 0
    }

    # 注册脚本
    mkdir -p "${GITEA_HOME}/.runner"
    cat > "${GITEA_HOME}/register-runner.sh" << 'REGSCRIPT'
#!/usr/bin/env bash
# Gitea Actions Runner 注册脚本
set -euo pipefail
GITEA_URL="${GITEA_URL:-http://localhost:3000}"
echo "请在 Gitea 后台获取 Runner Token: 站点管理 → Actions → Runners → 创建 Runner"
read -rp "Token: " TOKEN < /dev/tty
[ -z "$TOKEN" ] && { echo "Token 不能为空"; exit 1; }
exec /usr/local/bin/act_runner register --no-interactive \
    --instance "$GITEA_URL" --token "$TOKEN" \
    --name "runner-$(hostname)" \
    --labels "ubuntu-latest:docker://node:20-bullseye,ubuntu-22.04:docker://catthehacker/ubuntu:act-22.04"
REGSCRIPT
    chmod +x "${GITEA_HOME}/register-runner.sh"
    chown -R "${GITEA_USER}:${GITEA_USER}" "${GITEA_HOME}/.runner"
    _info "注册脚本: ${GITEA_HOME}/register-runner.sh"
}

# ──────────────────────────────────────────────────────────────
# 配置持久化
# ──────────────────────────────────────────────────────────────
save_config() {
    cat > "$CONFIG_FILE" << EOF
# Gitea Tools Manager — saved $(date '+%F %T')
GITEA_VERSION=${GITEA_VERSION}
GITEA_USER=${GITEA_USER}
GITEA_HOME=${GITEA_HOME}
GITEA_BIN=${GITEA_BIN}
GITEA_CONF=${GITEA_CONF}
GITEA_LISTEN=${GITEA_LISTEN}
PG_HOST=${PG_HOST}
PG_PORT=${PG_PORT}
PG_NAME=${PG_NAME}
PG_USER=${PG_USER}
PG_PASS=${PG_PASS}
ADMIN_USER=${ADMIN_USER}
ADMIN_PASS=${ADMIN_PASS}
ADMIN_MAIL=${ADMIN_MAIL}
CADDY_ENABLE=${CADDY_ENABLE}
CADDY_DOMAIN=${CADDY_DOMAIN}
RUNNER_ENABLE=${RUNNER_ENABLE}
EOF
    chmod 600 "$CONFIG_FILE"
}

load_config() {
    if [ -f "$CONFIG_FILE" ]; then source "$CONFIG_FILE"; fi
}

# ──────────────────────────────────────────────────────────────
# 状态面板 & 管理命令
# ──────────────────────────────────────────────────────────────
print_status() {
    local label="$1" ok="$2"
    printf "  %-15s %s\n" "$label" "$ok"
}

show_summary() {
    echo ""
    _title "部署完成"
    echo ""

    # 服务状态
    local gitea_ok="未运行";   systemctl is-active --quiet gitea 2>/dev/null      && gitea_ok="${C_GRN}● 运行中${C_RST}"
    local pg_ok="未运行";      systemctl is-active --quiet postgresql 2>/dev/null && pg_ok="${C_GRN}● 运行中${C_RST}"
    [ "$pg_ok" = "未运行" ] && { systemctl is-active --quiet postgresql-* 2>/dev/null && pg_ok="${C_GRN}● 运行中${C_RST}"; }
    local caddy_ok="未配置"
    [ "$CADDY_ENABLE" = "true" ] && { systemctl is-active --quiet caddy 2>/dev/null && caddy_ok="${C_GRN}● 运行中${C_RST}" || caddy_ok="${C_RED}○ 已停止${C_RST}"; }

    printf "  ${C_BLD}%-15s %-15s %-15s %-15s${C_RST}\n" "服务" "状态" "版本" "端口"
    _hr
    printf "  %-15s %b%-15s${C_RST} %-15s %-15s\n" \
        "Gitea" "$gitea_ok" "v${GITEA_VERSION}" "${GITEA_LISTEN}"
    printf "  %-15s %b%-15s${C_RST} %-15s %-15s\n" \
        "PostgreSQL" "$pg_ok" "$(psql --version 2>/dev/null | awk '{print $NF}' || echo '?')" "${PG_PORT}"
    printf "  %-15s %b%-15s${C_RST} %-15s %-15s\n" \
        "Caddy" "$caddy_ok" "$(caddy version 2>/dev/null | head -1 || echo 'N/A')" "80/443"

    echo ""
    if [ "$CADDY_ENABLE" = "true" ] && [ -n "$CADDY_DOMAIN" ]; then
        printf "  ${C_BWT}访问地址:${C_RST}  ${C_BCY}https://%s${C_RST}\n" "$CADDY_DOMAIN"
    else
        printf "  ${C_BWT}访问地址:${C_RST}  ${C_BCY}http://%s:%s${C_RST}\n" \
            "$(hostname -I 2>/dev/null | awk '{print $1}' || echo 'localhost')" "$GITEA_LISTEN"
    fi

    echo ""
    printf "  ${C_BWT}管理员:${C_RST}  %-16s ${C_DIM}密码: %s${C_RST}\n" "$ADMIN_USER" "$ADMIN_PASS"
    printf "  ${C_DIM}密码已保存至 ${CONFIG_FILE}${C_RST}\n"
    echo ""
}

cmd_status() {
    load_config 2>/dev/null || true
    show_summary
}

cmd_config() {
    load_config 2>/dev/null || true
    _title "当前配置"
    echo ""
    print_status "Gitea 版本"    "v${GITEA_VERSION:-N/A}"
    print_status "监听端口"      "${GITEA_LISTEN:-3000}"
    print_status "数据库"        "${PG_USER:-?}@${PG_HOST:-?}:${PG_PORT:-?}/${PG_NAME:-?}"
    print_status "Caddy 域名"    "${CADDY_DOMAIN:-未配置}"
    print_status "管理员"        "${ADMIN_USER:-N/A}"
    print_status "配置文件"      "${CONFIG_FILE}"
    echo ""
}

cmd_check() {
    load_config 2>/dev/null || true
    _title "检查更新"
    local current; current="$($GITEA_BIN --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "0")"
    local latest; latest="$(curl -sSL https://api.github.com/repos/go-gitea/gitea/releases/latest 2>/dev/null \
        | grep -oP '"tag_name":\s*"\K[^"]+' | sed 's/^v//')"
    printf "  %-15s v%s\n" "当前版本:" "$current"
    printf "  %-15s v%s\n" "最新版本:" "${latest:-?}"
    if [ -n "$latest" ] && [ "$current" != "$latest" ]; then
        printf "\n  ${C_BYL}发现新版本!${C_RST} 运行 ${C_BCY}$0 update${C_RST} 来升级\n"
    else
        printf "\n  ${C_GRN}已是最新版本${C_RST}\n"
    fi
    echo ""
}

cmd_update() {
    load_config 2>/dev/null || true
    _title "更新 Gitea"
    _info "当前: v$("$GITEA_BIN" --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "?")"
    GITEA_VERSION="latest"; fetch_gitea_version
    _info "最新: v${GITEA_VERSION}"

    systemctl stop gitea 2>/dev/null || true
    cp "$GITEA_CONF" "${GITEA_CONF}.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
    _info "备份 → ${GITEA_CONF}.bak.*"

    local url="https://dl.gitea.com/gitea/${GITEA_VERSION}/gitea-${GITEA_VERSION}-linux-${ARCH}"
    curl -fsSL -o "${GITEA_BIN}.tmp" "$url" && chmod +x "${GITEA_BIN}.tmp" && mv "${GITEA_BIN}.tmp" "$GITEA_BIN"

    save_config
    systemctl start gitea
    _ok "更新完成 → v${GITEA_VERSION}"
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# 主安装流程
# ═══════════════════════════════════════════════════════════════
cmd_install() {
    # 权限检查
    if [ "$(id -u)" -ne 0 ]; then
        _err "请以 root 运行: sudo $0 install"
        exit 1
    fi

    # 已安装检查
    if [ -f "$GITEA_BIN" ]; then
        load_config 2>/dev/null || true
        _warn "Gitea 已安装 ($("$GITEA_BIN" --version 2>/dev/null | head -1 || echo "?"))"
        local ans; ans="$(_ask "  ${C_WHT}重新安装?${C_RST} ${C_DIM}[y/N]${C_RST} " "n")"
        [ "${ans,,}" != "y" ] && { _info "已取消"; exit 0; }
    fi

    # Banner
    clear 2>/dev/null || true
    printf "${C_BLD}%*s${C_RST}\n" "$WIDTH" "" | tr ' ' '─'
    printf "  ${C_BLD}Gitea Tools Manager${C_RST}  ${C_DIM}v%s${C_RST}\n" "$SCRIPT_VERSION"
    printf "  ${C_BCY}Gitea · Caddy · PostgreSQL · Actions${C_RST}  ${C_DIM}—  一键部署${C_RST}\n"
    printf "${C_BLD}%*s${C_RST}\n" "$WIDTH" "" | tr ' ' '─'
    printf "\n  Gitea  ·  Caddy HTTPS  ·  PostgreSQL  ·  Docker  ·  Actions Runner\n\n"

    TOTAL_STEPS=10

    # ── 1. 系统环境 ──
    detect_system              # [01/10]

    # ── 2. 域名配置 (交互式) ──
    prompt_domain              # [02/10]

    # ── 3. 依赖 ──
    install_deps               # [03/10]

    # ── 4. PostgreSQL ──
    install_postgresql         # [04/10]

    # ── 5. Gitea 安装 ──
    install_gitea              # [05/10]

    # ── 6. Gitea 配置 ──
    write_gitea_config         # [06/10]

    # ── 7. Caddy 安装 ──
    install_caddy              # [07/10]

    # ── 8. 启动服务 ──
    start_all_services         # [08/10]

    # ── 9. 管理员 ──
    create_admin               # [09/10]

    # ── 10. Actions Runner ──
    setup_actions_runner       # [10/10]

    # ── 持久化 ──
    save_config

    show_summary
    _log INFO "install complete: gitea ${GITEA_VERSION}"
}

cmd_uninstall() {
    load_config 2>/dev/null || true
    _title "卸载 Gitea Tools Manager"

    local ans; ans="$(_ask "  ${C_BRD}确认卸载? 这会删除 Gitea、数据库和服务!${C_RST} 输入 DELETE 确认: " "")"
    [ "$ans" != "DELETE" ] && { _info "已取消"; exit 0; }

    systemctl stop gitea gitea-actions-runner caddy 2>/dev/null || true
    systemctl disable gitea gitea-actions-runner caddy 2>/dev/null || true
    rm -f /etc/systemd/system/gitea.service
    rm -f /etc/systemd/system/gitea-actions-runner.service
    systemctl daemon-reload

    rm -f "$GITEA_BIN" /usr/local/bin/act_runner
    rm -rf "$GITEA_HOME" /etc/gitea /etc/caddy/Caddyfile
    rm -f "$CONFIG_FILE" "$LOG_FILE"

    su - postgres -c "psql -c 'DROP DATABASE IF EXISTS ${PG_NAME};'" 2>/dev/null || true
    su - postgres -c "psql -c 'DROP ROLE IF EXISTS ${PG_USER};'" 2>/dev/null || true
    userdel -r "$GITEA_USER" 2>/dev/null || true

    _ok "卸载完成"
}

# ═══════════════════════════════════════════════════════════════
# 入口
# ═══════════════════════════════════════════════════════════════
usage() {
    cat << EOF

  ${C_BLD}Gitea Tools Manager${C_RST}  ${C_DIM}v${SCRIPT_VERSION}${C_RST}

  用法:  $0 <命令>

  命令:
    install     ${C_DIM}一键部署 Gitea + Caddy + PostgreSQL + Actions Runner${C_RST}
    update      ${C_DIM}更新 Gitea 到最新版本${C_RST}
    check       ${C_DIM}检查是否有新版本${C_RST}
    status      ${C_DIM}查看服务运行状态${C_RST}
    config      ${C_DIM}显示当前配置${C_RST}
    uninstall   ${C_DIM}完全卸载${C_RST}

  快速开始:
    ${C_BCY}curl -fsSL https://raw.githubusercontent.com/MomoFlora/Gitea-Tools-Manager/refs/heads/master/gitea-manager.sh | sudo bash -s install${C_RST}

EOF
}

case "${1:-}" in
    install)    cmd_install ;;
    update)     cmd_update ;;
    check)      cmd_check ;;
    status)     cmd_status ;;
    config)     cmd_config ;;
    uninstall)  cmd_uninstall ;;
    -h|--help|help|"") usage ;;
    *)          echo -e "${C_RED}未知命令: $1${C_RST}"; usage; exit 1 ;;
esac
