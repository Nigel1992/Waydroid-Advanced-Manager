[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/Nigel1992)

> **Support this project* All donations go towards your chosen charity. You can pick any charity you'd like, and 5% is retained for Ko-Fi development costs. As a thank you, your name will be listed as a supporter/donor in this project. Feel free to email me at thedjskywalker@gmail.com for proof! :)

# Waydroid Advanced Manager

<img width="663" height="474" alt="image" src="https://github.com/user-attachments/assets/2b301229-27c8-477e-baca-7dcb03999e08" />


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
- Python3 & pip (for `waydroid_script`)
- Git (for cloning `waydroid_script`)

### Kernel & Modules
- Linux **kernel 5.10+** recommended
- Required modules: `ashmem`, `binder`

## 💻 Supported Linux Distributions
Waydroid (and this manager) works on distributions where Waydroid can be installed. Officially tested:

### Debian-based
- Ubuntu 20.04, 22.04, 23.10
- Debian 11, 12
- Linux Mint 20.x, 21.x

### Arch-based
- Arch Linux (rolling release)
- Manjaro

### Fedora / RPM-based (community support)
- Fedora 37+
- openSUSE Leap 15.x

⚠️ **Note:** Older kernels (<5.10) or distributions without Wayland support may not work. Make sure `ashmem` and `binder` kernel modules are loaded.

## 📥 Installation
```bash
git clone https://github.com/Nigel1992/Waydroid-Advanced-Manager.git
cd Waydroid-Advanced-Manager
chmod +x waydroid-manager.sh
./waydroid-manager.sh
