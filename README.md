# Waydroid Advanced Manager

A professional Bash-based CLI tool to manage Waydroid sessions, automate ADB connections via universal IP detection, and integrate the `waydroid_script` for GApps and Magisk.

## 🚀 Features
- **Universal IP Detection:** Works regardless of your subnet.
- **One-Click Start:** Launches Weston, detects Wayland displays, and starts the UI.
- **ADB Auto-Handshake:** Pings the container and connects ADB automatically.
- **Script Integration:** Built-in installer for [waydroid_script](https://github.com/casualsnek/waydroid_script).
- **APK Installer:** GUI-based file picker for Android apps.

## 🛠️ Requirements
- Waydroid installed (`sudo apt install waydroid`)
- Weston (`sudo apt install weston`)
- Zenity (for file selection)
- ADB (`sudo apt install adb`)

## 📥 Installation
```bash
git clone [https://github.com/Nigel1992/Waydroid-Manager-Xubuntu.git](https://github.com/Nigel1992/Waydroid-Manager-Xubuntu.git)
cd Waydroid-Manager
chmod +x waydroid-manager.sh
./waydroid-manager.sh
