# Changelog

All notable changes to this project are documented here.

## (2026-01-19)

This release consolidates a series of improvements made since commit `3553f3a` up to the current HEAD. Highlights include new UX flows, safety checks, clipboard helpers, APK installer enhancements, and documentation updates.

### Added
- Zenity-based graphical "Uninstall from list" dialog for selecting apps to uninstall.
- APK installer: choice to install from a local APK file or a direct URL (downloads to `/tmp` then installs).
- `copy_paste_to_android` helper: prompts for text (Zenity if available, otherwise terminal) and copies to the host Wayland clipboard using `wl-copy` for easy pasting into Android.
- Display settings: added "Reset Display Settings" which runs `sudo waydroid shell wm size reset` and `sudo waydroid shell wm density reset`.
- Full README and installation updates (instructions to install required packages for full functionality).

### Changed / Fixed
- Main menu safety: critical options (stop, install, scripts, reconnect, display, app management, copy/paste) now check that Waydroid is running and provide guidance to start it (option 1) if not.
- APK-from-URL flow: added download logic with `curl`/`wget` fallback and guidance for validating downloaded APKs; script now handles common download failures more gracefully.
- Copy/paste: Zenity input now attempts to set `WAYLAND_DISPLAY`/`DISPLAY` when needed and falls back to terminal input; script validates presence of `wl-copy`.
- Menu renumbering and UX polish (exit and copy/paste option numbering adjusted, consistent prompts and pause screens).
- Improved ADB reconnect and device-check logic used across app-management flows.

### Notes
- `wl-clipboard` (`wl-copy`) is required for the copy/paste helper on Wayland. The script will tell users to install it if missing.
- `zenity` is optional; the script falls back to terminal input when GUI dialog commands fail.
- APK downloads must point to direct `.apk` files (no HTML redirects). Use `curl -fL` or `wget -O` to test downloads if needed.


## 2025-xx-xx - Previous Releases
- See earlier commits for historical changes.
