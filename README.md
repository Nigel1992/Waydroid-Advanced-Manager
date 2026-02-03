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
- ✅ Restore previous display settings (in-session)
- ✅ App export, search + uninstall
- ✅ Status view and self-update
- ✅ Batch APK install from a directory (interactive + CLI), with per-APK logging and end summary
- ✅ Batch uninstall from file or multi-select (interactive + CLI)
- ✅ Theme toggle (light/dark) with persistence to `~/.config/waydroid-manager.conf`
- ✅ Confirmations for destructive actions with `--yes/-y` override for automation
- ✅ New tablet and ultra-wide resolution presets
- ✅ CLI flags for non-interactive use
- ✅ Install/uninstall logs separated and rotated, plus logging verbosity

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

## ⚙️ CLI Flags (Non-Interactive)

```
--version, -v                Show version and exit
--help, -h                   Show help and exit
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
```

---

## 📝 Logging

Logs are written to:

```
~/.cache/waydroid-manager/waydroid-manager.log
~/.cache/waydroid-manager/install.log
~/.cache/waydroid-manager/uninstall.log
```

Install and uninstall actions are logged separately (per-APK results and batch summaries). Log files are rotated when they exceed 1 MB.

---

## 📋 Copy/Paste to Android (Option 9) — Important Notes

- Usage: focus the input field inside Android, select Option 9, type or paste text into your terminal and press ENTER. The script automatically sends the text to the currently active input box in Android.
- Supported: All plain text including special characters (e.g. `& | ; < > $ \` `). Newlines are not yet supported (single-line only).
- Safety: The tool only accepts plain text — files or binary data are not supported.

---

## 🧾 Changelog & Releases
See [`CHANGELOG.md`](CHANGELOG.md) for full history. Latest release: **v0.5.1** (2026-02-03).

---

## 📣 Contributing
Bug reports, PRs, and feature suggestions are welcome. Please open an issue with details and reproduction steps.

---

## 📜 License
See the `LICENSE` file in this repository.

---

> Built with care for the Waydroid community 💙  