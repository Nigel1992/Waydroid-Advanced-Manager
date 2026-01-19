# Changelog

All notable changes to this project are documented here.

## [Unreleased] - 2026-01-19
### Added
- Zenity-based graphical "Uninstall from list" dialog for selecting apps to uninstall.
- APK installer: option to install from a local file or a direct URL (downloads to /tmp and installs).
- `copy_paste_to_android` helper: prompts for text (Zenity or terminal) and copies to host Wayland clipboard via `wl-copy` for easy pasting into Android.
- Display settings: added "Reset Display Settings" (runs `sudo waydroid shell wm size reset` and `sudo waydroid shell wm density reset`).

### Changed
- Main menu safety: options that modify Waydroid or apps now require Waydroid to be running; messages instruct to start via option 1.
- Improved error handling and ADB reconnection logic across app management flows.
- Added APK download validation guidance and fallback behavior.

### Notes
- `wl-clipboard` (`wl-copy`) is required for the copy/paste helper to work on Wayland sessions.
- Zenity is optional; the script falls back to terminal input when GUI dialog commands fail.


## 2024-xx-xx - Previous Releases
- See earlier commits for historical changes.
