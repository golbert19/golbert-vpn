#!/bin/bash
set -euo pipefail

# Colores de la interfaz
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

LIMIT_FILE="/etc/golbert_limits.conf"
[ ! -f "$LIMIT_FILE" ] && touch "$LIMIT_FILE"

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Error: Debe ejecutarse como root.${NC}"
        exit 1
    fi
}

get_ip() {
    curl -s --max-time 2 ifconfig.me || wget -qO- --timeout=2 ifconfig.me || echo "N/A"
}

get_domain() {
    if [ -f /etc/stunnel/domain.txt ]; then
        cat /etc/stunnel/domain.txt
    else
        echo "Sin Dominio / Cloudflare"
    fi
}

get_ram() {
    free -m | awk 'NR==2{printf "%sMB / %sMB (%.1f%%)", $3, $2, $3*100/$2}'
}

get_cpu() {
    top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{printf "%.1f%% uso (%s núcleos)", 100 - $1, "'$(nproc)'"}'
}

get_uptime() {
    uptime -p | sed 's/up //'
}

get_total_users() {
    awk -F: '$3 >= 1000 && $1 != "nobody" {count++} END {print count+0}' /etc/passwd
}

get_online_users() {
    ps aux | grep -E 'dropbear|sshd' | grep -v grep | grep -v root | wc -l
}

get_user_limit() {
    local usr="$1"
    local lim
    lim=$(grep -w "^$usr" "$LIMIT_FILE" | cut -d'=' -f2 || true)
    echo "${lim:-1}"
}

get_port_dropbear() {
    grep -oP '(?<=DROPBEAR_PORT=)\d+' /etc/default/dropbear 2>/dev/null || echo "109"
}

get_port_stunnel() {
    grep -oP '(?<=accept = )\d+' /etc/stunnel/stunnel.conf 2>/dev/null || echo "443"
}

get_port_badvpn() {
    grep -oP '(?<=--listen-addr 0.0.0.0:)\d+' /etc/systemd/system/badvpn.service 2>/dev/null || echo "7300"
}

get_port_wsproxy() {
    if [ -f /usr/local/bin/ws-proxy.py ]; then
        grep -oP '(?<=LISTENING_PORTS = \[)[^\]]+' /usr/local/bin/ws-proxy.py 2>/dev/null || echo "80, 8080"
    else
        echo "80, 8080"
    fi
}

crear_usuario() {
    echo -e "\n${BLUE}=== CREAR USUARIO SSH / DROPBEAR ===${NC}"
    read -p "Nombre de usuario: " username
    if id "$username" &>/dev/null; then
        echo -e "${RED}El usuario ya existe.${NC}"
        read -p "Presione Enter para continuar..."
        return
    fi
    read -p "Contraseña: " password
    read -p "Días de validez: " days
    read -p "Límite Multi-Login (ej: 1 o 2): " max_conn

    if ! [[ "$max_conn" =~ ^[0-9]+$ ]]; then
        max_conn=1
    fi

    exp_date=$(date -d "+$days days" +%Y-%m-%d)
    useradd -M -s /bin/false -e "$exp_date" "$username"
    echo "$username:$password" | chpasswd

    sed -i "/^$username=/d" "$LIMIT_FILE"
    echo "$username=$max_conn" >> "$LIMIT_FILE"

    echo -e "\n${GREEN}[OK] Usuario creado con éxito!${NC}"
    echo "---------------------------------"
    echo "IP Servidor: $(get_ip)"
    echo "Dominio CF:  $(get_domain)"
    echo "Usuario:     $username"
    echo "Password:    $password"
    echo "Expiración:  $exp_date"
    echo "Límite:      $max_conn dispositivo(s)"
    echo "Puerto SSL:  $(get_port_stunnel)"
    echo "Puerto Drop: $(get_port_dropbear)"
    echo "Puerto Proxy:$(get_port_wsproxy)"
    echo "Puerto UDPGW:$(get_port_badvpn)"
    echo "---------------------------------"
    read -p "Presione Enter para continuar..."
}

eliminar_usuario() {
    echo -e "\n${BLUE}=== ELIMINAR USUARIO ===${NC}"
    read -p "Nombre de usuario a eliminar: " username
    if id "$username" &>/dev/null; then
        pkill -u "$username" 2>/dev/null || true
        userdel -f "$username"
        sed -i "/^$username=/d" "$LIMIT_FILE" 2>/dev/null || true
        echo -e "${GREEN}[OK] Usuario '$username' eliminado.${NC}"
    else
        echo -e "${RED}El usuario no existe.${NC}"
    fi
    read -p "Presione Enter para continuar..."
}

ver_conectados() {
    echo -e "\n${BLUE}=== USUARIOS CONECTADOS EN TIEMPO REAL ===${NC}"
    printf "%-15s %-10s %-20s\n" "USUARIO" "PID" "DESDE"
    echo "------------------------------------------------"
    ps aux | grep -E 'dropbear|sshd' | grep -v grep | grep -v root | awk '{print $1, $2, $9}' | while read -r usr pid time; do
        if [ -n "$usr" ]; then
            printf "%-15s %-10s %-20s\n" "$usr" "$pid" "$time"
        fi
    done
    echo "------------------------------------------------"
    echo -e "Total Conectados: ${GREEN}$(get_online_users)${NC}"
    read -p "Presione Enter para continuar..."
}

listar_usuarios() {
    echo -e "\n${BLUE}=== LISTA DE USUARIOS REGISTRADOS ===${NC}"
    printf "%-18s %-15s %-10s\n" "USUARIO" "EXPIRACIÓN" "LÍMITE"
    echo "---------------------------------------------------"
    while FS=':' read -r user _ uid _ _ _ _; do
        if [ "$uid" -ge 1000 ] && [ "$user" != "nobody" ]; then
            exp=$(chage -l "$user" | grep "Account expires" | cut -d: -f2)
            lim=$(get_user_limit "$user")
            printf "%-18s %-15s %-10s\n" "$user" "$exp" "$lim"
        fi
    done < /etc/passwd
    read -p "Presione Enter para continuar..."
}

configurar_dominio() {
    echo -e "\n${BLUE}=== CONFIGURAR DOMINIO CLOUDFLARE ===${NC}"
    read -p "Ingrese su Dominio / Subdominio: " nuevo_dominio
    mkdir -p /etc/stunnel
    echo "$nuevo_dominio" > /etc/stunnel/domain.txt
    echo -e "${GREEN}[OK] Dominio guardado correctamente.${NC}"
    read -p "Presione Enter para continuar..."
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
        echo -e " 0) Volver al menú principal"
        echo -e "${YELLOW}=====================================================${NC}"
        read -p " Seleccione una opción [0-4]: " opt_port

        case $opt_port in
            1)
                read -p "Nuevo puerto para Dropbear: " new_p
                if [[ "$new_p" =~ ^[0-9]+$ ]]; then
                    sed -i "s/^DROPBEAR_PORT=.*/DROPBEAR_PORT=$new_p/" /etc/default/dropbear
                    ufw allow "$new_p"/tcp
                    systemctl restart dropbear
                    echo -e "${GREEN}[OK] Dropbear actualizado al puerto $new_p${NC}"
                fi
                read -p "Presione Enter para continuar..."
                ;;
            2)
                read -p "Nuevo puerto para Stunnel SSL: " new_p
                if [[ "$new_p" =~ ^[0-9]+$ ]]; then
                    sed -i "s/^accept = .*/accept = $new_p/" /etc/stunnel/stunnel.conf
                    ufw allow "$new_p"/tcp
                    systemctl restart stunnel4 || systemctl restart stunnel
                    echo -e "${GREEN}[OK] Stunnel actualizado al puerto $new_p${NC}"
                fi
                read -p "Presione Enter para continuar..."
                ;;
            3)
                read -p "Nuevos puertos para HTTP Proxy (ej: 80, 8080): " new_p
                if [ -n "$new_p" ] && [ -f /usr/local/bin/ws-proxy.py ]; then
                    sed -i "s/LISTENING_PORTS = .*/LISTENING_PORTS = [$new_p]/" /usr/local/bin/ws-proxy.py
                    IFS=',' read -ra ADDR <<< "$new_p"
                    for p in "${ADDR[@]}"; do
                        clean_p=$(echo "$p" | xargs)
                        ufw allow "$clean_p"/tcp
                    done
                    systemctl restart ws-proxy
                    echo -e "${GREEN}[OK] HTTP Proxy actualizado a [$new_p]${NC}"
                fi
                read -p "Presione Enter para continuar..."
                ;;
            4)
                read -p "Nuevo puerto para BadVPN UDPGW: " new_p
                if [[ "$new_p" =~ ^[0-9]+$ ]]; then
                    sed -i "s/--listen-addr 0.0.0.0:[0-9]*/--listen-addr 0.0.0.0:$new_p/" /etc/systemd/system/badvpn.service
                    ufw allow "$new_p"/udp
                    systemctl daemon-reload
                    systemctl restart badvpn
                    echo -e "${GREEN}[OK] BadVPN actualizado al puerto $new_p${NC}"
                fi
                read -p "Presione Enter para continuar..."
                ;;
            0) break ;;
            *) echo -e "${RED}Opción inválida.${NC}" ;;
        esac
    done
}

cambiar_limite_usuario() {
    echo -e "\n${BLUE}=== CAMBIAR LÍMITE MULTI-LOGIN ===${NC}"
    read -p "Nombre de usuario: " username
    if ! id "$username" &>/dev/null; then
        echo -e "${RED}El usuario no existe.${NC}"
        read -p "Presione Enter para continuar..."
        return
    fi

    echo -e "Límite actual de $username: ${GREEN}$(get_user_limit "$username")${NC}"
    read -p "Nuevo límite de conexiones simultáneas: " new_limit

    if [[ "$new_limit" =~ ^[0-9]+$ ]]; then
        sed -i "/^$username=/d" "$LIMIT_FILE"
        echo "$username=$new_limit" >> "$LIMIT_FILE"
        echo -e "${GREEN}[OK] Límite actualizado a $new_limit conexión(es).${NC}"
    else
        echo -e "${RED}Límite no válido.${NC}"
    fi
    read -p "Presione Enter para continuar..."
}

configurar_banner() {
    echo -e "\n${BLUE}=== CONFIGURAR BANNER DE CONEXIÓN ===${NC}"
    echo "Edita el texto HTML o simple que verán tus clientes al conectarse."
    read -p "Presiona Enter para abrir el editor..."
    nano /etc/issue.net
    systemctl restart dropbear sshd 2>/dev/null || systemctl restart dropbear ssh || true
    echo -e "\n${GREEN}[OK] Banner actualizado y servicios reiniciados.${NC}"
    read -p "Presione Enter para continuar..."
}

eliminar_expirados() {
    echo -e "\n${BLUE}=== VERIFICANDO USUARIOS EXPIRADOS ===${NC}"
    hoy=$(date +%Y-%m-%d)
    hoy_sec=$(date -d "$hoy" +%s)
    eliminados=0

    while FS=':' read -r user _ uid _ _ _ _; do
        if [ "$uid" -ge 1000 ] && [ "$user" != "nobody" ]; then
            exp_date=$(chage -l "$user" | grep "Account expires" | cut -d: -f2 | xargs)
            if [ "$exp_date" != "never" ] && [ -n "$exp_date" ]; then
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
    read -p "Presione Enter para continuar..."
}

limpiar_sistema() {
    echo -e "\n${BLUE}=== LIMPIANDO SISTEMA Y LIBERANDO RAM ===${NC}"
    journalctl --vacuum-size=10M >/dev/null 2>&1 || true
    truncate -s 0 /var/log/syslog 2>/dev/null || true
    truncate -s 0 /var/log/auth.log 2>/dev/null || true
    sync; echo 3 > /proc/sys/vm/drop_caches
    apt-get clean >/dev/null 2>&1 || true
    apt-get autoremove -y >/dev/null 2>&1 || true
    echo -e "\n${GREEN}[OK] Limpieza del servidor completada con éxito.${NC}"
    read -p "Presione Enter para continuar..."
}

estado_servicios() {
    echo -e "\n${BLUE}=== ESTADO DE LOS SERVICIOS ===${NC}"
    for service in dropbear stunnel4 ws-proxy badvpn golbert-limiter; do
        if systemctl is-active --quiet "$service"; then
            echo -e "$service: ${GREEN}[ACTIVO]${NC}"
        else
            echo -e "$service: ${RED}[INACTIVO]${NC}"
        fi
    done
    read -p "Presione Enter para continuar..."
}

reiniciar_servicios() {
    echo -e "\n${BLUE}=== REINICIANDO SERVICIOS ===${NC}"
    systemctl restart dropbear stunnel4 ws-proxy badvpn golbert-limiter || true
    echo -e "${GREEN}[OK] Todos los servicios han sido reiniciados.${NC}"
    read -p "Presione Enter para continuar..."
}

check_root

while true; do
    clear
    echo -e "${YELLOW}=====================================================${NC}"
    echo -e "${YELLOW}             GOLBERT VPN - PANEL CONTROL             ${NC}"
    echo -e "${YELLOW}=====================================================${NC}"
    echo -e " ${CYAN}IP Pública:${NC}    $(get_ip)"
    echo -e " ${CYAN}Dominio CF:${NC}    $(get_domain)"
    echo -e " ${CYAN}Uso de RAM:${NC}    $(get_ram)"
    echo -e " ${CYAN}Uso de CPU:${NC}    $(get_cpu)"
    echo -e " ${CYAN}Uptime:${NC}        $(get_uptime)"
    echo -e " ${CYAN}Usuarios:${NC}      Total: ${GREEN}$(get_total_users)${NC} | Online: ${GREEN}$(get_online_users)${NC}"
    echo -e "${YELLOW}=====================================================${NC}"
    echo " 1) Crear usuario SSH/Dropbear"
    echo " 2) Eliminar usuario"
    echo " 3) Ver usuarios conectados (Online)"
    echo " 4) Listar todos los usuarios y vencimiento"
    echo " 5) Registrar/Modificar Dominio Cloudflare"
    echo " 6) Ver estado de servicios"
    echo " 7) Reiniciar servicios"
    echo " 8) Cambiar puertos de conexión"
    echo " 9) Configurar Límite Multi-Login"
    echo " 10) Editar Banner de conexión"
    echo " 11) Eliminar usuarios caducados ahora"
    echo " 12) Limpiar Logs y Liberar RAM"
    echo " 0) Salir"
    echo -e "${YELLOW}=====================================================${NC}"
    read -p " Seleccione una opción [0-12]: " opcion

    case $opcion in
        1) crear_usuario ;;
        2) eliminar_usuario ;;
        3) ver_conectados ;;
        4) listar_usuarios ;;
        5) configurar_dominio ;;
        6) estado_servicios ;;
        7) reiniciar_servicios ;;
        8) cambiar_puertos ;;
        9) cambiar_limite_usuario ;;
        10) configurar_banner ;;
        11) eliminar_expirados ;;
        12) limpiar_sistema ;;
        0) echo -e "${GREEN}¡Hasta luego!${NC}"; exit 0 ;;
        *) echo -e "${RED}Opción inválida.${NC}" ;;
    esac
done
