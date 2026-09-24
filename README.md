# Golbert VPN Script Panel

Panel interactivo y gestor de conexiones VPN para servidores Ubuntu / Debian.

## Características

- **Gestor SSH / Dropbear:** Crear, eliminar y listar usuarios con fechas de caducidad.
- **Soporte Multi-Protocolo:** Stunnel4 (SSL), HTTP/WS Proxy y BadVPN UDPGW (para juegos).
- **Control Anti Multi-Login:** Limita conexiones simultáneas por cuenta.
- **Mantenimiento Automático:** Eliminación de cuentas vencidas y rotación de logs.
- **Personalización:** Modificación dinámica de puertos y Banner HTML interactivo.

## Instalación Rápida

Ejecuta el siguiente comando como usuario **root** en tu servidor VPS:

```bash
apt update && apt install -y wget && wget -O instalador.sh [https://raw.githubusercontent.com/golbert19/golbert-vpn/main/instalador.sh](https://raw.githubusercontent.com/golbert19/golbert-vpn/main/instalador.sh) && chmod +x instalador.sh && ./instalador.sh
