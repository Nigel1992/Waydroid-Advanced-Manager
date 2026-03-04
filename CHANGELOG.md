
# 2026-03-04

## Release v0.8.0

### Added / Changed
- **Resource Monitor**: Now updates in-place, showing live CPU/RAM/Disk stats without scrolling or flicker.
- **Session Attach Fixes**: Attaching to an existing ADB session now enables all features (no more "Waydroid is not running" errors).
- **Improved Session Detection**: Smarter fallback logic for ADB device adoption and session status.
- **Bug Fixes**: Quoting, session attach, monitor display, and syntax issues resolved.

---

# 2026-03-04

## Release v0.7.0

### Added — New Tools Menu
- **Screenshot Capture** (Option 10): Take a screenshot of the Android screen via ADB and save it to `~/Pictures/Waydroid/`. Offers to open the image after capture.
- **Screen Recording** (Option 11): Record the Android screen (up to 180 seconds) and save to `~/Videos/Waydroid/`. Offers to open the video after recording.
- **File Transfer** (Option 12): Push files to or pull files/folders from Android. Supports zenity file picker dialogs or manual path entry.
- **Logcat Viewer** (Option 13): View live logcat output, save last 500 lines to file, filter by tag, or show errors only.
- **Freeze/Disable Apps** (Option 14): Disable (freeze) apps without uninstalling, re-enable them later, and list all disabled packages. Uses zenity app picker when available.
- **Clear App Data/Cache** (Option 15): Clear all data or just cache for a selected app. Supports zenity app picker.
- **Quick Launch App** (Option 16): Launch any installed third-party app by selecting its package name.
- **Device Info Panel** (Option 17): Comprehensive device overview showing Android version, SDK level, display resolution/density, storage, memory, network, uptime, and installed package count.

### Changed
- **Reorganized main menu**: Options grouped into four sections — Core, ADB, Settings & Apps, Tools, and System — for easier navigation.
- **Menu now has 21 options**: Previous options 10-13 renumbered to 18-21 (Status, Theme, Check for Updates, Exit).
- **DRY refactor**: Replaced repetitive "Waydroid not running" checks in the case statement with a shared `_require_running` helper function.

# 2026-03-04

## Release v0.6.0

### Added
- **Auto-detect existing sessions on launch**: The script now checks if Waydroid is already running or ADB devices are connected at startup, displays session info, and offers to connect automatically.
- **Update check shows GitHub URL**: When an update is available, the GitHub repository URL is displayed in the console and the user is prompted to open it in their default browser (`xdg-open`).
- **Weston compositor window focus**: Before showing APK install dialogs, the Weston compositor window is brought to the foreground via `xdotool` (matched by window class, not name, to avoid focusing unrelated windows).
- **Clear terminal on startup**: The terminal is cleared before the script begins for a clean launch experience.

### Changed
- **Option 1 renamed**: "START/RESTART Waydroid Full Stack" → "START/RESTART Waydroid".
- **Option 12 changed**: "SELF UPDATE" (git pull) replaced with "CHECK FOR UPDATES" — now runs the same GitHub version check as the startup update prompt.
- **Zenity dialogs use `--modal`**: All APK install zenity dialogs now use `--modal` to stay on top of the Weston window.
- **Fix: Version/colors defined before update check**: `SCRIPT_VERSION`, `RELEASE_DATE`, and color variables are now defined at the top of the script before `check_for_updates()` is called, fixing the empty "Current:" display in the update prompt.

### Dependencies
- `xdotool` is now used (optional) for Weston window focusing. Install with `sudo apt install xdotool`.

# 2026-02-03

## Release v0.5.1
- Added: Batch APK installer (`--install-apks-dir`) to install all `.apk` files from a directory (interactive + CLI), with per-APK logging and a summary report.
- Added: Batch uninstall from file (`--uninstall-list`) and interactive multi-select batch uninstall.
- Added: Confirmation helper and `--yes|-y` override for scripting/automation of destructive actions.
- Added: Download verification (Content-Length check) and sha256 logging for APK downloads.
- Added: Separate `install.log` and `uninstall.log` files and rotation support.
- Added: Theme toggle (light/dark) with persistence to `~/.config/waydroid-manager.conf` and an interactive theme chooser.
- Added: Tablet and Ultra-wide resolution presets (1200x1920, 3440x1440).
- Changed: Bumped script to **v0.5.1** and documented new CLI flags in `README.md`.

# 2026-01-31

## Release v0.4.0
- Released v0.4.0: includes copy/paste special-character fix, UI header version/date, and `--version` CLI flag. See entries below for details.

### Fixed
- Option 9 (Copy/Paste to Android): properly escape shell metacharacters (e.g. `&`, `|`, `;`, `<`, `>`, `$`, backticks and backslashes) so special characters are transmitted correctly to Android when using `input text`. Updated `README.md` to note that special characters are supported, and added guidance for testing.
- Minor: Improved robustness of text escaping to avoid clobbering backslashes.

### Added
- UI header now displays the script version and release date for easier identification when running the manager.
- CLI: `--version` / `-v` support to print the script version and release date and exit. Version is embedded in the script (`SCRIPT_VERSION`) rather than a separate `VERSION` file.

# 2026-01-29

### Fixed
- Restart logic now robustly handles Weston and Wayland socket lifecycle, ensuring clean shutdown and startup.
- Weston is now always launched with the X11 backend (`--backend=x11-backend.so`), fixing fatal errors when running under X11 sessions.
- Improved error reporting: if Weston fails to start, the script logs and displays the error output for easier debugging.

### Notes
- These changes resolve issues where the UI would not relaunch after a restart, and provide clear diagnostics if Weston or the Wayland socket fails.

# Changelog

All notable changes to this project are documented here.

## 2026-01-25

### Changed
- Option 9 (Copy/Paste to Android) now only accepts plain text input from the terminal. The script clearly instructs users to open and focus the input field on Android before sending text, and warns that only plain text is supported (files or non-text data will not work).
- Removed all GUI/Zenity prompts from the copy/paste flow for a more reliable terminal-only experience.

### Notes
- This update improves clarity and reliability for users who need to send text to Android via ADB, especially in non-GUI environments.

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
