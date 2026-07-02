# 🍵 Gitea Tools Manager

> 一键部署 Gitea + Caddy 反向代理 + Actions Runner + PostgreSQL 的全自动脚本

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-linux%2Famd64%7Carm64-brightgreen.svg)]()
[![Shell](https://img.shields.io/badge/shell-bash-4EAA25.svg)]()

---

## ✨ 功能特性

- 🚀 **一键安装** — Gitea + Caddy 反代 + PostgreSQL + Actions Runner 全自动部署
- 🌐 **Caddy 反向代理** — 输入域名即可自动配置 HTTPS + Let's Encrypt SSL
- 🏗️ **多架构支持** — amd64 / arm64 / armv7 / riscv64 / loong64
- 🐘 **PostgreSQL 数据库** — 自动安装、配置、授权
- 🐳 **Actions Runner** — Docker 环境 + act_runner 自动配置
- 🔄 **更新检测** — 支持手动检查 `check` / 一键更新 `update`
- 📡 **后台监控** — `watch` 模式定时检查新版本
- 🎨 **美观输出** — 彩色终端 UI、进度条、表格面板
- 🔐 **自动生成密码** — 数据库 & 管理员密码自动生成并保存
- 📦 **多发行版** — Ubuntu / Debian / CentOS / Rocky / Fedora / Arch

---

## 📋 系统要求

| 项目 | 要求 |
|------|------|
| 操作系统 | Linux (Debian/Ubuntu, RHEL/CentOS/Rocky, Arch) |
| 权限 | root (sudo) |
| 内存 | ≥ 1 GB (推荐 2 GB+) |
| 磁盘 | ≥ 2 GB 可用空间 |
| 网络 | 需访问 GitHub、Gitea 官方下载站 |

---

## 🚀 快速开始

```bash
# 1. 克隆仓库
git clone https://github.com/MomoFlora/Gitea-Tools-Manager.git
cd Gitea-Tools-Manager

# 2. 赋予执行权限
chmod +x gitea-manager.sh

# 3. 一键安装
sudo ./gitea-manager.sh install
```

安装完成后，打开浏览器访问 `http://<你的服务器IP>:3000`，使用脚本输出的管理员账号密码登录。

---

## 📖 命令说明

```
用法: ./gitea-manager.sh <命令> [选项]

命令:
  install     一键安装 Gitea + Caddy 反代 + PostgreSQL + Actions Runner
  update      更新 Gitea 到最新版本
  check       检查是否有新版本
  status      查看服务运行状态
  config      显示当前配置信息
  watch       后台监控更新 (可选: 检查间隔秒数)
  uninstall   卸载 Gitea 及相关服务

示例:
  sudo ./gitea-manager.sh install      # 完整安装
  ./gitea-manager.sh check             # 检查更新
  ./gitea-manager.sh watch 43200       # 每12小时检查一次
```

---

## 🏗️ 安装流程

```
┌─────────────────────────────────────────────────────────┐
│  Step 1  配置域名 & Caddy 反代 (交互式输入)               │
│  Step 2  安装系统依赖 (curl, git, gnupg, ...)            │
│  Step 3  安装 PostgreSQL 数据库                          │
│  Step 4  创建数据库 & 用户 & 授权                         │
│  Step 5  安装 Caddy Web Server                           │
│  Step 6  获取 Gitea 最新版本号                            │
│  Step 7  创建 Gitea 系统用户                             │
│  Step 8  创建目录结构                                    │
│  Step 9  生成 Gitea 配置文件 (app.ini)                   │
│  Step 10 下载 Gitea 二进制 (SHA256 校验)                 │
│  Step 11 创建 Systemd 服务                               │
│  Step 12 启动 Gitea 服务 & 健康检查                       │
│  Step 13 配置 Caddy 反向代理 + SSL 证书                   │
│  Step 14 创建管理员用户                                   │
│          + 配置 Actions Runner + Docker                  │
└─────────────────────────────────────────────────────────┘
```

---

## 🔧 安装后配置

### 注册 Actions Runner

```bash
# 登录 Gitea → Site Administration → Actions → Runners → Create new Runner
# 复制 Registration Token，然后运行:
sudo /var/lib/gitea/register-runner.sh
```

### 反向代理与 HTTPS

安装脚本会**交互式提示你输入域名**（如 `git.example.com`）。输入后 Caddy 自动：

1. 配置反向代理（Gitea → 你的域名）
2. 通过 Let's Encrypt 自动申请 SSL 证书
3. 启用 HTTP→HTTPS 自动跳转
4. 配置防火墙规则（UFW / Firewalld）
5. 证书到期自动续期，无需人工干预

如果留空则跳过，Gitea 将直接通过 HTTP + IP:端口 访问。

```bash
# 安装时会提示：
#   请输入域名 (留空跳过反代配置): git.example.com
```

之后可以通过 `systemctl status caddy` 查看 Caddy 状态。

---

## 🔄 更新

```bash
# 检查是否有更新
./gitea-manager.sh check

# 执行更新 (自动备份配置、下载新版本、重启服务)
sudo ./gitea-manager.sh update

# 后台定时检查 (配合 screen/tmux 使用)
./gitea-manager.sh watch 86400
```

---

## 📁 文件结构

```
/usr/local/bin/gitea                    # Gitea 可执行文件
/usr/local/bin/act_runner               # Actions Runner 可执行文件
/etc/gitea/app.ini                      # Gitea 配置文件
/etc/caddy/Caddyfile                    # Caddy 反代配置
/var/lib/gitea/                         # Gitea 数据目录
/var/lib/gitea/repositories/            # Git 仓库存储
/var/lib/gitea/.runner/                 # Actions Runner 配置
/var/log/caddy/gitea.log                # Caddy 访问日志
/etc/systemd/system/gitea.service       # Gitea 服务
/etc/systemd/system/caddy.service       # Caddy 服务
/etc/systemd/system/gitea-actions-runner.service  # Runner 服务
```

---

## 🗑️ 卸载

```bash
sudo ./gitea-manager.sh uninstall
```

输入 `DELETE` 确认。此操作将删除 Gitea 服务、配置文件、数据目录和数据库。

---

## 🎨 终端预览

```
  ██████╗ ██╗████████╗███████╗ █████╗
 ██╔════╝ ██║╚══██╔══╝██╔════╝██╔══██╗
 ██║  ███╗██║   ██║   █████╗  ███████║
 ██║   ██║██║   ██║   ██╔══╝  ██╔══██║
 ╚██████╔╝██║   ██║   ███████╗██║  ██║
  ╚═════╝ ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝

  Tools Manager v1.0.0
  Gitea + Caddy 反代 + Actions Runner + PostgreSQL 一键部署

┌─ Step 1/14 ──────────────────────────────────────────────────┐
│ ▶ 配置域名与反向代理
└──────────────────────────────────────────────────────────────┘
  ┌─────────────────────────────────────────────────────────────┐
  │                     🌐 反向代理配置                          │
  ├─────────────────────────────────────────────────────────────┤
  │  Caddy 将自动为你的域名申请 SSL 证书 (Let's Encrypt)         │
  │  实现 HTTPS 安全访问 + 自动续期                             │
  └─────────────────────────────────────────────────────────────┘

  你的服务器 IP: 192.168.1.100
  请确保域名 DNS 已解析到该 IP 地址

  请输入域名 (留空跳过反代配置): git.example.com

  ╔══════════════════════════════════════════════════════════════╗
  ║  域名配置确认                                                ║
  ║ ──────────────────────────────────────────────────────────── ║
  ║  域名:       git.example.com                                 ║
  ║  Gitea 地址: https://git.example.com                         ║
  ║  SSH 地址:   git@git.example.com                             ║
  ║  SSL 证书:   Let's Encrypt 自动管理                          ║
  ╚══════════════════════════════════════════════════════════════╝

  ... 后续步骤 ...

  ╔══════════════════════════════════════════════════════════════╗
  ║              ✅ 安装全部完成!                                ║
  ╚══════════════════════════════════════════════════════════════╝

  ╔══════════════════════════════════════════════════════════════╗
  ║ 📊 Gitea 服务状态                                           ║
  ║ ────────────────────────────────────────────────────────────║
  ║ Gitea:          ● 运行中                                    ║
  ║ PostgreSQL:     ● 运行中                                    ║
  ║ Actions Runner: ● 已安装                                    ║
  ║ Caddy (HTTPS):  ● 运行中                                    ║
  ║                                                              ║
  ║ 🌐 访问地址: https://git.example.com                        ║
  ╚══════════════════════════════════════════════════════════════╝

  ┌─────────────────────────────────────────────────────────────┐
  │                    🔐 管理员凭据                             │
  ├─────────────────────────────────────────────────────────────┤
  │  用户名: gitea_admin                                        │
  │  密码:   xxxxxxxxxxxxxxxxxxxxxxxx                           │
  │  ⚠ 请立即登录修改密码!                                      │
  └─────────────────────────────────────────────────────────────┘
```

---

## 📄 License

MIT © [MomoFlora](https://github.com/MomoFlora)
