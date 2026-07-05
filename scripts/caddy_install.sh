#!/usr/bin/env bash
#===============================================================================
#  CADDY WEB SERVER — EASYCADDY INSTALLER
#  Version: 1.0.0
#  Source:  https://github.com/MomoFlora/EasyCaddy
#  Installs Caddy with APT + EasyCaddy GPG keyring
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

readonly C_RST C_BLD C_DIM C_RED C_GRN C_YEL C_BLU C_CYN

ui_banner() {
    clear
    printf "\n"
    printf "${C_CYN}${C_BLD}  C A D D Y   W E B   S E R V E R${C_RST}\n"
    printf "${C_DIM}  EasyCaddy APT Installer — github.com/MomoFlora/EasyCaddy${C_RST}\n"
    printf "${C_DIM}  ============================================================${C_RST}\n\n"
}

ui_step()  { printf "\n${C_BLD}${C_CYN}✦ %s${C_RST}\n" "$*"; }
ui_info()  { printf "  ${C_DIM}│${C_RST}  %s\n" "$*"; }
ui_ok()    { printf "  ${C_DIM}│${C_RST}  ${C_GRN}✔${C_RST} %s\n" "$*"; }
ui_err()   { printf "  ${C_DIM}│${C_RST}  ${C_RED}✖${C_RST} %s\n" "$*" >&2; }
ui_warn()  { printf "  ${C_DIM}│${C_RST}  ${C_YEL}⚠${C_RST} %s\n" "$*"; }

#===============================================================================
#  CONSTANTS
#===============================================================================
readonly GPG_KEYRING="/usr/share/keyrings/caddy-archive-keyring.gpg"
readonly APT_SOURCE="/etc/apt/sources.list.d/caddy.list"
readonly GPG_URL="https://github.com/MomoFlora/EasyCaddy/releases/latest/download/caddy-archive-keyring.gpg"
readonly APT_REPO="https://github.com/MomoFlora/EasyCaddy/releases/latest/download/"

#===============================================================================
#  SYSTEM DETECTION
#===============================================================================
detect_system() {
    ui_step "Environment Detection"

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            ubuntu|debian) ;;
            *)
                ui_err "Unsupported OS: ${ID}. This script only supports Debian/Ubuntu."
                exit 1
                ;;
        esac
        ui_ok "OS: ${NAME} ${VERSION_ID:-} | Arch: $(uname -m)"
    else
        ui_err "Cannot detect OS — /etc/os-release missing."
        exit 1
    fi

    if ! command -v apt &>/dev/null; then
        ui_err "APT package manager not found."
        exit 1
    fi
    ui_ok "Package manager: APT"

    if ! command -v curl &>/dev/null; then
        ui_info "curl not found — installing..."
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq >/dev/null 2>&1 || true
        apt-get install -y -qq -o Dpkg::Use-Pty=0 curl >/dev/null 2>&1
        ui_ok "curl installed"
    else
        ui_ok "curl $(curl --version | head -1 | awk '{print $2}')"
    fi
}

#===============================================================================
#  STEP 1 — GPG KEYRING
#===============================================================================
install_gpg_keyring() {
    ui_step "GPG Keyring"

    ui_info "Fetching: ${GPG_URL}"

    if curl -fsSL "${GPG_URL}" | tee "${GPG_KEYRING}" > /dev/null; then
        ui_ok "Keyring saved → ${GPG_KEYRING}"
    else
        ui_err "Failed to download GPG keyring — check network connectivity."
        exit 1
    fi

    if [[ ! -s "${GPG_KEYRING}" ]]; then
        ui_err "GPG keyring file is empty or corrupt."
        exit 1
    fi
    ui_ok "Keyring validated ($(stat -c%s "${GPG_KEYRING}" 2>/dev/null || stat -f%z "${GPG_KEYRING}" 2>/dev/null || echo 'ok') bytes)"
}

#===============================================================================
#  STEP 2 — APT SOURCE
#===============================================================================
add_apt_source() {
    ui_step "APT Repository"

    local apt_line="deb [signed-by=${GPG_KEYRING}] ${APT_REPO} ./"

    # Backup existing source file if present
    if [[ -f "${APT_SOURCE}" ]]; then
        local backup="${APT_SOURCE}.bak.$(date +%Y%m%d%H%M%S)"
        cp -f "${APT_SOURCE}" "${backup}"
        ui_info "Previous source backed up → ${backup}"
    fi

    echo "${apt_line}" | tee "${APT_SOURCE}" > /dev/null
    ui_ok "Repository source registered"
    ui_info "${C_DIM}${apt_line}${C_RST}"
}

#===============================================================================
#  STEP 3 — INSTALL CADDY
#===============================================================================
install_caddy_pkg() {
    ui_step "Package Installation"

    # Check if already installed
    if command -v caddy &>/dev/null; then
        local existing_ver
        existing_ver=$(caddy version 2>&1 | head -1)
        ui_warn "Caddy already present: ${existing_ver}"
        ui_info "Proceeding with upgrade/reinstall..."
    fi

    ui_info "Refreshing package index..."
    if apt-get update -qq 2>&1; then
        ui_ok "Package index updated"
    else
        ui_err "apt-get update failed — check your APT sources."
        exit 1
    fi

    ui_info "Installing caddy..."
    if apt-get install -y caddy 2>&1; then
        ui_ok "Caddy installed successfully"
    else
        ui_err "apt-get install caddy failed."
        exit 1
    fi
}

#===============================================================================
#  POST-INSTALL — VALIDATE & CONFIGURE
#===============================================================================
post_install() {
    ui_step "Post-Install Validation"

    # Verify binary
    if ! command -v caddy &>/dev/null; then
        ui_err "Caddy binary not found on PATH — installation may have failed."
        exit 1
    fi

    local caddy_ver caddy_bin
    caddy_ver=$(caddy version 2>&1 | head -1)
    caddy_bin=$(command -v caddy)
    ui_ok "Binary: ${caddy_bin}"
    ui_info "${C_DIM}${caddy_ver}${C_RST}"

    # Service status
    if systemctl is-enabled --quiet caddy 2>/dev/null; then
        ui_ok "Systemd service: ${C_GRN}enabled${C_RST}"
    else
        ui_warn "Systemd service: not enabled"
        ui_info "  Run → ${C_CYN}systemctl enable --now caddy${C_RST}"
    fi

    if systemctl is-active --quiet caddy 2>/dev/null; then
        ui_ok "Service status: ${C_GRN}running${C_RST}"
    else
        ui_info "Service status: ${C_YEL}stopped${C_RST}"
        ui_info "  Run → ${C_CYN}systemctl start caddy${C_RST}"
    fi

    # Config check
    if [[ -d /etc/caddy ]]; then
        ui_ok "Config directory: /etc/caddy"
    fi
}

#===============================================================================
#  SUMMARY SCREEN
#===============================================================================
show_summary() {
    local caddy_ver
    caddy_ver=$(caddy version 2>&1 | head -1)

    printf "\n"
    printf "  ${C_BLD}${C_CYN}╭────────────────────────────────────────────────────────╮${C_RST}\n"
    printf "  ${C_BLD}${C_CYN}│${C_RST}  ${C_BLD}INSTALLATION COMPLETE                                   ${C_CYN}│${C_RST}\n"
    printf "  ${C_BLD}${C_CYN}├────────────────────────────────────────────────────────┤${C_RST}\n"
    printf "  ${C_BLD}${C_CYN}│${C_RST}  ${C_DIM}%-14s${C_RST} %-36s ${C_CYN}│${C_RST}\n" "Version" "${caddy_ver}"
    printf "  ${C_BLD}${C_CYN}│${C_RST}  ${C_DIM}%-14s${C_RST} %-36s ${C_CYN}│${C_RST}\n" "Binary" "$(command -v caddy)"
    printf "  ${C_BLD}${C_CYN}│${C_RST}  ${C_DIM}%-14s${C_RST} %-36s ${C_CYN}│${C_RST}\n" "Source" "EasyCaddy (MomoFlora)"
    printf "  ${C_BLD}${C_CYN}╰────────────────────────────────────────────────────────╯${C_RST}\n"

    printf "\n"
    printf "  ${C_BLD}Quick Reference${C_RST}\n"
    printf "  ${C_DIM}─────────────────────────────────────────────────────${C_RST}\n"
    printf "  ${C_DIM}▸${C_RST}  Start & enable     ${C_CYN}systemctl enable --now caddy${C_RST}\n"
    printf "  ${C_DIM}▸${C_RST}  Edit config         ${C_CYN}nano /etc/caddy/Caddyfile${C_RST}\n"
    printf "  ${C_DIM}▸${C_RST}  Reload config       ${C_CYN}systemctl reload caddy${C_RST}\n"
    printf "  ${C_DIM}▸${C_RST}  View logs           ${C_CYN}journalctl -u caddy -f${C_RST}\n"
    printf "  ${C_DIM}▸${C_RST}  Test config         ${C_CYN}caddy validate --config /etc/caddy/Caddyfile${C_RST}\n"
    printf "  ${C_DIM}▸${C_RST}  Check status        ${C_CYN}systemctl status caddy${C_RST}\n"
    printf "\n"
    printf "  ${C_DIM}Repository: https://github.com/MomoFlora/EasyCaddy${C_RST}\n"
    printf "\n"
}

#===============================================================================
#  ERROR HANDLER
#===============================================================================
on_error() {
    printf "\n"
    printf "  ${C_RED}${C_BLD}✖  Installation aborted due to an unexpected error.${C_RST}\n"
    printf "  ${C_DIM}Please review the output above for details.${C_RST}\n\n"
    exit 1
}

trap on_error ERR

#===============================================================================
#  ENTRY POINT
#===============================================================================
main() {
    # Root check
    if [ "$(id -u)" -ne 0 ]; then
        printf "${C_RED}${C_BLD}Error: This script must be run as root.${C_RST}\n" >&2
        printf "${C_DIM}Please re-run with:  sudo bash %s${C_RST}\n" "$0" >&2
        exit 1
    fi

    ui_banner
    detect_system
    install_gpg_keyring
    add_apt_source
    install_caddy_pkg
    post_install
    show_summary
}

main "$@"
