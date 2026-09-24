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
apt-get install -y openvpn easy-rsa dropbear stunnel4 build-essential cmake git ufw curl wget openssl

# 2. Instalar V2Ray
echo "=== Instalando V2Ray ==="
curl -sS -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh | bash || true
systemctl enable v2ray --now || true

# 3. Configurar Dropbear de forma segura
echo "=== Configurando Dropbear ==="
sed -i 's/^NO_START=1/NO_START=0/' /etc/default/dropbear 2>/dev/null || true

if grep -q "^DROPBEAR_PORT=" /etc/default/dropbear; then
    sed -i 's/^DROPBEAR_PORT=.*/DROPBEAR_PORT=109/' /etc/default/dropbear
else
    echo 'DROPBEAR_PORT=109' >> /etc/default/dropbear
fi

systemctl enable dropbear
systemctl restart dropbear

# 4. Compilar e instalar BadVPN (UDPGW) limpiando archivos temporales
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

# 5. Crear e iniciar el servicio Systemd para BadVPN
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

# 6. Configurar Stunnel4
echo "=== Configurando Stunnel ==="
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

# Habilitar stunnel en /etc/default/stunnel4
if [ -f /etc/default/stunnel4 ]; then
    sed -i 's/^ENABLED=0/ENABLED=1/' /etc/default/stunnel4
fi

# Generar certificado SSL solo si no existe
if [ ! -f /etc/stunnel/stunnel.pem ]; then
    openssl req -new -x509 -days 365 -nodes \
        -out /etc/stunnel/stunnel.pem \
        -keyout /etc/stunnel/stunnel.pem \
        -subj "/CN=golbert19"
    chmod 600 /etc/stunnel/stunnel.pem
fi

systemctl enable stunnel4 --now || systemctl restart stunnel4

# 7. Configurar UFW (sin resetear reglas existentes para evitar pérdida de conexión SSH)
echo "=== Configurando Firewall (UFW) ==="
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 109/tcp
ufw allow 8080/tcp
ufw allow 8180/udp
ufw allow 7300/udp
ufw --force enable

# 8. Verificación final de estado
echo "=== ESTADO DE LOS SERVICIOS ==="
systemctl is-active --quiet badvpn && echo "[OK] BadVPN: Activo" || echo "[FAIL] BadVPN: Falló"
systemctl is-active --quiet stunnel4 && echo "[OK] Stunnel4: Activo" || echo "[FAIL] Stunnel4: Falló"
systemctl is-active --quiet dropbear && echo "[OK] Dropbear: Activo" || echo "[FAIL] Dropbear: Falló"
systemctl is-active --quiet v2ray && echo "[OK] V2Ray: Activo" || echo "[FAIL] V2Ray: Falló"

echo "=== GOLBERT VPN OK ==="
