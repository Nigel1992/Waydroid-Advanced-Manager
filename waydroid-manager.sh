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
# Determine script path for version/date detection
SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_SELF_DIR="$(dirname "$SCRIPT_PATH")"

# Embedded version (single source of truth inside script)
SCRIPT_VERSION="0.4.0"

get_version() {
    # Prefer embedded SCRIPT_VERSION
    if [ -n "${SCRIPT_VERSION:-}" ]; then
        echo "$SCRIPT_VERSION"
        return
    fi

    # Try git tags/describe
    if git -C "$SCRIPT_SELF_DIR" describe --tags --always >/dev/null 2>&1; then
        git -C "$SCRIPT_SELF_DIR" describe --tags --always 2>/dev/null
        return
    fi
    # Fallback to commit short hash
    if git -C "$SCRIPT_SELF_DIR" rev-parse --short HEAD >/dev/null 2>&1; then
        git -C "$SCRIPT_SELF_DIR" rev-parse --short HEAD 2>/dev/null
        return
    fi
    echo "dev"
}

get_release_date() {
    # Prefer last git commit date
    local d
    d=$(git -C "$SCRIPT_SELF_DIR" log -1 --format=%cd --date=format:%Y-%m-%d 2>/dev/null || true)
    if [ -n "$d" ]; then echo "$d"; return; fi
    # Fallback to script file modification date
    d=$(date -r "$SCRIPT_PATH" +%Y-%m-%d 2>/dev/null || true)
    if [ -n "$d" ]; then echo "$d"; return; fi
    echo "$(date +%Y-%m-%d)"
}

print_header() {
    clear
    local version=$(get_version)
    local release_date=$(get_release_date)
    echo -e "${CYAN}${BOLD}=================================================="
    echo -e "           WAYDROID ADVANCED MANAGER  ${YELLOW}v${version} ${NC}${CYAN}(${release_date})"
    echo -e "==================================================${NC}"
}

# CLI: --version / --help support
if [ "${1:-}" = "--version" ] || [ "${1:-}" = "-v" ]; then
    echo "$(get_version) ($(get_release_date))"
    exit 0
fi
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "Waydroid Advanced Manager"
    echo "Usage: $0 [--version|-v] [--help|-h]"
    echo "Runs the interactive Waydroid manager. See README.md for details."
    exit 0
fi

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
    # Wait for Weston to fully stop and socket to disappear
    for i in {1..10}; do
        if ! pgrep -f weston >/dev/null 2>&1 && [ ! -e "/run/user/$UID/wayland-0" ]; then
            break
        fi
        sleep 0.5
    done
    sudo systemctl restart waydroid-container.service

    print_status "Launching Weston & UI..."
    WESTON_LOG="/tmp/weston-launch-$$.log"
    weston --backend=x11-backend.so > "$WESTON_LOG" 2>&1 &

    # Wait for Wayland socket to appear (max 10s)
    WAYLAND_SOCKET=""
    for i in {1..20}; do
        _wd=$(ls -d /run/user/$UID/wayland-* 2>/dev/null | head -n1 || true)
        if [ -n "$_wd" ]; then
            WAYLAND_SOCKET="$_wd"
            break
        fi
        sleep 0.5
    done
    if [ -n "$WAYLAND_SOCKET" ]; then
        WAYLAND_DISPLAY=$(basename "$WAYLAND_SOCKET")
        export WAYLAND_DISPLAY
        print_success "Wayland socket found: $WAYLAND_DISPLAY"
    else
        print_error "No Wayland socket found after starting Weston. UI will not launch."
        print_error "Weston log output:"
        cat "$WESTON_LOG"
        print_status "Try running 'weston' manually in another terminal to debug."
        unset WAYLAND_DISPLAY
        read -n 1 -p "Press any key to return to menu..."
        return
    fi

    waydroid show-full-ui >/dev/null 2>&1 &

    local W_IP=""
    print_status "Waiting for Waydroid to provide a valid IP address..."
    for i in {1..30}; do
        W_IP=$(get_waydroid_ip)
        if [ -n "$W_IP" ] && [[ "$W_IP" =~ ^[0-9] ]]; then
            break
        fi
        sleep 1
    done
    if [ -z "$W_IP" ] || [[ ! "$W_IP" =~ ^[0-9] ]]; then
        print_error "Waydroid did not provide a valid IP address after restart. Please check the container status."
        read -n 1 -p "Press any key to return to menu..."
        return
    fi
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
    local APK=""
    local install_method=$(zenity --list --radiolist --title="APK Install Method" --text="Choose how to install the APK" --column="Select" --column="Method" TRUE "Select Local APK" FALSE "Install from URL" --height=200 --width=400 2>/dev/null)
    if [ "$install_method" = "Select Local APK" ]; then
        APK=$(zenity --file-selection --title="Select APK" --file-filter="*.apk" 2>/dev/null)
        if [ -f "$APK" ]; then
            print_status "Installing $(basename "$APK")..."
            adb -s "${CONNECTED_DEVICES[0]}" install -r "$APK"
            print_success "Done."
        fi
    elif [ "$install_method" = "Install from URL" ]; then
        local APK_URL=$(zenity --entry --title="APK URL" --text="Enter direct APK URL (https://.../app.apk)" --width=500 2>/dev/null)
        if [[ "$APK_URL" =~ ^https?://.*\.apk$ ]]; then
            local TMP_APK="/tmp/waydroid_apk_$$.apk"
            print_status "Downloading APK..."
            if command -v curl >/dev/null 2>&1; then
                curl -L -o "$TMP_APK" "$APK_URL"
            elif command -v wget >/dev/null 2>&1; then
                wget -O "$TMP_APK" "$APK_URL"
            else
                print_error "curl or wget required to download APK."
                read -n 1 -p "Press any key..."
                return
            fi
            if [ -f "$TMP_APK" ]; then
                print_status "Installing $(basename "$TMP_APK")..."
                adb -s "${CONNECTED_DEVICES[0]}" install -r "$TMP_APK"
                print_success "Done."
                rm -f "$TMP_APK"
            else
                print_error "Failed to download APK."
            fi
        else
            print_error "Invalid URL. Must end with .apk"
        fi
    fi
    read -n 1 -p "Press any key..."
}

# Copy/Paste to Android
copy_paste_to_android() {
    print_header
    local text
    echo -e "${YELLOW}Before continuing:${NC} Please make sure the input field (keyboard or text box) is open and focused in your Android environment. The text will be typed automatically into the currently active input box."
    echo -e "\n${CYAN}Only plain text is supported. Do not enter files or non-text data.${NC}"
    echo "Enter the text you want to send to Android (then press ENTER):"
    read -r text

    if [ -z "$text" ]; then
        print_status "Cancelled"
        sleep 1
        return
    fi

    # Ensure ADB connection
    if [ ${#CONNECTED_DEVICES[@]} -eq 0 ]; then
        print_status "Establishing ADB connection..."
        wait_and_connect_adb $(get_waydroid_ip) || {
            print_error "Failed to connect to ADB. Please try again."
            sleep 2
            return
        }
    fi

    # Escape text for adb shell input (replace spaces with %s, escape shell metacharacters so chars like &, |, ; are sent correctly)
    local safe_text
    # Escape backslashes first to avoid clobbering
    safe_text=${text//\\/\\\\}
    # Replace spaces with %s for `input text`
    safe_text=${safe_text// /%s}
    # Escape characters that the remote shell would interpret
    safe_text=${safe_text//"/\\"}
    safe_text=${safe_text//&/\\&}
    safe_text=${safe_text//|/\\|}
    safe_text=${safe_text//;/\\;}
    safe_text=${safe_text//</\\<}
    safe_text=${safe_text//>/\\>}
    safe_text=${safe_text//\$/\\\$}
    safe_text=${safe_text//\`/\\\`}


    print_status "Sending text to Android via ADB..."
    adb -s "${CONNECTED_DEVICES[0]}" shell input text "$safe_text"
    print_success "Text sent to Android device."
    echo "Check the currently focused input field in your Android environment."
    read -n 1 -p "Press any key to return to menu..."
}

# Uninstall Apps Menu
uninstall_apps_menu() {
    # Check if Waydroid is running
    if ! waydroid status 2>/dev/null | grep -q "RUNNING"; then
        print_header
        print_error "Waydroid is not running!"
        echo ""
        read -p "Start Waydroid now? (y/N): " start_choice
        if [[ "$start_choice" =~ ^[Yy]$ ]]; then
            restart_waydroid
        else
            print_status "App Management requires Waydroid to be running."
            sleep 2
            return
        fi
    fi
    
    # Ensure ADB connection
    if [ ${#CONNECTED_DEVICES[@]} -eq 0 ]; then
        print_status "Establishing ADB connection..."
        wait_and_connect_adb $(get_waydroid_ip) || {
            print_error "Failed to connect to ADB. Please try again."
            sleep 2
            return
        }
    fi
    
    while true; do
        print_header
        echo -e "${BOLD}${GREEN}━━━ APPLICATION MANAGEMENT ━━━${NC}"
        echo ""
        echo -e "${BOLD}${CYAN}┌─ OPTIONS${NC} ${BOLD}${CYAN}───────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}1)${NC}  📋 List Installed Apps"
        echo -e "${CYAN}│${NC}  ${BOLD}2)${NC}  🗑 Uninstall App by Package Name"
        echo -e "${CYAN}│${NC}  ${BOLD}3)${NC}  🗑 Uninstall from List (Interactive)"
        echo -e "${CYAN}└${NC}${CYAN}──────────────────────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "${BOLD}${MAGENTA}4)${NC}  ${MAGENTA}↩ Back to Main Menu${NC}"
        echo -e "${CYAN}==================================================${NC}"
        echo ""
        
        read -p "Selection: " APP_CHOICE
        case "$APP_CHOICE" in
            1) list_installed_apps ;;
            2) uninstall_by_package ;;
            3) uninstall_from_list ;;
            4) break ;;
            *) echo -e "${RED}❌ Invalid selection.${NC}"; sleep 1 ;;
        esac
    done
}

# List Installed Apps
list_installed_apps() {
    # Check if Waydroid is running
    if ! waydroid status 2>/dev/null | grep -q "RUNNING"; then
        print_header
        print_error "Waydroid is not running!"
        echo ""
        read -p "Start Waydroid now? (y/N): " start_choice
        if [[ "$start_choice" =~ ^[Yy]$ ]]; then
            restart_waydroid
        else
            print_status "Listing apps requires Waydroid to be running."
            sleep 2
            return
        fi
    fi
    
    print_header
    echo -e "${BOLD}${CYAN}━━━ INSTALLED APPLICATIONS ━━━${NC}\n"
    
    if [ ${#CONNECTED_DEVICES[@]} -eq 0 ]; then
        print_error "Not connected to ADB. Attempting to reconnect..."
        wait_and_connect_adb $(get_waydroid_ip) || {
            print_error "Failed to connect"
            sleep 2
            return
        }
    fi
    
    echo -e "${BOLD}${BLUE}┌─ SYSTEM APPS + USER APPS${NC} ${BOLD}${BLUE}──────────────────────────┐${NC}"
    echo ""
    print_status "Fetching apps list..."
    echo ""
    
    local apps=$(adb -s "${CONNECTED_DEVICES[0]}" shell pm list packages 2>/dev/null | sed 's/package://')
    local app_count=$(echo "$apps" | grep -c . || echo 0)
    
    if [ $app_count -gt 0 ]; then
        echo "$apps" | head -50
        echo ""
        if [ $app_count -gt 50 ]; then
            echo -e "${YELLOW}... and $((app_count - 50)) more apps${NC}"
        fi
        echo ""
        echo -e "${BLUE}└${NC}${BLUE}─────────────────────────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "${BOLD}📊 Total Installed:${NC} $app_count packages"
    else
        print_error "No apps found or device not responding"
        echo -e "${YELLOW}Make sure Waydroid is running and ADB connection is active.${NC}"
    fi
    
    echo ""
    read -n 1 -p "Press any key to continue..."
}

# Uninstall by Package Name
uninstall_by_package() {
    # Check if Waydroid is running
    if ! waydroid status 2>/dev/null | grep -q "RUNNING"; then
        print_header
        print_error "Waydroid is not running!"
        echo ""
        read -p "Start Waydroid now? (y/N): " start_choice
        if [[ "$start_choice" =~ ^[Yy]$ ]]; then
            restart_waydroid
        else
            print_status "Uninstalling apps requires Waydroid to be running."
            sleep 2
            return
        fi
    fi
    
    print_header
    echo -e "${BOLD}${YELLOW}━━━ UNINSTALL APP BY PACKAGE NAME ━━━${NC}\n"
    
    if [ ${#CONNECTED_DEVICES[@]} -eq 0 ]; then
        print_error "Not connected to ADB. Attempting to reconnect..."
        wait_and_connect_adb $(get_waydroid_ip) || {
            print_error "Failed to connect"
            sleep 2
            return
        }
    fi
    
    read -p "📦 Enter package name to uninstall (e.g., com.example.app): " package_name
    
    if [ -z "$package_name" ]; then
        print_error "Package name cannot be empty"
        sleep 2
        return
    fi
    
    echo ""
    echo -e "${BOLD}${CYAN}━━━ UNINSTALLING ━━━${NC}\n"
    print_status "Attempting to uninstall: ${BOLD}${package_name}${NC}..."
    
    local result=$(adb -s "${CONNECTED_DEVICES[0]}" shell pm uninstall "$package_name" 2>&1)
    
    if echo "$result" | grep -q "Success"; then
        echo ""
        print_success "✓ Successfully uninstalled ${BOLD}${package_name}${NC}"
    else
        echo ""
        print_error "✗ Failed to uninstall ${BOLD}${package_name}${NC}"
        echo -e "${YELLOW}Response: $result${NC}"
    fi
    
    # Check if Waydroid is still running
    sleep 1
    if ! waydroid status 2>/dev/null | grep -q "RUNNING"; then
        echo ""
        print_error "Waydroid stopped during operation!"
        echo -e "${YELLOW}Automatically restarting Waydroid...${NC}"
        sleep 2
        restart_waydroid
    fi
}

# Uninstall from Interactive List
uninstall_from_list() {
    # Check if Waydroid is running
    if ! waydroid status 2>/dev/null | grep -q "RUNNING"; then
        print_header
        print_error "Waydroid is not running!"
        echo ""
        read -p "Start Waydroid now? (y/N): " start_choice
        if [[ "$start_choice" =~ ^[Yy]$ ]]; then
            restart_waydroid
        else
            print_status "Uninstalling apps requires Waydroid to be running."
            sleep 2
            return
        fi
    fi

    while true; do
        clear
        print_header
        # Live status info
        echo -e "${BOLD}${YELLOW}━━━ SELECT APP TO UNINSTALL ━━━${NC}\n"
        echo -e "${CYAN}Waydroid status:${NC} $(waydroid status 2>/dev/null | grep -o 'RUNNING\|STOPPED')"
        echo -e "${CYAN}ADB devices:${NC} $(adb devices | grep -v 'List' | grep -v '^$' | wc -l)"
        echo -e "${CYAN}Date:${NC} $(date '+%Y-%m-%d %H:%M:%S')\n"

        # Ask user: all apps or user apps
        app_type=$(zenity --list --radiolist --title="App List Type" --text="Show all apps or only user-installed?" --column="Select" --column="Type" TRUE "User Installed" FALSE "All Apps" --height=200 --width=400 2>/dev/null)
        if [ -z "$app_type" ]; then
            print_status "Cancelled"
            sleep 1
            return
        fi

        print_status "Fetching installed apps..."
        if [ "$app_type" = "User Installed" ]; then
            # Only user apps (not system)
            apps_array=($(adb -s "${CONNECTED_DEVICES[0]}" shell pm list packages -3 2>/dev/null | sed 's/package://' | sort))
        else
            # All apps
            apps_array=($(adb -s "${CONNECTED_DEVICES[0]}" shell pm list packages 2>/dev/null | sed 's/package://' | sort))
        fi
        app_count=${#apps_array[@]}

        if [ $app_count -eq 0 ]; then
            print_error "No apps found or device not responding"
            echo -e "${YELLOW}Make sure Waydroid is running and ADB connection is active.${NC}"
            sleep 2
            return
        fi

        print_success "Found $app_count applications\n"

        # Use zenity for graphical selection
        app_list_str=""
        for pkg in "${apps_array[@]}"; do
            app_list_str+="$pkg\n"
        done
        selected_app=$(echo -e "$app_list_str" | zenity --list --title="Select App to Uninstall" --column="Package Name" --height=500 --width=600 2>/dev/null)
        if [ -z "$selected_app" ]; then
            print_status "Cancelled"
            sleep 1
            return
        fi
        echo ""
        echo -e "${BOLD}${CYAN}Confirm uninstall of:${NC} ${BOLD}${selected_app}${NC}?"
        zenity --question --title="Confirm Uninstall" --text="Uninstall $selected_app?" --width=400 2>/dev/null
        if [ $? -eq 0 ]; then
            echo ""
            print_status "Uninstalling ${BOLD}${selected_app}${NC}..."
            result=$(adb -s "${CONNECTED_DEVICES[0]}" shell pm uninstall "$selected_app" 2>&1)
            if echo "$result" | grep -q "Success"; then
                echo ""
                print_success "✓ Successfully uninstalled ${BOLD}${selected_app}${NC}"
            else
                echo ""
                print_error "✗ Failed to uninstall ${BOLD}${selected_app}${NC}"
                echo -e "${YELLOW}Response: $result${NC}"
            fi
            sleep 1
            if ! waydroid status 2>/dev/null | grep -q "RUNNING"; then
                echo ""
                print_error "Waydroid stopped during operation!"
                echo -e "${YELLOW}Automatically restarting Waydroid...${NC}"
                sleep 2
                restart_waydroid
            fi
            sleep 2
            break
        else
            print_status "Uninstall cancelled"
            sleep 1
            break
        fi
    done
}

# Display Settings Menu
change_display_settings() {
    while true; do
        print_header
        echo -e "${BOLD}${GREEN}━━━ DISPLAY SETTINGS ━━━${NC}"
        echo ""
        echo -e "${BOLD}${CYAN}┌─ QUICK APPLY${NC} ${BOLD}${CYAN}─────────────────────────────────┐${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}1)${NC}  📱 Preset Resolutions"
        echo -e "${CYAN}│${NC}  ${BOLD}2)${NC}  📐 Preset Densities"
        echo -e "${CYAN}│${NC}  ${BOLD}3)${NC}  📊 View Current Settings"
        echo -e "${CYAN}│${NC}  ${BOLD}4)${NC}  ♻️  Reset Display Settings"
        echo -e "${CYAN}└${NC}${CYAN}─────────────────────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "${BOLD}${YELLOW}┌─ CUSTOM OPTIONS${NC} ${BOLD}${YELLOW}──────────────────────────────────┐${NC}"
        echo -e "${YELLOW}│${NC}  ${BOLD}5)${NC}  🎯 Custom Resolution"
        echo -e "${YELLOW}│${NC}  ${BOLD}6)${NC}  🎯 Custom Density"
        echo -e "${YELLOW}│${NC}  ${BOLD}7)${NC}  🎯 Custom Both (Resolution + Density)"
        echo -e "${YELLOW}└${NC}${YELLOW}─────────────────────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "${BOLD}${MAGENTA}8)${NC}  ${MAGENTA}↩ Back to Main Menu${NC}"
        echo -e "${CYAN}==================================================${NC}"
        echo ""
        read -p "Selection: " DISPLAY_CHOICE
        case "$DISPLAY_CHOICE" in
            1) preset_resolutions ;;
            2) preset_densities ;;
            3) view_current_settings ;;
            4)
                echo -e "${YELLOW}Resetting display size and density to default...${NC}"
                sudo waydroid shell wm size reset
                sudo waydroid shell wm density reset
                echo -e "${GREEN}Display settings reset to default.${NC}"
                sleep 2
                ;;
            5) custom_resolution ;;
            6) custom_density ;;
            7) custom_both ;;
            8) break ;;
            *) echo -e "${RED}❌ Invalid selection.${NC}"; sleep 1 ;;
        esac
    done
}

# Preset Resolutions
preset_resolutions() {
    print_header
    echo -e "${BOLD}${CYAN}━━━ SELECT RESOLUTION ━━━${NC}"
    echo ""
    echo -e "${BOLD}${GREEN}┌─ PORTRAIT MODES${NC} ${BOLD}${GREEN}──────────────────────────────────┐${NC}"
    echo -e "${GREEN}│${NC}  ${BOLD}1)${NC}  📱 1080 x 2340 (FHD+ - Flagship)"
    echo -e "${GREEN}│${NC}  ${BOLD}2)${NC}  📱 1440 x 3120 (QHD+ - Premium)"
    echo -e "${GREEN}│${NC}  ${BOLD}3)${NC}  📱 720 x 1520 (HD+ - Budget)"
    echo -e "${GREEN}│${NC}  ${BOLD}4)${NC}  📱 1440 x 2560 (QHD - Mid-range)"
    echo -e "${GREEN}└${NC}${GREEN}─────────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "${BOLD}${BLUE}┌─ LANDSCAPE MODE${NC} ${BOLD}${BLUE}────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC}  ${BOLD}5)${NC}  🖥 1080 x 1920 (FHD Landscape)"
    echo -e "${BLUE}└${NC}${BLUE}─────────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "${BOLD}${MAGENTA}6)${NC}  ${MAGENTA}↩ Back${NC}"
    echo -e "${CYAN}==================================================${NC}"
    
    read -p "Selection: " RES_CHOICE
    local width height
    case "$RES_CHOICE" in
        1) width=1080; height=2340 ;;
        2) width=1440; height=3120 ;;
        3) width=720; height=1520 ;;
        4) width=1080; height=1920 ;;
        5) width=1440; height=2560 ;;
        6) return ;;
        *) echo -e "${RED}Invalid selection.${NC}"; sleep 1; return ;;
    esac
    
    apply_resolution "$width" "$height"
}

# Preset Densities
preset_densities() {
    print_header
    echo -e "${BOLD}${CYAN}━━━ SELECT DENSITY (DPI) ━━━${NC}"
    echo ""
    echo -e "${BOLD}${GREEN}┌─ STANDARD DENSITIES${NC} ${BOLD}${GREEN}──────────────────────────────────┐${NC}"
    echo -e "${GREEN}│${NC}  ${BOLD}1)${NC}  📊 160 dpi   MDPI (Standard - Older devices)"
    echo -e "${GREEN}│${NC}  ${BOLD}2)${NC}  📊 213 dpi   TVDPI (TV Density)"
    echo -e "${GREEN}│${NC}  ${BOLD}3)${NC}  📊 240 dpi   HDPI (High)"
    echo -e "${GREEN}└${NC}${GREEN}─────────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "${BOLD}${BLUE}┌─ HIGH DENSITIES${NC} ${BOLD}${BLUE}────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC}  ${BOLD}4)${NC}  📊 320 dpi   XHDPI (Extra-High)"
    echo -e "${BLUE}│${NC}  ${BOLD}5)${NC}  📊 480 dpi   XXHDPI (Extra-Extra-High)"
    echo -e "${BLUE}│${NC}  ${BOLD}6)${NC}  📊 640 dpi   XXXHDPI (Ultra - High-end devices)"
    echo -e "${BLUE}└${NC}${BLUE}─────────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "${BOLD}${MAGENTA}7)${NC}  ${MAGENTA}↩ Back${NC}"
    echo -e "${CYAN}==================================================${NC}"
    
    read -p "Selection: " DEN_CHOICE
    local density
    case "$DEN_CHOICE" in
        1) density=160 ;;
        2) density=213 ;;
        3) density=240 ;;
        4) density=320 ;;
        5) density=480 ;;
        6) density=640 ;;
        7) return ;;
        *) echo -e "${RED}Invalid selection.${NC}"; sleep 1; return ;;
    esac
    
    apply_density "$density"
}

# Custom Resolution
custom_resolution() {
    print_header
    echo -e "${BOLD}${YELLOW}━━━ CUSTOM RESOLUTION ━━━${NC}"
    echo ""
    echo -e "${YELLOW}Examples: 1080, 720, 1440, 2160${NC}"
    echo ""
    read -p "📏 Enter width in pixels: " width
    read -p "📏 Enter height in pixels: " height
    
    if [[ "$width" =~ ^[0-9]+$ ]] && [[ "$height" =~ ^[0-9]+$ ]]; then
        apply_resolution "$width" "$height"
    else
        print_error "Invalid input. Please enter numeric values."
        sleep 2
    fi
}

# Custom Density
custom_density() {
    print_header
    echo -e "${BOLD}${YELLOW}━━━ CUSTOM DENSITY (DPI) ━━━${NC}"
    echo ""
    echo -e "${YELLOW}Standard ranges: 160-640${NC}"
    echo -e "${YELLOW}Common values: 160, 213, 240, 320, 480, 640${NC}"
    echo ""
    read -p "📊 Enter density in DPI: " density
    
    if [[ "$density" =~ ^[0-9]+$ ]]; then
        apply_density "$density"
    else
        print_error "Invalid input. Please enter numeric value."
        sleep 2
    fi
}

# Custom Both
custom_both() {
    print_header
    echo -e "${BOLD}${YELLOW}━━━ CUSTOM RESOLUTION + DENSITY ━━━${NC}"
    echo ""
    echo -e "${YELLOW}Configure both display size and pixel density${NC}"
    echo ""
    read -p "📏 Enter width in pixels (e.g., 1080): " width
    read -p "📏 Enter height in pixels (e.g., 2340): " height
    read -p "📊 Enter density in DPI (e.g., 240): " density
    
    if [[ "$width" =~ ^[0-9]+$ ]] && [[ "$height" =~ ^[0-9]+$ ]] && [[ "$density" =~ ^[0-9]+$ ]]; then
        apply_resolution "$width" "$height"
        apply_density "$density"
    else
        print_error "Invalid input. Please enter numeric values."
        sleep 2
    fi
}

# Apply Resolution
apply_resolution() {
    local width=$1
    local height=$2
    
    if [ ${#CONNECTED_DEVICES[@]} -eq 0 ]; then
        wait_and_connect_adb $(get_waydroid_ip) || return
    fi
    
    echo -e "\n${BOLD}${CYAN}━━━ APPLYING RESOLUTION ━━━${NC}\n"
    print_status "Setting resolution to ${BOLD}${width}x${height}${NC}..."
    adb -s "${CONNECTED_DEVICES[0]}" shell wm size "${width}x${height}" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo ""
        print_success "✓ Resolution successfully set to ${BOLD}${width}x${height}${NC}"
    else
        echo ""
        print_error "✗ Failed to set resolution"
    fi
    sleep 3
}

# Apply Density
apply_density() {
    local density=$1
    
    if [ ${#CONNECTED_DEVICES[@]} -eq 0 ]; then
        wait_and_connect_adb $(get_waydroid_ip) || return
    fi
    
    echo -e "\n${BOLD}${CYAN}━━━ APPLYING DENSITY ━━━${NC}\n"
    print_status "Setting density to ${BOLD}${density} dpi${NC}..."
    adb -s "${CONNECTED_DEVICES[0]}" shell wm density "$density" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo ""
        print_success "✓ Density successfully set to ${BOLD}${density} dpi${NC}"
    else
        echo ""
        print_error "✗ Failed to set density"
    fi
    sleep 3
}

# View Current Settings
view_current_settings() {
    print_header
    echo -e "${BOLD}${CYAN}━━━ CURRENT DISPLAY SETTINGS ━━━${NC}\n"
    
    if [ ${#CONNECTED_DEVICES[@]} -eq 0 ]; then
        wait_and_connect_adb $(get_waydroid_ip) || return
    fi
    
    echo -e "${BOLD}${GREEN}┌─ DEVICE INFORMATION${NC} ${BOLD}${GREEN}─────────────────────────────────┐${NC}"
    echo -e "${GREEN}│${NC}  Connected Device: ${CONNECTED_DEVICES[0]}"
    echo -e "${GREEN}└${NC}${GREEN}─────────────────────────────────────────────────────────┘${NC}"
    echo ""
    
    echo -e "${BOLD}${BLUE}┌─ DISPLAY CONFIGURATION${NC} ${BOLD}${BLUE}──────────────────────────────────┐${NC}"
    
    echo -ne "${BLUE}│${NC}  📏 Display Size:     "
    local resolution=$(adb -s "${CONNECTED_DEVICES[0]}" shell wm size 2>/dev/null | grep -oP '\d+x\d+' || echo "Unable to retrieve")
    echo -e "${BOLD}${resolution}${NC}"
    
    echo -ne "${BLUE}│${NC}  📊 Display Density:  "
    local density=$(adb -s "${CONNECTED_DEVICES[0]}" shell wm density 2>/dev/null | grep -oP '\d+' | head -1 || echo "Unable to retrieve")
    echo -e "${BOLD}${density} dpi${NC}"
    
    echo -e "${BLUE}└${NC}${BLUE}─────────────────────────────────────────────────────────┘${NC}"
    
    echo ""
    read -n 1 -p "Press any key to return..."
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
    echo -e "  ${BOLD}7)${NC} ${GREEN}DISPLAY SETTINGS${NC} (Resolution, Density, etc.)"
    echo -e "  ${BOLD}8)${NC} ${CYAN}APP MANAGEMENT${NC} (Install/Uninstall)"
    echo -e "  ${BOLD}9)${NC} ${MAGENTA}COPY/PASTE${NC} to Android"
    echo -e "  ${BOLD}10)${NC} ${YELLOW}EXIT${NC}"
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
        2)
            if waydroid status 2>/dev/null | grep -q "RUNNING"; then
                stop_waydroid
            else
                print_header
                print_error "Waydroid is not running! Start it using option 1 in the main menu."
                echo ""
                read -n 1 -p "Press any key..."
            fi
            ;;
        3)
            if waydroid status 2>/dev/null | grep -q "RUNNING"; then
                install_apk
            else
                print_header
                print_error "Waydroid is not running! Start it using option 1 in the main menu."
                echo ""
                read -n 1 -p "Press any key..."
            fi
            ;;
        4)
            if waydroid status 2>/dev/null | grep -q "RUNNING"; then
                run_waydroid_script
            else
                print_header
                print_error "Waydroid is not running! Start it using option 1 in the main menu."
                echo ""
                read -n 1 -p "Press any key..."
            fi
            ;;
        5)
            if waydroid status 2>/dev/null | grep -q "RUNNING"; then
                print_header; adb devices -l; read -n 1 -p "Press any key..."
            else
                print_header
                print_error "Waydroid is not running! Start it using option 1 in the main menu."
                echo ""
                read -n 1 -p "Press any key..."
            fi
            ;;
        6)
            if waydroid status 2>/dev/null | grep -q "RUNNING"; then
                wait_and_connect_adb $(get_waydroid_ip)
            else
                print_header
                print_error "Waydroid is not running! Start it using option 1 in the main menu."
                echo ""
                read -n 1 -p "Press any key..."
            fi
            ;;
        7)
            if waydroid status 2>/dev/null | grep -q "RUNNING"; then
                change_display_settings
            else
                print_header
                print_error "Waydroid is not running! Start it using option 1 in the main menu."
                echo ""
                read -n 1 -p "Press any key..."
            fi
            ;;
        8)
            if waydroid status 2>/dev/null | grep -q "RUNNING"; then
                uninstall_apps_menu
            else
                print_header
                print_error "Waydroid is not running! Start it using option 1 in the main menu."
                echo ""
                read -n 1 -p "Press any key..."
            fi
            ;;
        9)
            if waydroid status 2>/dev/null | grep -q "RUNNING"; then
                copy_paste_to_android
            else
                print_header
                print_error "Waydroid is not running! Start it using option 1 in the main menu."
                echo ""
                read -n 1 -p "Press any key..."
            fi
            ;;
        10) clear; exit 0 ;;
        *) echo -e "${RED}Invalid selection.${NC}"; sleep 1 ;;
    esac
done
