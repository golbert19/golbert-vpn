#!/bin/bash
set -euo pipefail

# Colores para la instalación
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
apt-get install -y curl wget net-tools ufw dropbear stunnel4 python3 cmake gcc gasp build-essential nano cron

# 2. Configurar Banner /etc/issue.net
echo -e "${GREEN}[2/7] Configurando Banner por defecto...${NC}"
cat > /etc/issue.net <<'BANNER_EOF'
<p style="text-align:center;">
<font color="green"><b>=================================</b></font><br>
<font color="blue"><b>       BIENVENIDO A GOLBERT VPN   </b></font><br>
<font color="red"><b>  PROHIBIDO SPAM / TORRENT / DDOS </b></font><br>
<font color="green"><b>=================================</b></font>
</p>
BANNER_EOF

# Configurar Dropbear y OpenSSH para usar el banner
sed -i 's|^DROPBEAR_BANNER=.*|DROPBEAR_BANNER="/etc/issue.net"|' /etc/default/dropbear 2>/dev/null || echo 'DROPBEAR_BANNER="/etc/issue.net"' >> /etc/default/dropbear
sed -i 's|^#Banner none|Banner /etc/issue.net|' /etc/ssh/sshd_config 2>/dev/null || true
sed -i 's|^Banner none|Banner /etc/issue.net|' /etc/ssh/sshd_config 2>/dev/null || true

# 3. Configurar Dropbear
echo -e "${GREEN}[3/7] Configurando Dropbear (Puerto 109)...${NC}"
sed -i 's/NO_START=1/NO_START=0/' /etc/default/dropbear
sed -i 's/DROPBEAR_PORT=.*/DROPBEAR_PORT=109/' /etc/default/dropbear

# 4. Configurar Stunnel4
echo -e "${GREEN}[4/7] Configurando Stunnel4 (Puerto 443)...${NC}"
openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 -sha256 \
    -subj "/C=US/ST=State/L=City/O=GolbertVPN/CN=golbert.vpn" \
    -keyout /etc/stunnel/stunnel.pem -out /etc/stunnel/stunnel.pem >/dev/null 2>&1

cat > /etc/stunnel/stunnel.conf <<'STUNNEL_EOF'
cert = /etc/stunnel/stunnel.pem
client = no
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1

[dropbear]
accept = 443
connect = 127.0.0.1:109
STUNNEL_EOF

sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/stunnel4 2>/dev/null || true

# 5. Instalar BadVPN (UDPGW) en Puerto 7300
echo -e "${GREEN}[5/7] Compilando e Instalando BadVPN UDPGW...${NC}"
wget -q -O /tmp/badvpn.tar.gz https://github.com/ambrop72/badvpn/archive/refs/tags/1.999.130.tar.gz || true
if [ -f /tmp/badvpn.tar.gz ]; then
    cd /tmp && tar -xf badvpn.tar.gz && cd badvpn-1.999.130
    mkdir build && cd build
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

# 6. Crear HTTP/WS Proxy Script (Puerto 80, 8080)
echo -e "${GREEN}[6/7] Creando Servicio HTTP/WS Proxy...${NC}"
cat > /usr/local/bin/ws-proxy.py <<'PROXY_EOF'
import socket, threading, select

LISTENING_PORTS = [80, 8080]
BUFLEN = 4096
BACKLOG = 100

class Proxy(threading.Thread):
    def __init__(self, client, address):
        super().__init__()
        self.client = client
        self.address = address

    def run(self):
        try:
            data = self.client.recv(BUFLEN)
            if data:
                target = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                target.connect(('127.0.0.1', 109))
                self.client.sendall(b'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n')
                self.forward(self.client, target)
        except Exception:
            pass
        finally:
            self.client.close()

    def forward(self, source, destination):
        sockets = [source, destination]
        while True:
            read_sockets, _, _ = select.select(sockets, [], [])
            for sock in read_sockets:
                data = sock.recv(BUFLEN)
                if not data:
                    return
                if sock is source:
                    destination.sendall(data)
                else:
                    source.sendall(data)

def start_server(port):
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('0.0.0.0', port))
    server.listen(BACKLOG)
    while True:
        client, addr = server.accept()
        threading.Thread(target=Proxy(client, addr).run).start()

if __name__ == '__main__':
    for port in LISTENING_PORTS:
        threading.Thread(target=start_server, args=(port,)).start()
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

# 7. Configurar Anti Multi-Login y Limpiador Automático
echo -e "${GREEN}[7/7] Configurando Limitador y Limpieza Automática...${NC}"
cat > /usr/local/bin/limiter.sh <<'LIMITER_EOF'
#!/bin/bash
LIMIT_FILE="/etc/golbert_limits.conf"
[ ! -f "$LIMIT_FILE" ] && touch "$LIMIT_FILE"
DEFAULT_LIMIT=1

while true; do
    USERS=$(ps aux | grep -E 'dropbear|sshd' | grep -v grep | grep -v root | awk '{print $1}' | sort | uniq)
    for user in $USERS; do
        USER_LIMIT=$(grep -w "^$user" "$LIMIT_FILE" | cut -d'=' -f2 || true)
        USER_LIMIT=${USER_LIMIT:-$DEFAULT_LIMIT}

        PIDS=$(ps aux | grep -E 'dropbear|sshd' | grep -v grep | grep -w "^$user" | awk '{print $2}')
        CONN_COUNT=$(echo "$PIDS" | wc -l)

        if [ "$CONN_COUNT" -gt "$USER_LIMIT" ]; then
            EXCESS=$((CONN_COUNT - USER_LIMIT))
            PIDS_TO_KILL=$(ps aux | grep -E 'dropbear|sshd' | grep -v grep | grep -w "^$user" | awk '{print $2}' | tail -n "$EXCESS")
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
hoy=$(date +%Y-%m-%d)
hoy_sec=$(date -d "$hoy" +%s)

while FS=':' read -r user _ uid _ _ _ _; do
    if [ "$uid" -ge 1000 ] && [ "$user" != "nobody" ]; then
        exp_date=$(chage -l "$user" | grep "Account expires" | cut -d: -f2 | xargs)
        if [ "$exp_date" != "never" ] && [ -n "$exp_date" ]; then
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

(crontab -l 2>/dev/null | grep -v "/usr/local/bin/expcleaner.sh" ; echo "0 */6 * * * /bin/bash /usr/local/bin/expcleaner.sh") | crontab -

# Descargar el menú interactivo desde el repositorio
echo -e "${GREEN}Descargando Panel del Menú...${NC}"
wget -q -O /usr/local/bin/menu.sh https://raw.githubusercontent.com/golbert19/golbert-vpn/main/menu.sh
chmod +x /usr/local/bin/menu.sh

# Configurar alias 'menu' para ingresar directo desde la terminal
if ! grep -q "alias menu=" ~/.bashrc; then
    echo "alias menu='bash /usr/local/bin/menu.sh'" >> ~/.bashrc
fi

# Iniciar todos los servicios y configurar Firewall
systemctl daemon-reload
systemctl enable --now dropbear stunnel4 badvpn ws-proxy golbert-limiter

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
echo -e "Escribe ${YELLOW}menu${NC} o ejecuta ${YELLOW}bash /usr/local/bin/menu.sh${NC} para abrir el panel."
