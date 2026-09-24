#!/bin/bash
set -e
echo "=== GOLBERT VPN INSTALLER FIX ==="
apt update && apt upgrade -y
apt install -y openvpn easy-rsa dropbear stunnel4 build-essential cmake git ufw curl wget

bash <(curl -Ls https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh) || true
systemctl enable v2ray --now || true

sed -i 's/NO_START=1/NO_START=0/' /etc/default/dropbear
sed -i 's/DROPBEAR_PORT=22/DROPBEAR_PORT=109/' /etc/default/dropbear
echo 'DROPBEAR_EXTRA_ARGS="-p 109"' > /etc/default/dropbear
systemctl enable dropbear
systemctl restart dropbear

rm -rf /tmp/badvpn
git clone https://github.com/ambrop72/badvpn.git /tmp/badvpn
mkdir -p /tmp/badvpn/build
cd /tmp/badvpn/build
cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1
make -j$(nproc)
make install

cat > /etc/systemd/system/badvpn.service <<'BADVPN_EOF'
[Unit]
Description=BadVPN UDPGW Golbert
After=network.target
[Service]
ExecStart=/usr/local/bin/badvpn-udpgw --listen-addr 0.0.0.0:7300 --max-clients 1000
Restart=always
[Install]
WantedBy=multi-user.target
BADVPN_EOF

systemctl daemon-reload
systemctl enable badvpn
systemctl restart badvpn

cat > /etc/stunnel/stunnel.conf <<'STUNNEL_EOF'
cert = /etc/stunnel/stunnel.pem
client = no
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1
[dropbear]
accept = 443
connect = 127.0.0.1:109
STUNNEL_EOF

openssl req -new -x509 -days 365 -nodes -out /etc/stunnel/stunnel.pem -keyout /etc/stunnel/stunnel.pem -subj "/CN=golbert19" -quiet
systemctl enable stunnel4 || true
systemctl restart stunnel4 || systemctl restart stunnel || true

ufw --force reset
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 109/tcp
ufw allow 8080/tcp
ufw allow 8180/udp
ufw allow 7300/udp
ufw allow out 443/tcp
ufw allow out 80/tcp
ufw allow out 53
ufw --force enable
ufw status

echo "=== GOLBERT VPN OK ==="
