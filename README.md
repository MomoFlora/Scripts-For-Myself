# Gitea Tools Manager

> Gitea · Caddy · PostgreSQL · Actions Runner — 一键部署

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-linux%2Famd64%7Carm64-brightgreen.svg)]()

---

## 快速开始

```bash
curl -fsSL https://raw.githubusercontent.com/MomoFlora/Gitea-Tools-Manager/refs/heads/master/gitea-manager.sh | sudo bash -s install
```

安装时输入你的域名（如 `git.example.com`），Caddy 自动申请 Let's Encrypt SSL 证书实现 HTTPS。留空则跳过。

## 命令

```bash
sudo ./gitea-manager.sh install      # 一键部署
./gitea-manager.sh status            # 查看服务状态
./gitea-manager.sh check             # 检查更新
sudo ./gitea-manager.sh update       # 升级到最新版
sudo ./gitea-manager.sh uninstall    # 完全卸载
```

## 安装流程 (10 步)

```
[01/10] 检测系统环境        → OS / 架构
[02/10] 域名配置            → 交互式输入 / 跳过
[03/10] 安装系统依赖        → curl git docker ...
[04/10] 安装 PostgreSQL     → 数据库 + 用户 + scram-sha-256
[05/10] 安装 Gitea          → 下载二进制 + 用户 + systemd
[06/10] 生成 Gitea 配置     → app.ini (PostgreSQL 后端)
[07/10] 安装 Caddy          → 反代 + 自动 HTTPS
[08/10] 启动全部服务        → PostgreSQL → Gitea → Caddy
[09/10] 创建管理员账户      → 自动生成密码
[10/10] 配置 Actions Runner → act_runner + Docker
```

## 支持系统

| 发行版 | 架构 |
|--------|------|
| Debian / Ubuntu | amd64, arm64, armv7, riscv64, loong64 |
| RHEL / Rocky / Alma / Fedora | amd64, arm64 |
| Arch | amd64 |

## 文件结构

```
/usr/local/bin/gitea            # Gitea 二进制
/etc/gitea/app.ini              # Gitea 配置
/etc/caddy/Caddyfile            # Caddy 反代配置
/var/lib/gitea/                 # Gitea 数据目录
/etc/systemd/system/gitea.service
```

## 终端预览

```
────────────────────────────────────────────────────────────────
  Gitea Tools Manager  v1.1.0
  Gitea · Caddy · PostgreSQL · Actions  —  一键部署
────────────────────────────────────────────────────────────────

  [01/10] 检测系统环境
  ────────────────────────────────────────────────────────────
    ✓ 系统: debian 12 · 架构: amd64

  [02/10] 域名配置
  ────────────────────────────────────────────────────────────
    域名 (留空跳过): git.example.com

    域名:       git.example.com
    访问地址:   https://git.example.com
    SSL 证书:   Let's Encrypt 自动管理

  ... ...

  ──────────────────────────────────────────────────────────────
  部署完成
  ──────────────────────────────────────────────────────────────

    服务         状态           版本         端口
  ──────────────────────────────────────────────────────────────
    Gitea        ● 运行中       v1.26.4      3000
    PostgreSQL   ● 运行中       15.7         5432
    Caddy        ● 运行中       v2.8.4       80/443

    访问地址:  https://git.example.com
    管理员:    gitea_admin   密码: kVHiTX4FEg0UxbT
```

## License

MIT © [MomoFlora](https://github.com/MomoFlora)
