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
        echo -e " 0) Volver al menú principal"
        echo -e "${YELLOW}=====================================================${NC}"
        read -rp " Seleccione una opción [0-4]: " opt_port

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
    truncate -s 0 /var/log/auth.log 2>/dev/null || true
    sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    apt-get clean >/dev/null 2>&1 || true
    apt-get autoremove -y >/dev/null 2>&1 || true
    echo -e "\n${GREEN}[OK] Limpieza del servidor completada con éxito.${NC}"
    read -rp "Presione Enter para continuar..." _
}

estado_servicios() {
    echo -e "\n${BLUE}=== ESTADO DE LOS SERVICIOS ===${NC}"
    for service in dropbear stunnel4 ws-proxy badvpn golbert-limiter; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo -e "$service: ${GREEN}[ACTIVO]${NC}"
        else
            echo -e "$service: ${RED}[INACTIVO]${NC}"
        fi
    done
    read -rp "Presione Enter para continuar..." _
}

reiniciar_servicios() {
    echo -e "\n${BLUE}=== REINICIANDO SERVICIOS ===${NC}"
    systemctl restart dropbear stunnel4 ws-proxy badvpn golbert-limiter 2>/dev/null || true
    echo -e "${GREEN}[OK] Todos los servicios han sido reiniciados.${NC}"
    read -rp "Presione Enter para continuar..." _
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
    echo " 5) Consultar detalle específico de un usuario"
    echo " 6) Registrar/Modificar Dominio Cloudflare"
    echo " 7) Ver estado de servicios"
    echo " 8) Reiniciar servicios"
    echo " 9) Cambiar puertos de conexión"
    echo " 10) Configurar Límite Multi-Login"
    echo " 11) Editar Banner de conexión"
    echo " 12) Eliminar usuarios caducados ahora"
    echo " 13) Limpiar Logs y Liberar RAM"
    echo " 0) Salir"
    echo -e "${YELLOW}=====================================================${NC}"
    read -rp " Seleccione una opción [0-13]: " opcion

    case $opcion in
        1) crear_usuario ;;
        2) eliminar_usuario ;;
        3) ver_conectados ;;
        4) listar_usuarios ;;
        5) ver_detalle_usuario ;;
        6) configurar_dominio ;;
        7) estado_servicios ;;
        8) reiniciar_servicios ;;
        9) cambiar_puertos ;;
        10) cambiar_limite_usuario ;;
        11) configurar_banner ;;
        12) eliminar_expirados ;;
        13) limpiar_sistema ;;
        0) echo -e "${GREEN}¡Hasta luego!${NC}"; exit 0 ;;
        *) echo -e "${RED}Opción inválida.${NC}"; sleep 1 ;;
    esac
done
