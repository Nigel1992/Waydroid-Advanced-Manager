#!/bin/bash

# =================================================================
# Waydroid Advanced Manager (Universal Support)
# GitHub: [Your GitHub Username]/Waydroid-Manager
# =================================================================

# ---------------- COLORS & UI ----------------
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' 

# ---------------- CONFIG ----------------
CONNECTED_DEVICES=()
SCRIPT_DIR="$HOME/waydroid_script"

# UI Helpers
print_header() {
    clear
    echo -e "${CYAN}${BOLD}=================================================="
    echo -e "           WAYDROID ADVANCED MANAGER"
    echo -e "==================================================${NC}"
}

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ---------------- UNIVERSAL IP DETECTION ----------------
get_waydroid_ip() {
    # Attempt 1: waydroid status
    local ip=$(waydroid status 2>/dev/null | grep -i "^IP" | awk '{print $NF}')
    
    # Attempt 2: Direct Container Shell (Fallback)
    if [ -z "$ip" ] || [[ ! "$ip" =~ ^[0-9] ]]; then
        ip=$(sudo waydroid shell ip -4 addr show eth0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    fi
    
    # Attempt 3: Route table (Last resort)
    if [ -z "$ip" ]; then
        ip=$(sudo waydroid shell ip route 2>/dev/null | awk '/src/ {print $NF}')
    fi
    
    echo "$ip"
}

wait_and_connect_adb() {
    local target_ip=$1
    if [ -z "$target_ip" ] || [[ "$target_ip" == "address:" ]]; then
        print_error "IP Detection failed. Ensure Waydroid is fully started."
        return 1
    fi

    echo -e "${YELLOW}⏳ Pinging $target_ip...${NC}"
    local attempts=0
    while ! ping -c 1 -W 1 "$target_ip" >/dev/null 2>&1; do
        ((attempts++))
        echo -ne "${YELLOW}.${NC}"
        if [ $attempts -ge 25 ]; then
            echo -e "\n"
            print_error "Network bridge unreachable."
            return 1
        fi
        sleep 1
    done

    echo -e "\n"
    print_status "Network verified. Connecting ADB..."
    adb connect "$target_ip:5555" >/dev/null 2>&1
    CONNECTED_DEVICES=("$target_ip:5555")
    print_success "ADB Link Established: $target_ip"
}

# ---------------- CORE FUNCTIONS ----------------

run_waydroid_script() {
    print_header
    if [ ! -d "$SCRIPT_DIR" ]; then
        print_status "Cloning waydroid_script to $SCRIPT_DIR..."
        git clone https://github.com/casualsnek/waydroid_script "$SCRIPT_DIR"
    fi
    cd "$SCRIPT_DIR" || return
    if [ ! -d "venv" ]; then
        python3 -m venv venv
        venv/bin/pip install -r requirements.txt
    fi
    print_success "Launching Script UI..."
    sudo venv/bin/python3 main.py
    read -n 1 -p "Press any key to return..."
}

restart_waydroid() {
    print_header
    print_status "Resetting Waydroid services..."
    waydroid session stop 2>/dev/null
    pkill -f weston 2>/dev/null
    sleep 2
    sudo systemctl restart waydroid-container.service
    
    print_status "Initializing Weston & UI..."
    weston >/dev/null 2>&1 &
    sleep 3
    
    # Auto-detect Wayland Display
    local W_DISP=$(ls /run/user/$UID/wayland-* 2>/dev/null | head -n1 | xargs -n1 basename)
    export WAYLAND_DISPLAY=$W_DISP
    
    waydroid show-full-ui >/dev/null 2>&1 &

    print_status "Searching for IP..."
    local W_IP=""
    for i in {1..20}; do
        W_IP=$(get_waydroid_ip)
        [ -n "$W_IP" ] && [[ "$W_IP" =~ ^[0-9] ]] && break
        sleep 1
    done
    wait_and_connect_adb "$W_IP"
    read -n 1 -p "Done. Press any key..."
}

stop_waydroid() {
    print_header
    print_status "Stopping Waydroid & Weston..."
    waydroid session stop 2>/dev/null
    pkill -f weston 2>/dev/null
    adb disconnect >/dev/null 2>&1
    CONNECTED_DEVICES=()
    print_success "System Cleaned."
    sleep 1.5
}

install_apk() {
    print_header
    if [ ${#CONNECTED_DEVICES[@]} -eq 0 ]; then
        local IP=$(get_waydroid_ip)
        wait_and_connect_adb "$IP" || return
    fi
    local APK=$(zenity --file-selection --title="Select APK" --file-filter="*.apk" 2>/dev/null)
    if [ -f "$APK" ]; then
        print_status "Installing $(basename "$APK")..."
        adb -s "${CONNECTED_DEVICES[0]}" install -r "$APK"
        print_success "Installation Finished."
    fi
    read -n 1 -p "Press any key..."
}

# ---------------- MAIN MENU ----------------
while true; do
    print_header
    echo -e " ${BOLD}1)${NC} ${GREEN}START/RESTART${NC} Waydroid Full Stack"
    echo -e " ${BOLD}2)${NC} ${RED}STOP${NC} Waydroid & Weston"
    echo -e " ${BOLD}3)${NC} ${CYAN}INSTALL${NC} APK File"
    echo -e " ${BOLD}4)${NC} ${MAGENTA}WAYDROID SCRIPT${NC} (GApps/Magisk)"
    echo -e " ${BOLD}5)${NC} ${BLUE}LIST${NC} ADB Devices"
    echo -e " ${BOLD}6)${NC} ${YELLOW}RECONNECT${NC} ADB"
    echo -e " ${BOLD}7)${NC} EXIT"
    echo -e "${CYAN}==================================================${NC}"
    
    if [ ${#CONNECTED_DEVICES[@]} -gt 0 ]; then
        echo -e "${GREEN} ● ACTIVE:${NC} ${CONNECTED_DEVICES[*]}"
    else
        echo -e "${RED} ● STATUS:${NC} Offline"
    fi
    echo -e "${CYAN}==================================================${NC}"
    
    read -p "Selection: " CHOICE
    case "$CHOICE" in
        1) restart_waydroid ;;
        2) stop_waydroid ;;
        3) install_apk ;;
        4) run_waydroid_script ;;
        5) print_header; adb devices -l; read -n 1 -p "Press any key..." ;;
        6) wait_and_connect_adb $(get_waydroid_ip) ;;
        7) clear; exit 0 ;;
        *) echo -e "${RED}Invalid choice.${NC}"; sleep 1 ;;
    esac
done
