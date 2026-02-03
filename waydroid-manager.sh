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
CONFIG_FILE="$HOME/.config/waydroid-manager.conf"
LOG_DIR="$HOME/.cache/waydroid-manager"
LOG_FILE="$LOG_DIR/waydroid-manager.log"
DEBUG=0
WESTON_PID=""
WESTON_STARTED=0
PREV_RESOLUTION=""
PREV_DENSITY=""
PREV_SETTINGS_SAVED=0
DEFAULT_DPI=""
DEFAULT_RESOLUTION=""
THEME="light"  # persisted theme (light|dark) - can be overridden in ~/.config/waydroid-manager.conf

# UI Helpers
# Determine script path for version/date detection
SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_SELF_DIR="$(dirname "$SCRIPT_PATH")"

# Embedded version (single source of truth inside script)
SCRIPT_VERSION="0.5.1"
RELEASE_DATE="2026-02-03"

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck disable=SC1090
        . "$CONFIG_FILE"
    fi
    LOG_DIR="${LOG_DIR:-$HOME/.cache/waydroid-manager}"
    LOG_FILE="${LOG_FILE:-$LOG_DIR/waydroid-manager.log}"
    SCRIPT_DIR="${SCRIPT_DIR:-$HOME/waydroid_script}"
}

ensure_log_dir() {
    mkdir -p "$LOG_DIR"
}

rotate_logs() {
    if [ -f "$LOG_FILE" ]; then
        local size
        size=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo 0)
        if [ "$size" -gt 1048576 ]; then
            mv -f "$LOG_FILE" "${LOG_FILE}.1" 2>/dev/null || true
        fi
    fi
}

log_line() {
    local level="$1"
    shift
    local msg="$*"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$ts] [$level] $msg" >> "$LOG_FILE"
}

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
    # Prefer embedded RELEASE_DATE
    if [ -n "${RELEASE_DATE:-}" ]; then
        echo "$RELEASE_DATE"
        return
    fi
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

show_help() {
    cat <<EOF
Waydroid Advanced Manager
Usage: $0 [options]

Options:
  --version, -v                Show version and exit
  --help, -h                   Show this help and exit
  --debug                      Enable debug logging
  --restart                    Restart Waydroid stack
  --stop                       Stop Waydroid and Weston
  --status                     Show system status
  --install-apk <path|url>     Install APK from file or URL
  --install-apks-dir <dir>     Install all APKs from a directory
  --set-dpi <dpi>              Set display density
  --set-res <WxH>              Set display resolution
  --list-apps-export [file]    Export installed apps list
  --theme <dark|light>         Set and persist terminal theme (light or dark)
  --self-update                Update script from git
EOF
}

parse_args() {
    local action_taken=0
    local deps_checked=0
    ensure_deps() {
        if [ "$deps_checked" -eq 0 ]; then
            check_dependencies || exit 1
            deps_checked=1
        fi
    }
    while [ $# -gt 0 ]; do
        case "$1" in
            --version|-v)
                echo "$(get_version) ($(get_release_date))"
                exit 0
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            --debug)
                DEBUG=1
                ;;
            --restart)
                ensure_deps
                restart_waydroid
                action_taken=1
                ;;
            --stop)
                ensure_deps
                stop_waydroid
                action_taken=1
                ;;
            --status)
                ensure_deps
                show_status
                action_taken=1
                ;;
            --install-apk)
                shift
                ensure_deps
                install_apk_cli "$1"
                action_taken=1
                ;;
            --set-dpi)
                shift
                ensure_deps
                apply_density "$1"
                action_taken=1
                ;;
            --set-res)
                shift
                if [[ "$1" =~ ^[0-9]+x[0-9]+$ ]]; then
                    local w=${1%x*}
                    local h=${1#*x}
                    ensure_deps
                    apply_resolution "$w" "$h"
                    action_taken=1
                else
                    print_error "Invalid resolution format. Use WxH (e.g., 1080x2340)."
                    exit 1
                fi
                ;;
            --list-apps-export)
                shift
                ensure_deps
                export_installed_apps "$1"
                action_taken=1
                ;;
            --install-apks-dir)
                shift
                ensure_deps
                install_apks_dir_cli "$1"
                action_taken=1
                ;;
            --theme)
                shift
                set_theme_cli "$1" "no-pause"
                action_taken=1
                ;;
            --self-update)
                ensure_deps
                self_update
                action_taken=1
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
        shift
    done

    if [ "$action_taken" -eq 1 ]; then
        exit 0
    fi
}

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; log_line "INFO" "$1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; log_line "OK" "$1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; log_line "ERROR" "$1"; }

check_dependencies() {
    local missing=()
    local required=(waydroid adb zenity git weston ping awk grep sed date)
    for cmd in "${required[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        missing+=("curl/wget")
    fi
    if [ ${#missing[@]} -gt 0 ]; then
        print_error "Missing dependencies: ${missing[*]}"
        print_status "Install them and re-run the script."
        return 1
    fi
    return 0
}

cleanup() {
    if [ -n "${CONNECTED_DEVICES[*]}" ]; then
        adb disconnect >/dev/null 2>&1 || true
    fi
    if [ "$WESTON_STARTED" -eq 1 ] && [ -n "$WESTON_PID" ]; then
        kill "$WESTON_PID" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

# ---------------- LOGIC ----------------

get_waydroid_ip() {
    local ip=$(waydroid status 2>/dev/null | grep -i "^IP" | awk '{print $NF}')
    echo "$ip"
}

adb_device_connected() {
    local target="$1"
    adb devices 2>/dev/null | awk 'NR>1 {print $1}' | grep -x "$target" >/dev/null 2>&1
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
    local device="$target_ip:5555"
    local tries=0
    while [ $tries -lt 3 ]; do
        adb connect "$device" >/dev/null 2>&1
        sleep 1
        if adb_device_connected "$device"; then
            CONNECTED_DEVICES=("$device")
            return 0
        fi
        ((tries++))
    done
    print_error "ADB connection failed."
    return 1
}

snapshot_display_settings() {
    if [ "$PREV_SETTINGS_SAVED" -eq 1 ]; then
        return
    fi
    PREV_RESOLUTION=$(adb -s "${CONNECTED_DEVICES[0]}" shell wm size 2>/dev/null | grep -oP '\d+x\d+' | head -1 || true)
    PREV_DENSITY=$(adb -s "${CONNECTED_DEVICES[0]}" shell wm density 2>/dev/null | grep -oP '\d+' | head -1 || true)
    if [ -n "$PREV_RESOLUTION" ] || [ -n "$PREV_DENSITY" ]; then
        PREV_SETTINGS_SAVED=1
    fi
}

restore_previous_display_settings() {
    if [ ${#CONNECTED_DEVICES[@]} -eq 0 ]; then
        wait_and_connect_adb $(get_waydroid_ip) || return
    fi
    if [ "$PREV_SETTINGS_SAVED" -ne 1 ]; then
        print_error "No previous display settings saved in this session."
        sleep 2
        return
    fi
    print_status "Restoring previous display settings..."
    if [ -n "$PREV_RESOLUTION" ]; then
        adb -s "${CONNECTED_DEVICES[0]}" shell wm size "$PREV_RESOLUTION" 2>/dev/null
    fi
    if [ -n "$PREV_DENSITY" ]; then
        adb -s "${CONNECTED_DEVICES[0]}" shell wm density "$PREV_DENSITY" 2>/dev/null
    fi
    print_success "Previous settings restored."
    sleep 2
}

show_status() {
    print_header
    echo -e "${BOLD}${CYAN}━━━ STATUS ━━━${NC}\n"
    echo -e "${CYAN}Waydroid status:${NC} $(waydroid status 2>/dev/null | grep -o 'RUNNING\|STOPPED' || echo UNKNOWN)"
    echo -e "${CYAN}Waydroid IP:${NC} $(get_waydroid_ip)"
    echo -e "${CYAN}ADB devices:${NC} $(adb devices | awk 'NR>1 && $1!="" {print $1}' | wc -l)"
    echo -e "${CYAN}Weston PID:${NC} ${WESTON_PID:-N/A}"
    echo -e "${CYAN}Theme:${NC} ${THEME:-light}"
    if [ ${#CONNECTED_DEVICES[@]} -gt 0 ]; then
        local res
        local den
        res=$(adb -s "${CONNECTED_DEVICES[0]}" shell wm size 2>/dev/null | grep -oP '\d+x\d+' || echo "N/A")
        den=$(adb -s "${CONNECTED_DEVICES[0]}" shell wm density 2>/dev/null | grep -oP '\d+' | head -1 || echo "N/A")
        echo -e "${CYAN}Display:${NC} ${res} @ ${den} dpi"
    fi
    echo ""
    read -n 1 -p "Press any key to return..."
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
    WESTON_PID=$!
    WESTON_STARTED=1

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
    WESTON_PID=""
    WESTON_STARTED=0
    print_success "System halted."
    sleep 1.5
}

install_apk() {
    print_header
    if [ ${#CONNECTED_DEVICES[@]} -eq 0 ]; then
        wait_and_connect_adb $(get_waydroid_ip) || return
    fi
    local APK=""
    local install_method=$(zenity --list --radiolist --title="APK Install Method" --text="Choose how to install the APK" --column="Select" --column="Method" TRUE "Select Local APK" FALSE "Install from URL" FALSE "Batch Install from Directory" --height=200 --width=400 2>/dev/null)
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
    elif [ "$install_method" = "Batch Install from Directory" ]; then
        local APK_DIR=$(zenity --file-selection --title="Select Directory with APKs" --directory 2>/dev/null)
        if [ -d "$APK_DIR" ]; then
            install_apks_dir_cli "$APK_DIR"
        else
            print_error "No directory selected or directory invalid."
        fi
    fi
    read -n 1 -p "Press any key..."
}

install_apk_cli() {
    local src="$1"
    if [ -z "$src" ]; then
        print_error "Missing APK path or URL."
        exit 1
    fi
    if [ ${#CONNECTED_DEVICES[@]} -eq 0 ]; then
        wait_and_connect_adb $(get_waydroid_ip) || exit 1
    fi
    if [[ "$src" =~ ^https?://.*\.apk$ ]]; then
        local TMP_APK="/tmp/waydroid_apk_$$.apk"
        print_status "Downloading APK..."
        if command -v curl >/dev/null 2>&1; then
            curl -L -o "$TMP_APK" "$src"
        elif command -v wget >/dev/null 2>&1; then
            wget -O "$TMP_APK" "$src"
        else
            print_error "curl or wget required to download APK."
            exit 1
        fi
        if [ -f "$TMP_APK" ]; then
            adb -s "${CONNECTED_DEVICES[0]}" install -r "$TMP_APK"
            rm -f "$TMP_APK"
        else
            print_error "Failed to download APK."
            exit 1
        fi
    else
        if [ ! -f "$src" ]; then
            print_error "APK file not found: $src"
            exit 1
        fi
        adb -s "${CONNECTED_DEVICES[0]}" install -r "$src"
    fi
}

self_update() {
    print_header
    if [ ! -d "$SCRIPT_SELF_DIR/.git" ]; then
        print_error "Self-update requires a git clone of this script."
        read -n 1 -p "Press any key to return..."
        return
    fi
    print_status "Updating script from git..."
    if git -C "$SCRIPT_SELF_DIR" pull --ff-only; then
        print_success "Update complete."
    else
        print_error "Update failed."
    fi
    read -n 1 -p "Press any key to return..."
}

# Batch install all APKs in a directory (CLI-friendly)
install_apks_dir_cli() {
    local dir="$1"
    if [ -z "$dir" ] || [ ! -d "$dir" ]; then
        print_error "Directory not found: $dir"
        return 1
    fi

    if [ ${#CONNECTED_DEVICES[@]} -eq 0 ]; then
        wait_and_connect_adb $(get_waydroid_ip) || return 1
    fi

    local found=0
    for apk in "$dir"/*.apk; do
        [ -e "$apk" ] || continue
        found=1
        print_status "Installing $(basename "$apk")..."
        adb -s "${CONNECTED_DEVICES[0]}" install -r "$apk" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            print_success "Installed: $(basename "$apk")"
        else
            print_error "Failed: $(basename "$apk")"
        fi
        sleep 1
    done
    if [ $found -eq 0 ]; then
        print_error "No .apk files found in $dir"
        return 1
    fi
    return 0
}

# Apply terminal theme (colors)
# NOTE: Per user request the label meanings are swapped:
# Selecting THEME="dark" applies the light palette, and THEME="light" applies the darker/bold palette.
apply_theme() {
    if [ "${THEME:-light}" = "dark" ]; then
        # Light palette (mapped to the 'dark' label)
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        BLUE='\033[0;34m'
        CYAN='\033[0;36m'
        YELLOW='\033[1;33m'
        BOLD='\033[1m'
        NC='\033[0m'
    else
        # Darker/bold palette (mapped to the 'light' label)
        RED='\033[1;31m'
        GREEN='\033[1;32m'
        BLUE='\033[1;34m'
        CYAN='\033[1;36m'
        YELLOW='\033[1;33m'
        BOLD='\033[1m'
        NC='\033[0m'
    fi
}

# Set theme and persist to config (CLI)
# Usage: set_theme_cli <light|dark> [no-pause]
# If second arg is 'no-pause' the function will not block (useful for CLI flags)
set_theme_cli() {
    local t="$1"
    local no_pause="$2"
    if [ -z "$t" ]; then
        print_error "Missing theme. Use 'light' or 'dark'."
        exit 1
    fi
    if [[ ! "$t" =~ ^(light|dark)$ ]]; then
        print_error "Invalid theme: $t. Use 'light' or 'dark'."
        exit 1
    fi
    THEME="$t"
    apply_theme

    mkdir -p "$(dirname "$CONFIG_FILE")"
    if [ -f "$CONFIG_FILE" ]; then
        if grep -q '^THEME=' "$CONFIG_FILE"; then
            sed -i "s/^THEME=.*/THEME=\"$THEME\"/" "$CONFIG_FILE"
        else
            echo "THEME=\"$THEME\"" >> "$CONFIG_FILE"
        fi
    else
        echo "THEME=\"$THEME\"" > "$CONFIG_FILE"
    fi

    # Show confirmation: prefer zenity if available, but do not block CLI calls
    if command -v zenity >/dev/null 2>&1; then
        if [ "${no_pause}" = "no-pause" ]; then
            zenity --info --title="Theme Changed" --text="Theme set to $THEME and saved to $CONFIG_FILE" --width=300 2>/dev/null &
        else
            zenity --info --title="Theme Changed" --text="Theme set to $THEME and saved to $CONFIG_FILE" --width=300 2>/dev/null
        fi
    fi

    print_success "Theme set to $THEME and saved to $CONFIG_FILE"

    # Pause only when called interactively (no_pause not provided)
    if [ "${no_pause}" != "no-pause" ] && [ -t 0 ]; then
        read -n 1 -p "Press any key to continue..."
    fi
}

# Interactive theme chooser
set_theme_interactive() {
    local choice
    if command -v zenity >/dev/null 2>&1; then
        choice=$(zenity --list --radiolist --title="Select Theme" --text="Choose a terminal theme" --column="Select" --column="Theme" TRUE "light" FALSE "dark" --height=200 --width=300 2>/dev/null)
        if [ -n "$choice" ]; then
            set_theme_cli "$choice"
            read -n 1 -p "Press any key to continue..."
        fi
    else
        echo "Current theme: ${THEME:-light}"
        read -p "Enter theme (light/dark): " choice
        set_theme_cli "$choice"
        read -n 1 -p "Press any key to continue..."
    fi
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
        echo -e "${CYAN}│${NC}  ${BOLD}4)${NC}  🔎 Search + Uninstall (Partial Match)"
        echo -e "${CYAN}│${NC}  ${BOLD}5)${NC}  💾 Export Installed Apps"
        echo -e "${CYAN}└${NC}${CYAN}──────────────────────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "${BOLD}${MAGENTA}6)${NC}  ${MAGENTA}↩ Back to Main Menu${NC}"
        echo -e "${CYAN}==================================================${NC}"
        echo ""
        
        read -p "Selection: " APP_CHOICE
        case "$APP_CHOICE" in
            1) list_installed_apps ;;
            2) uninstall_by_package ;;
            3) uninstall_from_list ;;
            4) uninstall_by_search ;;
            5) export_installed_apps "" ;;
            6) break ;;
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

uninstall_by_search() {
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

    if [ ${#CONNECTED_DEVICES[@]} -eq 0 ]; then
        print_error "Not connected to ADB. Attempting to reconnect..."
        wait_and_connect_adb $(get_waydroid_ip) || {
            print_error "Failed to connect"
            sleep 2
            return
        }
    fi

    print_header
    read -p "🔎 Enter part of package name to search: " query
    if [ -z "$query" ]; then
        print_error "Search query cannot be empty"
        sleep 2
        return
    fi

    local matches
    matches=$(adb -s "${CONNECTED_DEVICES[0]}" shell pm list packages 2>/dev/null | sed 's/package://' | grep -i "$query" | sort)
    if [ -z "$matches" ]; then
        print_error "No packages matched '$query'"
        sleep 2
        return
    fi

    local selected_app
    selected_app=$(echo -e "$matches" | zenity --list --title="Select App to Uninstall" --column="Package Name" --height=500 --width=600 2>/dev/null)
    if [ -z "$selected_app" ]; then
        print_status "Cancelled"
        sleep 1
        return
    fi

    zenity --question --title="Confirm Uninstall" --text="Uninstall $selected_app?" --width=400 2>/dev/null
    if [ $? -eq 0 ]; then
        print_status "Uninstalling ${BOLD}${selected_app}${NC}..."
        local result
        result=$(adb -s "${CONNECTED_DEVICES[0]}" shell pm uninstall "$selected_app" 2>&1)
        if echo "$result" | grep -q "Success"; then
            print_success "✓ Successfully uninstalled ${BOLD}${selected_app}${NC}"
        else
            print_error "✗ Failed to uninstall ${BOLD}${selected_app}${NC}"
            echo -e "${YELLOW}Response: $result${NC}"
        fi
        sleep 2
    else
        print_status "Uninstall cancelled"
        sleep 1
    fi
}

export_installed_apps() {
    local out_file="$1"
    if [ -z "$out_file" ]; then
        out_file="$HOME/waydroid_apps_$(date +%Y%m%d).txt"
    fi
    if [ ${#CONNECTED_DEVICES[@]} -eq 0 ]; then
        wait_and_connect_adb $(get_waydroid_ip) || return
    fi
    print_status "Exporting app list to $out_file"
    adb -s "${CONNECTED_DEVICES[0]}" shell pm list packages 2>/dev/null | sed 's/package://' | sort > "$out_file"
    print_success "Export complete."
    if [ -t 0 ]; then
        read -n 1 -p "Press any key to continue..."
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
        echo -e "${BOLD}${MAGENTA}9)${NC}  ${MAGENTA}↩ Restore Previous Settings${NC}"
        echo -e "${CYAN}==================================================${NC}"
        echo ""
        read -p "Selection: " DISPLAY_CHOICE
        case "$DISPLAY_CHOICE" in
            1) preset_resolutions ;;
            2) preset_densities ;;
            3) view_current_settings ;;
            4)
                echo -e "${YELLOW}Resetting display size and density to default...${NC}"
                if [ ${#CONNECTED_DEVICES[@]} -eq 0 ]; then
                    wait_and_connect_adb $(get_waydroid_ip) || continue
                fi
                snapshot_display_settings
                sudo waydroid shell wm size reset
                sudo waydroid shell wm density reset
                echo -e "${GREEN}Display settings reset to default.${NC}"
                sleep 2
                ;;
            5) custom_resolution ;;
            6) custom_density ;;
            7) custom_both ;;
            8) break ;;
            9) restore_previous_display_settings ;;
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
    echo -e "${BOLD}${MAGENTA}6)${NC}  ${MAGENTA}↩ 1200 x 1920 (Tablet)${NC}"
    echo -e "${BOLD}${MAGENTA}7)${NC}  ${MAGENTA}↩ 3440 x 1440 (Ultra-wide)${NC}"
    echo -e "${BOLD}${MAGENTA}8)${NC}  ${MAGENTA}↩ Back${NC}"
    echo -e "${CYAN}==================================================${NC}"
    
    read -p "Selection: " RES_CHOICE
    local width height
    case "$RES_CHOICE" in
        1) width=1080; height=2340 ;;
        2) width=1440; height=3120 ;;
        3) width=720; height=1520 ;;
        4) width=1080; height=1920 ;;
        5) width=1440; height=2560 ;;
        6) width=1200; height=1920 ;;
        7) width=3440; height=1440 ;;
        8) return ;;
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
    
    snapshot_display_settings
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
    
    snapshot_display_settings
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

load_config
# Ensure theme colors are applied from config
apply_theme
ensure_log_dir
rotate_logs
parse_args "$@"
check_dependencies || exit 1

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
    echo -e "  ${BOLD}10)${NC} ${CYAN}STATUS${NC}"
    echo -e "  ${BOLD}11)${NC} ${MAGENTA}THEME${NC} (Light/Dark)"
    echo -e "  ${BOLD}12)${NC} ${MAGENTA}SELF UPDATE${NC}"
    echo -e "  ${BOLD}13)${NC} ${YELLOW}EXIT${NC}"
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
        10) show_status ;;
        11) set_theme_interactive ;;
        12) self_update ;;
        13) clear; exit 0 ;;
        *) echo -e "${RED}Invalid selection.${NC}"; sleep 1 ;;
    esac
done
