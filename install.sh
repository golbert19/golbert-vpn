#!/bin/bash
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Ejecuta este script como usuario root.${NC}"
    exit 1
fi

echo -e "${YELLOW}=====================================================${NC}"
echo -e "${YELLOW}         INSTALADOR AUTOMÁTICO GOLBERT VPN          ${NC}"
echo -e "${YELLOW}=====================================================${NC}"

# 1. Actualizar repositorios e instalar paquetes base
echo -e "${GREEN}[1/7] Actualizando paquetes del sistema...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y && apt-get upgrade -y
apt-get install -y curl wget net-tools ufw dropbear stunnel4 python3 cmake gcc build-essential nano cron

# 2. Configurar Banner /etc/issue.net
echo -e "${GREEN}[2/7] Configurando Banner por defecto...${NC}"
cat > /etc/issue.net <<'BANNER_EOF'
=================================
       BIENVENIDO A GOLBERT VPN   
  PROHIBIDO SPAM / TORRENT / DDOS 
=================================
BANNER_EOF

sed -i 's|^DROPBEAR_BANNER=.*|DROPBEAR_BANNER="/etc/issue.net"|' /etc/default/dropbear 2>/dev/null || echo 'DROPBEAR_BANNER="/etc/issue.net"' >> /etc/default/dropbear
sed -i 's|^#Banner none|Banner /etc/issue.net|' /etc/ssh/sshd_config 2>/dev/null || true
sed -i 's|^Banner none|Banner /etc/issue.net|' /etc/ssh/sshd_config 2>/dev/null || true

# 3. Configurar Dropbear (Puerto interno 109)
echo -e "${GREEN}[3/7] Configurando Dropbear (Puerto 109)...${NC}"
sed -i 's/NO_START=1/NO_START=0/' /etc/default/dropbear
sed -i 's/DROPBEAR_PORT=.*/DROPBEAR_PORT=109/' /etc/default/dropbear

# 4. Script Python WS Proxy
echo -e "${GREEN}[4/7] Creando Servicio HTTP/WS Proxy...${NC}"
cat > /usr/local/bin/ws-proxy.py <<'PROXY_EOF'
import socket
import select
import threading
import time

LISTENING_PORTS = [80, 8080]
TARGET_HOST = '127.0.0.1'
TARGET_PORT = 109
BUFLEN = 8192
RESPONSE_101 = b'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n'

def handler(client_socket, address):
    target_socket = None
    try:
        request = client_socket.recv(BUFLEN)
        if not request:
            client_socket.close()
            return

        target_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        target_socket.connect((TARGET_HOST, TARGET_PORT))
        client_socket.sendall(RESPONSE_101)

        sockets = [client_socket, target_socket]
        while True:
            readable, _, errors = select.select(sockets, [], sockets, 10)
            if errors:
                break
            for s in readable:
                data = s.recv(BUFLEN)
                if not data:
                    return
                if s is client_socket:
                    target_socket.sendall(data)
                else:
                    client_socket.sendall(data)
    except Exception:
        pass
    finally:
        client_socket.close()
        if target_socket:
            try:
                target_socket.close()
            except Exception:
                pass

def server_thread(port):
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('0.0.0.0', port))
    server.listen(100)
    while True:
        try:
            client, addr = server.accept()
            t = threading.Thread(target=handler, args=(client, addr))
            t.daemon = True
            t.start()
        except Exception:
            pass

if __name__ == '__main__':
    for port in LISTENING_PORTS:
        t = threading.Thread(target=server_thread, args=(port,))
        t.daemon = True
        t.start()
    while True:
        time.sleep(3600)
PROXY_EOF

cat > /etc/systemd/system/ws-proxy.service <<'WSPROXY_EOF'
[Unit]
Description=WebSocket / HTTP Proxy Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/ws-proxy.py
Restart=always

[Install]
WantedBy=multi-user.target
WSPROXY_EOF

# 5. Configurar Stunnel4
echo -e "${GREEN}[5/7] Configurando Stunnel4 (Puerto 443)...${NC}"
mkdir -p /etc/stunnel
openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 -sha256 \
    -subj "/C=US/ST=State/L=City/O=GolbertVPN/CN=golbert.vpn" \
    -keyout /etc/stunnel/stunnel.pem -out /etc/stunnel/stunnel.pem >/dev/null 2>&1

cat > /etc/stunnel/stunnel.conf <<'STUNNEL_EOF'
cert = /etc/stunnel/stunnel.pem
client = no
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1

[ws-ssl]
accept = 443
connect = 127.0.0.1:80
STUNNEL_EOF

sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/stunnel4 2>/dev/null || true

cat > /etc/systemd/system/stunnel4.service <<'STUNNEL_SERVICE_EOF'
[Unit]
Description=SSL tunnel for network daemon
After=network.target

[Service]
ExecStart=/usr/bin/stunnel4 /etc/stunnel/stunnel.conf
Restart=always

[Install]
WantedBy=multi-user.target
STUNNEL_SERVICE_EOF

# 6. Instalar BadVPN (UDPGW)
echo -e "${GREEN}[6/7] Compilando e Instalando BadVPN UDPGW...${NC}"
if wget -q -O /tmp/badvpn.tar.gz https://github.com/ambrop72/badvpn/archive/refs/tags/1.999.130.tar.gz; then
    cd /tmp && tar -xf badvpn.tar.gz && cd badvpn-1.999.130
    mkdir -p build && cd build
    cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 >/dev/null
    make install >/dev/null
    cd / && rm -rf /tmp/badvpn*
fi

cat > /etc/systemd/system/badvpn.service <<'BADVPN_EOF'
[Unit]
Description=BadVPN UDPGW Service
After=network.target

[Service]
ExecStart=/usr/local/bin/badvpn-udpgw --listen-addr 0.0.0.0:7300 --max-clients 1000 --max-connections-for-client 10
Restart=always

[Install]
WantedBy=multi-user.target
BADVPN_EOF

# 7. Configurar Anti Multi-Login y Limpieza Automática
echo -e "${GREEN}[7/7] Configurando Limitador y Limpieza Automática...${NC}"
touch /etc/golbert_limits.conf

cat > /usr/local/bin/limiter.sh <<'LIMITER_EOF'
#!/bin/bash
LIMIT_FILE="/etc/golbert_limits.conf"
[ ! -f "$LIMIT_FILE" ] && touch "$LIMIT_FILE"
DEFAULT_LIMIT=2

while true; do
    USERS=$(ps aux | grep -E 'dropbear|sshd' | grep -v grep | grep -v root | awk '{print $1}' | sort | uniq)
    for user in $USERS; do
        USER_LIMIT=$(grep -w "^$user" "$LIMIT_FILE" | cut -d'=' -f2 2>/dev/null || echo "")
        if [ -z "$USER_LIMIT" ]; then
            USER_LIMIT=$DEFAULT_LIMIT
        fi

        PIDS=$(ps aux | grep -E 'dropbear|sshd' | grep -v grep | grep -w "^$user" | awk '{print $2}')
        CONN_COUNT=$(echo "$PIDS" | sed '/^$/d' | wc -l)

        if [ "$CONN_COUNT" -gt "$USER_LIMIT" ]; then
            EXCESS=$((CONN_COUNT - USER_LIMIT))
            PIDS_TO_KILL=$(echo "$PIDS" | tail -n "$EXCESS")
            for pid in $PIDS_TO_KILL; do
                kill -9 "$pid" 2>/dev/null || true
            done
        fi
    done
    sleep 3
done
LIMITER_EOF
chmod +x /usr/local/bin/limiter.sh

cat > /etc/systemd/system/golbert-limiter.service <<'SERVICE_EOF'
[Unit]
Description=Golbert Anti Multi-Login Limiter Service
After=network.target

[Service]
ExecStart=/bin/bash /usr/local/bin/limiter.sh
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
SERVICE_EOF

cat > /usr/local/bin/expcleaner.sh <<'EXPCLEAN_EOF'
#!/bin/bash
hoy_sec=$(date +%s)

while FS=':' read -r user _ uid _ _ _ _; do
    if [ "$uid" -ge 1000 ] && [ "$user" != "nobody" ]; then
        exp_date=$(chage -l "$user" 2>/dev/null | grep "Account expires" | cut -d: -f2 | xargs)
        if [ -n "$exp_date" ] && [ "$exp_date" != "never" ]; then
            exp_sec=$(date -d "$exp_date" +%s 2>/dev/null || echo 0)
            if [ "$exp_sec" -gt 0 ] && [ "$exp_sec" -lt "$hoy_sec" ]; then
                pkill -u "$user" 2>/dev/null || true
                userdel -f "$user" 2>/dev/null || true
                sed -i "/^$user=/d" /etc/golbert_limits.conf 2>/dev/null || true
            fi
        fi
    fi
done < /etc/passwd

journalctl --vacuum-size=50M >/dev/null 2>&1 || true
truncate -s 0 /var/log/syslog 2>/dev/null || true
truncate -s 0 /var/log/auth.log 2>/dev/null || true
EXPCLEAN_EOF
chmod +x /usr/local/bin/expcleaner.sh

(crontab -l 2>/dev/null || true) | grep -v "/usr/local/bin/expcleaner.sh" | { cat; echo "0 */6 * * * /bin/bash /usr/local/bin/expcleaner.sh"; } | crontab -

# Configuración directa del ejecutable menu
echo -e "${GREEN}Instalando el ejecutable del menú...${NC}"
cat > /usr/local/bin/menu <<'MENU_EOF'
#!/bin/bash
while true; do
    clear
    echo "================================="
    echo "       PANEL GOLBERT VPN         "
    echo "================================="
    echo "1) Crear usuario SSH/VPN"
    echo "2) Eliminar usuario"
    echo "3) Ver usuarios activos"
    echo "4) Estado de los servicios"
    echo "0) Salir"
    echo "================================="
    read -rp "Seleccione una opción: " opt
    case $opt in
        1)
            read -rp "Nombre de usuario: " u
            read -rp "Contraseña: " p
            read -rp "Días de duración: " d
            useradd -m -s /bin/false "$u"
            echo "$u:$p" | chpasswd
            exp=$(date -d "+$d days" +%Y-%m-%d)
            chage -E "$exp" "$u"
            echo "Usuario $u creado hasta $exp"
            read -rp "Presione Enter para continuar..."
            ;;
        2)
            read -rp "Usuario a eliminar: " u
            pkill -u "$u" 2>/dev/null || true
            userdel -r "$u" 2>/dev/null || true
            sed -i "/^$u=/d" /etc/golbert_limits.conf 2>/dev/null || true
            echo "Usuario $u eliminado."
            read -rp "Presione Enter para continuar..."
            ;;
        3)
            echo "Usuarios conectados:"
            ps aux | grep -E 'dropbear|sshd' | grep -v grep | grep -v root
            read -rp "Presione Enter para continuar..."
            ;;
        4)
            systemctl status ws-proxy stunnel4 badvpn dropbear --no-pager
            read -rp "Presione Enter para continuar..."
            ;;
        0) exit 0 ;;
        *) echo "Opción inválida" ;;
    esac
done
MENU_EOF

# Asignación de permisos de ejecución directos
chmod +x /usr/local/bin/menu
cp /usr/local/bin/menu /usr/bin/menu 2>/dev/null || true

# Iniciar y habilitar servicios
systemctl daemon-reload
systemctl restart dropbear
systemctl enable --now ws-proxy stunnel4 badvpn golbert-limiter

# Abrir puertos en UFW
ufw allow 22/tcp
ufw allow 109/tcp
ufw allow 443/tcp
ufw allow 80/tcp
ufw allow 8080/tcp
ufw allow 7300/udp
echo "y" | ufw enable >/dev/null 2>&1 || true

echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}     ¡INSTALACIÓN COMPLETADA EXITOSAMENTE!           ${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo -e "Escribe ${YELLOW}menu${NC} para abrir el panel inmediatamente."
