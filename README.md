# Waydroid Advanced Manager

A professional Bash-based CLI tool to manage Waydroid sessions, automate ADB connections via universal IP detection, and integrate the `waydroid_script` for GApps and Magisk.

## Features
- Universal IP Detection: Works regardless of your subnet.
- One-Click Start: Launches Weston, detects Wayland displays, and starts the UI.
- ADB Auto-Handshake: Pings the container and connects ADB automatically.
- Script Integration: Built-in installer for `waydroid_script`.
- APK Installer: GUI-based file picker and URL installer for Android apps.
- Graphical uninstall-from-list (Zenity).
- Copy/Paste helper to copy host clipboard for pasting inside Android.

## Requirements
- Waydroid installed (`sudo apt install waydroid`)
- Weston (`sudo apt install weston`)
- Zenity (optional, for GUI prompts)
- ADB (`sudo apt install adb`)
- Python3 & pip (for `waydroid_script`)
- Git (for cloning `waydroid_script`)

## Installation
```bash
git clone https://github.com/Nigel1992/Waydroid-Advanced-Manager.git
cd Waydroid-Advanced-Manager
chmod +x waydroid-manager.sh
./waydroid-manager.sh
```

## Recent Changes (2026-01-19)
- Improved CLI layout and status header.
- Added graphical uninstall-from-list and APK-from-URL installer.
- Added display reset option and stricter Waydroid-running checks.
- Added `copy_paste_to_android` helper for easy pasting into Android.
 - Main menu now enforces Waydroid running for critical actions and provides guidance to start it (option 1).
 - APK-from-URL now validates downloads and provides curl/wget fallback.
 - Several usability and input fallbacks added (Zenity -> terminal).

See `CHANGELOG.md` for full details.
