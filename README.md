# 🚀 Golbert VPN - Script de Instalación Automática y Panel SSH/VPN

Un script automatizado e interactivo para desplegar y administrar un servidor SSH / WS / SSL / UDPGW en distribuciones basadas en Debian y Ubuntu. Diseñado para gestionar clientes, puertos, dominios y seguridad en un solo lugar.

---

## 💻 Requisitos del Sistema

* **Sistema Operativo:** Debian 10 / 11 / 12 o Ubuntu 20.04 / 22.04 / 24.04 LTS.
* **Arquitectura:** x86_64 / ARM64.
* **Permisos:** Acceso directo como usuario `root`.
* **Dominio:** Recomendado para SSL y Cloudflare (opcional).

---

## ✨ Características

* Gestión de usuarios SSH con fecha de vencimiento y límite de conexiones.
* Proxy WebSocket Universal (Puertos 80 y 8080 compatible con Cloudflare).
* Conexión SSL / TLS segura (Puerto 443 vía Stunnel).
* Servicio API CheckUser integrado en puerto 54321 (compatible con HTTP Custom, Injector, ePro).
* UDPGW (BadVPN) para optimizar llamadas y juegos (Puerto 7300).
* Panel de control interactivo por consola (`menu`).
* Limpiador automático de cuentas vencidas y limitador anti multi-login.

---

## ⚡ Instalación Rápida

Ejecuta el siguiente comando en tu terminal con acceso `root`:

```bash
apt update -y && apt upgrade -y && apt install -y wget && wget [https://raw.githubusercontent.com/golbert19/golbert-vpn/main/install.sh](https://raw.githubusercontent.com/golbert19/golbert-vpn/main/install.sh) && chmod +x install.sh && ./install.sh


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
CheckUser API | 54321 | Consulta de expiración y estado para apps clientes

> **Nota Cloudflare:** Para que funcione con subdominio en Cloudflare, activa la nube naranja y usa el puerto 80 (ws) y 443 (wss). Dominios como `ws.tudominio.com` apuntando a la IP del VPS.
