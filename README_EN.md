<p align="center">
  <img src="https://img.shields.io/badge/Scripts-For%20Myself-333.svg?style=for-the-badge" alt="Scripts For Myself">
  <br>
  <img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License">
  <img src="https://img.shields.io/badge/platform-linux%2Famd64%7Carm64-brightgreen.svg" alt="Platform">
  <img src="https://img.shields.io/badge/shell-bash-4EAA25.svg?logo=gnubash&logoColor=white" alt="Shell">
</p>

<h3 align="center">Personal Collection · One-Click Deploy Scripts</h3>

<p align="center">
  <a href="#-caddy">Caddy Installer</a> ·
  <a href="#-gitea">Gitea Deployer</a> ·
  <a href="#-quick-reference">Quick Reference</a> ·
  <a href="#-file-structure">File Structure</a> ·
  <a href="README.md">中文</a>
</p>

---

## 🚀 Caddy — EasyCaddy Installer

> Install Caddy Web Server via APT from the [EasyCaddy](https://github.com/MomoFlora/EasyCaddy) custom repository.

### One-Liner

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/MomoFlora/Scripts-For-Myself/refs/heads/master/scripts/caddy_install.sh)"
```

Or run locally:

```bash
sudo bash scripts/caddy_install.sh
```

### Installation Steps (3 stages)

```
[1/3] GPG Keyring    → /usr/share/keyrings/caddy-archive-keyring.gpg
[2/3] APT Source     → /etc/apt/sources.list.d/caddy.list
[3/3] Install Caddy  → apt update && apt install caddy
```

### Terminal Preview

```
  ═══════════════════════════════════════════════════════
         C A D D Y   W E B   S E R V E R
         EasyCaddy APT Installer
  ═══════════════════════════════════════════════════════

  ✦ Environment Detection
    │  ✔ OS: Debian GNU/Linux 12 | Arch: x86_64
    │  ✔ Package manager: APT
    │  ✔ curl 8.5.0

  ✦ GPG Keyring
    │  ✔ Keyring saved → /usr/share/keyrings/caddy-archive-keyring.gpg
    │  ✔ Keyring validated (1234 bytes)

  ✦ APT Repository
    │  ✔ Repository source registered

  ✦ Package Installation
    │  ✔ Package index updated
    │  ✔ Caddy installed successfully

  ✦ Post-Install Validation
    │  ✔ Binary: /usr/bin/caddy
    │  ✔ Systemd service: enabled
    │  ✔ Service status: running

  ╭───────────────────────────────────────────────────╮
  │  INSTALLATION COMPLETE                            │
  ├───────────────────────────────────────────────────┤
  │  Version    v2.9.1                                │
  │  Binary     /usr/bin/caddy                        │
  │  Source     EasyCaddy (MomoFlora)                 │
  ╰───────────────────────────────────────────────────╯

  Quick Reference
  ─────────────────────────────────────────────────────
  ▸  Start & enable     systemctl enable --now caddy
  ▸  Edit config         nano /etc/caddy/Caddyfile
  ▸  Reload config       systemctl reload caddy
  ▸  View logs           journalctl -u caddy -f
```

---

## 🏗 Gitea — Full-Stack Infrastructure

> Deploy Gitea + Caddy + PostgreSQL + Actions Runner in one shot.

### One-Liner

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/MomoFlora/Scripts-For-Myself/refs/heads/master/scripts/gitea_install.sh)"
```

Enter your domain (e.g. `git.example.com`) when prompted — Caddy auto-provisions Let's Encrypt SSL. Leave blank for IP:Port mode.

### Installation Flow (10 steps)

```
[01/10] Environment Detection   → OS / Arch
[02/10] Domain Configuration    → Interactive input / skip
[03/10] System Dependencies     → curl git docker ...
[04/10] PostgreSQL Setup        → Database + user + scram-sha-256
[05/10] Gitea Binary            → Download + user + systemd
[06/10] Gitea Config            → app.ini (PostgreSQL backend)
[07/10] Caddy Reverse Proxy     → Auto HTTPS
[08/10] Start All Services      → PostgreSQL → Gitea → Caddy
[09/10] Admin Account           → Auto-generated credentials
[10/10] Actions Runner          → act_runner + Docker
```

### Supported Platforms

| Distribution | Architecture |
|--------------|--------------|
| Debian / Ubuntu | amd64, arm64, armv7, riscv64, loong64 |
| RHEL / Rocky / Alma / Fedora | amd64, arm64 |
| Arch | amd64 |

---

## 📋 Quick Reference

### Caddy

```bash
systemctl enable --now caddy    # Start & enable on boot
systemctl reload caddy          # Graceful config reload
systemctl status caddy          # Check service status
journalctl -u caddy -f          # Follow logs
caddy validate --config /etc/caddy/Caddyfile  # Validate config
nano /etc/caddy/Caddyfile       # Edit Caddyfile
```

### Gitea

```bash
systemctl restart gitea         # Restart Gitea
systemctl status gitea          # Check service status
journalctl -u gitea -f          # Follow logs
nano /etc/gitea/app.ini         # Edit configuration
su - gitea -c "gitea admin user list"  # List admin users
```

---

## 📁 File Structure

```
/usr/bin/caddy                     # Caddy binary
/etc/caddy/Caddyfile               # Caddy configuration
/etc/systemd/system/caddy.service  # Caddy systemd unit

/usr/local/bin/gitea               # Gitea binary
/etc/gitea/app.ini                 # Gitea configuration
/var/lib/gitea/                    # Gitea data directory
/etc/systemd/system/gitea.service  # Gitea systemd unit

/etc/systemd/system/gitea-runner.service  # Actions Runner unit
```

---

## ⚙ Environment Variables

Customize behavior before running:

```bash
# Caddy Installer (fully automated, no interaction)
sudo bash scripts/caddy_install.sh

# Gitea Deployer
export GT_VER="1.23.0"       # Pin Gitea version, default latest
export GT_PORT="8080"        # Custom HTTP port, default 3000
export CD_ENABLE="true"      # Force Caddy reverse proxy
export CD_DOMAIN="git.example.com"  # Pre-set domain (skip prompt)
sudo -E bash scripts/gitea_install.sh
```

---

## 📄 License

MIT © [MomoFlora](https://github.com/MomoFlora)
