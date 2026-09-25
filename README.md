# 🚀 Golbert VPN - Script de Instalación Automática y Panel SSH/VPN

Un script automatizado e interactivo para desplegar y administrar un servidor **SSH / WS / SSL / UDPGW** en distribuciones basadas en Debian y Ubuntu. Diseñado para gestionar clientes, puertos, dominios y seguridad en un solo lugar.

---

## 💻 Requisitos del Sistema

* **Sistema Operativo:** Debian 10 / 11 / 12 o Ubuntu 20.04 / 22.04 / 24.04 LTS (Recomendados).
* **Arquitectura:** x86_64 / ARM64.
* **Permisos:** Acceso directo como usuario `root`.
* **Dominio:** Recomendado para SSL y Cloudflare (opcional).

## ✨ Características

* Gestión de usuarios SSH con expiración
* Proxy WebSocket (Puerto 80 compatible con Cloudflare)
* Conexión SSL / TLS (Puerto 443)
* UDPGW para llamadas / juegos
* Panel interactivo
* Instalación de BadVPN, Dropbear, Squid, Stunnel
* Optimización del sistema y BBR

## ⚡ Instalación Rápida

Ejecuta el siguiente comando en tu terminal con acceso `root`:

```bash
wget https://raw.githubusercontent.com/golbert19/golbert-vpn/main/install.sh -O install.sh && bash install.sh

```

## 🔧 Puertos por Defecto

| Servicio | Puerto |
| :--- | :--- |
| SSH | 22 |
| Dropbear | 2222 |
| WebSocket | 80 |
| WebSocket SSL | 443 |
| Squid | 8080 / 3128 |
| UDPGW | 7300 |

> **Nota Cloudflare:** Para que funcione con subdominio en Cloudflare, activa la nube naranja y usa el puerto 80 (ws) y 443 (wss). Dominios como `ws.tudominio.com` apuntando a la IP del VPS.
