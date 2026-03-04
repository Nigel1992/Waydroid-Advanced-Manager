# 🚀 Waydroid Advanced Manager

<div align="center">

[![Join Discord](https://img.shields.io/badge/Discord-Join%20Community-5865F2?style=for-the-badge&logo=discord&logoColor=white)](https://discord.gg/fpsC7CjChY)
[![Version](https://img.shields.io/badge/Version-0.8.0-brightgreen?style=for-the-badge)](https://github.com/Nigel1992/Waydroid-Advanced-Manager)
[![License](https://img.shields.io/github/license/Nigel1992/Waydroid-Advanced-Manager?style=for-the-badge)](LICENSE)
[![Stars](https://img.shields.io/github/stars/Nigel1992/Waydroid-Advanced-Manager?style=for-the-badge&color=yellow)](https://github.com/Nigel1992/Waydroid-Advanced-Manager/stargazers)

**The ultimate all-in-one terminal toolkit for Waydroid power users.**

Start, stop, manage apps, transfer files, capture screenshots, record screens, view logs — and much more — all from a beautiful, organized CLI with safety checks and graphical dialog support.

[Getting Started](#-quick-start) · [Features](#-features-at-a-glance) · [CLI Flags](#%EF%B8%8F-cli-flags-non-interactive) · [FAQ](#-frequently-asked-questions) · [Contributing](#-contributing)

</div>

---

## 📋 Table of Contents

- [Features at a Glance](#-features-at-a-glance)
- [Requirements](#-requirements)
- [Quick Start](#-quick-start)
- [Menu Overview](#%EF%B8%8F-menu-overview)
- [CLI Flags (Non-Interactive)](#%EF%B8%8F-cli-flags-non-interactive)
- [Logging](#-logging)
- [Copy/Paste to Android](#-copypaste-to-android-option-9)
- [Frequently Asked Questions](#-frequently-asked-questions)
- [Changelog & Releases](#-changelog--releases)
- [Contributing](#-contributing)
- [License](#-license)

---

## ✨ Features at a Glance

### 🆕 What's New in 0.8.0

- **Realtime Resource Monitor**: Option 19 now shows live CPU, RAM, and Disk usage, updating in-place every second for a true dashboard experience.
- **Session Attach Fix**: Menu options now work after attaching to an existing ADB session, even if Waydroid status is not RUNNING.
- **Robust ADB detection**: Improved fallback logic for session detection and device connection.
- **Bugfixes**: No more false "Waydroid is not running" errors when attached; resource monitor no longer scrolls, but updates in-place.

### 🟢 Core
| Feature | Description |
|---------|-------------|
| **Start / Restart** | Launch Waydroid stack + Weston with automatic Wayland socket detection |
| **Stop** | Gracefully stop Waydroid and Weston compositor |
| **Auto-detect Sessions** | On launch, detects running Waydroid / ADB devices and offers to connect |
| **APK Install** | Install from local files, URLs (curl/wget), or batch from a directory |
| **Waydroid Script** | One-click access to GApps, Magisk, and more via casualsnek/waydroid_script |

### 🔵 ADB & Connectivity
| Feature | Description |
|---------|-------------|
| **ADB Auto-Handshake** | Automatic connection and reconnect logic for reliable operations |
| **List Devices** | View all connected ADB devices |
| **Reconnect ADB** | Quick re-establish connection if it drops |

### ⚙️ Settings & Apps
| Feature | Description |
|---------|-------------|
| **Display Settings** | Change resolution & density; tablet/ultra-wide presets; restore defaults |
| **App Management** | Search, uninstall, batch uninstall, export installed app lists |
| **Copy / Paste** | Send terminal text into Android input fields — special characters supported |
| **Theme Toggle** | Light/dark terminal theme with persistence to config file |

### 🛠️ Tools
| Feature | Description |
|---------|-------------|
| 📸 **Screenshot** | Capture Android screen → `~/Pictures/Waydroid/` |
| 🎬 **Screen Recording** | Record up to 180s → `~/Videos/Waydroid/` |
| 📂 **File Transfer** | Push/pull files and folders between host ↔ Android |
| 📋 **Logcat Viewer** | Live logcat, filter by tag, errors-only, save to file |
| ❄️ **Freeze / Disable Apps** | Disable bloatware without uninstalling; re-enable anytime |
| 🗑 **Clear App Data** | Wipe all data or just cache for any app |
| 🚀 **Quick Launch** | Launch any installed app by package name |
| ℹ️ **Device Info** | Android version, display, storage, memory, network, uptime |
| 🟢 **Realtime Resource Monitor** | NEW: Live CPU/RAM/Disk usage updates in-place every second (option 19) |

### 🔒 Safety & Automation
| Feature | Description |
|---------|-------------|
| **Zenity Dialogs** | Optional graphical prompts (always-on-top with `--modal`) |
| **Weston Focus** | APK install dialogs auto-focus the compositor window via `xdotool` |
| **Confirmations** | Destructive actions require confirmation; bypass with `--yes` |
| **Batch Operations** | Batch APK install/uninstall from files or directories |
| **Logging** | Separate install/uninstall logs with auto-rotation at 1 MB |
| **Update Check** | Compares local version against GitHub; offers to open release page |

---

## 🔧 Requirements

| Dependency | Purpose | Required |
|------------|---------|:--------:|
| `waydroid` | Android container | ✅ |
| `weston` | Wayland compositor | ✅ |
| `adb` | Android Debug Bridge | ✅ |
| `git` | Version control / self-update | ✅ |
| `curl` or `wget` | APK downloads & update checks | ✅ |
| `python3` | Waydroid script support | ✅ |
| `zenity` | Graphical dialogs (file picker, app selector) | Optional |
| `wl-clipboard` | Wayland clipboard (`wl-copy` / `wl-paste`) | Optional |
| `xdotool` | Window focus for modal dialogs | Optional |

### One-Line Install (Debian / Ubuntu)

```bash
sudo apt update && sudo apt install -y \
  waydroid weston adb zenity curl wget git \
  python3 python3-pip wl-clipboard xdotool
```

### Arch Linux

```bash
sudo pacman -S waydroid weston android-tools zenity curl wget git python wl-clipboard xdotool
```

---

## 🚀 Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/Nigel1992/Waydroid-Advanced-Manager.git

# 2. Enter the directory
cd Waydroid-Advanced-Manager

# 3. Make executable
chmod +x waydroid-manager.sh

# 4. Launch!
./waydroid-manager.sh
```

> 💡 **Tip:** Run `./waydroid-manager.sh --version` to check the installed version and release date.

---

## 🖥️ Menu Overview

The interactive menu is organized into **5 sections** with **23 options**:

```
── CORE ──
 1)  START/RESTART Waydroid
 2)  STOP Waydroid & Weston
 3)  ADB SHELL ACCESS (Direct)
 4)  INSTALL APK File
 5)  WAYDROID SCRIPT (GApps, Magisk, etc.)

── ADB ──
 6)  LIST ADB Devices
 7)  RECONNECT ADB

── SETTINGS & APPS ──
 8)  DISPLAY SETTINGS (Resolution, Density)
 9)  APP MANAGEMENT (Install/Uninstall)
 10)  COPY/PASTE to Android

── TOOLS ──
 11) 📸 SCREENSHOT
 12) 🎬 SCREEN RECORDING
 13) 📂 FILE TRANSFER (Push/Pull)
 14) 📋 LOGCAT VIEWER
 15) ❄️  FREEZE/DISABLE Apps
 16) 🗑  CLEAR APP DATA/Cache
 17) 🚀 QUICK LAUNCH App
 18) ℹ️  DEVICE INFO

── SYSTEM ──
 19) STATUS
 20) RESOURCE MONITOR (CPU/RAM/Disk)
 21) THEME (Light/Dark)
 22) CHECK FOR UPDATES
 23) EXIT
```

---

## ⚙️ CLI Flags (Non-Interactive)

Run any action directly from the command line without entering the interactive menu:

| Flag | Description |
|------|-------------|
| `--version`, `-v` | Show version and exit |
| `--help`, `-h` | Show help and exit |
| `--debug` | Enable debug logging |
| `--restart` | Restart Waydroid stack |
| `--stop` | Stop Waydroid and Weston |
| `--status` | Show system status |
| `--install-apk <path\|url>` | Install APK from file or URL |
| `--install-apks-dir <dir>` | Batch install all APKs from a directory |
| `--uninstall-list <file>` | Uninstall packages from a newline-delimited file |
| `--yes`, `-y` | Auto-confirm destructive actions (scripting) |
| `--set-dpi <dpi>` | Set display density |
| `--set-res <WxH>` | Set display resolution |
| `--list-apps-export [file]` | Export installed apps list |
| `--theme <dark\|light>` | Set and persist terminal theme |
| `--self-update` | Update script from git |

**Examples:**

```bash
# Install an APK from URL
./waydroid-manager.sh --install-apk https://example.com/app.apk

# Batch install a folder of APKs, auto-confirm
./waydroid-manager.sh --install-apks-dir ~/apks/ --yes

# Set resolution to tablet mode
./waydroid-manager.sh --set-res 1200x1920 --set-dpi 240
```

---

## 📝 Logging

All actions are logged to `~/.cache/waydroid-manager/`:

| Log File | Contents |
|----------|----------|
| `waydroid-manager.log` | General operations, errors, session events |
| `install.log` | Per-APK install results and batch summaries |
| `uninstall.log` | Per-app uninstall results |

Log files are **automatically rotated** when they exceed **1 MB**.

---

## 📋 Copy/Paste to Android (Option 9)

| | Details |
|---|---------|
| **How to use** | Focus an input field in Waydroid → select Option 9 → type or paste text → press Enter |
| **Supported** | All plain text including special characters: `& \| ; < > $ \` ` |
| **Not supported** | Multi-line text, files, or binary data |
| **How it works** | Uses `adb shell input text` with proper escaping for shell metacharacters |

---

## ❓ Frequently Asked Questions

<details>
<summary><strong>🔹 How do I install Waydroid in the first place?</strong></summary>

Waydroid requires a **Wayland-based** desktop session (GNOME on Wayland, Sway, etc.) and a compatible Linux kernel.

```bash
# Ubuntu/Debian
sudo apt install waydroid

# Initialize Waydroid (first-time only)
sudo waydroid init
```

For detailed instructions, see the official [Waydroid documentation](https://docs.waydro.id/).

</details>

<details>
<summary><strong>🔹 Waydroid won't start — "Session is already running"</strong></summary>

This happens when a previous Waydroid session wasn't cleanly shut down. Fix it with:

```bash
# Stop the container
sudo waydroid container stop

# Kill any leftover sessions
waydroid session stop

# Now start fresh with the manager
./waydroid-manager.sh
```

The manager's **auto-detect** feature (on launch) will also notice an existing session and offer to reconnect.

</details>

<details>
<summary><strong>🔹 ADB won't connect — "Connection refused" or device not found</strong></summary>

1. **Make sure Waydroid is running** — use Option 1 to start it first.
2. **Check the IP** — Waydroid typically uses `192.168.240.112`. The manager auto-detects this.
3. **Restart ADB** — try Option 6 (Reconnect ADB) or manually:
   ```bash
   adb kill-server && adb start-server
   adb connect 192.168.240.112:5555
   ```
4. **Firewall** — ensure your firewall isn't blocking local connections on port 5555.

</details>

<details>
<summary><strong>🔹 APK installation fails — "INSTALL_FAILED_..."</strong></summary>

| Error | Cause | Fix |
|-------|-------|-----|
| `INSTALL_FAILED_OLDER_SDK` | APK requires a newer Android version | Find a compatible APK version |
| `INSTALL_FAILED_NO_MATCHING_ABIS` | APK is built for wrong architecture (e.g., ARM on x86) | Use an x86/x86_64 build or enable ARM translation via Waydroid Script (Option 4) |
| `INSTALL_FAILED_ALREADY_EXISTS` | App already installed | Uninstall first via Option 8, then retry |
| `INSTALL_FAILED_INSUFFICIENT_STORAGE` | Not enough space in the container | Clear app caches (Option 15) or resize the Waydroid image |

</details>

<details>
<summary><strong>🔹 How do I get Google Play Store / GApps?</strong></summary>

Use **Option 4 (Waydroid Script)** which integrates [casualsnek/waydroid_script](https://github.com/casualsnek/waydroid_script):

1. Start Waydroid (Option 1)
2. Select Option 4
3. Choose "Install GApps"

After installation, reboot Waydroid. You'll need to sign in with your Google account. Some apps may require device certification — the Waydroid Script can register your device ID with Google.

</details>

<details>
<summary><strong>🔹 How do I install Magisk / root Waydroid?</strong></summary>

Also via **Option 4 (Waydroid Script)**:

1. Start Waydroid (Option 1)
2. Select Option 4
3. Choose "Install Magisk"

This patches the Waydroid system image with Magisk for root access. Useful for apps that need superuser privileges.

</details>

<details>
<summary><strong>🔹 Screenshot / screen recording doesn't work</strong></summary>

- **Ensure ADB is connected** — the "ACTIVE" indicator at the bottom of the menu should show a device.
- **Screenshots** use `adb shell screencap` — if this fails, it typically means the container's display isn't rendering properly. Try restarting Waydroid.
- **Screen recording** uses `adb shell screenrecord` — some Waydroid builds may have limited support for this. Make sure the container is fully booted (wait 10-15 seconds after start).
- **Output folders** are auto-created:
  - Screenshots: `~/Pictures/Waydroid/`
  - Recordings: `~/Videos/Waydroid/`

</details>

<details>
<summary><strong>🔹 File transfer fails — "Permission denied"</strong></summary>

Android's `/sdcard/` is the safest target for file operations:

```bash
# Push to Android
adb push myfile.txt /sdcard/

# Pull from Android
adb pull /sdcard/myfile.txt ~/Downloads/
```

If pushing to system paths (e.g., `/system/`), you'll need root (Magisk). For most use cases, stick to `/sdcard/` — this is what the File Transfer tool (Option 12) uses by default.

</details>

<details>
<summary><strong>🔹 How do I change the screen resolution / DPI?</strong></summary>

**Interactive:** Use Option 7 (Display Settings) — choose from presets or enter custom values:

| Preset | Resolution | Use Case |
|--------|-----------|----------|
| Phone | 720×1280 | Mobile apps |
| Tablet | 1200×1920 | Tablet-optimized apps |
| Desktop | 1920×1080 | Landscape / productivity |
| Ultra-wide | 3440×1440 | Ultra-wide monitors |

**CLI:**
```bash
./waydroid-manager.sh --set-res 1920x1080 --set-dpi 160
```

Changes take effect immediately. Use the "Reset to defaults" option to revert.

</details>

<details>
<summary><strong>🔹 Can I disable bloatware / pre-installed apps?</strong></summary>

Yes! Use **Option 14 (Freeze/Disable Apps)**:

1. Select "Disable (freeze) an app"
2. Pick the app from the list (uses zenity picker if available)
3. The app is disabled without being uninstalled — no data is lost

To re-enable: select "Enable (unfreeze) an app" and pick from the disabled list.

This is the safest way to deal with bloatware since you can always re-enable the app if needed.

</details>

<details>
<summary><strong>🔹 The zenity dialog appears behind other windows</strong></summary>

All zenity dialogs should use `--modal` to stay on top. If you're still experiencing issues:

1. Make sure `xdotool` is installed: `sudo apt install xdotool`
2. The manager uses `xdotool` to focus the Weston compositor before opening dialogs
3. If a dialog still hides, click the taskbar/panel to bring it forward

</details>

<details>
<summary><strong>🔹 Logcat shows too much output — how do I filter?</strong></summary>

Use **Option 13 (Logcat Viewer)** which offers four modes:

| Mode | What it shows |
|------|---------------|
| **Live logcat** | Everything (Ctrl+C to stop) |
| **Save to file** | Dumps last 500 lines for offline analysis |
| **Filter by tag** | Only messages from a specific Android component (e.g., `ActivityManager`) |
| **Errors only** | Only ERROR-level messages (`*:E` filter) |

**From CLI** (outside the manager):
```bash
# Filter by tag
adb logcat -s ActivityManager

# Errors only
adb logcat *:E

# Save to file
adb logcat -d -t 1000 > ~/logcat_dump.txt
```

</details>

<details>
<summary><strong>🔹 How do I update the manager?</strong></summary>

**Option A — From the menu:**
Select Option 20 (Check for Updates). If a new version is available, the manager shows the GitHub URL and offers to open it in your browser.

**Option B — CLI:**
```bash
./waydroid-manager.sh --self-update
```

**Option C — Manual:**
```bash
cd Waydroid-Advanced-Manager
git pull origin main
```

</details>

<details>
<summary><strong>🔹 Can I run this on X11 instead of Wayland?</strong></summary>

Waydroid **requires Wayland**. The manager uses **Weston** as a nested Wayland compositor, which means it works even if your desktop session is X11. Weston creates a Wayland environment inside an X11 window.

If you're on X11, the manager handles Weston for you automatically — just use Option 1 to start.

</details>

<details>
<summary><strong>🔹 How do I use CLI flags for scripting / automation?</strong></summary>

Combine flags for headless operation:

```bash
# Install APK without prompts
./waydroid-manager.sh --install-apk ~/Downloads/app.apk --yes

# Batch install + auto-confirm
./waydroid-manager.sh --install-apks-dir ~/apks/ --yes

# Set display and exit
./waydroid-manager.sh --set-res 1920x1080 --set-dpi 240

# Export app list to file
./waydroid-manager.sh --list-apps-export ~/apps.txt
```

Use `--yes` / `-y` to skip all confirmation prompts — ideal for scripts and CI pipelines.

</details>

<details>
<summary><strong>🔹 Where are config and cache files stored?</strong></summary>

| Path | Contents |
|------|----------|
| `~/.config/waydroid-manager.conf` | Theme preference and settings |
| `~/.cache/waydroid-manager/` | Logs directory |
| `~/.cache/waydroid-manager/waydroid-manager.log` | General log |
| `~/.cache/waydroid-manager/install.log` | APK install history |
| `~/.cache/waydroid-manager/uninstall.log` | Uninstall history |
| `~/Pictures/Waydroid/` | Saved screenshots |
| `~/Videos/Waydroid/` | Saved screen recordings |

</details>

<details>
<summary><strong>🔹 The "Quick Launch" feature doesn't work for my app</strong></summary>

Quick Launch (Option 16) uses `am start` to resolve and launch an app's main activity. If it fails:

1. **App may not have a launcher activity** — some background services or system apps can't be launched this way.
2. **Try the full package name** — make sure you're using the complete package (e.g., `com.example.app`, not just `app`).
3. **App might be disabled** — check Option 14 to see if it's in the disabled list.
4. **Check logcat** — use Option 13 to see what error Android reports when trying to launch.

</details>

<details>
<summary><strong>🔹 How do I completely reset Waydroid?</strong></summary>

If Waydroid is in a broken state:

```bash
# 1. Stop everything
waydroid session stop
sudo waydroid container stop

# 2. Reset the Waydroid data (WARNING: deletes all Android apps and data!)
sudo rm -rf /var/lib/waydroid /home/$USER/.local/share/waydroid

# 3. Re-initialize
sudo waydroid init

# 4. Start fresh
./waydroid-manager.sh
```

> ⚠️ **Warning:** This removes ALL Android apps, data, and settings. Back up important files first using the File Transfer tool (Option 12).

</details>

---

## 🧾 Changelog & Releases

See [`CHANGELOG.md`](CHANGELOG.md) for the full release history.

**Latest release: v0.7.0** (2026-03-04)

---

## 📣 Contributing

Contributions are welcome! Here's how you can help:

1. **🐛 Report bugs** — [Open an issue](https://github.com/Nigel1992/Waydroid-Advanced-Manager/issues) with details and reproduction steps
2. **💡 Suggest features** — Describe your idea in an issue or start a discussion
3. **🔧 Submit a PR** — Fork the repo, make your changes, and open a pull request
4. **⭐ Star the repo** — It helps others discover the project!

Please join our [Discord community](https://discord.gg/fpsC7CjChY) for discussions, support, and updates.

---

## 📜 License

This project is licensed under the **MIT License**. See the [`LICENSE`](LICENSE) file for the full text.

Copyright © 2026 Nigel Hagen

---

<div align="center">

**Built with care for the Waydroid community** 💙

[⬆ Back to top](#-waydroid-advanced-manager)

</div>
