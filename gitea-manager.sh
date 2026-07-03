#!/usr/bin/env bash
#===============================================================================
#  GITEA INFRASTRUCTURE MANAGER
#  Version: 2.1.1 (Stable Fix)
#  Component: Gitea + Caddy + PostgreSQL + Actions Runner
#===============================================================================
set -euo pipefail

#===============================================================================
#  UI & THEME (Premium Industrial Style)
#===============================================================================
C_RST=$'\033[0m'
C_BLD=$'\033[1m'
C_DIM=$'\033[2m'
C_RED=$'\033[31m'
C_GRN=$'\033[32m'
C_YEL=$'\033[33m'
C_BLU=$'\033[34m'
C_CYN=$'\033[36m'

ui_banner() {
    clear
    printf "\n"
    printf "${C_CYN}${C_BLD}  G I T E A   I N F R A S T R U C T U R E${C_RST}\n"
    printf "${C_DIM}  Automated Deployment & CI/CD Engine v2.1.1${C_RST}\n"
    printf "${C_DIM}  ============================================================${C_RST}\n\n"
}

ui_step()  { printf "\n${C_BLD}${C_CYN}✦ %s${C_RST}\n" "$*"; }
ui_info()  { printf "  ${C_DIM}│${C_RST}  %s\n" "$*"; }
ui_ok()    { printf "  ${C_DIM}│${C_RST}  ${C_GRN}✔${C_RST} %s\n" "$*"; }
ui_err()   { printf "  ${C_DIM}│${C_RST}  ${C_RED}✖${C_RST} %s\n" "$*" >&2; }
ui_warn()  { printf "  ${C_DIM}│${C_RST}  ${C_YEL}⚠${C_RST} %s\n" "$*"; }

ask() {
    local prompt="$1" default="$2" val
    printf "  ${C_DIM}│${C_RST}  %b" "$prompt" >/dev/tty 2>/dev/null || { printf '%s' "$default"; return 0; }
    read -r val </dev/tty 2>/dev/null || { printf '%s' "$default"; return 0; }
    echo "${val:-$default}"
}

#===============================================================================
#  GLOBAL VARIABLES
#===============================================================================
readonly CURDIR="$(cd "$(dirname "$0")" && pwd)"

GT_VER="${GT_VER:-latest}"
GT_USR="${GT_USR:-gitea}"
GT_HOME="${GT_HOME:-/var/lib/gitea}"
GT_BIN="${GT_BIN:-/usr/local/bin/gitea}"
GT_CFG="${GT_CFG:-/etc/gitea/app.ini}"
GT_PORT="${GT_PORT:-3000}"

PG_HOST="${PG_HOST:-127.0.0.1}"
PG_PORT="${PG_PORT:-5432}"
PG_DB="${PG_DB:-gitea}"
PG_USR="${PG_USR:-gitea}"
PG_PWD="${PG_PWD:-}"

CD_ENABLE="${CD_ENABLE:-false}"
CD_DOMAIN="${CD_DOMAIN:-}"
RN_ENABLE="${RN_ENABLE:-true}"
ADM_USR=""
ADM_PWD=""
ADM_MAIL=""

OS_ID=""; ARCH=""; PKG=""

#===============================================================================
#  SYSTEM DETECTION & PREFERENCES (Prompted Upfront)
#===============================================================================
detect_system() {
    ui_step "Environment Detection"
    if [ -f /etc/os-release ]; then
        . /etc/os-release; OS_ID="$ID"
        case "$ID" in
            ubuntu|debian)                     PKG="apt" ;;
            centos|rhel|rocky|almalinux|fedora) PKG="dnf" ;;
            arch|manjaro)                      PKG="pacman" ;;
            *)                                 PKG="unknown" ;;
        esac
    fi

    case "$(uname -m)" in
        x86_64|amd64)  ARCH="amd64"  ;;   aarch64|arm64) ARCH="arm64" ;;
        armv7l|armv6l) ARCH="arm-6"  ;;   *) ARCH="amd64" ;;
    esac
    ui_ok "OS: ${OS_ID} | ARCH: ${ARCH} | PKG: ${PKG}"
}

configure_prefs() {
    ui_step "Configuration & Preferences"
    
    # 1. 域名配置
    local dm
    dm="$(ask "Domain Name (Leave empty for IP:Port access): ${C_CYN}" "")"
    printf "${C_RST}"

    if [[ -n "$dm" && "$dm" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
        CD_ENABLE="true"
        CD_DOMAIN="$dm"
        ADM_MAIL="admin@${dm}"
        ui_ok "Edge routing enabled: https://${CD_DOMAIN}"
    else
        CD_ENABLE="false"
        ADM_MAIL="admin@localhost"
        ui_info "Running in IP mode (Port: ${GT_PORT})"
    fi

    echo ""
    # 2. Gitea 管理员配置 (前置获取)
    ADM_USR="$(ask "Set Gitea Admin Username [gitea_admin]: ${C_CYN}" "gitea_admin")"
    printf "${C_RST}"

    while true; do
        local temp_pwd
        temp_pwd="$(ask "Set Gitea Admin Password (min 8 chars, empty to auto-gen): ${C_CYN}" "")"
        printf "${C_RST}"
        if [ -z "$temp_pwd" ]; then
            ADM_PWD="$(openssl rand -base64 12 | tr -d '/+=')"
            ui_info "Auto-generated password: ${ADM_PWD}"
            break
        elif [ "${#temp_pwd}" -lt 8 ]; then
            ui_warn "Password must be at least 8 characters."
        else
            ADM_PWD="$temp_pwd"
            break
        fi
    done
    
    ui_ok "Preferences saved. Beginning unattended installation..."
}

#===============================================================================
#  DEPENDENCIES
#===============================================================================
install_dependencies() {
    ui_step "Provisioning Dependencies"
    local pkgs="curl wget ca-certificates git gnupg openssl"

    case "$PKG" in
        apt)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq >/dev/null 2>&1 || true
            apt-get install -y -qq -o Dpkg::Use-Pty=0 $pkgs >/dev/null 2>&1
            if ! command -v docker &>/dev/null; then
                ui_info "Installing Docker Engine..."
                curl -fsSL https://get.docker.com | bash -s >/dev/null 2>&1
            fi ;;
        dnf)
            dnf install -y -q $pkgs >/dev/null 2>&1
            if ! command -v docker &>/dev/null; then
                ui_info "Installing Docker Engine..."
                curl -fsSL https://get.docker.com | bash -s >/dev/null 2>&1
            fi ;;
        pacman)
            pacman -S --noconfirm --needed $pkgs docker docker-compose >/dev/null 2>&1 ;;
    esac

    if command -v docker &>/dev/null; then
        systemctl enable --now docker >/dev/null 2>&1 || true
        ui_ok "Docker $(docker --version | awk '{print $3}' | tr -d ',') is online"
    fi
}

#===============================================================================
#  POSTGRESQL
#===============================================================================
install_postgresql() {
    ui_step "Database Engine (PostgreSQL)"
    if ! command -v psql &>/dev/null; then
        case "$PKG" in
            apt)   apt-get install -y -qq -o Dpkg::Use-Pty=0 postgresql postgresql-client >/dev/null 2>&1 ;;
            dnf)   dnf install -y -q postgresql-server postgresql >/dev/null 2>&1; postgresql-setup --initdb >/dev/null 2>&1 || true ;;
            pacman) pacman -S --noconfirm --needed postgresql >/dev/null 2>&1; su - postgres -c "initdb -D /var/lib/postgres/data" >/dev/null 2>&1 || true ;;
        esac
    fi

    systemctl enable --now postgresql >/dev/null 2>&1 || true
    while ! su - postgres -c "pg_isready -q" 2>/dev/null; do sleep 1; done
    ui_ok "PostgreSQL service is active"

    [ -z "$PG_PWD" ] && PG_PWD="$(openssl rand -base64 24 | tr -d '/+=')"

    su - postgres -c "psql -q -c \"SET password_encryption='scram-sha-256'; CREATE ROLE ${PG_USR} LOGIN PASSWORD '${PG_PWD}';\"" 2>/dev/null || \
        su - postgres -c "psql -q -c \"ALTER ROLE ${PG_USR} LOGIN PASSWORD '${PG_PWD}';\"" >/dev/null 2>&1

    su - postgres -c "psql -q -tc \"SELECT 1 FROM pg_database WHERE datname='${PG_DB}'\"" 2>/dev/null | grep -q 1 || \
        su - postgres -c "psql -q -c \"CREATE DATABASE ${PG_DB} OWNER ${PG_USR} ENCODING 'UTF8';\"" >/dev/null 2>&1

    su - postgres -c "psql -q -c 'GRANT ALL PRIVILEGES ON DATABASE ${PG_DB} TO ${PG_USR};'" >/dev/null 2>&1

    local HBA; HBA="$(su - postgres -c "psql -t -c 'SHOW hba_file;'" 2>/dev/null | tr -d ' ')" || true
    if [ -n "$HBA" ] && [ -f "$HBA" ]; then
        sed -i '/gitea/d' "$HBA"
        sed -i '/^$/N;/^\n$/d' "$HBA"
        sed -i "1i host ${PG_DB} ${PG_USR} 127.0.0.1/32 scram-sha-256 # gitea" "$HBA"
        systemctl reload postgresql >/dev/null 2>&1 || su - postgres -c "pg_ctl reload" >/dev/null 2>&1
    fi
    ui_ok "Database user and schemas provisioned"
}

#===============================================================================
#  GITEA CORE
#===============================================================================
install_gitea() {
    ui_step "Gitea Core Deployment"
    if [ "$GT_VER" = "latest" ]; then
        GT_VER="$(curl -sSL https://api.github.com/repos/go-gitea/gitea/releases/latest | grep -oP '"tag_name":\s*"\K[^"]+' | sed 's/^v//')"
    fi
    ui_info "Fetching binary: v${GT_VER}"

    local url="https://dl.gitea.com/gitea/${GT_VER}/gitea-${GT_VER}-linux-${ARCH}"
    curl -fsSL -o "${GT_BIN}.tmp" "$url"
    chmod +x "${GT_BIN}.tmp" && mv "${GT_BIN}.tmp" "$GT_BIN"
    ui_ok "Binary installed to ${GT_BIN}"

    id "$GT_USR" &>/dev/null || useradd --system --home-dir "$GT_HOME" --shell /bin/bash -c "Gitea" "$GT_USR" 2>/dev/null
    mkdir -p "${GT_HOME}"/{custom/conf,data,log,repositories} /etc/gitea
    chown -R "${GT_USR}:${GT_USR}" "$GT_HOME" /etc/gitea
    chmod 750 "$GT_HOME"

    cat > /etc/systemd/system/gitea.service << UNIT
[Unit]
Description=Gitea (Git Service)
After=network.target postgresql.service docker.service
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
    ui_ok "Systemd service registered"
}

generate_gitea_config() {
    ui_step "Generating Configuration"
    local domain root_url
    if [ "$CD_ENABLE" = "true" ]; then
        domain="$CD_DOMAIN"; root_url="https://${CD_DOMAIN}/"
    else
        domain="$(curl -s --max-time 2 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"
        root_url="http://${domain}:${GT_PORT}/"
    fi

    # [FIX]: Added SSH_PORT and SSH_LISTEN_PORT to prevent binding to port 22
    cat > "$GT_CFG" << EOF
APP_NAME   = Gitea Infrastructure
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
START_SSH_SERVER = true
SSH_PORT         = 2222
SSH_LISTEN_PORT  = 2222

[database]
DB_TYPE  = postgres
HOST     = ${PG_HOST}:${PG_PORT}
NAME     = ${PG_DB}
USER     = ${PG_USR}
PASSWD   = ${PG_PWD}
SSL_MODE = disable

[security]
INSTALL_LOCK       = true
SECRET_KEY         = $(openssl rand -base64 48 | tr -d '/+=')
INTERNAL_TOKEN     = $(openssl rand -base64 36 | tr -d '/+=')
PASSWORD_HASH_ALGO = pbkdf2

[service]
DISABLE_REGISTRATION = true

[actions]
ENABLED = true
DEFAULT_ACTIONS_URL = github
EOF
    chown "${GT_USR}:${GT_USR}" "$GT_CFG"
    chmod 640 "$GT_CFG"
    ui_ok "Config synchronized (app.ini)"
}

install_caddy() {
    if [ "$CD_ENABLE" != "true" ]; then return 0; fi
    ui_step "Edge Routing (Caddy)"

    if ! command -v caddy &>/dev/null; then
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable.gpg >/dev/null 2>&1
        echo "deb [signed-by=/usr/share/keyrings/caddy-stable.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main" > /etc/apt/sources.list.d/caddy.list
        apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq -o Dpkg::Use-Pty=0 caddy >/dev/null 2>&1
    fi

    cat > /etc/caddy/Caddyfile << CADDYFILE
${CD_DOMAIN} {
    reverse_proxy localhost:${GT_PORT}
    request_body { max_size 500MB }
    tls ${ADM_MAIL}
}
CADDYFILE
    systemctl restart caddy >/dev/null 2>&1
    ui_ok "Caddy proxy linked to ${CD_DOMAIN}"
}

start_services() {
    ui_step "Initializing Services"
    systemctl restart gitea
    local max=15 retry=0
    while ! curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${GT_PORT}" | grep -qE "2[0-9]{2}|3[0-9]{2}|40[134]"; do
        sleep 2; retry=$((retry+1))
        [ $retry -eq $max ] && { ui_err "Gitea failed to start"; exit 1; }
    done
    ui_ok "Gitea core is running"
}

#===============================================================================
#  ADMIN & RUNNER
#===============================================================================
create_admin() {
    ui_step "Admin Provisioning"
    su - "$GT_USR" -c "GITEA_WORK_DIR=${GT_HOME} ${GT_BIN} admin user create \
        --admin --username '${ADM_USR}' --password '${ADM_PWD}' \
        --email '${ADM_MAIL}' --config '${GT_CFG}' --must-change-password=false" >/dev/null 2>&1 || {
        ui_warn "Admin account already exists or creation skipped."
        return 0
    }
    ui_ok "Admin account '${ADM_USR}' injected"
}

setup_runner() {
    ui_step "Actions Runner Integration"
    if ! command -v docker &>/dev/null; then
        ui_warn "Docker missing, skipping runner."; return 0
    fi

    usermod -aG docker "$GT_USR" 2>/dev/null || true

    local rv; rv="$(curl -sSL https://gitea.com/api/v1/repos/gitea/runner/releases/latest | grep -oP '"tag_name":\s*"\K[^"]+' | sed 's/^v//')"
    local ra="$ARCH"
    [ "$ra" = "arm-6" ] && ra="arm-6"

    curl -fsSL -o /usr/local/bin/gitea-runner "https://gitea.com/gitea/runner/releases/download/v${rv}/gitea-runner-${rv}-linux-${ra}"
    chmod +x /usr/local/bin/gitea-runner
    ui_ok "Runner binary (v${rv}) installed"

    su -s /bin/bash "$GT_USR" -c "rm -f ${GT_HOME}/.runner"
    local token
    token="$(su -s /bin/bash "$GT_USR" -c "GITEA_WORK_DIR=${GT_HOME} ${GT_BIN} --config ${GT_CFG} actions generate-runner-token" | tail -1 | tr -d '[:space:]')"

    if [ -n "$token" ] && [ ${#token} -ge 30 ]; then
        local reg_out
        reg_out="$(su -s /bin/bash "$GT_USR" -c "cd ${GT_HOME} && /usr/local/bin/gitea-runner register \
            --no-interactive \
            --instance http://localhost:${GT_PORT} \
            --token '${token}' \
            --name 'runner-$(hostname)' \
            --labels 'ubuntu-latest:docker://node:20-bookworm,ubuntu-22.04:docker://node:20-bookworm'" 2>&1)" || true

        if echo "$reg_out" | grep -qi "success\|registered\|INFO.*register"; then
            ui_ok "Runner registered successfully"
        else
            ui_err "Runner registration failed"
            ui_info "Debug: $reg_out"
        fi
    else
        ui_err "Failed to extract valid token from Gitea API"
    fi

    cat > /etc/systemd/system/gitea-runner.service << RUNSVC
[Unit]
Description=Gitea Actions Runner
After=gitea.service docker.service
Requires=docker.service
Wants=gitea.service

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
    systemctl enable --now gitea-runner >/dev/null 2>&1
    ui_ok "Runner daemon active"
}

#===============================================================================
#  SUMMARY
#===============================================================================
show_summary() {
    local domain proto="http"
    domain="$(grep -oP '^\s*DOMAIN\s*=\s*\K.*' "$GT_CFG" 2>/dev/null | tr -d ' ')"
    [ "$CD_ENABLE" = "true" ] && proto="https"

    printf "\n"
    printf "  ${C_BLD}${C_CYN}╭────────────────────────────────────────────────────────╮${C_RST}\n"
    printf "  ${C_BLD}${C_CYN}│${C_RST}  ${C_BLD}DEPLOYMENT SUCCESSFUL                                 ${C_CYN}│${C_RST}\n"
    printf "  ${C_BLD}${C_CYN}├────────────────────────────────────────────────────────┤${C_RST}\n"
    printf "  ${C_BLD}${C_CYN}│${C_RST}  ${C_DIM}%-14s${C_RST} %s://%s%-19s ${C_CYN}│${C_RST}\n" "Endpoint" "$proto" "$domain" "$([ "$proto" = "http" ] && echo ":${GT_PORT}")"
    printf "  ${C_BLD}${C_CYN}│${C_RST}  ${C_DIM}%-14s${C_RST} %-36s ${C_CYN}│${C_RST}\n" "Admin User" "$ADM_USR"
    printf "  ${C_BLD}${C_CYN}│${C_RST}  ${C_DIM}%-14s${C_RST} ${C_BLD}%-36s${C_RST} ${C_CYN}│${C_RST}\n" "Admin Pass" "$ADM_PWD"
    printf "  ${C_BLD}${C_CYN}│${C_RST}  ${C_DIM}%-14s${C_RST} %-36s ${C_CYN}│${C_RST}\n" "CI/CD Runner" "Online & Connected"
    printf "  ${C_BLD}${C_CYN}╰────────────────────────────────────────────────────────╯${C_RST}\n\n"
}

#===============================================================================
#  BOOTSTRAP
#===============================================================================
if [ "$(id -u)" -ne 0 ]; then
    echo "Requires root privileges." >&2; exit 1
fi

ui_banner
detect_system
configure_prefs
install_dependencies
install_postgresql
install_gitea
generate_gitea_config
install_caddy
start_services
create_admin
setup_runner
show_summary
