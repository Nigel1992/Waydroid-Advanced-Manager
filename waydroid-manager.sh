# --- ADB Shell Access ---
adb_shell_access() {
    print_header
    local dev="${CONNECTED_DEVICES[0]}"
    if [ -z "$dev" ]; then
        print_error "No ADB device connected."
        return
    fi
    local state
    state=$(adb devices | awk -v d="$dev" '$1==d {print $2}')
    echo -e "Device: $dev\nState: $state"
    if [ "$state" != "device" ]; then
        echo -e "\nDevice is not ready (state: $state). Attempting to reconnect..."
        adb disconnect "$dev" >/dev/null 2>&1
        adb connect "$dev" || true
        sleep 2
        state=$(adb devices | awk -v d="$dev" '$1==d {print $2}')
        echo -e "New state: $state"
        if [ "$state" != "device" ]; then
            print_error "Device is still not ready. Please check Waydroid and try again."
            return
        fi
    fi
    echo -e "\n${BOLD}${BLUE}Opening interactive ADB shell for device: ${dev}${NC}"
    echo -e "Type 'exit' to return to the menu.\n"
    adb -s "$dev" shell
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
  --install-apk <path|url>     Install APK from file or URL (supports Content-Length verification & sha256 logging)
  --install-apks-dir <dir>     Install all APKs from a directory (batch summary & logs)
  --uninstall-list <file>     Uninstall packages from a newline-delimited file
  --yes, -y                    Auto-confirm destructive actions (useful for scripting)
  --set-dpi <dpi>              Set display density
  --set-res <WxH>              Set display resolution
  --list-apps-export [file]    Export installed apps list
  --theme <dark|light>         Set and persist terminal theme (light or dark)
  --self-update                Update script from git
EOF
}
#!/bin/bash
# Clear terminal on startup
clear
# --- Device Info Panel ---

# ---------------- COLORS & UI ----------------
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

# Embedded version (single source of truth inside script)
SCRIPT_VERSION="0.8.0"
RELEASE_DATE="2026-03-04"

# --- Update Check on Launch ---
get_latest_version_from_github() {
    local raw_url="https://raw.githubusercontent.com/Nigel1992/Waydroid-Advanced-Manager/main/waydroid-manager.sh"
    local latest_version
    latest_version=$(curl -s "$raw_url" | grep -E '^SCRIPT_VERSION=' | head -1 | cut -d'=' -f2 | tr -d '"')
    echo "$latest_version"
}

check_for_updates() {
    local latest_version
    local github_url="https://github.com/Nigel1992/Waydroid-Advanced-Manager"
    latest_version=$(get_latest_version_from_github)
    if [ -n "$latest_version" ]; then
        if [ "$SCRIPT_VERSION" != "$latest_version" ]; then
            echo -e "${YELLOW}Update available!${NC} Current: ${SCRIPT_VERSION}, Latest: ${latest_version}"
            echo -e "Download the latest script from GitHub:"
            echo -e "${CYAN}${github_url}${NC}"
            echo ""
            read -p "Open GitHub page in your browser? (y/N): " open_browser
            if [[ "$open_browser" =~ ^[Yy]$ ]]; then
                if command -v xdg-open >/dev/null 2>&1; then
                    xdg-open "$github_url" 2>/dev/null &
                elif command -v open >/dev/null 2>&1; then
                    open "$github_url" 2>/dev/null &
                else
                    echo -e "${RED}Could not detect a browser. Please open the URL manually.${NC}"
                fi
            fi
        else
            echo -e "${GREEN}Waydroid Manager is up to date.${NC} (v${SCRIPT_VERSION})"
        fi
    else
        echo -e "${RED}Could not check for updates.${NC}"
    fi
    echo -e "\nPress Enter to continue..."
    read -r _
}

check_for_updates

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
YES_FLAG=0  # set by --yes or -y to auto-confirm destructive actions
LARGE_TEXT=0  # accessibility: large text mode
HIGH_CONTRAST=0  # accessibility: high-contrast mode
INSTALL_LOG="$LOG_DIR/install.log"
UNINSTALL_LOG="$LOG_DIR/uninstall.log"

# UI Helpers
# Determine script path for version/date detection
SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_SELF_DIR="$(dirname "$SCRIPT_PATH")"

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
    local max=1048576
    for f in "$LOG_FILE" "$INSTALL_LOG" "$UNINSTALL_LOG"; do
        if [ -f "$f" ]; then
            local size
            size=$(stat -c %s "$f" 2>/dev/null || echo 0)
            if [ "$size" -gt "$max" ]; then
                mv -f "$f" "${f}.1" 2>/dev/null || true
            fi
        fi
    done
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
    # Theme display with emoji (standard mapping)
    local theme_label="${THEME:-light}"
    local theme_emoji=""
    local theme_text=""
    if [ "$theme_label" = "dark" ]; then
        theme_emoji="🌙"
        theme_text="dark palette"
    else
        theme_emoji="🔆"
        theme_text="light palette"
    fi
    echo -e "${CYAN}${BOLD}=================================================="
    echo -e "           WAYDROID ADVANCED MANAGER  ${YELLOW}v${version} ${NC}${CYAN}(${release_date})"
    echo -e "               ${BOLD}${theme_emoji}${NC} Theme: ${theme_label} (${theme_text})"
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
  --install-apk <path|url>     Install APK from file or URL (supports Content-Length verification & sha256 logging)
  --install-apks-dir <dir>     Install all APKs from a directory (batch summary & logs)
  --uninstall-list <file>     Uninstall packages from a newline-delimited file
  --yes, -y                    Auto-confirm destructive actions (useful for scripting)
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
            --yes|-y)
                YES_FLAG=1
                ;;
            --uninstall-list)
                shift
                ensure_deps
                uninstall_list_cli "$1"
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

# Confirm helper: respects global YES_FLAG; uses zenity if available for GUI prompt
confirm() {
    local msg="$1"
    if [ "$YES_FLAG" -eq 1 ]; then
        return 0
    fi
    if command -v zenity >/dev/null 2>&1; then
        zenity --question --title="Confirm" --text="$msg" --width=400 --modal 2>/dev/null
        return $?  # 0 if Yes
    else
        read -p "$msg [y/N]: " ans
        case "$ans" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            *) return 1 ;;
        esac
    fi
}

log_install() {
    local msg="$1"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$ts] $msg" >> "${INSTALL_LOG:-$LOG_DIR/install.log}"
    log_line "INFO" "$msg"
}

log_uninstall() {
    local msg="$1"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$ts] $msg" >> "${UNINSTALL_LOG:-$LOG_DIR/uninstall.log}"
    log_line "INFO" "$msg"
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

# Focus the Weston compositor window, then bring zenity dialog to front
focus_waydroid_window() {
    if command -v xdotool >/dev/null 2>&1; then
        local wid
        # Match Weston by window class (not name, to avoid matching browser/editor windows)
        wid=$(xdotool search --class "weston" 2>/dev/null | head -1)
        if [ -z "$wid" ]; then
            # Fallback: match by class "Weston" (capitalised)
            wid=$(xdotool search --class "Weston" 2>/dev/null | head -1)
        fi
        if [ -n "$wid" ]; then
            xdotool windowactivate --sync "$wid" 2>/dev/null
            sleep 0.3
            return 0
        fi
    fi
    return 1
}

install_apk() {
    print_header
    if [ ${#CONNECTED_DEVICES[@]} -eq 0 ]; then
        wait_and_connect_adb $(get_waydroid_ip) || return
    fi

    # Focus Weston compositor window first, then show zenity on top
    focus_waydroid_window

    local APK=""
    local install_method
    install_method=$(zenity --list --radiolist --title="APK Install Method" --text="Choose how to install the APK" --column="Select" --column="Method" TRUE "Select Local APK" FALSE "Install from URL" FALSE "Batch Install from Directory" --height=200 --width=400 --modal 2>/dev/null)
    if [ "$install_method" = "Select Local APK" ]; then
        APK=$(zenity --file-selection --title="Select APK" --file-filter="*.apk" --modal 2>/dev/null)
        if [ -f "$APK" ]; then
            print_status "Installing $(basename "$APK")..."
            adb -s "${CONNECTED_DEVICES[0]}" install -r "$APK"
            print_success "Done."
        fi
    elif [ "$install_method" = "Install from URL" ]; then
        local APK_URL=$(zenity --entry --title="APK URL" --text="Enter direct APK URL (https://.../app.apk)" --width=500 --modal 2>/dev/null)
        if [[ "$APK_URL" =~ ^https?://.*\.apk$ ]]; then
            local TMP_APK="/tmp/waydroid_apk_$$.apk"
            print_status "Downloading APK..."
            if ! download_verify_apk "$APK_URL" "$TMP_APK"; then
                print_error "Failed to download or verify APK."
                read -n 1 -p "Press any key..."
                return
            fi
            print_status "Installing $(basename "$TMP_APK")..."
            adb -s "${CONNECTED_DEVICES[0]}" install -r "$TMP_APK"
            local rc=$?
            if [ $rc -eq 0 ]; then
                log_install "SUCCESS $(basename "$TMP_APK")"
                print_success "Done."
            else
                log_install "FAIL $(basename "$TMP_APK") rc=$rc"
                print_error "Install failed."
            fi
            rm -f "$TMP_APK"
        else
            print_error "Invalid URL. Must end with .apk"
        fi
    elif [ "$install_method" = "Batch Install from Directory" ]; then
        local APK_DIR=$(zenity --file-selection --title="Select Directory with APKs" --directory --modal 2>/dev/null)
        if [ -d "$APK_DIR" ]; then
            install_apks_dir_cli "$APK_DIR"
        else
            print_error "No directory selected or directory invalid."
        fi
    fi
    read -n 1 -p "Press any key..."
}

# Download URL into target file and verify content-length when available
download_verify_apk() {
    local url="$1"
    local target="$2"
    # Try to fetch content-length
    local cl
    if command -v curl >/dev/null 2>&1; then
        cl=$(curl -sI "$url" | awk '/[Cc]ontent-[Ll]ength/ {print $2}' | tr -d '\r')
        curl -fL -o "$target" "$url"
    elif command -v wget >/dev/null 2>&1; then
        cl=$(wget --spider --server-response "$url" 2>&1 | awk '/Content-Length/ {print $2}' | tr -d '\r')
        wget -O "$target" "$url"
    else
        print_error "curl or wget required to download APK."
        return 2
    fi

    if [ ! -f "$target" ]; then
        print_error "Failed to download APK."
        return 2
    fi

    # Verify size if Content-Length present
    if [ -n "$cl" ]; then
        local actual
        actual=$(stat -c %s "$target" 2>/dev/null || echo 0)
        if [ "$actual" -ne "$cl" ]; then
            print_error "Downloaded file size ($actual) does not match Content-Length ($cl). Aborting."
            return 3
        fi
    fi

    # Generate sha256 for user's verification
    if command -v sha256sum >/dev/null 2>&1; then
        local shasum
        shasum=$(sha256sum "$target" | awk '{print $1}')
        log_line "INFO" "Downloaded $target sha256=$shasum"
    fi
    return 0
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
        if ! download_verify_apk "$src" "$TMP_APK"; then
            print_error "Failed to download or verify APK."
            [ -f "$TMP_APK" ] && rm -f "$TMP_APK"
            exit 1
        fi
        adb -s "${CONNECTED_DEVICES[0]}" install -r "$TMP_APK"
        local rc=$?
        if [ $rc -eq 0 ]; then
            log_install "SUCCESS $(basename "$TMP_APK")"
        else
            log_install "FAIL $(basename "$TMP_APK") rc=$rc"
        fi
        rm -f "$TMP_APK"
        exit $rc
    else
        if [ ! -f "$src" ]; then
            print_error "APK file not found: $src"
            exit 1
        fi
        adb -s "${CONNECTED_DEVICES[0]}" install -r "$src"
        local rc=$?
        if [ $rc -eq 0 ]; then
            log_install "SUCCESS $(basename "$src")"
        else
            log_install "FAIL $(basename "$src") rc=$rc"
        fi
        exit $rc
    fi
}

self_update() {
    print_header
    check_for_updates
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
    local success_count=0
    local fail_count=0
    local failed_list=()

    for apk in "$dir"/*.apk; do
        [ -e "$apk" ] || continue
        found=1
        print_status "Installing $(basename "$apk")..."
        adb -s "${CONNECTED_DEVICES[0]}" install -r "$apk" >/tmp/waydroid_install_out_$$ 2>&1
        local rc=$?
        if [ $rc -eq 0 ]; then
            print_success "Installed: $(basename "$apk")"
            log_install "SUCCESS $(basename "$apk")"
            success_count=$((success_count+1))
        else
            print_error "Failed: $(basename "$apk") (rc=$rc)"
            log_install "FAIL $(basename "$apk") rc=$rc"
            failed_list+=("$(basename "$apk")")
            fail_count=$((fail_count+1))
        fi
        sleep 1
    done

    if [ $found -eq 0 ]; then
        print_error "No .apk files found in $dir"
        return 1
    fi

    print_status "Batch install summary: $success_count succeeded, $fail_count failed"
    if [ ${#failed_list[@]} -gt 0 ]; then
        echo "Failed packages:"; printf '%s
' "${failed_list[@]}"
    fi

    if [ $fail_count -gt 0 ]; then
        return 2
    fi
    return 0
}

# Apply terminal theme (colors)
# Selecting THEME="dark" applies a darker/bold palette, THEME="light" applies a light palette.
apply_theme() {
    case "${THEME:-light}" in
        dark)
            RED='\033[1;31m'; GREEN='\033[1;32m'; BLUE='\033[1;34m'
            CYAN='\033[1;36m'; YELLOW='\033[1;33m'; MAGENTA='\033[1;35m'
            BOLD='\033[1m'; NC='\033[0m'
            ;;
        ocean)
            RED='\033[0;31m'; GREEN='\033[0;36m'; BLUE='\033[1;34m'
            CYAN='\033[1;36m'; YELLOW='\033[0;33m'; MAGENTA='\033[0;34m'
            BOLD='\033[1m'; NC='\033[0m'
            ;;
        forest)
            RED='\033[0;33m'; GREEN='\033[1;32m'; BLUE='\033[0;32m'
            CYAN='\033[0;36m'; YELLOW='\033[0;33m'; MAGENTA='\033[0;35m'
            BOLD='\033[1m'; NC='\033[0m'
            ;;
        sunset)
            RED='\033[1;31m'; GREEN='\033[0;33m'; BLUE='\033[0;34m'
            CYAN='\033[0;31m'; YELLOW='\033[1;33m'; MAGENTA='\033[1;31m'
            BOLD='\033[1m'; NC='\033[0m'
            ;;
        neon)
            RED='\033[1;35m'; GREEN='\033[1;32m'; BLUE='\033[1;34m'
            CYAN='\033[1;36m'; YELLOW='\033[1;33m'; MAGENTA='\033[1;35m'
            BOLD='\033[1m'; NC='\033[0m'
            ;;
        *)
            RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'
            CYAN='\033[0;36m'; YELLOW='\033[1;33m'; MAGENTA='\033[0;35m'
            BOLD='\033[1m'; NC='\033[0m'
            ;;
    esac
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
            zenity --info --title="Theme Changed" --text="Theme set to $THEME and saved to $CONFIG_FILE" --width=300 --modal 2>/dev/null &
        else
            zenity --info --title="Theme Changed" --text="Theme set to $THEME and saved to $CONFIG_FILE" --width=300 --modal 2>/dev/null
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
        choice=$(zenity --list --radiolist --title="Select Theme" --text="Choose a terminal theme" --column="Select" --column="Theme" TRUE "light" FALSE "dark" --height=200 --width=300 --modal 2>/dev/null)
        if [ -n "$choice" ]; then
            # use no-pause so set_theme_cli does not block; we pause once here
            set_theme_cli "$choice" "no-pause"
            read -n 1 -p "Press any key to continue..."
        fi
    else
        echo "Current theme: ${THEME:-light}"
        read -p "Enter theme (light/dark): " choice
        set_theme_cli "$choice" "no-pause"
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
        echo -e "${CYAN}│${NC}  ${BOLD}6)${NC}  🗑 Batch Uninstall (File or Multi-Select)"
        echo -e "${CYAN}└${NC}${CYAN}──────────────────────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "${BOLD}${MAGENTA}7)${NC}  ${MAGENTA}↩ Back to Main Menu${NC}"
        echo -e "${CYAN}==================================================${NC}"
        echo ""
        
        read -p "Selection: " APP_CHOICE
        case "$APP_CHOICE" in
            1) list_installed_apps ;;
            2) uninstall_by_package ;;
            3) uninstall_from_list ;;
            4) uninstall_by_search ;;
            5) export_installed_apps "" ;;
            6)
                # Batch uninstall: let user select a file or multi-select packages via zenity
                if command -v zenity >/dev/null 2>&1; then
                    choice=$(zenity --list --radiolist --title="Batch Uninstall" --text="Choose method" --column="Select" --column="Method" TRUE "Select File (.txt with package per line)" FALSE "Multi-select from installed apps" --height=200 --width=500 --modal 2>/dev/null)
                    if [ "$choice" = "Select File (.txt with package per line)" ]; then
                        FILE=$(zenity --file-selection --title="Select package list file" --modal 2>/dev/null)
                        if [ -n "$FILE" ] && [ -f "$FILE" ]; then
                            uninstall_list_cli "$FILE"
                        else
                            print_error "No valid file selected"
                        fi
                    else
                        # multi-select installed apps
                        pkgs=$(adb -s "${CONNECTED_DEVICES[0]}" shell pm list packages 2>/dev/null | sed 's/package://' | sort)
                        selected=$(echo -e "$pkgs" | zenity --list --multiple --title="Select packages to uninstall" --column="Package" --height=600 --width=600 --modal 2>/dev/null)
                        if [ -n "$selected" ]; then
                            IFS="," read -r -a arr <<< "$selected"
                            tmpfile="/tmp/waydroid_uninstall_$$.txt"
                            for p in "${arr[@]}"; do echo "$p" >> "$tmpfile"; done
                            uninstall_list_cli "$tmpfile"
                            rm -f "$tmpfile"
                        else
                            print_status "Cancelled"
                        fi
                    fi
                else
                    print_status "Zenity not available. Use --uninstall-list <file> to uninstall from CLI."
                fi
                ;;
            7) break ;;
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
    
    local apps=$(adb -s "${CONNECTED_DEVICES[0]}" shell pm list packages 2>/dev/null | sed 's/package://' | sort)
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
    
    if ! confirm "Uninstall $package_name?"; then
        print_status "Cancelled"
        sleep 1
        return
    fi

    echo ""
    echo -e "${BOLD}${CYAN}━━━ UNINSTALLING ━━━${NC}\n"
    print_status "Attempting to uninstall: ${BOLD}${package_name}${NC}..."
    
    local result=$(adb -s "${CONNECTED_DEVICES[0]}" shell pm uninstall "$package_name" 2>&1)
    
    if echo "$result" | grep -q "Success"; then
        echo ""
        print_success "✓ Successfully uninstalled ${BOLD}${package_name}${NC}"
        log_uninstall "SUCCESS $package_name"
    else
        echo ""
        print_error "✗ Failed to uninstall ${BOLD}${package_name}${NC}"
        echo -e "${YELLOW}Response: $result${NC}"
        log_uninstall "FAIL $package_name: $result"
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

# Batch uninstall from file (CLI)
uninstall_list_cli() {
    local file="$1"
    if [ -z "$file" ] || [ ! -f "$file" ]; then
        print_error "List file not found: $file"
        exit 1
    fi
    if [ ${#CONNECTED_DEVICES[@]} -eq 0 ]; then
        wait_and_connect_adb $(get_waydroid_ip) || exit 1
    fi
    local total=0
    local success=0
    local fail=0
    while IFS= read -r pkg; do
        pkg=$(echo "$pkg" | tr -d '\r' | tr -d '\n')
        [ -z "$pkg" ] && continue
        total=$((total+1))
        if confirm "Uninstall $pkg?"; then
            print_status "Uninstalling $pkg..."
            local result
            result=$(adb -s "${CONNECTED_DEVICES[0]}" shell pm uninstall "$pkg" 2>&1)
            if echo "$result" | grep -q "Success"; then
                print_success "Uninstalled $pkg"
                log_uninstall "SUCCESS $pkg"
                success=$((success+1))
            else
                print_error "Failed to uninstall $pkg"
                print_status "Response: $result"
                log_uninstall "FAIL $pkg: $result"
                fail=$((fail+1))
            fi
        else
            print_status "Skipped $pkg"
        fi
    done < "$file"
    print_status "Batch uninstall summary: $success succeeded, $fail failed (total $total)"
    if [ $fail -gt 0 ]; then
        return 2
    fi
    return 0
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
    selected_app=$(echo -e "$matches" | zenity --list --title="Select App to Uninstall" --column="Package Name" --height=500 --width=600 --modal 2>/dev/null)
    if [ -z "$selected_app" ]; then
        print_status "Cancelled"
        sleep 1
        return
    fi

    if confirm "Uninstall $selected_app?"; then
        print_status "Uninstalling ${BOLD}${selected_app}${NC}..."
        local result
        result=$(adb -s "${CONNECTED_DEVICES[0]}" shell pm uninstall "$selected_app" 2>&1)
        if echo "$result" | grep -q "Success"; then
            print_success "✓ Successfully uninstalled ${BOLD}${selected_app}${NC}"
            log_uninstall "SUCCESS $selected_app"
        else
            print_error "✗ Failed to uninstall ${BOLD}${selected_app}${NC}"
            echo -e "${YELLOW}Response: $result${NC}"
            log_uninstall "FAIL $selected_app: $result"
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
        app_type=$(zenity --list --radiolist --title="App List Type" --text="Show all apps or only user-installed?" --column="Select" --column="Type" TRUE "User Installed" FALSE "All Apps" --height=200 --width=400 --modal 2>/dev/null)
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
        selected_app=$(echo -e "$app_list_str" | zenity --list --title="Select App to Uninstall" --column="Package Name" --height=500 --width=600 --modal 2>/dev/null)
        if [ -z "$selected_app" ]; then
            print_status "Cancelled"
            sleep 1
            return
        fi
        echo ""
        if confirm "Uninstall $selected_app?"; then
            echo ""
            print_status "Uninstalling ${BOLD}${selected_app}${NC}..."
            result=$(adb -s "${CONNECTED_DEVICES[0]}" shell pm uninstall "$selected_app" 2>&1)
            if echo "$result" | grep -q "Success"; then
                echo ""
                print_success "✓ Successfully uninstalled ${BOLD}${selected_app}${NC}"
                log_uninstall "SUCCESS $selected_app"
            else
                echo ""
                print_error "✗ Failed to uninstall ${BOLD}${selected_app}${NC}"
                echo -e "${YELLOW}Response: $result${NC}"
                log_uninstall "FAIL $selected_app: $result"
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
                if ! confirm "Reset display size and density to defaults?"; then
                    print_status "Cancelled"
                    sleep 1
                    continue
                fi
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
# Initialize specialised logs
mkdir -p "$LOG_DIR"
INSTALL_LOG="${INSTALL_LOG:-$LOG_DIR/install.log}"
UNINSTALL_LOG="${UNINSTALL_LOG:-$LOG_DIR/uninstall.log}"
: > "$INSTALL_LOG" 2>/dev/null || true
: > "$UNINSTALL_LOG" 2>/dev/null || true
rotate_logs
parse_args "$@"
check_dependencies || exit 1

# --- Auto-detect running Waydroid / ADB devices on launch ---
detect_existing_session() {
    local wd_running=0
    local wd_ip=""

    # Check if Waydroid is already running
    if waydroid status 2>/dev/null | grep -q "RUNNING"; then
        wd_running=1
        wd_ip=$(get_waydroid_ip)
    fi

    # Check for any ADB devices already connected
    local existing_devices
    existing_devices=$(adb devices 2>/dev/null | awk 'NR>1 && $1!="" {print $1}')

    if [ "$wd_running" -eq 1 ] || [ -n "$existing_devices" ]; then
        clear
        echo -e "${GREEN}${BOLD}━━━ EXISTING SESSION DETECTED ━━━${NC}"
        if [ "$wd_running" -eq 1 ]; then
            echo -e "${GREEN}  ✓ Waydroid is running${NC}"
            [ -n "$wd_ip" ] && echo -e "${CYAN}  IP: ${wd_ip}${NC}"
        fi
        if [ -n "$existing_devices" ]; then
            echo -e "${CYAN}  ADB device(s):${NC}"
            echo "$existing_devices" | while read -r dev; do
                echo -e "    ${BOLD}${dev}${NC}"
            done
        fi
        echo ""
        read -p "Connect to existing session? (Y/n): " connect_choice
        if [[ ! "$connect_choice" =~ ^[Nn]$ ]]; then
            if [ -n "$wd_ip" ] && [[ "$wd_ip" =~ ^[0-9] ]]; then
                local target="$wd_ip:5555"
                adb connect "$target" >/dev/null 2>&1
                sleep 1
                if adb_device_connected "$target"; then
                    CONNECTED_DEVICES=("$target")
                    echo -e "${GREEN}  ✓ Connected to ${target}${NC}"
                else
                    echo -e "${YELLOW}  ⚠ Could not connect via ADB to ${target}${NC}"
                fi
            elif [ -n "$existing_devices" ]; then
                # Use the first already-connected device
                local first_dev
                first_dev=$(echo "$existing_devices" | head -1)
                CONNECTED_DEVICES=("$first_dev")
                echo -e "${GREEN}  ✓ Using existing ADB device: ${first_dev}${NC}"
            fi
        else
            echo -e "${CYAN}  Skipped. You can connect later from the menu.${NC}"
        fi
        sleep 1
    fi
}

detect_existing_session

# ===================== NEW UTILITY FUNCTIONS =====================

# --- Screenshot Capture ---
take_screenshot() {
    print_header
    echo -e "${BOLD}${CYAN}━━━ SCREENSHOT CAPTURE ━━━${NC}\n"

    if [ ${#CONNECTED_DEVICES[@]} -eq 0 ]; then
        wait_and_connect_adb $(get_waydroid_ip) || return
    fi

    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local remote_path="/sdcard/screenshot_${timestamp}.png"
    local save_dir="$HOME/Pictures/Waydroid"
    mkdir -p "$save_dir"
    local local_path="$save_dir/screenshot_${timestamp}.png"

    print_status "Capturing screenshot..."
    adb -s "${CONNECTED_DEVICES[0]}" shell screencap -p "$remote_path" 2>/dev/null
    if [ $? -ne 0 ]; then
        print_error "Failed to capture screenshot."
        read -n 1 -p "Press any key..."
        return
    fi

    print_status "Pulling screenshot to $local_path..."
    adb -s "${CONNECTED_DEVICES[0]}" pull "$remote_path" "$local_path" 2>/dev/null
    adb -s "${CONNECTED_DEVICES[0]}" shell rm -f "$remote_path" 2>/dev/null

    if [ -f "$local_path" ]; then
        print_success "Screenshot saved: $local_path"
        echo ""
        read -p "Open screenshot? (y/N): " open_choice
        if [[ "$open_choice" =~ ^[Yy]$ ]]; then
            if command -v xdg-open >/dev/null 2>&1; then
                xdg-open "$local_path" 2>/dev/null &
            else
                print_status "Cannot auto-open. File is at: $local_path"
            fi
        fi
    else
        print_error "Failed to save screenshot."
    fi
    read -n 1 -p "Press any key..."
}

# --- Screen Recording ---
record_screen() {
    print_header
    echo -e "${BOLD}${CYAN}━━━ SCREEN RECORDING ━━━${NC}\n"

    if [ ${#CONNECTED_DEVICES[@]} -eq 0 ]; then
        wait_and_connect_adb $(get_waydroid_ip) || return
    fi

    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local remote_path="/sdcard/recording_${timestamp}.mp4"
    local save_dir="$HOME/Videos/Waydroid"
    mkdir -p "$save_dir"
    local local_path="$save_dir/recording_${timestamp}.mp4"

    local duration
    read -p "Recording duration in seconds (default 30, max 180): " duration
    duration=${duration:-30}
    if ! [[ "$duration" =~ ^[0-9]+$ ]] || [ "$duration" -gt 180 ]; then
        duration=30
    fi

    echo -e "\n${YELLOW}Recording for ${duration}s... Press Ctrl+C in another terminal to stop early.${NC}"
    print_status "Starting screen recording..."
    adb -s "${CONNECTED_DEVICES[0]}" shell screenrecord --time-limit "$duration" "$remote_path" 2>/dev/null
    sleep 1

    print_status "Pulling recording to $local_path..."
    adb -s "${CONNECTED_DEVICES[0]}" pull "$remote_path" "$local_path" 2>/dev/null
    adb -s "${CONNECTED_DEVICES[0]}" shell rm -f "$remote_path" 2>/dev/null

    if [ -f "$local_path" ]; then
        print_success "Recording saved: $local_path"
        echo ""
        read -p "Open recording? (y/N): " open_choice
        if [[ "$open_choice" =~ ^[Yy]$ ]]; then
            if command -v xdg-open >/dev/null 2>&1; then
                xdg-open "$local_path" 2>/dev/null &
            fi
        fi
    else
        print_error "Failed to save recording."
    fi
    read -n 1 -p "Press any key..."
}

# --- File Transfer (Push/Pull) ---
file_transfer_menu() {
    while true; do
        print_header
        echo -e "${BOLD}${GREEN}━━━ FILE TRANSFER ━━━${NC}"
        echo ""
        echo -e "  ${BOLD}1)${NC}  📤 Push file to Android"
        echo -e "  ${BOLD}2)${NC}  📥 Pull file from Android"
        echo -e "  ${BOLD}3)${NC}  📥 Pull folder from Android"
        echo -e "  ${BOLD}4)${NC}  ↩ Back"
        echo ""
        read -p "Selection: " FT_CHOICE

        if [ ${#CONNECTED_DEVICES[@]} -eq 0 ]; then
            wait_and_connect_adb $(get_waydroid_ip) || return
        fi

        case "$FT_CHOICE" in
            1)
                local src_file
                if command -v zenity >/dev/null 2>&1; then
                    src_file=$(zenity --file-selection --title="Select file to push" --modal 2>/dev/null)
                else
                    read -p "Local file path: " src_file
                fi
                if [ -z "$src_file" ] || [ ! -f "$src_file" ]; then
                    print_error "No valid file selected."
                    sleep 1
                    continue
                fi
                local dest
                read -p "Android destination (default /sdcard/): " dest
                dest=${dest:-/sdcard/}
                print_status "Pushing $(basename "$src_file") to $dest..."
                adb -s "${CONNECTED_DEVICES[0]}" push "$src_file" "$dest" 2>&1
                print_success "Done."
                read -n 1 -p "Press any key..."
                ;;
            2)
                local remote_file
                read -p "Android file path (e.g. /sdcard/myfile.txt): " remote_file
                if [ -z "$remote_file" ]; then
                    print_error "No path entered."
                    sleep 1
                    continue
                fi
                local local_dest
                if command -v zenity >/dev/null 2>&1; then
                    local_dest=$(zenity --file-selection --save --title="Save file as..." --modal 2>/dev/null)
                else
                    read -p "Local save path (default ~/Downloads/): " local_dest
                    local_dest=${local_dest:-$HOME/Downloads/}
                fi
                print_status "Pulling $remote_file..."
                adb -s "${CONNECTED_DEVICES[0]}" pull "$remote_file" "$local_dest" 2>&1
                print_success "Done."
                read -n 1 -p "Press any key..."
                ;;
            3)
                local remote_dir
                read -p "Android directory (e.g. /sdcard/DCIM/): " remote_dir
                if [ -z "$remote_dir" ]; then
                    print_error "No path entered."
                    sleep 1
                    continue
                fi
                local local_dir
                if command -v zenity >/dev/null 2>&1; then
                    local_dir=$(zenity --file-selection --directory --title="Select local destination" --modal 2>/dev/null)
                else
                    read -p "Local save directory (default ~/Downloads/): " local_dir
                    local_dir=${local_dir:-$HOME/Downloads/}
                fi
                print_status "Pulling $remote_dir..."
                adb -s "${CONNECTED_DEVICES[0]}" pull "$remote_dir" "$local_dir" 2>&1
                print_success "Done."
                read -n 1 -p "Press any key..."
                ;;
            4) break ;;
            *) echo -e "${RED}Invalid selection.${NC}"; sleep 1 ;;
        esac
    done
}

# --- Logcat Viewer ---
logcat_viewer() {
    print_header
    echo -e "${BOLD}${CYAN}━━━ LOGCAT VIEWER ━━━${NC}\n"

    if [ ${#CONNECTED_DEVICES[@]} -eq 0 ]; then
        wait_and_connect_adb $(get_waydroid_ip) || return
    fi

    echo -e "  ${BOLD}1)${NC}  Show live logcat (Ctrl+C to stop)"
    echo -e "  ${BOLD}2)${NC}  Save last 500 lines to file"
    echo -e "  ${BOLD}3)${NC}  Filter by tag (live)"
    echo -e "  ${BOLD}4)${NC}  Show errors only"
    echo -e "  ${BOLD}5)${NC}  ↩ Back"
    echo ""
    read -p "Selection: " LOG_CHOICE

    local save_dir="$HOME/.cache/waydroid-manager"
    mkdir -p "$save_dir"

    case "$LOG_CHOICE" in
        1)
            echo -e "${YELLOW}Live logcat output (Ctrl+C to stop):${NC}\n"
            adb -s "${CONNECTED_DEVICES[0]}" logcat 2>/dev/null
            ;;
        2)
            local logfile="$save_dir/logcat_$(date +%Y%m%d_%H%M%S).txt"
            print_status "Saving last 500 lines to $logfile..."
            adb -s "${CONNECTED_DEVICES[0]}" logcat -d -t 500 2>/dev/null > "$logfile"
            if [ -s "$logfile" ]; then
                print_success "Saved: $logfile"
            else
                print_error "No logcat output captured."
            fi
            read -n 1 -p "Press any key..."
            ;;
        3)
            read -p "Enter tag to filter (e.g. ActivityManager): " tag
            if [ -n "$tag" ]; then
                echo -e "${YELLOW}Filtered logcat for '$tag' (Ctrl+C to stop):${NC}\n"
                adb -s "${CONNECTED_DEVICES[0]}" logcat -s "$tag" 2>/dev/null
            fi
            ;;
        4)
            echo -e "${YELLOW}Errors only (Ctrl+C to stop):${NC}\n"
            adb -s "${CONNECTED_DEVICES[0]}" logcat "*:E" 2>/dev/null
            ;;
        5) return ;;
        *) echo -e "${RED}Invalid selection.${NC}"; sleep 1 ;;
    esac
}

# --- Freeze / Disable Apps ---
freeze_apps_menu() {
    while true; do
        print_header
        echo -e "${BOLD}${GREEN}━━━ FREEZE / DISABLE APPS ━━━${NC}\n"

        if [ ${#CONNECTED_DEVICES[@]} -eq 0 ]; then
            wait_and_connect_adb $(get_waydroid_ip) || return
        fi

        echo -e "  ${BOLD}1)${NC}  ❄️  Disable (freeze) an app"
        echo -e "  ${BOLD}2)${NC}  🔥 Enable (unfreeze) an app"
        echo -e "  ${BOLD}3)${NC}  📋 List disabled apps"
        echo -e "  ${BOLD}4)${NC}  ↩ Back"
        echo ""
        read -p "Selection: " FREEZE_CHOICE

        case "$FREEZE_CHOICE" in
            1)
                local pkg
                if command -v zenity >/dev/null 2>&1; then
                    local pkgs
                    pkgs=$(adb -s "${CONNECTED_DEVICES[0]}" shell pm list packages -e 2>/dev/null | sed 's/package://' | sort)
                    pkg=$(echo "$pkgs" | zenity --list --title="Select App to Disable" --column="Package" --height=500 --width=600 --modal 2>/dev/null)
                else
                    read -p "Package name to disable: " pkg
                fi
                if [ -n "$pkg" ]; then
                    if confirm "Disable $pkg? (It can be re-enabled later)"; then
                        adb -s "${CONNECTED_DEVICES[0]}" shell pm disable-user --user 0 "$pkg" 2>&1
                        print_success "Disabled: $pkg"
                        log_line "INFO" "FREEZE $pkg"
                    else
                        print_status "Cancelled."
                    fi
                fi
                sleep 1
                ;;
            2)
                local pkg
                if command -v zenity >/dev/null 2>&1; then
                    local disabled
                    disabled=$(adb -s "${CONNECTED_DEVICES[0]}" shell pm list packages -d 2>/dev/null | sed 's/package://' | sort)
                    if [ -z "$disabled" ]; then
                        print_status "No disabled apps found."
                        sleep 1
                        continue
                    fi
                    pkg=$(echo "$disabled" | zenity --list --title="Select App to Enable" --column="Package" --height=500 --width=600 --modal 2>/dev/null)
                else
                    read -p "Package name to enable: " pkg
                fi
                if [ -n "$pkg" ]; then
                    adb -s "${CONNECTED_DEVICES[0]}" shell pm enable "$pkg" 2>&1
                    print_success "Enabled: $pkg"
                    log_line "INFO" "UNFREEZE $pkg"
                fi
                sleep 1
                ;;
            3)
                print_header
                echo -e "${BOLD}${CYAN}━━━ DISABLED APPS ━━━${NC}\n"
                local disabled
                disabled=$(adb -s "${CONNECTED_DEVICES[0]}" shell pm list packages -d 2>/dev/null | sed 's/package://' | sort)
                if [ -z "$disabled" ]; then
                    print_status "No disabled apps."
                else
                    echo "$disabled"
                    echo ""
                    echo -e "${CYAN}Total: $(echo "$disabled" | wc -l) disabled packages${NC}"
                fi
                echo ""
                read -n 1 -p "Press any key..."
                ;;
            4) break ;;
            *) echo -e "${RED}Invalid selection.${NC}"; sleep 1 ;;
        esac
    done
}

# --- Clear App Data / Cache ---
clear_app_data() {
    print_header
    echo -e "${BOLD}${YELLOW}━━━ CLEAR APP DATA / CACHE ━━━${NC}\n"

    if [ ${#CONNECTED_DEVICES[@]} -eq 0 ]; then
        wait_and_connect_adb $(get_waydroid_ip) || return
    fi

    echo -e "  ${BOLD}1)${NC}  🗑 Clear ALL data for an app"
    echo -e "  ${BOLD}2)${NC}  🧹 Clear cache only for an app"
    echo -e "  ${BOLD}3)${NC}  ↩ Back"
    echo ""
    read -p "Selection: " CLEAR_CHOICE

    local pkg=""
    if [ "$CLEAR_CHOICE" = "1" ] || [ "$CLEAR_CHOICE" = "2" ]; then
        if command -v zenity >/dev/null 2>&1; then
            local pkgs
            pkgs=$(adb -s "${CONNECTED_DEVICES[0]}" shell pm list packages 2>/dev/null | sed 's/package://' | sort)
            pkg=$(echo "$pkgs" | zenity --list --title="Select App" --column="Package" --height=500 --width=600 --modal 2>/dev/null)
        else
            read -p "Package name: " pkg
        fi
    fi

    case "$CLEAR_CHOICE" in
        1)
            if [ -n "$pkg" ]; then
                if confirm "Clear ALL data for $pkg? This cannot be undone."; then
                    adb -s "${CONNECTED_DEVICES[0]}" shell pm clear "$pkg" 2>&1
                    print_success "All data cleared for $pkg."
                    log_line "INFO" "CLEAR_DATA $pkg"
                else
                    print_status "Cancelled."
                fi
            fi
            ;;
        2)
            if [ -n "$pkg" ]; then
                print_status "Clearing cache for $pkg..."
                adb -s "${CONNECTED_DEVICES[0]}" shell pm clear --cache-only "$pkg" 2>/dev/null
                # Fallback: some Android versions need rm approach
                adb -s "${CONNECTED_DEVICES[0]}" shell run-as "$pkg" rm -rf /data/data/"$pkg"/cache/* 2>/dev/null
                print_success "Cache cleared for $pkg."
                log_line "INFO" "CLEAR_CACHE $pkg"
            fi
            ;;
        3) return ;;
        *) echo -e "${RED}Invalid selection.${NC}"; sleep 1; return ;;
    esac
    read -n 1 -p "Press any key..."
}

# --- Quick Launch App ---
quick_launch_app() {
    print_header
    echo -e "${BOLD}${CYAN}━━━ QUICK LAUNCH APP ━━━${NC}\n"

    if [ ${#CONNECTED_DEVICES[@]} -eq 0 ]; then
        wait_and_connect_adb $(get_waydroid_ip) || return
    fi

    local pkg=""
    if command -v zenity >/dev/null 2>&1; then
        local pkgs
        pkgs=$(adb -s "${CONNECTED_DEVICES[0]}" shell pm list packages -3 2>/dev/null | sed 's/package://' | sort)
        pkg=$(echo "$pkgs" | zenity --list --title="Select App to Launch" --column="Package" --height=500 --width=600 --modal 2>/dev/null)
    else
        read -p "Package name to launch (e.g. com.example.app): " pkg
    fi

    if [ -z "$pkg" ]; then
        print_status "Cancelled."
        sleep 1
        return
    fi

    print_status "Launching $pkg..."
    # Use 'am start' to resolve and launch the app's main activity
    local launch_output
    launch_output=$(adb -s "${CONNECTED_DEVICES[0]}" shell am start -n "$(adb -s "${CONNECTED_DEVICES[0]}" shell cmd package resolve-activity --brief "$pkg" 2>/dev/null | tail -1)" 2>&1)
    if echo "$launch_output" | grep -qi "error\|exception\|not found"; then
        # Fallback: use am start with category launcher
        launch_output=$(adb -s "${CONNECTED_DEVICES[0]}" shell am start -a android.intent.action.MAIN -c android.intent.category.LAUNCHER "$pkg" 2>&1)
    fi
    if echo "$launch_output" | grep -q "Starting:"; then
        print_success "Launched: $pkg"
    else
        print_error "Failed to launch $pkg"
        echo -e "${YELLOW}$launch_output${NC}"
    fi
    read -n 1 -p "Press any key..."
}
device_info_panel() {
    print_header
    echo -e "${BOLD}${CYAN}━━━ DEVICE INFORMATION ━━━${NC}\n"

    if [ ${#CONNECTED_DEVICES[@]} -eq 0 ]; then
        wait_and_connect_adb $(get_waydroid_ip) || return
    fi

    local dev="${CONNECTED_DEVICES[0]}"

    echo -e "${BOLD}${GREEN}┌─ ANDROID / WAYDROID ─────────────────────────────┐${NC}"
    echo -e "${GREEN}│${NC}  Android Version:  ${BOLD}$(adb -s "$dev" shell getprop ro.build.version.release 2>/dev/null || echo N/A)${NC}"
    echo -e "${GREEN}│${NC}  SDK Level:        ${BOLD}$(adb -s "$dev" shell getprop ro.build.version.sdk 2>/dev/null || echo N/A)${NC}"
    echo -e "${GREEN}│${NC}  Build:            ${BOLD}$(adb -s "$dev" shell getprop ro.build.display.id 2>/dev/null || echo N/A)${NC}"
    echo -e "${GREEN}│${NC}  Device:           ${BOLD}$(adb -s "$dev" shell getprop ro.product.model 2>/dev/null || echo N/A)${NC}"
    echo -e "${GREEN}│${NC}  Architecture:     ${BOLD}$(adb -s "$dev" shell getprop ro.product.cpu.abi 2>/dev/null || echo N/A)${NC}"
    echo -e "${GREEN}└──────────────────────────────────────────────────┘${NC}"
    echo ""

    echo -e "${BOLD}${BLUE}┌─ DISPLAY ────────────────────────────────────────┐${NC}"
    local res
    local den
    res=$(adb -s "$dev" shell wm size 2>/dev/null | grep -oP '\d+x\d+' || echo "N/A")
    den=$(adb -s "$dev" shell wm density 2>/dev/null | grep -oP '\d+' | head -1 || echo "N/A")
    echo -e "${BLUE}│${NC}  Resolution:       ${BOLD}${res}${NC}"
    echo -e "${BLUE}│${NC}  Density:          ${BOLD}${den} dpi${NC}"
    echo -e "${BLUE}└──────────────────────────────────────────────────┘${NC}"
    echo ""

    echo -e "${BOLD}${YELLOW}┌─ STORAGE ────────────────────────────────────────┐${NC}"
    local storage
    storage=$(adb -s "$dev" shell df -h /data 2>/dev/null | tail -1)
    if [ -n "$storage" ]; then
        echo -e "${YELLOW}│${NC}  $storage"
    else
        echo -e "${YELLOW}│${NC}  Unable to retrieve storage info"
    fi
    echo -e "${YELLOW}└──────────────────────────────────────────────────┘${NC}"
    echo ""

    echo -e "${BOLD}${MAGENTA}┌─ MEMORY ─────────────────────────────────────────┐${NC}"
    local meminfo
    meminfo=$(adb -s "$dev" shell cat /proc/meminfo 2>/dev/null | head -3)
    if [ -n "$meminfo" ]; then
        echo "$meminfo" | while read -r line; do
            echo -e "${MAGENTA}│${NC}  $line"
        done
    fi
    echo -e "${MAGENTA}└──────────────────────────────────────────────────┘${NC}"
    echo ""

    echo -e "${BOLD}${CYAN}┌─ NETWORK ────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC}  Waydroid IP:      ${BOLD}$(get_waydroid_ip)${NC}"
    echo -e "${CYAN}│${NC}  ADB Device:       ${BOLD}${dev}${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
    echo ""

    local uptime_info
    uptime_info=$(adb -s "$dev" shell uptime 2>/dev/null | head -1)
    if [ -n "$uptime_info" ]; then
        echo -e "${CYAN}Uptime: ${uptime_info}${NC}"
    fi

    local app_count
    app_count=$(adb -s "$dev" shell pm list packages 2>/dev/null | wc -l)
    echo -e "${CYAN}Installed packages: ${BOLD}${app_count}${NC}"

    echo ""
    read -n 1 -p "Press any key to return..."
}

# --- APK Downloader ---
apk_downloader() {
    print_header
    echo -e "${BOLD}${GREEN}┌─ APK DOWNLOADER ──────────────────────────┐${NC}"
    echo -e "${GREEN}│${NC}  Search and download APKs from APKMirror"
    echo -e "${GREEN}│${NC}  or provide a direct download URL."
    echo -e "${GREEN}└────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BOLD}1)${NC} Search APKMirror by app name"
    echo -e "  ${BOLD}2)${NC} Download APK from direct URL"
    echo -e "  ${BOLD}3)${NC} Back to main menu"
    echo ""
    read -p "Selection: " dl_choice

    case "$dl_choice" in
        1)
            read -p "Enter app name to search: " search_term
            if [ -z "$search_term" ]; then
                print_error "No search term entered."
                sleep 2
                return
            fi
            local encoded
            encoded=$(echo "$search_term" | sed 's/ /+/g')
            local search_url="https://www.apkmirror.com/?post_type=app_release&searchtype=apk&s=${encoded}"
            echo -e "\n${CYAN}Opening APKMirror search in your browser...${NC}"
            echo -e "URL: ${BOLD}${search_url}${NC}\n"
            if command -v xdg-open >/dev/null 2>&1; then
                xdg-open "$search_url" 2>/dev/null &
            else
                echo -e "${YELLOW}Could not open browser automatically. Please visit the URL above.${NC}"
            fi
            echo ""
            echo -e "Once you have the direct APK download URL, use option 2 to download and install."
            read -n 1 -p "Press any key to continue..."
            ;;
        2)
            read -p "Enter direct APK URL: " apk_url
            if [ -z "$apk_url" ]; then
                print_error "No URL entered."
                sleep 2
                return
            fi
            # Validate URL format
            if [[ ! "$apk_url" =~ ^https?:// ]]; then
                print_error "Invalid URL. Must start with http:// or https://"
                sleep 2
                return
            fi
            local dl_dir="$HOME/Downloads/Waydroid"
            mkdir -p "$dl_dir"
            local filename
            filename=$(basename "$apk_url" | sed 's/?.*//')
            if [[ ! "$filename" =~ \.apk$ ]]; then
                filename="${filename}.apk"
            fi
            local dl_path="$dl_dir/$filename"
            echo -e "\n${CYAN}Downloading to: ${dl_path}${NC}"
            if command -v curl >/dev/null 2>&1; then
                curl -fL -o "$dl_path" "$apk_url"
            elif command -v wget >/dev/null 2>&1; then
                wget -O "$dl_path" "$apk_url"
            else
                print_error "Neither curl nor wget found. Cannot download."
                sleep 2
                return
            fi
            if [ -f "$dl_path" ] && [ -s "$dl_path" ]; then
                print_success "Downloaded: $dl_path"
                echo ""
                read -p "Install this APK now? (y/N): " install_yn
                if [[ "$install_yn" =~ ^[Yy] ]]; then
                    local dev="${CONNECTED_DEVICES[0]}"
                    if [ -n "$dev" ]; then
                        adb -s "$dev" install -r "$dl_path" && print_success "APK installed!" || print_error "Install failed."
                    else
                        print_error "No ADB device connected."
                    fi
                fi
            else
                print_error "Download failed or file is empty."
            fi
            read -n 1 -p "Press any key to continue..."
            ;;
        3) return ;;
        *) echo -e "${RED}Invalid selection.${NC}"; sleep 1 ;;
    esac
}

# --- Theme Customization ---
theme_customization() {
    print_header
    echo -e "${BOLD}${GREEN}┌─ THEME CUSTOMIZATION ─────────────────────┐${NC}"
    echo -e "${GREEN}│${NC}  Choose a color scheme for the manager"
    echo -e "${GREEN}└────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BOLD}1)${NC} 🔆 Light (default)"
    echo -e "  ${BOLD}2)${NC} 🌙 Dark"
    echo -e "  ${BOLD}3)${NC} 🌊 Ocean (blue/teal)"
    echo -e "  ${BOLD}4)${NC} 🌲 Forest (green)"
    echo -e "  ${BOLD}5)${NC} 🌅 Sunset (warm red/orange)"
    echo -e "  ${BOLD}6)${NC} 🔮 Neon (vibrant/magenta)"
    echo -e "  ${BOLD}7)${NC} Back to main menu"
    echo ""
    echo -e "  Current theme: ${BOLD}${THEME:-light}${NC}"
    echo ""
    read -p "Selection: " theme_choice

    case "$theme_choice" in
        1)  THEME="light"
            RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'
            CYAN='\033[0;36m'; YELLOW='\033[1;33m'; MAGENTA='\033[0;35m'
            BOLD='\033[1m'; NC='\033[0m'
            ;;
        2)  THEME="dark"
            RED='\033[1;31m'; GREEN='\033[1;32m'; BLUE='\033[1;34m'
            CYAN='\033[1;36m'; YELLOW='\033[1;33m'; MAGENTA='\033[1;35m'
            BOLD='\033[1m'; NC='\033[0m'
            ;;
        3)  THEME="ocean"
            RED='\033[0;31m'; GREEN='\033[0;36m'; BLUE='\033[1;34m'
            CYAN='\033[1;36m'; YELLOW='\033[0;33m'; MAGENTA='\033[0;34m'
            BOLD='\033[1m'; NC='\033[0m'
            ;;
        4)  THEME="forest"
            RED='\033[0;33m'; GREEN='\033[1;32m'; BLUE='\033[0;32m'
            CYAN='\033[0;36m'; YELLOW='\033[0;33m'; MAGENTA='\033[0;35m'
            BOLD='\033[1m'; NC='\033[0m'
            ;;
        5)  THEME="sunset"
            RED='\033[1;31m'; GREEN='\033[0;33m'; BLUE='\033[0;34m'
            CYAN='\033[0;31m'; YELLOW='\033[1;33m'; MAGENTA='\033[1;31m'
            BOLD='\033[1m'; NC='\033[0m'
            ;;
        6)  THEME="neon"
            RED='\033[1;35m'; GREEN='\033[1;32m'; BLUE='\033[1;34m'
            CYAN='\033[1;36m'; YELLOW='\033[1;33m'; MAGENTA='\033[1;35m'
            BOLD='\033[1m'; NC='\033[0m'
            ;;
        7)  return ;;
        *)  echo -e "${RED}Invalid selection.${NC}"; sleep 1; return ;;
    esac

    # Persist theme to config
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

    print_success "Theme set to '$THEME' and saved."
    read -n 1 -p "Press any key to continue..."
}

# --- Accessibility Tools ---
accessibility_tools() {
    print_header
    echo -e "${BOLD}${GREEN}┌─ ACCESSIBILITY TOOLS ─────────────────────┐${NC}"
    echo -e "${GREEN}│${NC}  Adjust the terminal display for comfort"
    echo -e "${GREEN}└────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BOLD}1)${NC} 🔍 Toggle Large Text Mode"
    echo -e "  ${BOLD}2)${NC} 🔊 Text-to-Speech (read status aloud)"
    echo -e "  ${BOLD}3)${NC} 🖥️  Toggle High-Contrast Mode"
    echo -e "  ${BOLD}4)${NC} Back to main menu"
    echo ""
    read -p "Selection: " a11y_choice

    case "$a11y_choice" in
        1)
            # Large text mode — zoom terminal in/out using xdotool or gsettings
            if [ "${LARGE_TEXT:-0}" -eq 0 ]; then
                if command -v xdotool >/dev/null 2>&1; then
                    # Send Ctrl+Shift+= (zoom in) multiple times for larger text
                    for _ in 1 2 3 4; do
                        xdotool key ctrl+shift+equal
                        sleep 0.1
                    done
                    LARGE_TEXT=1
                    print_success "Large text mode ENABLED. (Zoomed in 4 steps)"
                else
                    print_error "xdotool is required for Large Text mode."
                    echo -e "  ${CYAN}sudo apt install xdotool${NC}"
                fi
            else
                if command -v xdotool >/dev/null 2>&1; then
                    # Send Ctrl+minus (zoom out) to restore
                    for _ in 1 2 3 4; do
                        xdotool key ctrl+minus
                        sleep 0.1
                    done
                    LARGE_TEXT=0
                    print_success "Large text mode DISABLED. (Zoomed out 4 steps)"
                else
                    print_error "xdotool is required for Large Text mode."
                    echo -e "  ${CYAN}sudo apt install xdotool${NC}"
                fi
            fi
            read -n 1 -p "Press any key to continue..."
            ;;
        2)
            # Text-to-speech: read a summary of Waydroid status aloud
            if command -v espeak-ng >/dev/null 2>&1; then
                local tts_cmd="espeak-ng"
            elif command -v espeak >/dev/null 2>&1; then
                local tts_cmd="espeak"
            elif command -v spd-say >/dev/null 2>&1; then
                local tts_cmd="spd-say"
            else
                print_error "No text-to-speech engine found. Install espeak-ng or spd-say."
                echo -e "  ${CYAN}sudo apt install espeak-ng${NC}"
                read -n 1 -p "Press any key to continue..."
                return
            fi

            echo -e "${CYAN}Reading status aloud...${NC}"
            local status_text="Waydroid Manager. "
            if [ ${#CONNECTED_DEVICES[@]} -gt 0 ]; then
                status_text+="Connected devices: ${#CONNECTED_DEVICES[@]}. Device: ${CONNECTED_DEVICES[0]}. "
            else
                status_text+="No devices connected. "
            fi
            if waydroid status 2>/dev/null | grep -q "RUNNING"; then
                status_text+="Waydroid is running."
            else
                status_text+="Waydroid is not running."
            fi
            $tts_cmd "$status_text" 2>/dev/null &
            print_success "Speaking status..."
            sleep 3
            ;;
        3)
            # High-contrast mode: switch to bold white on black palette
            if [ "${HIGH_CONTRAST:-0}" -eq 0 ]; then
                RED='\033[1;97;41m'
                GREEN='\033[1;97;42m'
                BLUE='\033[1;97;44m'
                CYAN='\033[1;97;46m'
                YELLOW='\033[1;30;43m'
                MAGENTA='\033[1;97;45m'
                BOLD='\033[1;97m'
                NC='\033[0m'
                HIGH_CONTRAST=1
                print_success "High-contrast mode ENABLED."
            else
                apply_theme
                HIGH_CONTRAST=0
                print_success "High-contrast mode DISABLED. Theme restored."
            fi
            read -n 1 -p "Press any key to continue..."
            ;;
        4) return ;;
        *) echo -e "${RED}Invalid selection.${NC}"; sleep 1 ;;
    esac
}

# --- Waydroid Resource Monitor (realtime) ---
waydroid_resource_monitor() {
    if [ ${#CONNECTED_DEVICES[@]} -eq 0 ]; then
        wait_and_connect_adb $(get_waydroid_ip) || return
    fi
    local dev="${CONNECTED_DEVICES[0]}"
    if [ -z "$dev" ]; then
        print_error "No ADB device connected."
        sleep 2
        return
    fi

    # Draw header and a static frame once, then overwrite the dynamic lines in-place.
    print_header
    echo -e "${BOLD}${GREEN}┌─ WAYDROID RESOURCE MONITOR ────────────────┐${NC}"
    echo -e "${GREEN}│${NC}  Device: ${BOLD}${dev}${NC}"
    echo -e "${GREEN}│${NC}  IP:     ${BOLD}$(get_waydroid_ip)${NC}"
    echo -e "${GREEN}├────────────────────────────────────────────┤${NC}"

    # Save cursor at the start of the dynamic block. Use tput when available, fallback to ANSI.
    if command -v tput >/dev/null 2>&1; then
        tput sc
        save_cmd="tput rc"
    else
        printf '\033[s'
        save_cmd="printf '\\033[u'"
    fi

    # Print placeholders for the dynamic lines (these will be overwritten)
    echo -e "${GREEN}│${NC}  CPU (system_server): ${BOLD}Loading...${NC}"
    echo -e "${GREEN}│${NC}  RAM Used: ${BOLD}Loading...${NC}"
    echo -e "${GREEN}│${NC}  Disk: ${BOLD}Loading...${NC}"
    echo -e "${GREEN}└────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "${CYAN}Press any key to return. Updating every 1s...${NC}"

    while true; do
        # Restore to saved position at top of dynamic region
        eval "$save_cmd"

        # CPU (system_server)
        local cpu_usage
        cpu_usage=$(adb -s "$dev" shell top -b -n 1 2>/dev/null | awk '/system_server/ {print $9; exit}' || true)
        if [ -n "$cpu_usage" ]; then
            printf '\033[2K\r'
            printf "%b\n" "${GREEN}│${NC}  CPU (system_server): ${BOLD}${cpu_usage}%${NC}"
        else
            printf '\033[2K\r'
            printf "%b\n" "${GREEN}│${NC}  CPU (system_server): ${BOLD}Unavailable${NC}"
        fi

        # RAM
        local mem_total mem_available mem_used
        mem_total=$(adb -s "$dev" shell cat /proc/meminfo 2>/dev/null | awk '/MemTotal/ {print $2}' || true)
        mem_available=$(adb -s "$dev" shell cat /proc/meminfo 2>/dev/null | awk '/MemAvailable/ {print $2}' || true)
        if [ -n "$mem_total" ] && [ -n "$mem_available" ]; then
            mem_used=$((mem_total - mem_available))
            printf '\033[2K\r'
            printf "%b\n" "${GREEN}│${NC}  RAM Used: ${BOLD}$((mem_used/1024)) MB${NC} / ${BOLD}$((mem_total/1024)) MB${NC}"
        else
            printf '\033[2K\r'
            printf "%b\n" "${GREEN}│${NC}  RAM Used: ${BOLD}Unavailable${NC}"
        fi

        # Disk
        local disk_info
        disk_info=$(adb -s "$dev" shell df -h /data 2>/dev/null | tail -1 || true)
        printf '\033[2K\r'
        if [ -n "$disk_info" ]; then
            printf "%b\n" "${GREEN}│${NC}  Disk: ${BOLD}${disk_info}${NC}"
        else
            printf "%b\n" "${GREEN}│${NC}  Disk: ${BOLD}Unavailable${NC}"
        fi

        # Wait 1 second for keypress; exit loop if a key is pressed.
        if read -t 1 -n 1 -s key; then
            break
        fi
    done

    # Move cursor below the monitor before returning
    echo ""
}

# ---------------- MAIN MENU ----------------
while true; do
    print_header
    echo -e " ${BOLD}${GREEN}── CORE ──${NC}"
    echo -e "  ${BOLD}1)${NC}  ${GREEN}START/RESTART${NC} Waydroid"
    echo -e "  ${BOLD}2)${NC}  ${RED}STOP${NC} Waydroid & Weston"
    echo -e "  ${BOLD}3)${NC}  ${BLUE}ADB SHELL ACCESS${NC} (Direct)"
    echo -e "  ${BOLD}4)${NC}  ${CYAN}INSTALL${NC} APK File"
    echo -e "  ${BOLD}5)${NC}  ${MAGENTA}WAYDROID SCRIPT${NC} (GApps, Magisk, etc.)"
    echo ""
    echo -e " ${BOLD}${BLUE}── ADB ──${NC}"
    echo -e "  ${BOLD}6)${NC}  ${BLUE}LIST${NC} ADB Devices"
    echo -e "  ${BOLD}7)${NC}  ${YELLOW}RECONNECT${NC} ADB"
    echo ""
    echo -e " ${BOLD}${CYAN}── SETTINGS & APPS ──${NC}"
    echo -e "  ${BOLD}8)${NC}  ${GREEN}DISPLAY SETTINGS${NC} (Resolution, Density)"
    echo -e "  ${BOLD}9)${NC}  ${CYAN}APP MANAGEMENT${NC} (Install/Uninstall)"
    echo -e "  ${BOLD}10)${NC}  ${MAGENTA}COPY/PASTE${NC} to Android"
    echo ""
    echo -e " ${BOLD}${YELLOW}── TOOLS ──${NC}"
    echo -e "  ${BOLD}11)${NC} 📸 ${CYAN}SCREENSHOT${NC}"
    echo -e "  ${BOLD}12)${NC} 🎬 ${RED}SCREEN RECORDING${NC}"
    echo -e "  ${BOLD}13)${NC} 📂 ${GREEN}FILE TRANSFER${NC} (Push/Pull)"
    echo -e "  ${BOLD}14)${NC} 📋 ${YELLOW}LOGCAT VIEWER${NC}"
    echo -e "  ${BOLD}15)${NC} ❄️  ${BLUE}FREEZE/DISABLE${NC} Apps"
    echo -e "  ${BOLD}16)${NC} 🗑  ${RED}CLEAR APP DATA${NC}/Cache"
    echo -e "  ${BOLD}17)${NC} 🚀 ${GREEN}QUICK LAUNCH${NC} App"
    echo -e "  ${BOLD}18)${NC} ℹ️  ${CYAN}DEVICE INFO${NC}"
    echo -e "  ${BOLD}19)${NC} 📦 ${GREEN}APK DOWNLOADER${NC}"
    echo -e "  ${BOLD}20)${NC} 🎨 ${MAGENTA}THEME CUSTOMIZATION${NC}"
    echo -e "  ${BOLD}21)${NC} ♿ ${CYAN}ACCESSIBILITY TOOLS${NC}"
    echo ""
    echo -e " ${BOLD}${MAGENTA}── SYSTEM ──${NC}"
    echo -e "  ${BOLD}22)${NC} ${CYAN}STATUS${NC}"
    echo -e "  ${BOLD}23)${NC} ${GREEN}RESOURCE MONITOR${NC} (CPU/RAM/Disk)"
    echo -e "  ${BOLD}24)${NC} ${MAGENTA}THEME${NC} (Light/Dark)"
    echo -e "  ${BOLD}25)${NC} ${MAGENTA}CHECK FOR UPDATES${NC}"
    echo -e "  ${BOLD}26)${NC} ${YELLOW}EXIT${NC}"
    echo -e "${CYAN}==================================================${NC}"
    
    if [ ${#CONNECTED_DEVICES[@]} -gt 0 ]; then
        echo -e "${GREEN} ● ACTIVE:${NC} ${CONNECTED_DEVICES[*]}"
    else
        echo -e "${RED} ● STATUS:${NC} Disconnected"
    fi
    echo -e "${CYAN}==================================================${NC}"
    
    read -p "Selection: " CHOICE

    # Helper: require Waydroid running
    # Accepts an active ADB-connected device as a valid running session
    _require_running() {
        # Prefer explicit Waydroid status
        if waydroid status 2>/dev/null | grep -q "RUNNING"; then
            return 0
        fi

        # If we already have a remembered device, check it's still connected
        if [ ${#CONNECTED_DEVICES[@]} -gt 0 ]; then
            local dev="${CONNECTED_DEVICES[0]}"
            if adb_device_connected "$dev"; then
                return 0
            fi
        fi

        # Probe current adb devices and adopt the first one if present
        local anydev
        anydev=$(adb devices 2>/dev/null | awk 'NR>1 && $1!="" {print $1}' | head -n1 || true)
        if [ -n "$anydev" ]; then
            CONNECTED_DEVICES=("$anydev")
            return 0
        fi

        print_header
        print_error "Waydroid is not running! Start it using option 1 in the main menu."
        echo ""
        read -n 1 -p "Press any key..."
        return 1
    }

    case "$CHOICE" in
        1) restart_waydroid ;;
        2) _require_running && stop_waydroid ;;
        3) _require_running && adb_shell_access ;;
        4) _require_running && install_apk ;;
        5) _require_running && run_waydroid_script ;;
        6) _require_running && { print_header; adb devices -l; read -n 1 -p "Press any key..."; } ;;
        7) _require_running && wait_and_connect_adb $(get_waydroid_ip) ;;
        8) _require_running && change_display_settings ;;
        9) _require_running && uninstall_apps_menu ;;
        10) _require_running && copy_paste_to_android ;;
        11) _require_running && take_screenshot ;;
        12) _require_running && record_screen ;;
        13) _require_running && file_transfer_menu ;;
        14) _require_running && logcat_viewer ;;
        15) _require_running && freeze_apps_menu ;;
        16) _require_running && clear_app_data ;;
        17) _require_running && quick_launch_app ;;
        18) _require_running && device_info_panel ;;
        19) _require_running && apk_downloader ;;
        20) theme_customization ;;
        21) accessibility_tools ;;
        22) show_status ;;
        23) _require_running && waydroid_resource_monitor ;;
        24) set_theme_interactive ;;
        25) self_update ;;
        26) clear; exit 0 ;;
        *) echo -e "${RED}Invalid selection.${NC}"; sleep 1 ;;
    esac
done
