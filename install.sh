cat > install.sh <<'EOF'
#!/bin/bash
set -e
echo "=== GOLBERT VPN INSTALLER ==="
apt update && apt upgrade -y
apt install -y openvpn easy-rsa dropbear stunnel4 build-essential cmake git ufw curl wget

# V2Ray oficial
bash <(curl -Ls https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)
systemctl enable v2ray --now || true

# Dropbear 109
sed -i 's/NO_START=1/NO_START=0/' /etc/default/dropbear
sed -i 's/DROPBEAR_PORT=22/DROPBEAR_PORT=109/' /etc/default/dropbear
echo 'DROPBEAR_EXTRA_ARGS="-p 109"' >> /etc/default/dropbear
systemctl enable dropbear
systemctl restart dropbear

# BadVPN como servicio
rm -rf /tmp/badvpn
git clone https://github.com/ambrop72/badvpn.git /tmp/badvpn
mkdir /tmp/badvpn/badvpn-build
cd /tmp/badvpn/badvpn-build
cmake.. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1
make -j$(nproc)
make install
cat > /etc/systemd/system/badvpn.service <<EOL
[Unit]
Description=BadVPN UDPGW Golbert
After=network.target
[Service]
ExecStart=/usr/local/bin/badvpn-udpgw --listen-addr 0.0.0.0:7300 --max-clients 1000 --max-connections-for-client 10
Restart=always
[Install]
WantedBy=multi-user.target
EOL
systemctl daemon-reload
systemctl enable badvpn
systemctl restart badvpn
cd /root/golbert-vpn

# Stunnel 443 -> 109
cat > /etc/stunnel/stunnel.conf <<EOL
cert = /etc/stunnel/stunnel.pem
client = no
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1
[dropbear]
accept = 443
connect = 127.0.0.1:109
EOL
openssl req -new -x509 -days 365 -nodes -out /etc/stunnel/stunnel.pem -keyout /etc/stunnel/stunnel.pem -subj "/CN=golbert19" -quiet
systemctl enable stunnel4
systemctl restart stunnel4 || systemctl restart stunnel || true

# UFW - tus puertos
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

echo "=== INSTALADO GOLBERT VPN OK ==="
EOF

cat > README.md <<'EOF'
# golbert-vpn
Instalador VPS Golbert

**Instalacion en 1 comando:**
```bash
bash <(curl -Ls https://raw.githubusercontent.com/golbert19/golbert-vpn/main/install.sh)
