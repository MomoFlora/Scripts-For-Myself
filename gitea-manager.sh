#!/usr/bin/env bash
#===============================================================================
#  Gitea Tools Manager  v2.0.0
#  Gitea + Caddy + PostgreSQL + Actions Runner — 一键部署
#  https://github.com/MomoFlora/Gitea-Tools-Manager
#===============================================================================
set -euo pipefail

#===============================================================================
#  颜色定义 — 清晰、克制、可读
#===============================================================================
CLR_RED=$'\033[31m';    CLR_GRN=$'\033[32m';    CLR_YEL=$'\033[33m'
CLR_BLU=$'\033[34m';    CLR_CYN=$'\033[36m';    CLR_WHT=$'\033[37m'
CLR_BLD=$'\033[1m';     CLR_DIM=$'\033[2m';     CLR_RST=$'\033[0m'

#===============================================================================
#  日志函数 — OpenClash 风格
#===============================================================================
LOG_ERROR()  { printf "  ${CLR_RED}[ERROR]${CLR_RST} %s\n" "$*" >&2; }
LOG_WARN()   { printf "  ${CLR_YEL}[WARN]${CLR_RST}  %s\n" "$*"; }
LOG_OUT()    { printf "  ${CLR_CYN}[INFO]${CLR_RST}  %s\n" "$*"; }
LOG_OK()     { printf "  ${CLR_GRN}[OK]${CLR_RST}    %s\n" "$*"; }
LOG_DBG()    { printf "  ${CLR_DIM}[DEBUG]${CLR_RST} %s\n" "$*"; }

SEP()  { printf "${CLR_DIM}%*s${CLR_RST}\n" 64 "" | tr ' ' '-'; }
TITLE(){ printf "\n  ${CLR_BLD}%s${CLR_RST}\n" "$*"; SEP; }

#===============================================================================
#  全局变量
#===============================================================================
readonly VER="2.0.0"
readonly CURDIR="$(cd "$(dirname "$0")" && pwd)"
readonly SAVEFILE="${CURDIR}/gitea-manager.conf"
readonly LOGFILE="${CURDIR}/gitea-manager.log"
readonly W=64

# Gitea
GT_VER="${GT_VER:-latest}"
GT_USR="${GT_USR:-gitea}"
GT_HOME="${GT_HOME:-/var/lib/gitea}"
GT_BIN="${GT_BIN:-/usr/local/bin/gitea}"
GT_CFG="${GT_CFG:-/etc/gitea/app.ini}"
GT_PORT="${GT_PORT:-3000}"

# PostgreSQL
PG_HOST="${PG_HOST:-127.0.0.1}"
PG_PORT="${PG_PORT:-5432}"
PG_DB="${PG_DB:-gitea}"
PG_USR="${PG_USR:-gitea}"
PG_PWD="${PG_PWD:-}"

# Caddy
CD_ENABLE="${CD_ENABLE:-}"
CD_DOMAIN="${CD_DOMAIN:-}"

# Admin
ADM_USR="${ADM_USR:-gitea_admin}"
ADM_PWD="${ADM_PWD:-}"
ADM_MAIL="${ADM_MAIL:-}"

# Runner
RN_ENABLE="${RN_ENABLE:-true}"

# Runtime
OS_ID=""; ARCH=""; STEP=0; STEPS=0

#===============================================================================
#  交互输入 (curl|bash safe — 始终从 /dev/tty 读取)
#===============================================================================
ask() {
    local p="$1" d="$2" v
    printf "%b" "$p" >/dev/tty 2>/dev/null || { printf '%s' "$d"; return 0; }
    read -r v </dev/tty 2>/dev/null || { printf '%s' "$d"; return 0; }
    if [ -z "$v" ]; then v="$d"; fi
    printf '%s' "$v"
}

#===============================================================================
#  进度标记
#===============================================================================
step() {
    STEP=$((STEP+1))
    printf "\n  ${CLR_BLD}[${STEP}/${STEPS}]${CLR_RST} %s\n" "$*"
    SEP
}

#===============================================================================
#  系统探测
#===============================================================================
detect_system() {
    step "检测系统环境"

    if [ -f /etc/os-release ]; then
        . /etc/os-release; OS_ID="$ID"
        case "$ID" in
            ubuntu|debian)                     PKG="apt" ;;
            centos|rhel|rocky|almalinux|fedora) PKG="dnf" ;;
            arch|manjaro)                      PKG="pacman" ;;
            *)                                 PKG="unknown" ;;
        esac
    else
        OS_ID="unknown"; PKG="unknown"
    fi

    local m; m="$(uname -m)"
    case "$m" in
        x86_64|amd64)  ARCH="amd64"  ;;   aarch64|arm64) ARCH="arm64" ;;
        armv7l)        ARCH="arm-6"  ;;   armv6l)        ARCH="arm-6"  ;;
        riscv64)       ARCH="riscv64";;   loongarch64)   ARCH="loong64";;
        *)             ARCH="amd64"; LOG_WARN "未知架构 $m，回退到 amd64" ;;
    esac

    LOG_OK "系统: ${OS_ID} · 架构: ${ARCH} · 内核: $(uname -r)"
}

#===============================================================================
#  Step: 系统依赖 (curl git docker ...)
#===============================================================================
install_dependencies() {
    step "安装系统依赖"

    local pkgs="curl wget ca-certificates git gnupg openssl"

    case "$PKG" in
        apt)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq 2>/dev/null || true
            apt-get install -y -qq -o Dpkg::Use-Pty=0 $pkgs 2>/dev/null
            if ! command -v docker &>/dev/null; then
                LOG_OUT "安装 Docker ..."
                apt-get install -y -qq -o Dpkg::Use-Pty=0 docker.io docker-compose-v2 2>/dev/null || \
                    curl -fsSL https://get.docker.com | bash -s 2>/dev/null
            fi ;;
        dnf)
            dnf install -y -q $pkgs 2>/dev/null || yum install -y -q $pkgs 2>/dev/null
            if ! command -v docker &>/dev/null; then
                LOG_OUT "安装 Docker ..."
                dnf install -y -q docker docker-compose 2>/dev/null || \
                    curl -fsSL https://get.docker.com | bash -s 2>/dev/null
            fi ;;
        pacman)
            pacman -S --noconfirm --needed $pkgs docker docker-compose 2>/dev/null ;;
        *)
            LOG_WARN "未知包管理器，请手动安装: $pkgs docker" ;;
    esac

    if command -v docker &>/dev/null; then
        systemctl enable docker 2>/dev/null || true
        systemctl start docker 2>/dev/null || true
        LOG_OK "Docker $(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',') 已就绪"
    fi

    LOG_OK "系统依赖安装完成"
}

#===============================================================================
#  Step: PostgreSQL
#===============================================================================
install_postgresql() {
    step "安装 PostgreSQL 数据库"

    # --- 安装 ---
    if ! command -v psql &>/dev/null; then
        case "$PKG" in
            apt)   apt-get install -y -qq -o Dpkg::Use-Pty=0 postgresql postgresql-client 2>/dev/null ;;
            dnf)   dnf install -y -q postgresql-server postgresql 2>/dev/null || yum install -y -q postgresql-server postgresql 2>/dev/null
                   postgresql-setup --initdb 2>/dev/null || true ;;
            pacman) pacman -S --noconfirm --needed postgresql 2>/dev/null
                    if [ ! -d /var/lib/postgres/data ]; then
                        su - postgres -c "initdb -D /var/lib/postgres/data" 2>/dev/null || true
                    fi ;;
        esac
    fi

    # --- 启动 ---
    systemctl enable postgresql 2>/dev/null || true
    systemctl start postgresql 2>/dev/null || {
        local svc; svc="$(systemctl list-units -t service --all 2>/dev/null | grep -oP 'postgresql\S*\.service' | head -1 || true)"
        [ -n "$svc" ] && systemctl start "$svc" 2>/dev/null || true
    }

    # 等待 PostgreSQL 就绪
    local i=0
    while ! su - postgres -c "pg_isready -q" 2>/dev/null && [ $i -lt 15 ]; do
        sleep 1; i=$((i+1))
    done
    if su - postgres -c "pg_isready -q" 2>/dev/null; then
        LOG_OK "PostgreSQL $(psql --version 2>/dev/null | awk '{print $NF}') · 运行中"
    else
        LOG_ERROR "PostgreSQL 未能启动!"
        return 1
    fi

    # --- 生成/恢复密码 ---
    if [ -z "$PG_PWD" ]; then
        PG_PWD="$(openssl rand -base64 24 | tr -d '/+=')"
    fi

    # --- 清理旧的数据库状态 (如果用户要求重装) ---
    local HBA; HBA="$(su - postgres -c "psql -t -c 'SHOW hba_file;'" 2>/dev/null | tr -d ' ')" || true
    LOG_DBG "pg_hba.conf = ${HBA}"

    # --- 先尝试用当前密码连接 ---
    local need_reset=false
    if ! PGPASSWORD="$PG_PWD" psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USR" -d "$PG_DB" -c "SELECT 1;" &>/dev/null; then
        LOG_WARN "无法用当前密码连接数据库，重置用户和数据库 ..."
        su - postgres -c "psql -q -c 'DROP DATABASE IF EXISTS ${PG_DB} WITH (FORCE);'" 2>/dev/null || true
        su - postgres -c "psql -q -c 'DROP OWNED BY ${PG_USR} CASCADE;'" 2>/dev/null || true
        su - postgres -c "psql -q -c 'DROP ROLE IF EXISTS ${PG_USR};'" 2>/dev/null || true
        need_reset=true
    fi

    # --- 创建角色 (强制设密码) ---
    if [ "$need_reset" = true ] || ! su - postgres -c "psql -q -tc \"SELECT 1 FROM pg_roles WHERE rolname='${PG_USR}'\"" 2>/dev/null | grep -q 1; then
        LOG_OUT "创建角色 ${PG_USR} ..."
        su - postgres -c "psql -q -c \"SET password_encryption='scram-sha-256'; CREATE ROLE ${PG_USR} LOGIN PASSWORD '${PG_PWD}';\"" 2>/dev/null
    else
        LOG_OUT "更新角色 ${PG_USR} 密码 ..."
        su - postgres -c "psql -q -c \"ALTER ROLE ${PG_USR} LOGIN PASSWORD '${PG_PWD}';\""
    fi

    # --- 创建数据库 ---
    if ! su - postgres -c "psql -q -tc \"SELECT 1 FROM pg_database WHERE datname='${PG_DB}'\"" 2>/dev/null | grep -q 1; then
        LOG_OUT "创建数据库 ${PG_DB} ..."
        su - postgres -c "psql -q -c \"CREATE DATABASE ${PG_DB} OWNER ${PG_USR} ENCODING 'UTF8' LC_COLLATE='en_US.UTF-8' LC_CTYPE='en_US.UTF-8' TEMPLATE template0;\""
    fi

    su - postgres -c "psql -q -c 'GRANT ALL PRIVILEGES ON DATABASE ${PG_DB} TO ${PG_USR};'" 2>/dev/null
    su - postgres -c "psql -q -c 'GRANT ALL ON SCHEMA public TO ${PG_USR};' -d ${PG_DB}" 2>/dev/null || true

    # --- pg_hba.conf: 重建文件 — gitea 规则放最前面 ---
    if [ -n "$HBA" ] && [ -f "$HBA" ]; then
        # 总是重建 pg_hba.conf 以确保规则在最前面
        if grep -qF "gitea" "$HBA" 2>/dev/null; then
            LOG_OUT "pg_hba.conf 中已有旧 gitea 规则，清理并重建 ..."
            # 删除旧 gitea 行
            sed -i '/gitea/d' "$HBA"
            sed -i '/^$/N;/^\n$/d' "$HBA"   # 清理空行
        fi

        LOG_OUT "配置 pg_hba.conf (scram-sha-256 · 行首) ..."
        cp "$HBA" "${HBA}.bak.$(date +%Y%m%d%H%M%S)"
        local tmp_hba; tmp_hba="$(mktemp)"
        {
            printf "# Gitea — gitea-manager v%s\n" "$VER"
            printf "host    %-12s %-12s 127.0.0.1/32    scram-sha-256\n" "$PG_DB" "$PG_USR"
            printf "host    %-12s %-12s ::1/128         scram-sha-256\n" "$PG_DB" "$PG_USR"
            printf "\n"
            cat "$HBA"
        } > "$tmp_hba"
        mv "$tmp_hba" "$HBA"
        chown postgres:postgres "$HBA"
        chmod 640 "$HBA"

        systemctl reload postgresql 2>/dev/null || \
            su - postgres -c "pg_ctl reload -D /var/lib/postgresql/*/main/" 2>/dev/null || true
        sleep 1
    else
        LOG_ERROR "找不到 pg_hba.conf!"; return 1
    fi

    # --- 连接验证 ---
    LOG_OUT "验证数据库连接 (${PG_USR}@${PG_HOST}:${PG_PORT}/${PG_DB}) ..."
    if PGPASSWORD="$PG_PWD" psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USR" -d "$PG_DB" -c "SELECT 1 AS connected;" &>/dev/null; then
        LOG_OK "数据库连接验证通过"
    else
        LOG_ERROR "数据库连接失败!"
        LOG_OUT "pg_hba.conf 当前内容 (不含注释):"
        grep -v '^#' "$HBA" | grep -v '^$' | head -10 | while IFS= read -r line; do
            printf "          ${CLR_DIM}%s${CLR_RST}\n" "$line"
        done
        LOG_OUT "直接连接测试 (查看完整错误):"
        PGPASSWORD="$PG_PWD" psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USR" -d "$PG_DB" -c "SELECT 1;" 2>&1 | while IFS= read -r line; do
            printf "          ${CLR_RED}%s${CLR_RST}\n" "$line"
        done || true
    fi
}

#===============================================================================
#  Step: 域名配置 (Caddy)
#===============================================================================
configure_domain() {
    step "域名配置"

    printf "\n  ${CLR_WHT}Caddy 反向代理 + Let's Encrypt SSL 证书 (自动 HTTPS)${CLR_RST}\n"
    printf "  ${CLR_DIM}确保域名 DNS 已解析到此服务器 IP，留空则跳过反代配置${CLR_RST}\n\n"

    local dm; dm="$(ask "  ${CLR_WHT}域名 (留空跳过):${CLR_RST} " "")"

    if [ -z "$dm" ]; then
        LOG_OUT "跳过反向代理 — Gitea 直接通过端口 ${GT_PORT} 访问"
        CD_ENABLE="false"; CD_DOMAIN=""
        return 0
    fi

    if [[ ! "$dm" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
        LOG_WARN "域名格式无效: ${dm}，跳过反代"
        CD_ENABLE="false"; CD_DOMAIN=""
        return 0
    fi

    CD_ENABLE="true"; CD_DOMAIN="$dm"
    ADM_MAIL="${ADM_MAIL:-admin@${dm}}"

    printf "\n"
    printf "  %-14s ${CLR_BLD}%s${CLR_RST}\n" "域名:" "$CD_DOMAIN"
    printf "  %-14s ${CLR_BLD}https://%s${CLR_RST}\n" "访问:" "$CD_DOMAIN"
    printf "  %-14s ${CLR_DIM}Let's Encrypt 自动管理${CLR_RST}\n" "SSL:"
    printf "\n"

    local c; c="$(ask "  ${CLR_WHT}确认?${CLR_RST} ${CLR_DIM}[Y/n]${CLR_RST} " "y")"
    if [ "${c,,}" = "n" ]; then
        LOG_WARN "已取消"; CD_ENABLE="false"; CD_DOMAIN=""; return 0
    fi
    LOG_OK "域名已配置: ${CD_DOMAIN}"
}

#===============================================================================
#  Step: Gitea 安装
#===============================================================================
install_gitea() {
    step "安装 Gitea"

    # --- 版本 ---
    if [ "$GT_VER" = "latest" ]; then
        GT_VER="$(curl -sSL https://api.github.com/repos/go-gitea/gitea/releases/latest 2>/dev/null \
            | grep -oP '"tag_name":\s*"\K[^"]+' | sed 's/^v//')"
        [ -z "$GT_VER" ] && { LOG_ERROR "无法获取最新版本"; return 1; }
    fi
    LOG_OUT "版本: v${GT_VER}"

    # --- 下载 ---
    local url="https://dl.gitea.com/gitea/${GT_VER}/gitea-${GT_VER}-linux-${ARCH}"
    LOG_OUT "下载 ${url}"
    curl -fsSL -o "${GT_BIN}.tmp" "$url" || {
        LOG_ERROR "下载失败: ${url}"
        return 1
    }

    # SHA256 (尽力而为)
    if curl -fsSL "${url}.sha256" -o /tmp/gitea.sha256 2>/dev/null; then
        local exp; exp="$(awk '{print $1}' /tmp/gitea.sha256)"
        local act; act="$(sha256sum "${GT_BIN}.tmp" | awk '{print $1}')"
        if [ "$exp" = "$act" ]; then
            LOG_OK "SHA256 校验通过"
        else
            LOG_WARN "SHA256 不匹配，继续使用"
        fi
        rm -f /tmp/gitea.sha256
    fi

    chmod +x "${GT_BIN}.tmp" && mv "${GT_BIN}.tmp" "$GT_BIN"
    LOG_OK "Gitea 安装到 ${GT_BIN}"

    # --- 系统用户 ---
    if ! id "$GT_USR" &>/dev/null; then
        useradd --system --home-dir "$GT_HOME" --shell /bin/bash -c "Gitea" "$GT_USR" 2>/dev/null || \
            adduser --system --home "$GT_HOME" --group "$GT_USR" 2>/dev/null
        LOG_OK "用户 ${GT_USR} 已创建"
    else
        LOG_OUT "用户 ${GT_USR} 已存在"
    fi

    # --- 目录 ---
    mkdir -p "${GT_HOME}"/{custom/conf,data,log,repositories} /etc/gitea
    chown -R "${GT_USR}:${GT_USR}" "$GT_HOME" /etc/gitea
    chmod 750 "$GT_HOME"
    LOG_OK "目录结构就绪"

    # --- systemd ---
    cat > /etc/systemd/system/gitea.service << UNIT
[Unit]
Description=Gitea (Git Service)
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=${GT_USR}
Group=${GT_USR}
WorkingDirectory=${GT_HOME}
ExecStart=${GT_BIN} web --config ${GT_CFG}
Restart=always
RestartSec=5s
Environment=USER=${GT_USR} HOME=${GT_HOME} GITEA_WORK_DIR=${GT_HOME}
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload
    systemctl enable gitea 2>/dev/null || true
    LOG_OK "systemd 服务 gitea.service 已创建"
}

#===============================================================================
#  Step: Gitea 配置生成
#===============================================================================
generate_gitea_config() {
    step "生成 Gitea 配置文件"

    local domain root_url

    if [ "$CD_ENABLE" = "true" ] && [ -n "$CD_DOMAIN" ]; then
        domain="$CD_DOMAIN"; root_url="https://${CD_DOMAIN}/"
    else
        # 自动获取公网IP
        local pub; pub="$(curl -s --max-time 3 ifconfig.me 2>/dev/null || curl -s --max-time 3 icanhazip.com 2>/dev/null || echo '')"
        if [ -z "$pub" ]; then pub="$(hostname -I 2>/dev/null | awk '{print $1}' || echo 'localhost')"; fi
        LOG_OUT "公网 IP: ${pub}"
        domain="${pub}"
        root_url="http://${domain}:${GT_PORT}/"
    fi
    ADM_MAIL="${ADM_MAIL:-admin@${domain}}"

    local sk; sk="$(openssl rand -base64 48 | tr -d '/+=')"
    local it; it="$(openssl rand -base64 36 | tr -d '/+=')"

    cat > "$GT_CFG" << EOF
; Gitea config — gitea-manager v${VER} — $(date '+%F %T')

APP_NAME   = Gitea: Git with a cup of tea
RUN_USER   = ${GT_USR}
RUN_MODE   = prod

[repository]
ROOT           = ${GT_HOME}/repositories
DEFAULT_BRANCH = main

[server]
PROTOCOL         = http
DOMAIN           = ${domain}
ROOT_URL         = ${root_url}
HTTP_ADDR        = 0.0.0.0
HTTP_PORT        = ${GT_PORT}
SSH_DOMAIN       = ${domain}
SSH_PORT         = 2222
SSH_LISTEN_PORT  = 2222
START_SSH_SERVER = true
LANDING_PAGE     = explore

[database]
DB_TYPE  = postgres
HOST     = ${PG_HOST}:${PG_PORT}
NAME     = ${PG_DB}
USER     = ${PG_USR}
PASSWD   = ${PG_PWD}
SSL_MODE = disable

[security]
INSTALL_LOCK       = true
SECRET_KEY         = ${sk}
INTERNAL_TOKEN     = ${it}
PASSWORD_HASH_ALGO = pbkdf2

[service]
DISABLE_REGISTRATION       = false
REQUIRE_SIGNIN_VIEW        = false
REGISTER_EMAIL_CONFIRM     = false

[session]
PROVIDER = db

[log]
MODE      = file
LEVEL     = Info
ROOT_PATH = ${GT_HOME}/log

[actions]
ENABLED = true
DEFAULT_ACTIONS_URL = github

[other]
SHOW_FOOTER_VERSION = true
EOF

    chown "${GT_USR}:${GT_USR}" "$GT_CFG"
    chmod 640 "$GT_CFG"
    LOG_OK "配置 → ${GT_CFG}"
}

#===============================================================================
#  Step: Caddy 安装 & 反代配置
#===============================================================================
install_caddy() {
    step "安装 Caddy 反向代理"

    if [ "$CD_ENABLE" != "true" ]; then
        LOG_OUT "未配置域名，跳过"
        return 0
    fi

    if ! command -v caddy &>/dev/null; then
        case "$PKG" in
            apt)
                curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' 2>/dev/null \
                    | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null
                curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' 2>/dev/null \
                    > /etc/apt/sources.list.d/caddy-stable.list
                apt-get update -qq 2>/dev/null
                apt-get install -y -qq -o Dpkg::Use-Pty=0 caddy 2>/dev/null ;;
            dnf)
                dnf install -y -q 'dnf-command(copr)' 2>/dev/null || true
                dnf copr enable -y @caddy/caddy 2>/dev/null || true
                dnf install -y -q caddy 2>/dev/null ;;
            pacman)
                pacman -S --noconfirm --needed caddy 2>/dev/null ;;
        esac
    fi
    LOG_OK "Caddy $(caddy version 2>/dev/null | head -1)"

    # --- Caddyfile ---
    cat > /etc/caddy/Caddyfile << CADDYFILE
# Gitea reverse proxy — gitea-manager v${VER}

${CD_DOMAIN} {
    log {
        output file /var/log/caddy/gitea.log
        level INFO
    }

    reverse_proxy localhost:${GT_PORT} {
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto https
        header_up X-Forwarded-Host ${CD_DOMAIN}
        header_up Connection {http.request.header.Connection}
    }

    header {
        X-Frame-Options "SAMEORIGIN"
        X-Content-Type-Options "nosniff"
        -Server
    }

    request_body { max_size 500MB }

    tls ${ADM_MAIL}
}
CADDYFILE
    LOG_OK "Caddyfile → /etc/caddy/Caddyfile"

    # --- 防火墙 ---
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
        ufw allow 80/tcp comment "Caddy HTTP" 2>/dev/null || true
        ufw allow 443/tcp comment "Caddy HTTPS" 2>/dev/null || true
    elif command -v firewall-cmd &>/dev/null && firewall-cmd --state 2>/dev/null | grep -q "running"; then
        firewall-cmd --permanent --add-service=http --add-service=https 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
    fi
}

#===============================================================================
#  Step: 启动服务
#===============================================================================
start_services() {
    step "启动所有服务"

    # --- PostgreSQL ---
    if ! systemctl is-active --quiet postgresql 2>/dev/null; then
        LOG_OUT "启动 PostgreSQL ..."
        systemctl restart postgresql 2>/dev/null || true
        sleep 2
    fi

    # --- Gitea: doctor 诊断 ---
    LOG_OUT "运行 gitea doctor 诊断 ..."
    local doc; doc="$(su -s /bin/bash "$GT_USR" -c "GITEA_WORK_DIR=${GT_HOME} ${GT_BIN} doctor --config ${GT_CFG} 2>&1")" || true
    if echo "$doc" | grep -qiE "FAIL|ERROR|CRITICAL"; then
        LOG_ERROR "Gitea doctor 发现严重问题:"
        echo "$doc" | grep -iE "FAIL|ERROR|CRITICAL" | head -10 | while IFS= read -r l; do
            printf "  ${CLR_RED}%s${CLR_RST}\n" "$l"
        done
    else
        LOG_OK "Gitea doctor 检查通过"
    fi

    # --- Gitea: 前台测试 ---
    LOG_OUT "前台测试 Gitea 启动 (捕获 stderr) ..."
    local fg_out; fg_out="$(timeout 8 su -s /bin/bash "$GT_USR" -c "GITEA_WORK_DIR=${GT_HOME} ${GT_BIN} web --config ${GT_CFG}" 2>&1)" || true
    # 过滤掉正常的 info/warn 行，只保留异常
    local fg_err; fg_err="$(echo "$fg_out" | grep -vE '\[I\]|\[W\]|showWebStartupMessage|Prepare to run|Starting Gitea|Gitea version' || true)"
    if [ -n "$fg_err" ]; then
        LOG_OUT "Gitea 前台输出 (已过滤 INFO/WARN):"
        echo "$fg_err" | head -20 | while IFS= read -r l; do
            printf "  ${CLR_DIM}%s${CLR_RST}\n" "$l"
        done
    fi

    # --- 启动 systemd 服务 ---
    LOG_OUT "启动 Gitea systemd 服务 ..."
    systemctl stop gitea 2>/dev/null || true
    systemctl reset-failed gitea 2>/dev/null || true
    systemctl restart gitea

    # 等待并检测
    local retry=0 max=15
    while [ $retry -lt $max ]; do
        sleep 2; retry=$((retry+1))

        # 先检查 systemd 状态
        if systemctl is-active --quiet gitea 2>/dev/null; then
            # 再检查 HTTP
            if curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${GT_PORT}" 2>/dev/null | grep -qE "2[0-9]{2}|3[0-9]{2}|40[134]"; then
                LOG_OK "Gitea 已就绪 → http://127.0.0.1:${GT_PORT}"
                break
            fi
        fi

        # 每 5 次检查一次 journalctl
        if [ $((retry % 5)) -eq 0 ]; then
            local jerr; jerr="$(journalctl -u gitea --no-pager -n 5 2>/dev/null | grep -iE 'error|fail|fatal|panic|refused' | tail -3 || true)"
            if [ -n "$jerr" ]; then
                echo ""
                LOG_ERROR "Gitea 启动失败，日志显示:"
                printf "  ${CLR_RED}%s${CLR_RST}\n" "$jerr"
                break
            fi
        fi
    done

    if ! systemctl is-active --quiet gitea 2>/dev/null; then
        LOG_ERROR "Gitea 未能启动，完整日志:"
        journalctl -u gitea --no-pager -n 25 2>/dev/null | while IFS= read -r line; do
            printf "  ${CLR_DIM}%s${CLR_RST}\n" "$line"
        done || true
        echo ""
        LOG_OUT "诊断提示:"
        LOG_OUT "  1) 检查数据库连通: PGPASSWORD='***' psql -h ${PG_HOST} -p ${PG_PORT} -U ${PG_USR} -d ${PG_DB} -c 'SELECT 1;'"
        LOG_OUT "  2) 检查配置文件: ${GT_BIN} web --config ${GT_CFG} 2>&1 | tail -20"
        LOG_OUT "  3) 检查文件权限: ls -la ${GT_HOME}/ ${GT_CFG}"
        return 1
    fi

    # --- Caddy ---
    if [ "$CD_ENABLE" = "true" ]; then
        LOG_OUT "启动 Caddy ..."
        systemctl restart caddy 2>/dev/null || true
        sleep 2
        if systemctl is-active --quiet caddy 2>/dev/null; then
            LOG_OK "Caddy 已就绪 → https://${CD_DOMAIN}"
        else
            LOG_WARN "Caddy 启动失败: journalctl -u caddy -n 10"
        fi
    fi
}

#===============================================================================
#  Step: 管理员 & Runner
#===============================================================================
create_admin() {
    step "创建管理员账户"

    # 让用户设置管理员信息
    printf "\n"
    ADM_USR="$(ask "  ${CLR_WHT}管理员用户名${CLR_RST} ${CLR_DIM}[gitea_admin]${CLR_RST}: " "gitea_admin")"
    ADM_MAIL="$(ask "  ${CLR_WHT}管理员邮箱${CLR_RST}   ${CLR_DIM}[admin@${CD_DOMAIN:-example.com}]${CLR_RST}: " "admin@${CD_DOMAIN:-example.com}")"

    while true; do
        ADM_PWD="$(ask "  ${CLR_WHT}管理员密码${CLR_RST}   ${CLR_DIM}(至少 8 位，留空自动生成)${CLR_RST}: " "")"
        if [ -z "$ADM_PWD" ]; then
            ADM_PWD="$(openssl rand -base64 12 | tr -d '/+=')"
            break
        elif [ "${#ADM_PWD}" -lt 8 ]; then
            LOG_WARN "密码至少 8 位，请重新输入"
        else
            break
        fi
    done
    printf "\n"

    su - "$GT_USR" -c "GITEA_WORK_DIR=${GT_HOME} ${GT_BIN} admin user create \
        --admin --username '${ADM_USR}' --password '${ADM_PWD}' \
        --email '${ADM_MAIL}' --config '${GT_CFG}' \
        --must-change-password=false" 2>/dev/null && {
        LOG_OK "管理员 ${ADM_USR} 创建成功"
    } || {
        LOG_WARN "管理员可能已存在，跳过"
    }
}

setup_runner() {
    step "配置 Actions Runner"

    if [ "$RN_ENABLE" != "true" ]; then
        LOG_OUT "已禁用，跳过"; return 0
    fi
    if ! command -v docker &>/dev/null; then
        LOG_WARN "Docker 未安装，跳过"; return 0
    fi

    usermod -aG docker "$GT_USR" 2>/dev/null || true

    # 从 gitea/runner 仓库获取最新版本
    local rv; rv="$(curl -sSL https://gitea.com/api/v1/repos/gitea/runner/releases/latest 2>/dev/null \
        | grep -oP '"tag_name":\s*"\K[^"]+' | sed 's/^v//')"
    if [ -z "$rv" ]; then rv="2.0.0"; fi

    local ra="$ARCH"
    case "$ra" in amd64|arm64) ;; arm-6) ra="arm-6" ;; arm-5) ra="arm-5" ;; loong64) ra="loong64" ;; *) ra="amd64" ;; esac

    # 官方下载地址: gitea.com/gitea/runner/releases
    local rurl="https://gitea.com/gitea/runner/releases/download/v${rv}/gitea-runner-${rv}-linux-${ra}"
    if curl -fsSL -o /usr/local/bin/gitea-runner "$rurl" 2>/dev/null; then
        chmod +x /usr/local/bin/gitea-runner
        LOG_OK "gitea-runner v${rv} 已安装"
    else
        LOG_WARN "gitea-runner 下载失败"; return 0
    fi

    # 清理可能存在的旧目录冲突 (.runner 既是文件也是目录会出问题)
    rm -rf "${GT_HOME}/.runner" 2>/dev/null || true

    # 创建注册脚本 (手动备用)
    cat > "${GT_HOME}/register-runner.sh" << REGSCRIPT
#!/usr/bin/env bash
set -euo pipefail
echo "=== Gitea Actions Runner 注册 ==="
echo ""
INSTANCE="http://localhost:${GT_PORT}"
echo "Gitea 地址: \$INSTANCE"

# 尝试自动获取 token
TOKEN=\$(GITEA_WORK_DIR=${GT_HOME} ${GT_BIN} --config ${GT_CFG} --work-path ${GT_HOME} actions generate-runner-token 2>/dev/null | tail -1 | tr -d '[:space:]')
if [ -n "\$TOKEN" ]; then
    echo "Token: \$TOKEN"
else
    echo "请在 Gitea 后台获取 Runner Token:"
    echo "  \${INSTANCE}/-/admin/actions/runners"
    printf "Token: "
    read -r TOKEN < /dev/tty
fi

[ -z "\$TOKEN" ] && { echo "Token 不能为空"; exit 1; }
echo ""
echo "注册中..."
cd ${GT_HOME}
exec /usr/local/bin/gitea-runner register --no-interactive \
    --instance "\$INSTANCE" --token "\$TOKEN" \
    --name "runner-\$(hostname)" \
    --labels "ubuntu-latest:docker://node:20-bullseye,ubuntu-22.04:docker://catthehacker/ubuntu:act-22.04"
REGSCRIPT
    chmod +x "${GT_HOME}/register-runner.sh"

    # 尝试自动获取 token 并注册
    LOG_OUT "注册 Actions Runner ..."

    # gitea CLI 用 TCP 连数据库，root 也能执行
    local token; token="$(GITEA_WORK_DIR=${GT_HOME} ${GT_BIN} --config ${GT_CFG} --work-path ${GT_HOME} actions generate-runner-token 2>/dev/null | tail -1 | tr -d '[:space:]')" || true

    if [ -n "$token" ] && [ ${#token} -ge 8 ]; then
        # 必须在 .runner 目录内执行 register，否则 .runner 文件会写到当前目录
        cd "${GT_HOME}"
        local reg_out; reg_out="$(GITEA_WORK_DIR=${GT_HOME} /usr/local/bin/gitea-runner register \
            --no-interactive \
            --instance http://localhost:${GT_PORT} \
            --token "${token}" \
            --name "runner-$(hostname)" \
            --labels "ubuntu-latest:docker://node:20-bullseye,ubuntu-22.04:docker://catthehacker/ubuntu:act-22.04" 2>&1)" || true
        cd - >/dev/null

        if echo "$reg_out" | grep -qi "success\|registered\|ok\|INFO.*register"; then
            LOG_OK "Runner 注册成功"
            # 注册后立即启动守护进程
            systemctl start gitea-runner 2>/dev/null || true
            sleep 1
            if systemctl is-active --quiet gitea-runner 2>/dev/null; then
                LOG_OK "Runner 守护进程已启动"
            else
                LOG_WARN "Runner 守护进程启动失败: journalctl -u gitea-runner -n 5"
            fi
        else
            LOG_WARN "Runner 注册失败: $(echo "$reg_out" | tail -1)"
            LOG_OUT "请稍后手动注册: ${GT_HOME}/register-runner.sh"
        fi
    else
        LOG_OUT "Token: ${token:-空}"
        LOG_WARN "无法获取 Token，请手动注册: ${GT_HOME}/register-runner.sh"
    fi

    chown "${GT_USR}:${GT_USR}" "${GT_HOME}/.runner" 2>/dev/null || true

    # 创建 systemd 服务
    cat > /etc/systemd/system/gitea-runner.service << RUNSVC
[Unit]
Description=Gitea Actions Runner
After=gitea.service docker.service
Wants=gitea.service docker.service
ConditionPathExists=${GT_HOME}/.runner

[Service]
Type=simple
User=${GT_USR}
Group=${GT_USR}
WorkingDirectory=${GT_HOME}
ExecStart=/usr/local/bin/gitea-runner daemon
Restart=always
RestartSec=5s
Environment=HOME=${GT_HOME}

[Install]
WantedBy=multi-user.target
RUNSVC
    systemctl daemon-reload
    systemctl enable gitea-runner 2>/dev/null || true
    LOG_OUT "Runner systemd 服务已创建"
}

#===============================================================================
#  持久化 & 汇总
#===============================================================================
save_config() {
    cat > "$SAVEFILE" << EOF
# Gitea Tools Manager — $(date '+%F %T')
GT_VER=${GT_VER}
GT_USR=${GT_USR}
GT_HOME=${GT_HOME}
GT_BIN=${GT_BIN}
GT_CFG=${GT_CFG}
GT_PORT=${GT_PORT}
PG_HOST=${PG_HOST}
PG_PORT=${PG_PORT}
PG_DB=${PG_DB}
PG_USR=${PG_USR}
PG_PWD=${PG_PWD}
ADM_USR=${ADM_USR}
ADM_PWD=${ADM_PWD}
ADM_MAIL=${ADM_MAIL}
CD_ENABLE=${CD_ENABLE}
CD_DOMAIN=${CD_DOMAIN}
RN_ENABLE=${RN_ENABLE}
EOF
    chmod 600 "$SAVEFILE"
}

load_config() {
    if [ -f "$SAVEFILE" ]; then
        source "$SAVEFILE"
        # v1.x → v2.x 变量名兼容
        [ -n "${GITEA_DB_PASSWORD:-}" ] && PG_PWD="${GITEA_DB_PASSWORD}"
        [ -n "${GITEA_VERSION:-}" ]    && GT_VER="${GITEA_VERSION}"
        [ -n "${GITEA_HTTP_PORT:-}" ]  && GT_PORT="${GITEA_HTTP_PORT}"
    fi
}

show_summary() {
    # 从配置文件读取实际使用的域名/IP
    local domain; domain="$(grep -oP '^\s*DOMAIN\s*=\s*\K.*' "$GT_CFG" 2>/dev/null | tr -d ' ' || echo "?")"
    local proto="http"
    [ "$CD_ENABLE" = "true" ] && [ -n "$CD_DOMAIN" ] && proto="https"

    echo ""
    printf "  ${CLR_BLD}%s${CLR_RST}\n" "$(printf '%*s' 56 '' | tr ' ' '=')"
    printf "  ${CLR_GRN}  [OK]  Deployment Complete${CLR_RST}\n\n"

    local gok="${CLR_RED}DOWN${CLR_RST}"
    systemctl is-active --quiet gitea 2>/dev/null && gok="${CLR_GRN}UP${CLR_RST}"
    printf "  %-14s %b   ${CLR_DIM}v%s${CLR_RST}\n" "Gitea" "$gok" "${GT_VER}"

    local pok="${CLR_RED}DOWN${CLR_RST}"
    systemctl is-active --quiet postgresql 2>/dev/null && pok="${CLR_GRN}UP${CLR_RST}"
    printf "  %-14s %b   ${CLR_DIM}%s${CLR_RST}\n" "PostgreSQL" "$pok" "$(psql --version 2>/dev/null | awk '{print $NF}' || echo '?')"

    if [ "$CD_ENABLE" = "true" ]; then
        local cok="${CLR_RED}DOWN${CLR_RST}"
        systemctl is-active --quiet caddy 2>/dev/null && cok="${CLR_GRN}UP${CLR_RST}"
        printf "  %-14s %b\n" "Caddy" "$cok"
    fi

    printf "\n  ${CLR_BLD}访问地址${CLR_RST}\n"
    printf "  ${CLR_CYN}%s://%s${CLR_RST}" "$proto" "$domain"
    [ "$proto" = "http" ] && printf ":${GT_PORT}"
    printf "\n"

    printf "\n  ${CLR_BLD}管理员${CLR_RST}\n"
    printf "  ${CLR_DIM}用户${CLR_RST}  %s\n" "$ADM_USR"
    printf "  ${CLR_DIM}密码${CLR_RST}  ${CLR_WHT}%s${CLR_RST}\n" "$ADM_PWD"
    printf "  ${CLR_DIM}存档${CLR_RST}  %s\n" "$SAVEFILE"
    printf "\n  ${CLR_BLD}%s${CLR_RST}\n" "$(printf '%*s' 56 '' | tr ' ' '=')"
    echo ""
}

#===============================================================================
#  管理命令
#===============================================================================
cmd_install() {
    if [ "$(id -u)" -ne 0 ]; then
        LOG_ERROR "请以 root 运行: sudo $0 install"; exit 1
    fi

    # 已安装检查
    if [ -f "$GT_BIN" ]; then
        load_config 2>/dev/null || true
        LOG_WARN "Gitea 已安装 ($("$GT_BIN" --version 2>/dev/null | head -1 || echo '?'))"
        local a; a="$(ask "  ${CLR_WHT}重新安装?${CLR_RST} ${CLR_DIM}[y/N]${CLR_RST} " "n")"
        if [ "${a,,}" != "y" ]; then LOG_OUT "已取消"; exit 0; fi
    fi

    clear 2>/dev/null || true
    printf "\n"
    printf "  ${CLR_BLD}Gitea Tools Manager${CLR_RST} ${CLR_DIM}v%s${CLR_RST}\n" "$VER"
    printf "  ${CLR_DIM}Gitea · Caddy · PostgreSQL · Actions Runner${CLR_RST}\n"
    printf "\n"

    STEPS=10

    detect_system
    configure_domain
    install_dependencies
    install_postgresql
    install_gitea
    generate_gitea_config
    install_caddy
    start_services
    create_admin
    setup_runner

    save_config
    show_summary
}

cmd_status()   { load_config 2>/dev/null || true; show_summary; }

cmd_uninstall() {
    load_config 2>/dev/null || true
    TITLE "卸载"
    local a; a="$(ask "  ${CLR_RED}确认卸载? 删除 Gitea + 数据库 + 服务!${CLR_RST} 输入 DELETE 确认: " "")"
    [ "$a" != "DELETE" ] && { LOG_OUT "已取消"; exit 0; }

    systemctl stop gitea gitea-actions-runner caddy 2>/dev/null || true
    systemctl disable gitea gitea-actions-runner caddy 2>/dev/null || true
    rm -f /etc/systemd/system/gitea.service /etc/systemd/system/gitea-actions-runner.service
    systemctl daemon-reload
    rm -f "$GT_BIN" /usr/local/bin/gitea-runner /usr/local/bin/act_runner
    rm -rf "$GT_HOME" /etc/gitea /etc/caddy/Caddyfile
    rm -f "$SAVEFILE" "$LOGFILE"
    su - postgres -c "psql -q -c 'DROP DATABASE IF EXISTS ${PG_DB};'" 2>/dev/null || true
    su - postgres -c "psql -q -c 'DROP ROLE IF EXISTS ${PG_USR};'" 2>/dev/null || true
    userdel -r "$GT_USR" 2>/dev/null || true
    LOG_OK "卸载完成"
}

cmd_check() {
    load_config 2>/dev/null || true
    TITLE "检查更新"
    local cur; cur="$("$GT_BIN" --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "?")"
    local lat; lat="$(curl -sSL https://api.github.com/repos/go-gitea/gitea/releases/latest 2>/dev/null \
        | grep -oP '"tag_name":\s*"\K[^"]+' | sed 's/^v//')"
    printf "  %-12s v%s\n" "当前版本:" "$cur"
    printf "  %-12s v%s\n" "最新版本:" "${lat:-?}"
    if [ -n "$lat" ] && [ "$cur" != "$lat" ]; then
        printf "\n  ${CLR_YEL}发现新版本!${CLR_RST} 运行 ${CLR_CYN}$0 update${CLR_RST}\n"
    else
        printf "\n  ${CLR_GRN}已是最新版本${CLR_RST}\n"
    fi
    echo ""
}

cmd_update() {
    load_config 2>/dev/null || true
    TITLE "更新 Gitea"
    LOG_OUT "当前: v$("$GT_BIN" --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "?")"
    GT_VER="latest"
    if [ "$GT_VER" = "latest" ]; then
        GT_VER="$(curl -sSL https://api.github.com/repos/go-gitea/gitea/releases/latest 2>/dev/null \
            | grep -oP '"tag_name":\s*"\K[^"]+' | sed 's/^v//')"
    fi
    LOG_OUT "最新: v${GT_VER}"

    systemctl stop gitea 2>/dev/null || true
    cp "$GT_CFG" "${GT_CFG}.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true

    local url="https://dl.gitea.com/gitea/${GT_VER}/gitea-${GT_VER}-linux-${ARCH}"
    curl -fsSL -o "${GT_BIN}.tmp" "$url" && chmod +x "${GT_BIN}.tmp" && mv "${GT_BIN}.tmp" "$GT_BIN"

    save_config; systemctl start gitea
    LOG_OK "更新完成 → v${GT_VER}"
    echo ""
}

cmd_config() {
    load_config 2>/dev/null || true
    TITLE "当前配置"
    printf "  %-16s v%s\n"     "Gitea 版本"   "${GT_VER:-N/A}"
    printf "  %-16s %s\n"      "监听端口"     "${GT_PORT:-3000}"
    printf "  %-16s %s@%s:%s/%s\n" "数据库"  "${PG_USR:-?}" "${PG_HOST:-?}" "${PG_PORT:-?}" "${PG_DB:-?}"
    printf "  %-16s %s\n"      "Caddy 域名"   "${CD_DOMAIN:-未配置}"
    printf "  %-16s %s\n"      "管理员"       "${ADM_USR:-N/A}"
    printf "  %-16s %s\n"      "配置文件"     "${SAVEFILE}"
    echo ""
}

#===============================================================================
#  入口
#===============================================================================
usage() {
    printf "\n  ${CLR_BLD}Gitea Tools Manager${CLR_RST} ${CLR_DIM}v%s${CLR_RST}\n" "$VER"
    printf "\n"
    printf "  命令:\n"
    printf "    ${CLR_CYN}install${CLR_RST}     ${CLR_DIM}一键部署${CLR_RST}\n"
    printf "    ${CLR_CYN}update${CLR_RST}      ${CLR_DIM}更新 Gitea${CLR_RST}\n"
    printf "    ${CLR_CYN}check${CLR_RST}       ${CLR_DIM}检查更新${CLR_RST}\n"
    printf "    ${CLR_CYN}status${CLR_RST}      ${CLR_DIM}服务状态${CLR_RST}\n"
    printf "    ${CLR_CYN}config${CLR_RST}      ${CLR_DIM}查看配置${CLR_RST}\n"
    printf "    ${CLR_CYN}uninstall${CLR_RST}   ${CLR_DIM}完全卸载${CLR_RST}\n"
    printf "\n"
    printf "  快速开始:\n"
    printf "    ${CLR_DIM}curl -fsSL %s | sudo bash -s install${CLR_RST}\n" \
        "https://raw.githubusercontent.com/MomoFlora/Gitea-Tools-Manager/refs/heads/master/gitea-manager.sh"
    printf "\n"
}

case "${1:-}" in
    install)    cmd_install ;;
    update)     cmd_update ;;
    check)      cmd_check ;;
    status)     cmd_status ;;
    config)     cmd_config ;;
    uninstall)  cmd_uninstall ;;
    -h|--help|help|"") usage ;;
    *)          LOG_ERROR "未知命令: $1"; usage; exit 1 ;;
esac
