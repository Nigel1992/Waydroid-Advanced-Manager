# 🚀 Waydroid Advanced Manager  

[![version](https://img.shields.io/github/v/tag/Nigel1992/Waydroid-Advanced-Manager?label=version&style=flat-square)](https://github.com/Nigel1992/Waydroid-Advanced-Manager/releases)
[![license](https://img.shields.io/github/license/Nigel1992/Waydroid-Advanced-Manager?style=flat-square)](LICENSE)

A polished, user-friendly Bash CLI for managing Waydroid: start/stop Waydroid and Weston, manage ADB connections, install APKs, and send clipboard text into Android — all from your terminal with helpful prompts and safety checks.

---

## ✨ Highlights & Features

- ✅ Start/Restart Waydroid stack and Weston with automatic Wayland socket detection
- ✅ ADB auto-handshake and reconnect logic for reliable operations
- ✅ Install APKs from local files or direct URLs (curl/wget)
- ✅ Zenity integration for optional graphical dialogs (uninstall/installer)
- ✅ Copy/Paste helper (Option 9) — sends terminal text into Android input fields; special characters supported
- ✅ Change display resolution & density; reset to defaults
- ✅ CLI flags: `--version` / `-v` and `--help` / `-h`

---

## 🔧 Requirements

- Waydroid, Weston, ADB, Python3, Git
- Optional: `zenity` (GUI dialogs), `wl-clipboard` (`wl-copy` / `wl-paste` for Wayland)

Quick install (Debian/Ubuntu):

```bash
sudo apt update
sudo apt install -y waydroid weston adb zenity curl wget git python3 python3-pip wl-clipboard
```

---

## 🚀 Quick Start

```bash
git clone https://github.com/Nigel1992/Waydroid-Advanced-Manager.git
cd Waydroid-Advanced-Manager
chmod +x waydroid-manager.sh
./waydroid-manager.sh
```

Tip: run `./waydroid-manager.sh --version` to print the bundled version and release date.

---

## 📋 Copy/Paste to Android (Option 9) — Important Notes

- Usage: focus the input field inside Android, select Option 9, type or paste text into your terminal and press ENTER. The script automatically sends the text to the currently active input box in Android.
- Supported: All plain text including special characters (e.g. `& | ; < > $ \` `). Newlines are not yet supported (single-line only).
- Safety: The tool only accepts plain text — files or binary data are not supported.

---

## 🧾 Changelog & Releases
See [`CHANGELOG.md`](CHANGELOG.md) for full history. Latest release: **v0.4.0** (2026-01-31).

---

## 📣 Contributing
Bug reports, PRs, and feature suggestions are welcome. Please open an issue with details and reproduction steps.

---

## 📜 License
See the `LICENSE` file in this repository.

---

> Built with care for the Waydroid community 💙  