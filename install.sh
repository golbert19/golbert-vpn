#!/bin/bash
set -euo pipefail

echo "=== GOLBERT VPN INSTALLER FIX ==="

# Verificar permisos de root
if [ "$EUID" -ne 0 ]; then
    echo "Error: Este script debe ejecutarse como root."
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# 1. Actualizar el sistema e instalar dependencias
apt-get update && apt-get upgrade -y
apt-get install -y openvpn easy-rsa dropbear stunnel4 build-essential cmake git ufw curl wget openssl python3

# 2. Instalar V2Ray
echo "=== Instalando V2Ray ==="
curl -sS -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh | bash || true
systemctl enable v2ray --now || true

# 3. Configurar Dropbear (Puerto 109)
echo "=== Configurando Dropbear ==="
sed -i 's/^NO_START=1/NO_START=0/' /etc/default/dropbear 2>/dev/null || true

if grep -q "^DROPBEAR_PORT=" /etc/default/dropbear; then
    sed -i 's/^DROPBEAR_PORT=.*/DROPBEAR_PORT=109/' /etc/default/dropbear
else
    echo 'DROPBEAR_PORT=109' >> /etc/default/dropbear
fi

systemctl enable dropbear
systemctl restart dropbear

# 4. Compilar e instalar BadVPN (UDPGW - Puerto 7300)
echo "=== Compilando BadVPN ==="
BUILD_DIR=$(mktemp -d)
git clone --depth 1 https://github.com/ambrop72/badvpn.git "$BUILD_DIR/badvpn"
mkdir -p "$BUILD_DIR/badvpn/build"
cd "$BUILD_DIR/badvpn/build"
cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1
make -j"$(nproc)"
make install
cd /
rm -rf "$BUILD_DIR"

# Crear servicio BadVPN
cat > /etc/systemd/system/badvpn.service <<'BADVPN_EOF'
[Unit]
Description=BadVPN UDPGW Golbert Service
After=network.target

[Service]
ExecStart=/usr/local/bin/badvpn-udpgw --listen-addr 0.0.0.0:7300 --max-clients 1000
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
BADVPN_EOF

systemctl daemon-reload
systemctl enable badvpn --now

# 5. Configurar Python WS/HTTP Proxy (Puertos 80 y 8080)
echo "=== Configurando Proxy WS/HTTP (Puertos 80, 8080) ==="
cat > /usr/local/bin/ws-proxy.py <<'PROXY_EOF'
import socket, threading, select

LISTENING_PORTS = [80, 8080]
TARGET_HOST = '127.0.0.1'
TARGET_PORT = 109 # Redirige a Dropbear

def handle_client(client_socket):
    try:
        target_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        target_socket.connect((TARGET_HOST, TARGET_PORT))
        
        sockets = [client_socket, target_socket]
        while True:
            readable, _, _ = select.select(sockets, [], [], 60)
            if not readable:
                break
            for s in readable:
                other = target_socket if s is client_socket else client_socket
                data = s.recv(8192)
                if not data:
                    return
                other.sendall(data)
    except Exception:
        pass
    finally:
        client_socket.close()

def start_server(port):
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('0.0.0.0', port))
    server.listen(100)
    while True:
        client, _ = server.accept()
        threading.Thread(target=handle_client, args=(client,), daemon=True).start()

for port in LISTENING_PORTS:
    threading.Thread(target=start_server, args=(port,), daemon=True).start()

threading.Event().wait()
PROXY_EOF

cat > /etc/systemd/system/ws-proxy.service <<'WSPROXY_EOF'
[Unit]
Description=Golbert WS/HTTP Proxy Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/ws-proxy.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
WSPROXY_EOF

systemctl daemon-reload
systemctl enable ws-proxy --now

# 6. Configurar Stunnel4 (Puerto 443 -> SSL/TLS a Dropbear 109)
echo "=== Configurando Stunnel4 ==="
mkdir -p /etc/stunnel
cat > /etc/stunnel/stunnel.conf <<'STUNNEL_EOF'
pid = /var/run/stunnel4/stunnel.pid
cert = /etc/stunnel/stunnel.pem
client = no
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1

[dropbear]
accept = 443
connect = 127.0.0.1:109
STUNNEL_EOF

if [ -f /etc/default/stunnel4 ]; then
    sed -i 's/^ENABLED=0/ENABLED=1/' /etc/default/stunnel4
fi

if [ ! -f /etc/stunnel/stunnel.pem ]; then
    openssl req -new -x509 -days 365 -nodes \
        -out /etc/stunnel/stunnel.pem \
        -keyout /etc/stunnel/stunnel.pem \
        -subj "/CN=golbert19"
    chmod 600 /etc/stunnel/stunnel.pem
fi

systemctl enable stunnel4 --now || systemctl restart stunnel4

# 7. Configurar UFW (Habilitar todos tus puertos requeridos)
echo "=== Configurando Firewall (UFW) ==="
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # WS E-PROXY
ufw allow 443/tcp   # TUNNEL SSL WS
ufw allow 109/tcp   # DROPBEAR
ufw allow 8080/tcp  # BHTTP / Proxy
ufw allow 8180/udp  # HCR UDP
ufw allow 7300/udp  # BADVPN UDPGW
ufw --force enable

# 8. Descargar e instalar el menú interactivo
echo "=== Instalando Panel de Control (Menú) ==="
curl -sSL https://raw.githubusercontent.com/golbert19/golbert-vpn/main/menu.sh -o /usr/local/bin/menu || true
chmod +x /usr/local/bin/menu || true

# 9. Verificación final de estado
echo "=== PUERTOS CONFIGURADOS ==="
echo " [22/TCP]   SSH"
echo " [80/TCP]   WS E-PROXY"
echo " [443/TCP]  TUNNEL SSL WS"
echo " [109/TCP]  DROPBEAR"
echo " [8080/TCP] BHTTP"
echo " [8180/UDP] HCR"
echo " [7300/UDP] BADVPN"
echo "============================="

systemctl is-active --quiet badvpn && echo "[OK] BadVPN: Activo" || echo "[FAIL] BadVPN: Falló"
systemctl is-active --quiet ws-proxy && echo "[OK] WS-Proxy (80/8080): Activo" || echo "[FAIL] WS-Proxy: Falló"
systemctl is-active --quiet stunnel4 && echo "[OK] Stunnel4 (443): Activo" || echo "[FAIL] Stunnel4: Falló"
systemctl is-active --quiet dropbear && echo "[OK] Dropbear (109): Activo" || echo "[FAIL] Dropbear: Falló"

echo "=========================================="
echo "      GOLBERT VPN INSTALADO CON ÉXITO    "
echo "  Escribe 'menu' para abrir el panel     "
echo "=========================================="
