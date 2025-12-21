#!/bin/bash

# ---------------- COLORS & UI ----------------
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

# ---------------- LOGIC ----------------

get_waydroid_ip() {
    local ip=$(waydroid status 2>/dev/null | grep -i "^IP" | awk '{print $NF}')
    echo "$ip"
}

wait_and_connect_adb() {
    local target_ip=$1
    if [ -z "$target_ip" ] || [[ "$target_ip" == "address:" ]]; then
        print_error "No valid IP address detected."
        return 1
    fi

    echo -e "${YELLOW}⏳ Waiting for network response at $target_ip...${NC}"
    local attempts=0
    while ! ping -c 1 -W 1 "$target_ip" >/dev/null 2>&1; do
        ((attempts++))
        echo -ne "${YELLOW}.${NC}"
        [ $attempts -ge 20 ] && { echo -e "\n"; print_error "Ping timeout."; return 1; }
        sleep 1
    done

    echo -e "\n"
    print_success "Network active. Establishing ADB handshake..."
    adb connect "$target_ip:5555" >/dev/null 2>&1
    CONNECTED_DEVICES=("$target_ip:5555")
}

# ---------------- ACTIONS ----------------

run_waydroid_script() {
    print_header
    if [ ! -d "$SCRIPT_DIR" ]; then
        print_status "Script not found. Cloning to $SCRIPT_DIR..."
        git clone https://github.com/casualsnek/waydroid_script "$SCRIPT_DIR"
    fi

    cd "$SCRIPT_DIR" || { print_error "Failed to enter directory."; return; }

    if [ ! -d "venv" ]; then
        print_status "Setting up Python virtual environment..."
        python3 -m venv venv
        print_status "Installing requirements..."
        venv/bin/pip install -r requirements.txt
    fi

    print_success "Launching Waydroid Script..."
    echo -e "${YELLOW}Note: Root password may be required for script execution.${NC}"
    sudo venv/bin/python3 main.py
    
    echo -e "\n${BOLD}Press any key to return to menu...${NC}"
    read -n 1
}

restart_waydroid() {
    print_header
    print_status "Restarting Waydroid Stack..."
    waydroid session stop 2>/dev/null
    pkill -f weston 2>/dev/null
    sleep 2
    sudo systemctl restart waydroid-container.service
    
    print_status "Launching Weston & UI..."
    weston >/dev/null 2>&1 &
    sleep 3
    WAYLAND_DISPLAY=$(ls /run/user/$UID/wayland-* 2>/dev/null | head -n1 | xargs -n1 basename)
    export WAYLAND_DISPLAY
    waydroid show-full-ui >/dev/null 2>&1 &

    local W_IP=""
    for i in {1..15}; do
        W_IP=$(get_waydroid_ip)
        [ -n "$W_IP" ] && [[ "$W_IP" =~ ^[0-9] ]] && break
        sleep 1
    done
    wait_and_connect_adb "$W_IP"
    read -n 1 -p "Done. Press any key..."
}

stop_waydroid() {
    print_header
    print_status "Stopping services..."
    waydroid session stop 2>/dev/null
    pkill -f weston 2>/dev/null
    adb disconnect >/dev/null 2>&1
    CONNECTED_DEVICES=()
    print_success "System halted."
    sleep 1.5
}

install_apk() {
    print_header
    if [ ${#CONNECTED_DEVICES[@]} -eq 0 ]; then
        wait_and_connect_adb $(get_waydroid_ip) || return
    fi
    local APK=$(zenity --file-selection --title="Select APK" --file-filter="*.apk" 2>/dev/null)
    if [ -f "$APK" ]; then
        print_status "Installing $(basename "$APK")..."
        adb -s "${CONNECTED_DEVICES[0]}" install -r "$APK"
        print_success "Done."
    fi
    read -n 1 -p "Press any key..."
}

# ---------------- MAIN MENU ----------------
while true; do
    print_header
    echo -e " ${BOLD}1)${NC} ${GREEN}START/RESTART${NC} Waydroid Full Stack"
    echo -e "  ${BOLD}2)${NC} ${RED}STOP${NC} Waydroid & Weston"
    echo -e "  ${BOLD}3)${NC} ${CYAN}INSTALL${NC} APK File"
    echo -e "  ${BOLD}4)${NC} ${MAGENTA}WAYDROID SCRIPT${NC} (GApps, Magisk, etc. by casualsnek/waydroid_script)"
    echo -e "  ${BOLD}5)${NC} ${BLUE}LIST${NC} ADB Devices"
    echo -e "  ${BOLD}6)${NC} ${YELLOW}RECONNECT${NC} ADB"
    echo -e "  ${BOLD}7)${NC} EXIT"
    echo -e "${CYAN}==================================================${NC}"
    
    if [ ${#CONNECTED_DEVICES[@]} -gt 0 ]; then
        echo -e "${GREEN} ● ACTIVE:${NC} ${CONNECTED_DEVICES[*]}"
    else
        echo -e "${RED} ● STATUS:${NC} Disconnected"
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
        *) echo -e "${RED}Invalid selection.${NC}"; sleep 1 ;;
    esac
done
