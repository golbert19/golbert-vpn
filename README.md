# 🚀 Golbert VPN - Script de Instalación Automática y Panel SSH/VPN
Un script automatizado e interactivo para desplegar y administrar un servidor **SSH / WS / SSL / UDPGW** en distribuciones basadas en Debian y Ubuntu. Diseñado para gestionar clientes, puertos, dominios y seguridad en un solo lugar.
---
## 🛠️ Características Principales
* **Servicios Integrados:**
  * **Dropbear:** Servidor SSH liviano.
  * **WebSocket Proxy (Python):** Proxy HTTP/WS para tunelización HTTP Custom.
  * **Stunnel4:** Capa de cifrado SSL/TLS.
  * **BadVPN (UDPGW):** Soporte para juegos en línea y llamadas de voz (VoIP).
* **Gestión Avanzada:**
  * **Panel Interactivo (Menú):** Administración simplificada vía línea de comandos.
  * **Anti Multi-Login:** Limitador de conexiones simultáneas por usuario.
  * **Limpiador Automático:** Eliminación programada mediante `cron` de cuentas caducadas y purga de logs/RAM.
  * **Soporte Cloudflare:** Gestión e integración de dominios/subdominios.
---
## 📋 Puertos por Defecto

| Servicio | Puerto por Defecto | Protocolo |
| :--- | :--- | :--- |
| **SSH Standard** | `22` | TCP |
| **Dropbear** | `109` | TCP |
| **HTTP / WS Proxy** | `80, 8080` | TCP |
| **Stunnel SSL** | `443` | TCP |
| **BadVPN UDPGW** | `7300` | UDP |
---
##🖥️ Uso del Panel de Control
Una vez finalizada la instalación, puedes acceder al panel de administración en cualquier momento escribiendo:

menu
---
Opciones disponibles en el Panel:
Crear usuario SSH/Dropbear: Asigna contraseña, días de validez y límite de dispositivos.
Eliminar usuario: Desconecta y borra la cuenta inmediatamente.
Ver usuarios conectados: Monitor de conexiones activas en tiempo real.
Listar usuarios: Muestra todas las cuentas registradas y sus fechas de vencimiento.
Configurar Dominio Cloudflare: Guarda tu subdominio para usarlo en aplicaciones de conexión.
Estado de servicios: Verifica el estado (active/inactive) de todos los daemon.
Reiniciar servicios: Reinicia la pila completa de servicios en un solo paso.
Cambiar puertos: Configuración rápida de puertos para Dropbear, SSL, Proxy y BadVPN.
Límite Multi-Login: Modifica el máximo de conexiones simultáneas por usuario.
Editar Banner: Personaliza el mensaje de bienvenida /etc/issue.net.
Limpieza de caducados: Forzar la eliminación inmediata de cuentas vencidas.
Mantenimiento del sistema: Limpia logs (journalctl, syslog) y libera memoria RAM.
📋 Requisitos del Sistema
SO: Debian 10/11/12 o Ubuntu 20.04/22.04/24.04 (LTS recomendado).
Arquitectura: x86_64 / ARM64.
Permisos: Acceso root completo.
📞 Contacto y Soporte
Si tienes dudas, necesitas asistencia con la instalación o quieres adquirir accesos, puedes contactarme directamente a través de mis redes oficiales:



## ⚡ Instalación Rápida
Ejecuta el siguiente comando en tu terminal con acceso `root`:
```bash
bash <(curl -sSL [https://raw.githubusercontent.com/golbert19/golbert-vpn/main/install.sh](https://raw.githubusercontent.com/golbert19/golbert-vpn/main/install.sh))
