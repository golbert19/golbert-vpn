#!/bin/bash

# Colores ANSI
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Ejecuta este script como usuario root.${NC}"
    exit 1
fi

# Asegurar /bin/nologin en /etc/shells
if ! grep -q "^/bin/nologin$" /etc/shells; then
    echo "/bin/nologin" >> /etc/shells
fi

echo -e "${CYAN}=====================================================${NC}"
echo -e "${YELLOW}         INSTALADOR AUTOMÁTICO GOLBERT VPN          ${NC}"
echo -e "${CYAN}=====================================================${NC}"

# 1. Actualizar e instalar paquetes
echo -e "${GREEN}[1/7] Actualizando paquetes del sistema...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y && apt-get upgrade -y
apt-get install -y curl wget net-tools ufw dropbear stunnel4 python3 cmake gcc build-essential nano cron lsb-release

# 2. Configurar Banner inicial
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

# 3. Configurar Dropbear
echo -e "${GREEN}[3/7] Configurando Dropbear (Puerto 109)...${NC}"
sed -i 's/NO_START=1/NO_START=0/' /etc/default/dropbear 2>/dev/null || true
sed -i 's/DROPBEAR_PORT=.*/DROPBEAR_PORT=109/' /etc/default/dropbear 2>/dev/null || true
sed -i 's/DROPBEAR_EXTRA_ARGS=.*/DROPBEAR_EXTRA_ARGS="-p 109"/' /etc/default/dropbear 2>/dev/null || true

# 4. Proxy Python WS Adaptativo
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

        if b'HTTP/' in request or b'GET' in request or b'POST' in request or b'CONNECT' in request:
            client_socket.sendall(RESPONSE_101)
        else:
            target_socket.sendall(request)

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

# 5. Configurar Stunnel4 (SSL Puerto 443 -> Proxy WS Puerto 80)
echo -e "${GREEN}[5/7] Configurando Stunnel4 (SSL/TLS en Puerto 443)...${NC}"
mkdir -p /etc/stunnel
openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 -sha256 \
    -subj "/C=US/ST=State/L=City/O=GolbertVPN/CN=golbert.vpn" \
    -keyout /etc/stunnel/stunnel.pem -out /etc/stunnel/stunnel.pem >/dev/null 2>&1

cat > /etc/stunnel/stunnel.conf <<'STUNNEL_EOF'
cert = /etc/stunnel/stunnel.pem
client = no
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1

[ssl-ws-proxy]
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

# 6. BadVPN
echo -e "${GREEN}[6/7] Compilando e Instalando BadVPN UDPGW...${NC}"
if wget -q -O /tmp/badvpn.tar.gz https://github.com/ambrop72/badvpn/archive/refs/tags/1.999.130.tar.gz; then
    cd /tmp && tar -xf badvpn.tar.gz && cd badvpn-1.999.130
    mkdir -p build && cd build
    cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 >/dev/null 2>&1
    make install >/dev/null 2>&1
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

# 7. Limites, Limpieza y Menú Avanzado
echo -e "${GREEN}[7/7] Configurando Limitador, Limpieza y Menú...${NC}"
touch /etc/golbert_limits.conf
touch /etc/golbert_domain.conf

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

(crontab -l 2>/dev/null | grep -v "/usr/local/bin/expcleaner.sh"; echo "0 */6 * * * /bin/bash /usr/local/bin/expcleaner.sh") | crontab - 2>/dev/null || true

# Script del Menú Colorido
cat > /usr/local/bin/menu <<'MENU_EOF'
#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

draw_bar() {
    local pct=$1
    local width=18
    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))
    local bar="["
    for ((i=0; i<filled; i++)); do bar+="|"; done
    for ((i=0; i<empty; i++)); do bar+=" "; done
    bar+="]"
    echo "$bar"
}

while true; do
    clear
    
    OS_INFO=$(lsb_release -ds 2>/dev/null || cat /etc/issue | head -n1 | xargs || echo "Linux")
    UPTIME_INFO=$(uptime -p | sed 's/up //')
    IP_PUB=$(curl -s --max-time 2 https://api.ipify.org || hostname -I | awk '{print $1}')
    DOMAIN=$(cat /etc/golbert_domain.conf 2>/dev/null || echo "Sin dominio")
    [ -z "$DOMAIN" ] && DOMAIN="Sin dominio"

    DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
    DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
    DISK_FREE=$(df -h / | awk 'NR==2 {print $4}')
    
    CPU_CORES=$(nproc)
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}' | cut -d'.' -f1)
    [ -z "$CPU_USAGE" ] && CPU_USAGE=0
    CPU_BAR=$(draw_bar "$CPU_USAGE")
    
    RAM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
    RAM_USED=$(free -m | awk '/Mem:/ {print $3}')
    RAM_FREE=$(free -m | awk '/Mem:/ {print $4}')
    RAM_PCT=$(( RAM_USED * 100 / RAM_TOTAL ))
    RAM_BAR=$(draw_bar "$RAM_PCT")

    ONLINE_USERS=$(ps aux | grep -E 'dropbear|sshd' | grep -v grep | grep -v root | awk '{print $1}' | sort | uniq | wc -l)

    echo -e "${RED}───────────────────────────────────────────────────────────────${NC}"
    echo -e " ${CYAN}OS      :${NC} ${WHITE}$OS_INFO${NC}"
    echo -e " ${CYAN}UPTIME  :${NC} ${WHITE}$UPTIME_INFO${NC}"
    echo -e " ${CYAN}IP PUB  :${NC} ${WHITE}$IP_PUB${NC}"
    echo -e " ${CYAN}DOMINIO :${NC} ${YELLOW}$DOMAIN${NC}"
    echo -e " ${CYAN}ONLINE  :${NC} ${GREEN}${ONLINE_USERS} usuario(s) activo(s)${NC}"
    echo -e " ${CYAN}DISCO   :${NC} Total ${WHITE}${DISK_TOTAL}${NC}     Uso ${WHITE}${DISK_USED}${NC}     Libre ${WHITE}${DISK_FREE}${NC}"
    echo -e " ${CYAN}CPU     :${NC} ${BLUE}${CPU_BAR}${NC} ${YELLOW}${CPU_USAGE}.0%${NC}   Cores: ${WHITE}$CPU_CORES${NC}"
    echo -e " ${CYAN}RAM     :${NC} ${BLUE}${RAM_BAR}${NC} ${YELLOW}${RAM_USED}M/${RAM_TOTAL}M${NC}   Libre: ${WHITE}${RAM_FREE}M${NC}"
    echo -e "${RED}───────────────────────────────────────────────────────────────${NC}"
    echo -e "             ${MAGENTA}PANEL DE CONTROL GOLBERT VPN${NC}"
    echo -e "${RED}───────────────────────────────────────────────────────────────${NC}"
    echo -e " ${GREEN}[1]${NC} Crear usuario SSH/VPN"
    echo -e " ${GREEN}[2]${NC} Editar usuario / Renovar vencimiento"
    echo -e " ${GREEN}[3]${NC} Eliminar usuario"
    echo -e " ${GREEN}[4]${NC} Ver usuarios activos en detalle"
    echo -e " ${GREEN}[5]${NC} Configurar Dominio / Hostname (Cloudflare)"
    echo -e " ${GREEN}[6]${NC} Cambiar / Configurar Banner"
    echo -e " ${GREEN}[7]${NC} Estado de los servicios"
    echo -e " ${GREEN}[0]${NC} Salir"
    echo -e "${RED}───────────────────────────────────────────────────────────────${NC}"
    read -rp " Seleccione una opción: " opt

    case $opt in
        1)
            echo ""
            read -rp " Nombre de usuario: " u
            read -rp " Contraseña: " p
            read -rp " Días de duración: " d
            read -rp " Límite de conexiones simultáneas (Default 2): " lim
            [ -z "$lim" ] && lim=2

            useradd -M -s /bin/nologin "$u" 2>/dev/null || true
            echo "$u:$p" | chpasswd
            exp=$(date -d "+$d days" +%Y-%m-%d)
            chage -E "$exp" "$u"
            echo "$u=$lim" >> /etc/golbert_limits.conf

            HOST_DISP="$IP_PUB"
            [ "$DOMAIN" != "Sin dominio" ] && HOST_DISP="$DOMAIN"

            echo ""
            echo -e "${GREEN}=====================================================${NC}"
            echo -e "${GREEN}          USUARIO CREADO EXITOSAMENTE                ${NC}"
            echo -e "${GREEN}=====================================================${NC}"
            echo -e " ${CYAN}Host / IP          :${NC} ${WHITE}$HOST_DISP${NC}"
            echo -e " ${CYAN}Usuario            :${NC} ${WHITE}$u${NC}"
            echo -e " ${CYAN}Contraseña         :${NC} ${WHITE}$p${NC}"
            echo -e " ${CYAN}Vencimiento        :${NC} ${YELLOW}$exp ($d días)${NC}"
            echo -e " ${CYAN}Límite conexiones  :${NC} ${WHITE}$lim${NC}"
            echo -e "${GREEN}-----------------------------------------------------${NC}"
            echo -e " ${MAGENTA}PUERTOS DISPONIBLES EN EL SERVIDOR:${NC}"
            echo -e " ${CYAN}• SSL / TLS Proxy  :${NC} ${GREEN}443${NC}"
            echo -e " ${CYAN}• HTTP WS / Proxy  :${NC} ${GREEN}80, 8080${NC}"
            echo -e " ${CYAN}• Dropbear Directo :${NC} ${GREEN}109${NC}"
            echo -e " ${CYAN}• SSH Directo      :${NC} ${GREEN}22${NC}"
            echo -e " ${CYAN}• BadVPN UDPGW     :${NC} ${GREEN}7300${NC}"
            echo -e "${GREEN}=====================================================${NC}"
            read -rp " Presione Enter para continuar..."
            ;;
        2)
            echo ""
            echo -e "${CYAN}--- Editar Usuario / Cambiar Expiración ---${NC}"
            read -rp " Ingrese el nombre de usuario a editar: " u
            if id "$u" &>/dev/null; then
                curr_exp=$(chage -l "$u" | grep "Account expires" | cut -d: -f2 | xargs)
                curr_lim=$(grep -w "^$u" /etc/golbert_limits.conf | cut -d'=' -f2 || echo "2")
                echo -e " Expiración actual: ${YELLOW}$curr_exp${NC}"
                echo -e " Límite actual de conexiones: ${YELLOW}$curr_lim${NC}"
                echo ""
                echo -e " [1] Cambiar Contraseña"
                echo -e " [2] Agregar/Renovar Días de Vencimiento"
                echo -e " [3] Cambiar Límite de Conexiones"
                read -rp " Seleccione una opción: " ed_opt

                case $ed_opt in
                    1)
                        read -rp " Nueva Contraseña: " new_p
                        echo "$u:$new_p" | chpasswd
                        echo -e "${GREEN}✓ Contraseña actualizada correctamente.${NC}"
                        ;;
                    2)
                        read -rp " Días adicionales a sumar desde hoy: " add_d
                        new_exp=$(date -d "+$add_d days" +%Y-%m-%d)
                        chage -E "$new_exp" "$u"
                        echo -e "${GREEN}✓ Nueva fecha de vencimiento: $new_exp${NC}"
                        ;;
                    3)
                        read -rp " Nuevo límite de conexiones: " new_lim
                        sed -i "/^$u=/d" /etc/golbert_limits.conf
                        echo "$u=$new_lim" >> /etc/golbert_limits.conf
                        echo -e "${GREEN}✓ Límite actualizado a $new_lim conexiones.${NC}"
                        ;;
                    *) echo -e "${RED}Opción inválida.${NC}" ;;
                esac
            else
                echo -e "${RED}El usuario no existe.${NC}"
            fi
            read -rp " Presione Enter para continuar..."
            ;;
        3)
            echo ""
            read -rp " Usuario a eliminar: " u
            pkill -u "$u" 2>/dev/null || true
            userdel -r "$u" 2>/dev/null || true
            sed -i "/^$u=/d" /etc/golbert_limits.conf 2>/dev/null || true
            echo -e "${YELLOW}✓ Usuario $u eliminado.${NC}"
            read -rp " Presione Enter para continuar..."
            ;;
        4)
            echo ""
            echo -e "${CYAN}────────────── USUARIOS CONECTADOS ONLINE ──────────────${NC}"
            ps aux | grep -E 'dropbear|sshd' | grep -v grep | grep -v root | awk '{print "Usuario: "$1" | PID: "$2}'
            echo -e "${CYAN}────────────────────────────────────────────────────────${NC}"
            read -rp " Presione Enter para continuar..."
            ;;
        5)
            echo ""
            echo -e "${MAGENTA}--- Configurar Dominio de Cloudflare ---${NC}"
            echo -e " Ingresa tu subdominio/dominio apuntado previamente hacia la IP ${YELLOW}$IP_PUB${NC} en Cloudflare."
            echo -e " Ejemplo: ${CYAN}vpn.tudominio.com${NC}"
            echo ""
            read -rp " Dominio / Hostname: " new_dom
            if [ -n "$new_dom" ]; then
                echo "$new_dom" > /etc/golbert_domain.conf
                
                # Regenerar certificado SSL Stunnel para el dominio
                openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 -sha256 \
                    -subj "/C=US/ST=State/L=City/O=GolbertVPN/CN=$new_dom" \
                    -keyout /etc/stunnel/stunnel.pem -out /etc/stunnel/stunnel.pem >/dev/null 2>&1
                
                systemctl restart stunnel4 2>/dev/null || true
                echo -e "${GREEN}✓ Dominio registrado exitosamente y certificado SSL actualizado.${NC}"
            fi
            read -rp " Presione Enter para continuar..."
            ;;
        6)
            echo ""
            echo -e "${MAGENTA}--- Configuración de Banner (/etc/issue.net) ---${NC}"
            echo -e "Banner actual:"
            echo -e "${YELLOW}"
            cat /etc/issue.net
            echo -e "${NC}"
            read -rp "¿Desea editar el banner con Nano? (s/n): " ed
            if [[ "$ed" =~ ^[Ss]$ ]]; then
                nano /etc/issue.net
                systemctl restart dropbear 2>/dev/null || true
                systemctl restart ssh 2>/dev/null || true
                echo -e "${GREEN}✓ Banner actualizado exitosamente.${NC}"
            fi
            read -rp " Presione Enter para continuar..."
            ;;
        7)
            echo ""
            echo -e "${CYAN}────────────── ESTADO DE SERVICIOS ──────────────${NC}"
            systemctl status ws-proxy stunnel4 badvpn dropbear --no-pager
            echo -e "${CYAN}──────────────────────────────────────────────────${NC}"
            read -rp " Presione Enter para continuar..."
            ;;
        0) clear; exit 0 ;;
        *) echo -e "${RED}Opción inválida${NC}"; sleep 1 ;;
    esac
done
MENU_EOF

chmod +x /usr/local/bin/menu
cp /usr/local/bin/menu /usr/bin/menu 2>/dev/null || true
cp /usr/local/bin/menu /usr/local/sbin/menu 2>/dev/null || true

systemctl daemon-reload >/dev/null 2>&1 || true
systemctl restart dropbear >/dev/null 2>&1 || true
systemctl enable --now ws-proxy stunnel4 badvpn golbert-limiter >/dev/null 2>&1 || true

ufw allow 22/tcp >/dev/null 2>&1 || true
ufw allow 109/tcp >/dev/null 2>&1 || true
ufw allow 443/tcp >/dev/null 2>&1 || true
ufw allow 80/tcp >/dev/null 2>&1 || true
ufw allow 8080/tcp >/dev/null 2>&1 || true
ufw allow 7300/udp >/dev/null 2>&1 || true
echo "y" | ufw enable >/dev/null 2>&1 || true

echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}     ¡INSTALACIÓN COMPLETADA EXITOSAMENTE!           ${NC}"
echo -e "${GREEN}=====================================================${NC}"

/usr/local/bin/menu
