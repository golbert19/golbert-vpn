#!/bin/bash
set -euo pipefail

# Colores de la interfaz
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

LIMIT_FILE="/etc/golbert_limits.conf"
CHECKUSER_SCRIPT="/usr/local/bin/checkuser.py"
CHECKUSER_SERVICE="/etc/systemd/system/golbert-checkuser.service"
[ ! -f "$LIMIT_FILE" ] && touch "$LIMIT_FILE"

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Error: Debe ejecutarse como root.${NC}"
        exit 1
    fi
}

get_ip() {
    curl -s --max-time 2 ifconfig.me 2>/dev/null || wget -qO- --timeout=2 ifconfig.me 2>/dev/null || echo "N/A"
}

get_domain() {
    if [ -f /etc/stunnel/domain.txt ]; then
        cat /etc/stunnel/domain.txt
    elif [ -f /etc/golbert_domain.conf ]; then
        cat /etc/golbert_domain.conf
    else
        echo "Sin Dominio / Cloudflare"
    fi
}

get_ram() {
    free -m | awk 'NR==2{printf "%sMB / %sMB (%.1f%%)", $3, $2, $3*100/$2}' 2>/dev/null || echo "N/A"
}

get_cpu() {
    top -bn1 2>/dev/null | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk -v cores="$(nproc 2>/dev/null || echo 1)" '{printf "%.1f%% uso (%s núcleos)", 100 - $1, cores}' || echo "N/A"
}

get_uptime() {
    uptime -p 2>/dev/null | sed 's/up //' || echo "N/A"
}

get_total_users() {
    awk -F: '$3 >= 1000 && $1 != "nobody" {count++} END {print count+0}' /etc/passwd
}

get_online_users() {
    ps aux 2>/dev/null | grep -E 'dropbear|sshd' | grep -v grep | grep -v root | wc -l
}

get_user_limit() {
    local usr="$1"
    local lim
    lim=$(grep -w "^$usr" "$LIMIT_FILE" 2>/dev/null | cut -d'=' -f2 || true)
    echo "${lim:-2}"
}

get_port_dropbear() {
    local p
    p=$(grep -oP '(?<=DROPBEAR_PORT=)\d+' /etc/default/dropbear 2>/dev/null || true)
    echo "${p:-109}"
}

get_port_stunnel() {
    local p
    p=$(grep -oP '(?<=accept = )\d+' /etc/stunnel/stunnel.conf 2>/dev/null || true)
    echo "${p:-443}"
}

get_port_badvpn() {
    local p
    p=$(grep -oP '(?<=--listen-addr 0.0.0.0:)\d+' /etc/systemd/system/badvpn.service 2>/dev/null || true)
    echo "${p:-7300}"
}

get_port_wsproxy() {
    if [ -f /usr/local/bin/ws-proxy.py ]; then
        local p
        p=$(grep -oP '(?<=LISTENING_PORTS = \[)[^\]]+' /usr/local/bin/ws-proxy.py 2>/dev/null || true)
        echo "${p:-80, 8080}"
    else
        echo "80, 8080"
    fi
}

get_port_checkuser() {
    if [ -f "$CHECKUSER_SCRIPT" ]; then
        local p
        p=$(grep -oP '(?<=PORT = )\d+' "$CHECKUSER_SCRIPT" 2>/dev/null || true)
        echo "${p:-54321}"
    else
        echo "54321"
    fi
}

instalar_checkuser_script() {
    cat > "$CHECKUSER_SCRIPT" <<'PYEOF'
import socket
import threading
import subprocess
import json
import re
from datetime import datetime

PORT = 54321

def get_user_info(username):
    try:
        res = subprocess.run(["id", username], capture_output=True, text=True)
        if res.returncode != 0:
            return None

        chage_res = subprocess.run(["chage", "-l", username], capture_output=True, text=True)
        exp_date = "never"
        for line in chage_res.stdout.splitlines():
            if "Account expires" in line:
                exp_date = line.split(":")[1].strip()
                break

        limit = 2
        try:
            with open("/etc/golbert_limits.conf", "r") as f:
                for l in f:
                    if l.startswith(f"{username}="):
                        limit = int(l.strip().split("=")[1])
                        break
        except:
            pass

        ps_res = subprocess.run("ps aux | grep -E 'dropbear|sshd' | grep -v grep | grep -w '^" + username + "'", shell=True, capture_output=True, text=True)
        online = len([line for line in ps_res.stdout.splitlines() if line.strip()])

        days_left = "N/A"
        if exp_date != "never" and exp_date != "N/A":
            try:
                exp_dt = datetime.strptime(exp_date, "%b %d, %Y")
                diff = (exp_dt - datetime.now()).days + 1
                days_left = diff if diff > 0 else 0
            except:
                pass
        else:
            days_left = "never"

        return {
            "username": username,
            "expiration_date": exp_date,
            "expiration_days": days_left,
            "limit_connections": limit,
            "online_connections": online
        }
    except Exception:
        return None

def handle_client(sock):
    try:
        req = sock.recv(2048).decode('utf-8', errors='ignore')
        if not req:
            sock.close()
            return

        match = re.search(r'GET\s+/.*?user=([a-zA-Z0-9_-]+)', req)
        if not match:
            match = re.search(r'username=([a-zA-Z0-9_-]+)', req)

        if match:
            user = match.group(1)
            info = get_user_info(user)
            if info:
                body = json.dumps(info)
                resp = f"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: {len(body)}\r\n\r\n{body}"
            else:
                body = json.dumps({"error": "User not found"})
                resp = f"HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\nContent-Length: {len(body)}\r\n\r\n{body}"
        else:
            body = json.dumps({"status": "CheckUser Active", "usage": "/checkUser?user=USERNAME"})
            resp = f"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {len(body)}\r\n\r\n{body}"

        sock.sendall(resp.encode('utf-8'))
    except:
        pass
    finally:
        sock.close()

def main():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('0.0.0.0', PORT))
    s.listen(100)
    while True:
        try:
            client, _ = s.accept()
            t = threading.Thread(target=handle_client, args=(client,))
            t.daemon = True
            t.start()
        except:
            pass

if __name__ == '__main__':
    main()
PYEOF

    chmod +x "$CHECKUSER_SCRIPT"

    cat > "$CHECKUSER_SERVICE" <<'SERVEOF'
[Unit]
Description=Golbert VPN CheckUser Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/checkuser.py
Restart=always

[Install]
WantedBy=multi-user.target
SERVEOF

    systemctl daemon-reload 2>/dev/null || true
    systemctl enable golbert-checkuser 2>/dev/null || true
    systemctl restart golbert-checkuser 2>/dev/null || true
    ufw allow 54321/tcp >/dev/null 2>&1 || true
}

[ ! -f "$CHECKUSER_SCRIPT" ] && instalar_checkuser_script

crear_usuario() {
    echo -e "\n${BLUE}=== CREAR USUARIO SSH / DROPBEAR ===${NC}"
    read -rp "Nombre de usuario: " username
    if [ -z "$username" ]; then return; fi

    if id "$username" &>/dev/null; then
        echo -e "${RED}El usuario ya existe.${NC}"
        read -rp "Presione Enter para continuar..." _
        return
    fi
    read -rp "Contraseña: " password
    read -rp "Días de validez: " days
    read -rp "Límite Multi-Login (ej: 1 o 2): " max_conn

    if ! [[ "$max_conn" =~ ^[0-9]+$ ]]; then
        max_conn=2
    fi

    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        days=30
    fi

    exp_date=$(date -d "+$days days" +%Y-%m-%d)
    useradd -M -s /bin/false -e "$exp_date" "$username"
    echo "$username:$password" | chpasswd

    sed -i "/^$username=/d" "$LIMIT_FILE" 2>/dev/null || true
    echo "$username=$max_conn" >> "$LIMIT_FILE"

    echo -e "\n${GREEN}[OK] Usuario creado con éxito!${NC}"
    echo "---------------------------------"
    echo "IP Servidor: $(get_ip)"
    echo "Dominio CF:  $(get_domain)"
    echo "Usuario:     $username"
    echo "Password:    $password"
    echo "Expiración:  $exp_date ($days días)"
    echo "Límite:      $max_conn dispositivo(s)"
    echo "Puerto SSL:  $(get_port_stunnel)"
    echo "Puerto Drop: $(get_port_dropbear)"
    echo "Puerto Proxy:$(get_port_wsproxy)"
    echo "Puerto UDPGW:$(get_port_badvpn)"
    echo "CheckUser:   http://$(get_ip):$(get_port_checkuser)/checkUser?user=$username"
    echo "---------------------------------"
    read -rp "Presione Enter para continuar..." _
}

eliminar_usuario() {
    echo -e "\n${BLUE}=== ELIMINAR USUARIO ===${NC}"
    read -rp "Nombre de usuario a eliminar: " username
    if [ -z "$username" ]; then return; fi

    if id "$username" &>/dev/null; then
        pkill -u "$username" 2>/dev/null || true
        userdel -f "$username" 2>/dev/null || true
        sed -i "/^$username=/d" "$LIMIT_FILE" 2>/dev/null || true
        echo -e "${GREEN}[OK] Usuario '$username' eliminado.${NC}"
    else
        echo -e "${RED}El usuario no existe.${NC}"
    fi
    read -rp "Presione Enter para continuar..." _
}

ver_conectados() {
    echo -e "\n${BLUE}=== USUARIOS CONECTADOS EN TIEMPO REAL ===${NC}"
    printf "%-15s %-10s %-20s\n" "USUARIO" "PID" "DESDE"
    echo "------------------------------------------------"
    ps aux 2>/dev/null | grep -E 'dropbear|sshd' | grep -v grep | grep -v root | awk '{print $1, $2, $9}' | while read -r usr pid time || [ -n "$usr" ]; do
        if [ -n "$usr" ]; then
            printf "%-15s %-10s %-20s\n" "$usr" "$pid" "$time"
        fi
    done || true
    echo "------------------------------------------------"
    echo -e "Total Conectados: ${GREEN}$(get_online_users)${NC}"
    read -rp "Presione Enter para continuar..." _
}

listar_usuarios() {
    echo -e "\n${BLUE}=== LISTA DE USUARIOS REGISTRADOS ===${NC}"
    printf "%-16s %-14s %-8s %-10s\n" "USUARIO" "EXPIRACIÓN" "LÍMITE" "ESTADO"
    echo "---------------------------------------------------------"
    hoy_sec=$(date +%s)
    
    while FS=':' read -r user _ uid _ _ _ _ || [ -n "$user" ]; do
        if [ "$uid" -ge 1000 ] && [ "$user" != "nobody" ]; then
            exp=$(chage -l "$user" 2>/dev/null | grep "Account expires" | cut -d: -f2 | xargs || true)
            [ -z "$exp" ] && exp="Sin limite"
            
            lim=$(get_user_limit "$user")
            
            status_color="${GREEN}Activo${NC}"
            if [ "$exp" != "never" ] && [ "$exp" != "Sin limite" ] && [ -n "$exp" ]; then
                exp_sec=$(date -d "$exp" +%s 2>/dev/null || echo 0)
                if [ "$exp_sec" -gt 0 ] && [ "$exp_sec" -lt "$hoy_sec" ]; then
                    status_color="${RED}Vencido${NC}"
                fi
            fi

            printf "%-16s %-14s %-8s " "$user" "$exp" "$lim"
            echo -e "$status_color"
        fi
    done < /etc/passwd
    echo "---------------------------------------------------------"
    read -rp "Presione Enter para continuar..." _
}

ver_detalle_usuario() {
    echo -e "\n${BLUE}=== DETALLE DE USUARIO ===${NC}"
    read -rp "Ingrese el nombre de usuario a consultar: " username
    if [ -z "$username" ]; then return; fi

    if ! id "$username" &>/dev/null; then
        echo -e "${RED}El usuario '$username' no existe.${NC}"
        read -rp "Presione Enter para continuar..." _
        return
    fi

    exp_date=$(chage -l "$username" 2>/dev/null | grep "Account expires" | cut -d: -f2 | xargs || true)
    [ -z "$exp_date" ] && exp_date="never"
    
    lim=$(get_user_limit "$username")
    
    conn_count=$(ps aux 2>/dev/null | grep -E 'dropbear|sshd' | grep -v grep | grep -w "^$username" | wc -l)
    
    dias_restantes="N/A"
    estado="${GREEN}ACTIVO${NC}"
    if [ "$exp_date" != "never" ]; then
        exp_sec=$(date -d "$exp_date" +%s 2>/dev/null || echo 0)
        hoy_sec=$(date +%s)
        if [ "$exp_sec" -gt 0 ]; then
            diff_sec=$((exp_sec - hoy_sec))
            if [ "$diff_sec" -le 0 ]; then
                dias_restantes="0 (Caducado)"
                estado="${RED}VENCIDO${NC}"
            else
                dias_restantes="$((diff_sec / 86400)) día(s)"
            fi
        fi
    else
        dias_restantes="Ilimitado"
    fi

    echo -e "\n${CYAN}---------------------------------${NC}"
    echo -e " Usuario           : ${WHITE}$username${NC}"
    echo -e " Estado Cuenta     : $estado"
    echo -e " Fecha Expiración  : ${YELLOW}$exp_date${NC}"
    echo -e " Días Restantes    : ${YELLOW}$dias_restantes${NC}"
    echo -e " Límite Multi-login: ${WHITE}$lim dispositivo(s)${NC}"
    echo -e " Conexiones Activas: ${GREEN}$conn_count / $lim${NC}"
    echo -e " URL CheckUser     : ${MAGENTA}http://$(get_ip):$(get_port_checkuser)/checkUser?user=$username${NC}"
    echo -e "${CYAN}---------------------------------${NC}"
    read -rp "Presione Enter para continuar..." _
}

configurar_dominio() {
    echo -e "\n${BLUE}=== CONFIGURAR DOMINIO CLOUDFLARE ===${NC}"
    read -rp "Ingrese su Dominio / Subdominio: " nuevo_dominio
    if [ -n "$nuevo_dominio" ]; then
        mkdir -p /etc/stunnel
        echo "$nuevo_dominio" > /etc/stunnel/domain.txt
        echo "$nuevo_dominio" > /etc/golbert_domain.conf 2>/dev/null || true
        echo -e "${GREEN}[OK] Dominio guardado correctamente.${NC}"
    fi
    read -rp "Presione Enter para continuar..." _
}

cambiar_puertos() {
    while true; do
        clear
        echo -e "${YELLOW}=====================================================${NC}"
        echo -e "${YELLOW}             CAMBIAR PUERTOS DE SERVICIOS           ${NC}"
        echo -e "${YELLOW}=====================================================${NC}"
        echo -e " 1) Dropbear     [Actual: ${CYAN}$(get_port_dropbear)${NC}]"
        echo -e " 2) Stunnel SSL  [Actual: ${CYAN}$(get_port_stunnel)${NC}]"
        echo -e " 3) HTTP Proxy   [Actual: ${CYAN}$(get_port_wsproxy)${NC}]"
        echo -e " 4) BadVPN UDPGW [Actual: ${CYAN}$(get_port_badvpn)${NC}]"
        echo -e " 5) CheckUser    [Actual: ${CYAN}$(get_port_checkuser)${NC}]"
        echo -e " 0) Volver al menú principal"
        echo -e "${YELLOW}=====================================================${NC}"
        read -rp " Seleccione una opción [0-5]: " opt_port

        case $opt_port in
            1)
                read -rp "Nuevo puerto para Dropbear: " new_p
                if [[ "$new_p" =~ ^[0-9]+$ ]]; then
                    sed -i "s/^DROPBEAR_PORT=.*/DROPBEAR_PORT=$new_p/" /etc/default/dropbear
                    ufw allow "$new_p"/tcp >/dev/null 2>&1 || true
                    systemctl restart dropbear 2>/dev/null || true
                    echo -e "${GREEN}[OK] Dropbear actualizado al puerto $new_p${NC}"
                fi
                read -rp "Presione Enter para continuar..." _
                ;;
            2)
                read -rp "Nuevo puerto para Stunnel SSL: " new_p
                if [[ "$new_p" =~ ^[0-9]+$ ]]; then
                    sed -i "s/^accept = .*/accept = $new_p/" /etc/stunnel/stunnel.conf
                    ufw allow "$new_p"/tcp >/dev/null 2>&1 || true
                    systemctl restart stunnel4 2>/dev/null || systemctl restart stunnel 2>/dev/null || true
                    echo -e "${GREEN}[OK] Stunnel actualizado al puerto $new_p${NC}"
                fi
                read -rp "Presione Enter para continuar..." _
                ;;
            3)
                read -rp "Nuevos puertos para HTTP Proxy (ej: 80, 8080): " new_p
                if [ -n "$new_p" ] && [ -f /usr/local/bin/ws-proxy.py ]; then
                    sed -i "s/LISTENING_PORTS = .*/LISTENING_PORTS = [$new_p]/" /usr/local/bin/ws-proxy.py
                    IFS=',' read -ra ADDR <<< "$new_p"
                    for p in "${ADDR[@]}"; do
                        clean_p=$(echo "$p" | tr -d ' ')
                        if [[ "$clean_p" =~ ^[0-9]+$ ]]; then
                            ufw allow "$clean_p"/tcp >/dev/null 2>&1 || true
                        fi
                    done
                    systemctl restart ws-proxy 2>/dev/null || true
                    echo -e "${GREEN}[OK] HTTP Proxy actualizado a [$new_p]${NC}"
                fi
                read -rp "Presione Enter para continuar..." _
                ;;
            4)
                read -rp "Nuevo puerto para BadVPN UDPGW: " new_p
                if [[ "$new_p" =~ ^[0-9]+$ ]]; then
                    sed -i "s/--listen-addr 0.0.0.0:[0-9]*/--listen-addr 0.0.0.0:$new_p/" /etc/systemd/system/badvpn.service
                    ufw allow "$new_p"/udp >/dev/null 2>&1 || true
                    systemctl daemon-reload 2>/dev/null || true
                    systemctl restart badvpn 2>/dev/null || true
                    echo -e "${GREEN}[OK] BadVPN actualizado al puerto $new_p${NC}"
                fi
                read -rp "Presione Enter para continuar..." _
                ;;
            5)
                read -rp "Nuevo puerto para CheckUser: " new_p
                if [[ "$new_p" =~ ^[0-9]+$ ]] && [ -f "$CHECKUSER_SCRIPT" ]; then
                    sed -i "s/PORT = .*/PORT = $new_p/" "$CHECKUSER_SCRIPT"
                    ufw allow "$new_p"/tcp >/dev/null 2>&1 || true
                    systemctl restart golbert-checkuser 2>/dev/null || true
                    echo -e "${GREEN}[OK] CheckUser actualizado al puerto $new_p${NC}"
                fi
                read -rp "Presione Enter para continuar..." _
                ;;
            0) break ;;
            *) echo -e "${RED}Opción inválida.${NC}" ;;
        esac
    done
}

cambiar_limite_usuario() {
    echo -e "\n${BLUE}=== CAMBIAR LÍMITE MULTI-LOGIN ===${NC}"
    read -rp "Nombre de usuario: " username
    if ! id "$username" &>/dev/null; then
        echo -e "${RED}El usuario no existe.${NC}"
        read -rp "Presione Enter para continuar..." _
        return
    fi

    echo -e "Límite actual de $username: ${GREEN}$(get_user_limit "$username")${NC}"
    read -rp "Nuevo límite de conexiones simultáneas: " new_limit

    if [[ "$new_limit" =~ ^[0-9]+$ ]]; then
        sed -i "/^$username=/d" "$LIMIT_FILE" 2>/dev/null || true
        echo "$username=$new_limit" >> "$LIMIT_FILE"
        echo -e "${GREEN}[OK] Límite actualizado a $new_limit conexión(es).${NC}"
    else
        echo -e "${RED}Límite no válido.${NC}"
    fi
    read -rp "Presione Enter para continuar..." _
}

configurar_banner() {
    echo -e "\n${BLUE}=== CONFIGURAR BANNER DE CONEXIÓN ===${NC}"
    echo "Edita el texto que verán tus clientes al conectarse."
    read -rp "Presiona Enter para abrir el editor..." _
    nano /etc/issue.net
    systemctl restart dropbear 2>/dev/null || true
    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true
    echo -e "\n${GREEN}[OK] Banner actualizado y servicios reiniciados.${NC}"
    read -rp "Presione Enter para continuar..." _
}

eliminar_expirados() {
    echo -e "\n${BLUE}=== VERIFICANDO USUARIOS EXPIRADOS ===${NC}"
    hoy_sec=$(date +%s)
    eliminados=0

    while FS=':' read -r user _ uid _ _ _ _ || [ -n "$user" ]; do
        if [ "$uid" -ge 1000 ] && [ "$user" != "nobody" ]; then
            exp_date=$(chage -l "$user" 2>/dev/null | grep "Account expires" | cut -d: -f2 | xargs || true)
            if [ -n "$exp_date" ] && [ "$exp_date" != "never" ]; then
                exp_sec=$(date -d "$exp_date" +%s 2>/dev/null || echo 0)
                if [ "$exp_sec" -gt 0 ] && [ "$exp_sec" -lt "$hoy_sec" ]; then
                    pkill -u "$user" 2>/dev/null || true
                    userdel -f "$user" 2>/dev/null || true
                    sed -i "/^$user=/d" "$LIMIT_FILE" 2>/dev/null || true
                    echo -e "Usuario eliminado: ${RED}$user${NC} (Expiró el $exp_date)"
                    eliminados=$((eliminados + 1))
                fi
            fi
        fi
    done < /etc/passwd

    if [ "$eliminados" -eq 0 ]; then
        echo -e "${GREEN}[OK] No hay usuarios vencidos en el sistema.${NC}"
    else
        echo -e "${GREEN}[OK] Se eliminaron $eliminados usuario(s) caducado(s).${NC}"
    fi
    read -rp "Presione Enter para continuar..." _
}

limpiar_sistema() {
    echo -e "\n${BLUE}=== LIMPIANDO SISTEMA Y LIBERANDO RAM ===${NC}"
    journalctl --vacuum-size=10M >/dev/null 2>&1 || true
    truncate -s 0 /var/log/syslog 2>/dev/null || true
    trunc
