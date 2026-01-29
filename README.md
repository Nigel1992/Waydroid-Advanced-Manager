# 🚀 Waydroid Advanced Manager

A beautiful, professional Bash-based CLI tool for managing Waydroid sessions, automating ADB connections, and integrating advanced Android features—all from your terminal.

---

## ✨ Features

- **Universal IP Detection**: Seamlessly connects to Waydroid on any subnet.
- **One-Click Start**: Launches Weston, detects Wayland displays, and starts the Android UI.
- **ADB Auto-Handshake**: Pings the container and connects ADB automatically.
- **Script Integration**: Built-in installer for [`waydroid_script`](https://github.com/casualsnek/waydroid_script) (GApps, Magisk, etc).
- **APK Installer**: GUI-based file picker and URL installer for Android apps.
- **Graphical Uninstall**: Zenity-powered uninstall-from-list (optional).
- **Copy/Paste Helper**: Send plain text from your terminal directly into Android input fields (see below).
- **Display Tweaks**: Change resolution, density, and reset display settings.
- **Robust Safety Checks**: Ensures Waydroid is running before critical actions.

---

## 🖥️ Requirements

- **Waydroid** (`sudo apt install waydroid`)
- **Weston** (`sudo apt install weston`)
- **ADB** (`sudo apt install adb`)
- **Python3 & pip** (for `waydroid_script`)
- **Git** (for cloning `waydroid_script`)
- **Zenity** (optional, for GUI dialogs)
- **wl-clipboard** (optional, for Wayland clipboard integration)

### Recommended (Debian/Ubuntu):
```bash
sudo apt update
sudo apt install -y waydroid weston adb zenity curl wget git python3 python3-pip wl-clipboard
```
- `wl-clipboard` provides `wl-copy`/`wl-paste` (Wayland clipboard integration).
- `zenity` enables graphical dialogs (script falls back to terminal input if not available).
- `curl` or `wget` is required for APK downloads from URLs.

For Fedora/Arch/other: install the equivalent packages via your distro's package manager.

---

## ⚡ Installation
```bash
git clone https://github.com/Nigel1992/Waydroid-Advanced-Manager.git
cd Waydroid-Advanced-Manager
chmod +x waydroid-manager.sh
./waydroid-manager.sh
```

---

## 📝 Usage Highlights

### Main Menu
- Start/Restart Waydroid stack
- Stop all services
- Install APKs (file picker or URL)
- Run advanced scripts (GApps, Magisk, etc)
- List and manage installed apps
- Change display settings (resolution, density)
- **Copy/Paste to Android** (Option 9)

### 🚦 Copy/Paste to Android (Option 9)
- **Terminal-only, plain text only.**
- You will be prompted to enter the text you want to send.
- **Important:** Before entering your text, open and focus the input field (keyboard or text box) in your Android environment. The script will type your text into the currently active input box.
- ⚠️ *Only plain text is supported. Files or non-text data will not work.*

---


## 🆕 Recent Changes (2026-01-29)
- Restart logic is now robust: Weston and the Wayland socket are properly stopped and started, ensuring reliable relaunch of the UI.
- Weston is always launched with the X11 backend, fixing fatal errors when running under X11 sessions.
- If Weston fails to start, the script logs and displays the error output for easier debugging.
- See `CHANGELOG.md` for full details.

---

## 📖 See Also
- [CHANGELOG.md](CHANGELOG.md) — Full change history and details.
- [`waydroid_script`](https://github.com/casualsnek/waydroid_script) — For advanced Android modding inside Waydroid.

---

## 💡 Tips
- If you encounter issues, ensure all dependencies are installed and Waydroid is running.
- For best results, run from a desktop session (not SSH or TTY-only).
- The script will guide you if a required tool is missing or if Waydroid is not running.

---

> Made with ❤️ for the Waydroid community.
