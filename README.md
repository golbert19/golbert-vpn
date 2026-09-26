# 🚀 Golbert VPN & VPS Management Panel

An automated Bash setup script and interactive CLI management panel for Debian/Ubuntu VPS instances. Designed for managing multi-protocol tunneling including SSH/Dropbear, SSL/TLS proxies, HTTP/WebSocket payloads, BadVPN UDPGW, and multi-login connection limits.

---

## 📌 Key Features

- 👤 **SSH & Dropbear User Management:** Simple options to create, edit, extend expiration dates, and delete users.
- 🔒 **Multi-Login Limiter:** Embedded background daemon (`golbert-limiter.service`) enforcing maximum simultaneous connection counts.
- 🌐 **Multi-Protocol Proxying:** Integrated Python HTTP/WebSocket proxy handling custom payloads across multiple listening ports (`80`, `8080`, `8880`).
- 🔐 **SSL/TLS Tunneling:** Automatic `stunnel4` wrapper bound to port `443` supporting Cloudflare domains and custom SSL certificates.
- 🎮 **BadVPN UDPGW:** Dual UDP gateway instances on ports `7300` and `8180` (HCR) for low-latency UDP application and gaming support.
- 🧹 **Automated Housekeeping:** Automated Cron task (`expcleaner.sh`) running every 6 hours to purge expired accounts and clean up system/journal logs.
- 📊 **Resource Dashboard:** Real-time visual monitoring displaying CPU load, RAM usage, storage availability, server uptime, and active online users.

---

## 🛠️ Service Architecture & Default Ports

| Service | Protocol | Default Ports | Target / Description |
| :--- | :--- | :--- | :--- |
| **SSH Direct** | TCP | `22` | Native Linux SSH access |
| **Dropbear** | TCP | `109` | Lightweight SSH server |
| **HTTP / WS Proxy** | TCP | `80`, `8080`, `8880` | Python Proxy (`ws-proxy.py`) -> `127.0.0.1:109` |
| **SSL / TLS Proxy** | TCP | `443` | Stunnel4 -> `127.0.0.1:80` |
| **BadVPN UDPGW** | UDP | `7300` | Standard UDP Gateway Service |
| **BadVPN HCR** | UDP | `8180` | UDP HCR Service |

---
## 📥 Fast Installation

Run the following command as `root` on your VPS to automatically install and start the panel:


wget -O install.sh [https://raw.githubusercontent.com/golbert19/golbert-vps2/main/install.sh](https://raw.githubusercontent.com/golbert19/golbert-vps2/main/install.sh) && chmod +x install.sh && ./install.sh

---
## 📋 Interactive Menu

# 🚀 Golbert VPN Control Panel

A lightweight, terminal-based management panel for Linux VPS instances (Debian/Ubuntu). It provides a real-time system monitoring interface and simplified administration for SSH/VPN tunneling services, user management, custom domains, and banner configurations.

---

## 📌 Dashboard Features

- 📊 **Real-time System Monitoring:** Displays OS details, system uptime, public IP, configured domain/hostname, disk usage, active CPU load, and RAM memory consumption.
- 👥 **User Administration:** Interactive controls to create, modify, extend expiration dates, manage multi-login limits, and remove SSH/VPN accounts.
- 🌐 **Cloudflare & Domain Integration:** Quickly link subdomains and automatically update dynamic SSL certificates for TLS proxying.
- ⚙️ **Service Status & Control:** Monitor system background daemons (Dropbear, Stunnel, WebSocket Proxy, BadVPN) directly from the interface.
- 🎨 **Custom Banner Editor:** Native editing tool for SSH and Dropbear welcome messages (`/etc/issue.net`).

---

## 📋 Control Panel Interface

```text
───────────────────────────────────────────────────────────────
 OS      : Ubuntu 22.04.4 LTS
 UPTIME  : 12 days, 4 hours
 IP PUB  : 192.0.2.1
 DOMINIO : tu dominio.org.pe
 ONLINE  : 3 usuario(s) activo(s)
 DISCO   : Total 20G     Uso 4.2G     Libre 15G
 CPU     : [||                ] 12.0%   Cores: 2
 RAM     : [|||||             ] 420M/2048M   Libre: 1628M
───────────────────────────────────────────────────────────────
             PANEL DE CONTROL GOLBERT VPN
───────────────────────────────────────────────────────────────
 [1] Crear usuario SSH/VPN
 [2] Editar usuario / Renovar vencimiento
 [3] Eliminar usuario
 [4] Ver usuarios activos en detalle
 [5] Configurar Dominio / Hostname (Cloudflare)
 [6] Cambiar / Configurar Banner
 [7] Estado de los servicios
 [0] Salir
───────────────────────────────────────────────────────────────
──────────────────────────────────────────────.

---

## ⚙️ System Requirements
- **OS: Debian** 10/11/12 or Ubuntu 20.04/22.04/24.04 LTS
 * Permissions: Root access (EUID 0)
 * Dependencies: python3, curl, wget, net-tools, ufw, stunnel4, dropbear, cmake
## 📄 License
This project is open-source under the MIT License.


