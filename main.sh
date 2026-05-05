#!/usr/bin/env bash
# =============================================================================
#  WIFIMGR — WiFi Manager TUI
#  Compatible: cualquier distro Linux (Debian, Arch, RHEL, Alpine, etc.)
#  Dependencias: whiptail o dialog | nmcli (NetworkManager) | ip | iw | awk
#  Autor: generado para Nazareno @ Ainsophic
# =============================================================================

set -euo pipefail

# ──────────────────────────────────────────────
#  COLORES / ESTILOS (para mensajes en terminal)
# ──────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# ──────────────────────────────────────────────
#  DETECCIÓN DE TUI BACKEND
# ──────────────────────────────────────────────
TUI=""
if command -v whiptail &>/dev/null; then
    TUI="whiptail"
elif command -v dialog &>/dev/null; then
    TUI="dialog"
else
    echo -e "${RED}[ERROR]${RESET} Se requiere 'whiptail' o 'dialog'."
    echo "  Debian/Ubuntu : sudo apt install whiptail"
    echo "  Arch          : sudo pacman -S libnewt"
    echo "  RHEL/Fedora   : sudo dnf install newt"
    exit 1
fi

# ──────────────────────────────────────────────
#  VERIFICAR ROOT
# ──────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo -e "${YELLOW}[AVISO]${RESET} Ejecutando sin root. Algunas funciones requieren sudo."
    SUDO="sudo"
else
    SUDO=""
fi

# ──────────────────────────────────────────────
#  HELPERS TUI
# ──────────────────────────────────────────────
tui_msg() {
    # tui_msg "Título" "Mensaje" [alto] [ancho]
    local title="$1" msg="$2" h="${3:-10}" w="${4:-60}"
    $TUI --title "$title" --msgbox "$msg" "$h" "$w" 3>&1 1>&2 2>&3
}

tui_yesno() {
    local title="$1" msg="$2" h="${3:-8}" w="${4:-60}"
    $TUI --title "$title" --yesno "$msg" "$h" "$w" 3>&1 1>&2 2>&3
}

tui_input() {
    # tui_input "Título" "Prompt" "default"
    local title="$1" prompt="$2" default="${3:-}"
    $TUI --title "$title" --inputbox "$prompt" 10 60 "$default" 3>&1 1>&2 2>&3
}

tui_password() {
    local title="$1" prompt="$2"
    $TUI --title "$title" --passwordbox "$prompt" 10 60 3>&1 1>&2 2>&3
}

tui_menu() {
    # tui_menu "Título" "Prompt" item1 desc1 item2 desc2 ...
    local title="$1" prompt="$2"; shift 2
    $TUI --title "$title" --menu "$prompt" 22 72 14 "$@" 3>&1 1>&2 2>&3
}

tui_checklist() {
    local title="$1" prompt="$2"; shift 2
    $TUI --title "$title" --checklist "$prompt" 22 72 14 "$@" 3>&1 1>&2 2>&3
}

tui_gauge() {
    local title="$1" msg="$2"
    $TUI --title "$title" --gauge "$msg" 7 60 0
}

confirm() {
    tui_yesno "Confirmar" "$1" && return 0 || return 1
}

# ──────────────────────────────────────────────
#  DETECCIÓN DE INTERFAZ
# ──────────────────────────────────────────────
get_wifi_ifaces() {
    # Lista interfaces WiFi disponibles
    if command -v iw &>/dev/null; then
        iw dev 2>/dev/null | awk '/Interface/ {print $2}'
    else
        ls /sys/class/net/ | while read -r iface; do
            [[ -d "/sys/class/net/$iface/wireless" ]] && echo "$iface"
        done
    fi
}

get_all_ifaces() {
    ls /sys/class/net/ | grep -v lo
}

pick_iface() {
    local ifaces
    mapfile -t ifaces < <(get_wifi_ifaces)
    if [[ ${#ifaces[@]} -eq 0 ]]; then
        tui_msg "Sin interfaces" "No se encontraron interfaces WiFi." 7 50
        return 1
    elif [[ ${#ifaces[@]} -eq 1 ]]; then
        echo "${ifaces[0]}"
        return 0
    fi
    local items=()
    for i in "${ifaces[@]}"; do
        local state
        state=$(cat /sys/class/net/"$i"/operstate 2>/dev/null || echo "unknown")
        items+=("$i" "[$state]")
    done
    tui_menu "Seleccionar Interfaz" "Interfaces WiFi detectadas:" "${items[@]}"
}

# ──────────────────────────────────────────────
#  NMCLI HELPER
# ──────────────────────────────────────────────
nmcli_available() {
    command -v nmcli &>/dev/null && systemctl is-active --quiet NetworkManager 2>/dev/null
}

# ──────────────────────────────────────────────
#  1. ESTADO ACTUAL
# ──────────────────────────────────────────────
show_status() {
    local iface
    iface=$(pick_iface) || return

    local info=""

    # Info básica
    info+="── Interfaz: $iface\n"
    local state
    state=$(cat /sys/class/net/"$iface"/operstate 2>/dev/null || echo "?")
    info+="   Estado   : $state\n"

    # IP actual
    local ip4
    ip4=$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet / {print $2}' | head -1)
    info+="   IPv4     : ${ip4:-"(sin IP)"}\n"

    local ip6
    ip6=$(ip -6 addr show "$iface" 2>/dev/null | awk '/inet6 / && !/fe80/ {print $2}' | head -1)
    info+="   IPv6     : ${ip6:-"(sin IP global)"}\n"

    # MAC
    local mac
    mac=$(cat /sys/class/net/"$iface"/address 2>/dev/null || echo "?")
    info+="   MAC      : $mac\n"

    # Gateway
    local gw
    gw=$(ip route show dev "$iface" 2>/dev/null | awk '/default/ {print $3}' | head -1)
    info+="   Gateway  : ${gw:-"(sin gateway)"}\n"

    # DNS
    local dns=""
    if nmcli_available; then
        dns=$(nmcli dev show "$iface" 2>/dev/null | awk '/IP4.DNS/ {print $2}' | tr '\n' ' ')
    fi
    if [[ -z "$dns" ]]; then
        dns=$(awk '/^nameserver/ {print $2}' /etc/resolv.conf 2>/dev/null | tr '\n' ' ')
    fi
    info+="   DNS      : ${dns:-"?"}\n"

    # SSID conectado
    if command -v iw &>/dev/null; then
        local ssid
        ssid=$(iw dev "$iface" info 2>/dev/null | awk '/ssid/ {print substr($0, index($0,$2))}')
        info+="   SSID     : ${ssid:-"(no conectado)"}\n"
    fi

    # Señal
    if command -v iw &>/dev/null; then
        local signal
        signal=$(iw dev "$iface" station dump 2>/dev/null | awk '/signal:/ {print $2, $3}' | head -1)
        [[ -n "$signal" ]] && info+="   Señal    : $signal\n"
    fi

    # Driver
    local driver
    driver=$(readlink /sys/class/net/"$iface"/device/driver 2>/dev/null | xargs basename 2>/dev/null || echo "?")
    info+="   Driver   : $driver\n"

    # MTU
    local mtu
    mtu=$(cat /sys/class/net/"$iface"/mtu 2>/dev/null || echo "?")
    info+="   MTU      : $mtu\n"

    tui_msg "Estado de $iface" "$(echo -e "$info")" 22 65
}

# ──────────────────────────────────────────────
#  2. CAMBIAR IP
# ──────────────────────────────────────────────
change_ip() {
    local iface
    iface=$(pick_iface) || return

    local mode
    mode=$(tui_menu "Modo IP — $iface" "Selecciona el modo:" \
        "dhcp"   "Obtener IP automática (DHCP)" \
        "static" "Asignar IP estática manual") || return

    if [[ "$mode" == "dhcp" ]]; then
        if nmcli_available; then
            local conn
            conn=$(nmcli -t -f NAME,DEVICE con show --active 2>/dev/null | grep ":$iface" | cut -d: -f1 | head -1)
            if [[ -n "$conn" ]]; then
                $SUDO nmcli con modify "$conn" ipv4.method auto ipv4.addresses "" ipv4.gateway "" ipv4.dns "" \
                    && $SUDO nmcli con up "$conn" \
                    && tui_msg "Éxito" "IP configurada a DHCP en '$conn'." \
                    || tui_msg "Error" "No se pudo aplicar DHCP via nmcli."
            else
                $SUDO dhclient -r "$iface" 2>/dev/null; sleep 1
                $SUDO dhclient "$iface" 2>/dev/null \
                    && tui_msg "Éxito" "DHCP solicitado en $iface." \
                    || tui_msg "Error" "Fallo al solicitar DHCP. Verifica dhclient/dhcpcd."
            fi
        else
            $SUDO dhclient -r "$iface" 2>/dev/null; sleep 1
            $SUDO dhclient "$iface" 2>/dev/null \
                && tui_msg "Éxito" "DHCP solicitado en $iface." \
                || tui_msg "Error" "Fallo. Intenta manualmente: dhcpcd $iface"
        fi
        return
    fi

    # IP estática
    local ip gw dns prefix
    ip=$(tui_input "IP Estática" "Ingresa la dirección IP:" "192.168.1.100") || return
    prefix=$(tui_input "Prefijo / Máscara" "Ingresa el prefijo CIDR (ej. 24 = /24):" "24") || return
    gw=$(tui_input "Gateway" "Ingresa el gateway:" "192.168.1.1") || return
    dns=$(tui_input "DNS" "DNS primario (ej. 8.8.8.8):" "8.8.8.8") || return

    # Validación básica IP
    local re='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    if ! [[ "$ip" =~ $re ]] || ! [[ "$gw" =~ $re ]]; then
        tui_msg "Error de formato" "La IP o gateway ingresados no son válidos." 7 55
        return 1
    fi

    if nmcli_available; then
        local conn
        conn=$(nmcli -t -f NAME,DEVICE con show --active 2>/dev/null | grep ":$iface" | cut -d: -f1 | head -1)
        if [[ -n "$conn" ]]; then
            $SUDO nmcli con modify "$conn" \
                ipv4.method manual \
                ipv4.addresses "$ip/$prefix" \
                ipv4.gateway "$gw" \
                ipv4.dns "$dns" \
                && $SUDO nmcli con up "$conn" \
                && tui_msg "Aplicado" "IP $ip/$prefix en '$conn' (GW: $gw, DNS: $dns)." \
                || tui_msg "Error" "No se pudo aplicar la IP estática."
        else
            # Fallback: ip command
            $SUDO ip addr flush dev "$iface" 2>/dev/null
            $SUDO ip addr add "$ip/$prefix" dev "$iface"
            $SUDO ip link set "$iface" up
            $SUDO ip route add default via "$gw" dev "$iface" 2>/dev/null || true
            echo "nameserver $dns" | $SUDO tee /etc/resolv.conf > /dev/null
            tui_msg "Aplicado" "IP $ip/$prefix configurada (modo iproute2).\n\nNota: no persistirá tras reinicio sin NM." 10 60
        fi
    else
        $SUDO ip addr flush dev "$iface" 2>/dev/null
        $SUDO ip addr add "$ip/$prefix" dev "$iface"
        $SUDO ip link set "$iface" up
        $SUDO ip route add default via "$gw" dev "$iface" 2>/dev/null || true
        echo "nameserver $dns" | $SUDO tee /etc/resolv.conf > /dev/null
        tui_msg "Aplicado" "IP $ip/$prefix configurada (modo iproute2)." 9 60
    fi
}

# ──────────────────────────────────────────────
#  3. CAMBIAR MAC
# ──────────────────────────────────────────────
change_mac() {
    local iface
    iface=$(pick_iface) || return

    local current_mac
    current_mac=$(cat /sys/class/net/"$iface"/address 2>/dev/null || echo "?")

    local mode
    mode=$(tui_menu "MAC — $iface" "MAC actual: $current_mac\n\nSelecciona acción:" \
        "random"   "Generar MAC aleatoria (preservar vendor byte)" \
        "full_rand" "MAC completamente aleatoria" \
        "manual"   "Ingresar MAC manualmente" \
        "restore"  "Restaurar MAC original (hardware)") || return

    local new_mac=""

    case "$mode" in
        random)
            # Preserva el OUI del fabricante original, aleatoriza los últimos 3 octetos
            # Además bit 1 del primer octeto = 0 (unicast), bit 2 = 1 (localmente admin)
            local oui
            oui=$(cat /sys/class/net/"$iface"/address | cut -d: -f1-3)
            new_mac=$(printf '%s:%02x:%02x:%02x' \
                "$oui" \
                $((RANDOM % 256)) \
                $((RANDOM % 256)) \
                $((RANDOM % 256)))
            ;;
        full_rand)
            # Primer octeto: bit unicast=0, bit local=1
            local b1=$(( (RANDOM % 256) & 0xFE | 0x02 ))
            new_mac=$(printf '%02x:%02x:%02x:%02x:%02x:%02x' \
                $b1 \
                $((RANDOM % 256)) \
                $((RANDOM % 256)) \
                $((RANDOM % 256)) \
                $((RANDOM % 256)) \
                $((RANDOM % 256)))
            ;;
        manual)
            new_mac=$(tui_input "MAC Manual" "Ingresa la MAC (formato XX:XX:XX:XX:XX:XX):" "") || return
            local mac_re='^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$'
            if ! [[ "$new_mac" =~ $mac_re ]]; then
                tui_msg "Error" "Formato de MAC inválido." 7 45
                return 1
            fi
            ;;
        restore)
            # Leer MAC de hardware desde ethtool o sysfs permanente
            if command -v ethtool &>/dev/null; then
                local perm
                perm=$(ethtool -P "$iface" 2>/dev/null | awk '{print $NF}')
                if [[ -n "$perm" && "$perm" != "00:00:00:00:00:00" ]]; then
                    new_mac="$perm"
                fi
            fi
            if [[ -z "$new_mac" ]]; then
                tui_msg "Info" "No se puede obtener la MAC de hardware sin ethtool.\nInstala: apt/dnf/pacman install ethtool" 9 60
                return 1
            fi
            ;;
    esac

    confirm "Aplicar MAC: $new_mac\nen interfaz: $iface\n\n(La interfaz se bajará brevemente)" || return

    # Aplicar MAC
    if nmcli_available && [[ "$mode" != "random" ]] 2>/dev/null; then
        local conn
        conn=$(nmcli -t -f NAME,DEVICE con show --active 2>/dev/null | grep ":$iface" | cut -d: -f1 | head -1)
        if [[ -n "$conn" ]]; then
            $SUDO nmcli con modify "$conn" wifi.cloned-mac-address "$new_mac" 2>/dev/null
        fi
    fi

    $SUDO ip link set "$iface" down
    if ! $SUDO ip link set "$iface" address "$new_mac" 2>/dev/null; then
        # Fallback: macchanger
        if command -v macchanger &>/dev/null; then
            $SUDO macchanger -m "$new_mac" "$iface" 2>/dev/null
        else
            $SUDO ip link set "$iface" up
            tui_msg "Error" "No se pudo cambiar la MAC.\nPrueba instalar macchanger:\n  apt install macchanger" 9 55
            return 1
        fi
    fi
    $SUDO ip link set "$iface" up

    local actual_mac
    actual_mac=$(cat /sys/class/net/"$iface"/address 2>/dev/null)
    tui_msg "MAC Cambiada" "MAC aplicada exitosamente.\n\nAnterior : $current_mac\nNueva    : $actual_mac" 10 55
}

# ──────────────────────────────────────────────
#  4. ESCANEAR REDES
# ──────────────────────────────────────────────
scan_networks() {
    local iface
    iface=$(pick_iface) || return

    tui_msg "Escaneando..." "Buscando redes WiFi en $iface...\n(puede tardar unos segundos)" 8 50

    local scan_out=""

    if nmcli_available; then
        $SUDO nmcli dev wifi rescan ifname "$iface" 2>/dev/null || true
        sleep 2
        scan_out=$(nmcli -f SSID,BSSID,CHAN,RATE,SIGNAL,SECURITY,IN-USE dev wifi list ifname "$iface" 2>/dev/null)
    elif command -v iw &>/dev/null; then
        scan_out=$($SUDO iw dev "$iface" scan 2>/dev/null | awk '
            /^BSS / {bss=$2}
            /SSID:/ {ssid=substr($0,index($0,$2))}
            /signal:/ {sig=$2" "$3}
            /freq:/ {freq=$2}
            /RSN:/ || /WPA:/ {sec="WPA/WPA2"}
            /capability:/ && /Privacy/ && !sec {sec="WEP"}
            /^BSS / && bss {
                printf "%-32s %-20s Ch:%-4s %s\n", ssid, bss, freq, sec
                ssid=""; bss=""; sig=""; freq=""; sec="Open"
            }
        ')
    fi

    if [[ -z "$scan_out" ]]; then
        tui_msg "Sin resultados" "No se encontraron redes o faltan permisos.\nAsegúrate de ejecutar como root." 8 55
        return
    fi

    # Mostrar en scrollbox
    if [[ "$TUI" == "whiptail" ]]; then
        echo "$scan_out" | $TUI --title "Redes WiFi detectadas en $iface" --scrolltext --textbox /dev/stdin 24 80
    else
        echo "$scan_out" | $TUI --title "Redes WiFi detectadas en $iface" --textbox - 24 80
    fi
}

# ──────────────────────────────────────────────
#  5. CONECTAR A RED
# ──────────────────────────────────────────────
connect_network() {
    if ! nmcli_available; then
        tui_msg "Sin NetworkManager" "Esta función requiere NetworkManager (nmcli).\nInstala: apt install network-manager" 9 58
        return
    fi

    local iface
    iface=$(pick_iface) || return

    # Refrescar escaneo
    $SUDO nmcli dev wifi rescan ifname "$iface" 2>/dev/null || true
    sleep 1

    # Listar redes
    local raw_nets
    raw_nets=$(nmcli -t -f SSID,SIGNAL,SECURITY dev wifi list ifname "$iface" 2>/dev/null | grep -v '^:' | head -30)

    if [[ -z "$raw_nets" ]]; then
        tui_msg "Sin redes" "No se detectaron redes WiFi disponibles." 7 50
        return
    fi

    local items=()
    while IFS=: read -r ssid signal sec; do
        [[ -z "$ssid" ]] && continue
        items+=("$ssid" "Señal:${signal}% ${sec}")
    done <<< "$raw_nets"

    local chosen_ssid
    chosen_ssid=$(tui_menu "Conectar a Red" "Selecciona la red:" "${items[@]}") || return

    # ¿Ya existe perfil guardado?
    local existing
    existing=$(nmcli -t -f NAME con show 2>/dev/null | grep -F "$chosen_ssid" | head -1)

    if [[ -n "$existing" ]]; then
        if confirm "¿Conectar usando perfil guardado '$existing'?"; then
            $SUDO nmcli con up "$existing" ifname "$iface" \
                && tui_msg "Conectado" "Conectado a '$chosen_ssid' correctamente." \
                || tui_msg "Error" "No se pudo conectar. Revisa credenciales."
            return
        fi
    fi

    # Verificar seguridad
    local sec
    sec=$(nmcli -t -f SSID,SECURITY dev wifi list ifname "$iface" 2>/dev/null | grep "^$chosen_ssid:" | cut -d: -f2 | head -1)

    if [[ "$sec" == "--" ]] || [[ -z "$sec" ]]; then
        # Red abierta
        $SUDO nmcli dev wifi connect "$chosen_ssid" ifname "$iface" \
            && tui_msg "Conectado" "Conectado a red abierta '$chosen_ssid'." \
            || tui_msg "Error" "No se pudo conectar."
    else
        local password
        password=$(tui_password "Contraseña WiFi" "Contraseña para '$chosen_ssid':") || return
        $SUDO nmcli dev wifi connect "$chosen_ssid" password "$password" ifname "$iface" \
            && tui_msg "Conectado" "Conectado a '$chosen_ssid' correctamente." \
            || tui_msg "Error" "Contraseña incorrecta o red no disponible."
    fi
}

# ──────────────────────────────────────────────
#  6. DESCONECTAR
# ──────────────────────────────────────────────
disconnect_network() {
    local iface
    iface=$(pick_iface) || return

    confirm "¿Desconectar $iface de la red actual?" || return

    if nmcli_available; then
        $SUDO nmcli dev disconnect "$iface" \
            && tui_msg "Desconectado" "$iface desconectado." \
            || tui_msg "Error" "No se pudo desconectar."
    else
        $SUDO ip link set "$iface" down && sleep 1 && $SUDO ip link set "$iface" up
        tui_msg "Desconectado" "$iface bajado y vuelto a subir." 7 50
    fi
}

# ──────────────────────────────────────────────
#  7. CONFIGURAR DNS
# ──────────────────────────────────────────────
configure_dns() {
    local preset
    preset=$(tui_menu "Configurar DNS" "Selecciona servidor DNS:" \
        "custom"      "Ingresar DNS personalizado" \
        "cloudflare"  "Cloudflare — 1.1.1.1 / 1.0.0.1" \
        "google"      "Google — 8.8.8.8 / 8.8.4.4" \
        "quad9"       "Quad9 — 9.9.9.9 / 149.112.112.112" \
        "opendns"     "OpenDNS — 208.67.222.222" \
        "adguard"     "AdGuard — 94.140.14.14 (bloqueo ads)") || return

    local dns1 dns2=""
    case "$preset" in
        cloudflare) dns1="1.1.1.1"; dns2="1.0.0.1" ;;
        google)     dns1="8.8.8.8"; dns2="8.8.4.4" ;;
        quad9)      dns1="9.9.9.9"; dns2="149.112.112.112" ;;
        opendns)    dns1="208.67.222.222"; dns2="208.67.220.220" ;;
        adguard)    dns1="94.140.14.14"; dns2="94.140.15.15" ;;
        custom)
            dns1=$(tui_input "DNS Primario" "Servidor DNS primario:" "8.8.8.8") || return
            dns2=$(tui_input "DNS Secundario" "Servidor DNS secundario (dejar en blanco para omitir):" "") || true
            ;;
    esac

    # Aplicar
    local iface=""
    if nmcli_available; then
        iface=$(pick_iface) || return
        local conn
        conn=$(nmcli -t -f NAME,DEVICE con show --active 2>/dev/null | grep ":$iface" | cut -d: -f1 | head -1)
        if [[ -n "$conn" ]]; then
            local dns_val="$dns1"
            [[ -n "$dns2" ]] && dns_val="$dns1 $dns2"
            $SUDO nmcli con modify "$conn" ipv4.dns "$dns_val" ipv4.ignore-auto-dns yes \
                && $SUDO nmcli con up "$conn" \
                && tui_msg "DNS Aplicado" "DNS configurado a: $dns_val en '$conn'." \
                || tui_msg "Error" "No se pudo aplicar DNS via nmcli."
            return
        fi
    fi

    # Fallback: resolv.conf directo
    {
        echo "# Generado por wifimgr"
        echo "nameserver $dns1"
        [[ -n "$dns2" ]] && echo "nameserver $dns2"
    } | $SUDO tee /etc/resolv.conf > /dev/null
    tui_msg "DNS Aplicado" "DNS escrito en /etc/resolv.conf:\n  $dns1${dns2:+\n  $dns2}" 9 55
}

# ──────────────────────────────────────────────
#  8. MTU
# ──────────────────────────────────────────────
change_mtu() {
    local iface
    iface=$(pick_iface) || return

    local current_mtu
    current_mtu=$(cat /sys/class/net/"$iface"/mtu 2>/dev/null || echo "1500")

    local preset
    preset=$(tui_menu "Configurar MTU — $iface" "MTU actual: $current_mtu\n\nSelecciona valor:" \
        "1500"   "Estándar Ethernet (recomendado)" \
        "1492"   "PPPoE / DSL" \
        "1480"   "VPN / Túneles" \
        "9000"   "Jumbo frames (switches que lo soporten)" \
        "custom" "Valor personalizado") || return

    local new_mtu="$preset"
    if [[ "$preset" == "custom" ]]; then
        new_mtu=$(tui_input "MTU personalizado" "Ingresa el valor MTU (576-9000):" "$current_mtu") || return
    fi

    if ! [[ "$new_mtu" =~ ^[0-9]+$ ]] || (( new_mtu < 576 || new_mtu > 9000 )); then
        tui_msg "Error" "Valor MTU inválido. Debe estar entre 576 y 9000." 7 55
        return 1
    fi

    $SUDO ip link set "$iface" mtu "$new_mtu" \
        && tui_msg "MTU Aplicado" "MTU de $iface cambiado a $new_mtu." \
        || tui_msg "Error" "No se pudo cambiar el MTU."
}

# ──────────────────────────────────────────────
#  9. MODO MONITOR / MANAGED
# ──────────────────────────────────────────────
toggle_monitor_mode() {
    if ! command -v iw &>/dev/null; then
        tui_msg "Sin iw" "Se requiere el paquete 'iw'.\n  apt/dnf/pacman install iw" 8 50
        return
    fi

    local iface
    iface=$(pick_iface) || return

    local cur_mode
    cur_mode=$(iw dev "$iface" info 2>/dev/null | awk '/type/ {print $2}')

    local action
    if [[ "$cur_mode" == "monitor" ]]; then
        action=$(tui_menu "Modo Actual: MONITOR" "Interfaz $iface está en modo monitor." \
            "managed" "Cambiar a modo Managed (normal)" \
            "back"    "Volver al menú") || return
    else
        action=$(tui_menu "Modo Actual: MANAGED" "Interfaz $iface está en modo managed." \
            "monitor" "Cambiar a modo Monitor (captura)" \
            "back"    "Volver al menú") || return
    fi

    [[ "$action" == "back" ]] && return

    # Detener procesos que interfieran
    if command -v airmon-ng &>/dev/null && [[ "$action" == "monitor" ]]; then
        $SUDO airmon-ng check kill 2>/dev/null || true
    fi

    $SUDO ip link set "$iface" down
    $SUDO iw dev "$iface" set type "$action"
    $SUDO ip link set "$iface" up \
        && tui_msg "Modo Cambiado" "Interfaz $iface ahora en modo: $action" \
        || tui_msg "Error" "No se pudo cambiar el modo."
}

# ──────────────────────────────────────────────
#  10. PING / TEST CONECTIVIDAD
# ──────────────────────────────────────────────
test_connectivity() {
    local iface
    iface=$(pick_iface) || return

    local target
    target=$(tui_menu "Test de Conectividad" "¿Qué deseas probar?" \
        "gw"     "Gateway (red local)" \
        "dns"    "Servidor DNS" \
        "inet"   "Internet (8.8.8.8)" \
        "custom" "Objetivo personalizado") || return

    local host
    case "$target" in
        gw)
            host=$(ip route show dev "$iface" 2>/dev/null | awk '/default/ {print $3}' | head -1)
            [[ -z "$host" ]] && { tui_msg "Sin gateway" "No hay gateway configurado en $iface." 7 50; return; }
            ;;
        dns)
            host=$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf 2>/dev/null || echo "8.8.8.8")
            ;;
        inet) host="8.8.8.8" ;;
        custom)
            host=$(tui_input "Ping personalizado" "Host o IP a probar:" "google.com") || return
            ;;
    esac

    local result
    result=$(ping -c 4 -W 2 -I "$iface" "$host" 2>&1 || true)

    if echo "$result" | grep -q "bytes from"; then
        tui_msg "✓ Conectividad OK" "$host accesible desde $iface.\n\n$(echo "$result" | tail -3)" 12 65
    else
        tui_msg "✗ Sin conectividad" "No se pudo alcanzar $host desde $iface.\n\n$(echo "$result" | head -5)" 12 65
    fi
}

# ──────────────────────────────────────────────
#  11. PERFILES GUARDADOS
# ──────────────────────────────────────────────
manage_profiles() {
    if ! nmcli_available; then
        tui_msg "Sin NetworkManager" "La gestión de perfiles requiere nmcli." 7 55
        return
    fi

    local action
    action=$(tui_menu "Perfiles WiFi" "Gestión de conexiones guardadas:" \
        "list"   "Ver todos los perfiles" \
        "delete" "Eliminar perfil" \
        "export" "Exportar perfil a archivo") || return

    case "$action" in
        list)
            local profiles
            profiles=$(nmcli -f NAME,TYPE,DEVICE,TIMESTAMP con show 2>/dev/null | head -40)
            echo "$profiles" | $TUI --title "Perfiles de Conexión" --scrolltext --textbox /dev/stdin 22 75
            ;;
        delete)
            local raw
            raw=$(nmcli -t -f NAME,TYPE con show 2>/dev/null | grep wifi | head -20)
            [[ -z "$raw" ]] && { tui_msg "Sin perfiles" "No hay perfiles WiFi guardados." 7 50; return; }
            local items=()
            while IFS=: read -r name type; do
                items+=("$name" "$type")
            done <<< "$raw"
            local chosen
            chosen=$(tui_menu "Eliminar Perfil" "Selecciona perfil a eliminar:" "${items[@]}") || return
            confirm "¿Eliminar perfil '$chosen'? Esta acción no se puede deshacer." || return
            $SUDO nmcli con delete "$chosen" \
                && tui_msg "Eliminado" "Perfil '$chosen' eliminado." \
                || tui_msg "Error" "No se pudo eliminar '$chosen'."
            ;;
        export)
            local raw2
            raw2=$(nmcli -t -f NAME,TYPE con show 2>/dev/null | grep wifi | head -20)
            [[ -z "$raw2" ]] && { tui_msg "Sin perfiles" "No hay perfiles WiFi guardados." 7 50; return; }
            local items2=()
            while IFS=: read -r name type; do
                items2+=("$name" "$type")
            done <<< "$raw2"
            local chosen2
            chosen2=$(tui_menu "Exportar Perfil" "Selecciona perfil a exportar:" "${items2[@]}") || return
            local outfile="/tmp/nm-profile-$(echo "$chosen2" | tr ' ' '_').txt"
            nmcli con show "$chosen2" 2>/dev/null > "$outfile"
            tui_msg "Exportado" "Perfil guardado en:\n$outfile" 8 60
            ;;
    esac
}

# ──────────────────────────────────────────────
#  12. REINICIAR INTERFAZ / NETWORKMANAGER
# ──────────────────────────────────────────────
restart_network() {
    local what
    what=$(tui_menu "Reiniciar Red" "¿Qué deseas reiniciar?" \
        "iface"  "Solo la interfaz WiFi" \
        "nm"     "NetworkManager completo" \
        "full"   "Todo (interfaz + NM + lease)") || return

    local iface=""
    if [[ "$what" != "nm" ]]; then
        iface=$(pick_iface) || return
    fi

    confirm "¿Reiniciar '${iface:-NetworkManager}'?\nPerderás conexión brevemente." || return

    case "$what" in
        iface)
            $SUDO ip link set "$iface" down; sleep 1
            $SUDO ip link set "$iface" up
            if nmcli_available; then
                $SUDO nmcli dev connect "$iface" 2>/dev/null || true
            fi
            tui_msg "Reiniciada" "Interfaz $iface reiniciada." 7 50
            ;;
        nm)
            $SUDO systemctl restart NetworkManager 2>/dev/null \
                && tui_msg "Reiniciado" "NetworkManager reiniciado." \
                || tui_msg "Error" "No se pudo reiniciar NetworkManager."
            ;;
        full)
            $SUDO ip link set "$iface" down
            $SUDO dhclient -r "$iface" 2>/dev/null || true
            $SUDO systemctl restart NetworkManager 2>/dev/null || true
            sleep 2
            $SUDO ip link set "$iface" up
            tui_msg "Reiniciado" "Red completamente reiniciada en $iface." 7 55
            ;;
    esac
}

# ──────────────────────────────────────────────
#  13. INFORMACIÓN DEL SISTEMA
# ──────────────────────────────────────────────
system_info() {
    local info="── Herramientas disponibles ──\n"

    local tools=("nmcli" "iw" "ip" "iwconfig" "ethtool" "macchanger" "airmon-ng" "dhclient" "dhcpcd" "hostapd")
    for t in "${tools[@]}"; do
        if command -v "$t" &>/dev/null; then
            info+="  ✓ $t  ($(command -v "$t"))\n"
        else
            info+="  ✗ $t  (no instalado)\n"
        fi
    done

    info+="\n── Kernel & Drivers ──\n"
    info+="  Kernel: $(uname -r)\n"
    info+="  Distro: $(cat /etc/os-release 2>/dev/null | awk -F= '/^PRETTY_NAME/ {gsub(/"/, ""); print $2}' | head -1)\n"

    info+="\n── Módulos WiFi cargados ──\n"
    local wifi_mods
    wifi_mods=$(lsmod 2>/dev/null | awk 'NR>1 {print $1}' | grep -iE 'mac80211|cfg80211|iwl|ath|rtl|brcm|mt76|r8' | tr '\n' ' ')
    info+="  ${wifi_mods:-"(no detectados)"}\n"

    tui_msg "Información del Sistema" "$(echo -e "$info")" 28 70
}

# ──────────────────────────────────────────────
#  MENÚ PRINCIPAL
# ──────────────────────────────────────────────
main_menu() {
    while true; do
        local choice
        choice=$(tui_menu \
            "WIFIMGR — Gestor WiFi TUI" \
            "$(date '+%H:%M:%S') | $(hostname) | $(id -un)" \
            "1"  "📊  Estado actual de la interfaz" \
            "2"  "🌐  Cambiar dirección IP (DHCP / estática)" \
            "3"  "🔀  Cambiar dirección MAC" \
            "4"  "📡  Escanear redes WiFi disponibles" \
            "5"  "🔗  Conectar a una red WiFi" \
            "6"  "✂️   Desconectar de la red actual" \
            "7"  "🔍  Configurar servidores DNS" \
            "8"  "📏  Cambiar MTU" \
            "9"  "🛡️   Modo Monitor / Managed" \
            "10" "🏓  Test de conectividad (ping)" \
            "11" "💾  Gestionar perfiles guardados" \
            "12" "🔄  Reiniciar interfaz / NetworkManager" \
            "13" "ℹ️   Información del sistema y herramientas" \
            "0"  "❌  Salir" \
        ) || { clear; exit 0; }

        case "$choice" in
            1)  show_status ;;
            2)  change_ip ;;
            3)  change_mac ;;
            4)  scan_networks ;;
            5)  connect_network ;;
            6)  disconnect_network ;;
            7)  configure_dns ;;
            8)  change_mtu ;;
            9)  toggle_monitor_mode ;;
            10) test_connectivity ;;
            11) manage_profiles ;;
            12) restart_network ;;
            13) system_info ;;
            0)  clear; echo -e "${GREEN}Hasta luego.${RESET}"; exit 0 ;;
        esac
    done
}

# ──────────────────────────────────────────────
#  ENTRY POINT
# ──────────────────────────────────────────────
# Verificar dependencias mínimas
for dep in ip awk grep; do
    if ! command -v "$dep" &>/dev/null; then
        echo -e "${RED}[FATAL]${RESET} Dependencia mínima no encontrada: $dep"
        exit 1
    fi
done

main_menu
