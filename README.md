# Roblox Multi-Instance AFK Monitor

An AutoHotkey v2 overlay and alert tool for running multiple Roblox windows at once.

**It never sends keys, clicks, or messages to Roblox.** It only watches your own physical inputs, tracks each window's 20-minute idle clock separately, checks for the grey disconnect dialog, and warns you before a client gets kicked.

## One-Click Installer (For Your Friend — No AutoHotkey Install Needed)
Send your friend **`dist\Setup-RobloxAfkMonitor.exe`** (0.66 MB):
- Bundles the official `AutoHotkey64.exe` v2 runtime inside `bin\AutoHotkey64.exe` — your friend does **not** need to install AutoHotkey.
- Extracts to `%LOCALAPPDATA%\Programs\RobloxAfkMonitor` (zero administrator / UAC prompts).
- Creates **Desktop** and **Start Menu** shortcuts (`Roblox AFK Monitor`) and launches the monitor immediately.
- Includes `Uninstall.bat` in the install folder and a **Start with Windows** toggle in the Tray menu.

## Pushing Zero-Reinstall Updates to Your Friend (OTA Auto-Updater)
1. **One-time GitHub repo setup**:
   - Create a public GitHub repository (e.g. `https://github.com/yourname/roblox-afk-monitor`) and set it as your git `origin`.
   - Set `Repo=yourname/roblox-afk-monitor` under `[Update]` in `settings.ini` (or set the default in `lib/Config.ahk` before building `dist\Setup-RobloxAfkMonitor.exe`).
2. **Publishing an update in one command**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\publish.ps1 -BumpPatch -Push -Message "Describe your change"
   ```
   `publish.ps1` automatically:
   - Validates syntax and runs all 37 unit tests (`tests\RunTests.ahk`).
   - Bumps `VERSION` (`1.0.0` -> `1.0.1`) and generates `manifest.json` with SHA-256 hashes for every file.
   - Rebuilds `RobloxAfkMonitor.exe` and `dist\Setup-RobloxAfkMonitor.exe`.
   - Commits and pushes to GitHub when `-Push` is passed.
3. **How your friend gets the update**:
   - Automatically on startup, every 6 hours in the background, or immediately via **Tray -> Check for updates...**
   - `lib/Updater.ahk` compares `manifest.json`, downloads only modified files into `.update_stage\`, verifies every file's **SHA-256 hash** via Windows CNG (`bcrypt.dll`), swaps them in atomically without touching `settings.ini` or `state.ini`, and hot-reloads in place.

## Running Locally
Double-click **`RobloxAfkMonitor.exe`** (or `Start Roblox AFK Monitor.bat`, or `RobloxAfkMonitor.ahk`).
You can also pin `RobloxAfkMonitor.exe` to your Taskbar or Start Menu.

On first launch it creates `settings.ini` next to the executable and puts an icon in the system tray.

## Hotkeys (all configurable in `settings.ini`)
| Key | Action |
|---|---|
| `F7` | Focus the most urgent / most-idle Roblox window. Press again within 3 s to cycle through the rest in urgency order. |
| `Shift+F7` | Acknowledge current alerts (stops the flashing HUD and repeat sounds for existing issues, and clears `MISSING` rows). |
| `F8` | Rename the active Roblox window's slot label (`Main`, `Alt1`, ...). |
| `F9` | Show / hide the HUD. *(Note: `F9` also opens Roblox's Developer Console; change `ToggleHud` in `settings.ini` if you use it.)* |
| `Shift+F9` | Toggle HUD **Move Mode** — drag the HUD anywhere, then press `Shift+F9` again to lock and save. |

## Reading the HUD
```
5/5  next: Alt2 kick 03:58
Main     OK      02:14  kick 17:46
Alt1     OK~     04:01  kick 15:59
Alt2     WARN    16:02  kick 03:58  VD
Alt3     FROZEN  05:10  kick 14:50
Alt4     DC      01:12  kick 18:48 [IDLE20]
```
- **`OK` / `WARN` (15m) / `URGENT` (18m)**: per-window idle state against Roblox's 20-minute kick.
- **Virtual Desktop Support (`VD`)**: You can move any or all Roblox windows to another Windows 10/11 Virtual Desktop (`Win+Tab`). The monitor detects windows across all virtual desktops (`DetectHiddenWindows` + `IVirtualDesktopManager::IsWindowOnCurrentVirtualDesktop`), never mistakes them for `MISSING`, shows a `VD` tag on their row while you're on another desktop, and lets `F7` jump straight to that desktop when it's time to check in.
- **`~` after a status (`OK~`)**: you haven't pressed a key or mouse button in this window since the monitor started, so its real idle time inside Roblox could be older than shown.
- **`MIN` & Keep Windows Renderable (`KeepRenderable=1`)**: Windows stops drawing minimized windows. When `KeepRenderable=1` (on by default, toggleable in the Tray menu), the monitor automatically un-minimizes background Roblox clients behind your active window (`SW_SHOWNOACTIVATE` + `HWND_BOTTOM`) without stealing focus so CV and disconnect detection can see all 5 clients.
- **`DC [REASON]`**: the grey disconnect popup was detected on 2 consecutive scans, and OCR classified the exact popup text (`[IDLE20]`, `[SAME_ACCT]`, `[NET]`, `[SHUTDOWN]`, `[KICKED]`, `[ERR_277]`).
- **`FROZEN`**: the 3D viewport's 64-bit pixel hash has been 100% static for `FreezeSeconds` (default 45 s), catching silent render freezes where Windows does not mark the window "Not Responding".
- **`HUNG`**: Windows reports the client as "Not Responding" for more than `HungGraceSeconds`.
- **`MISSING`**: a window closed or crashed. Launching a new client reuses that slot and keeps its label.

## Inspecting & Calibrating Computer Vision
- **Inspect current window CV**: Choose **Tray -> Inspect current window CV...** to capture a Roblox client and display the live disconnect check, 64-bit viewport hash, and raw + parsed OCR output.
- **Calibrate disconnect color**: If a theme, shader, or future Roblox update changes the disconnect dialog's shade of grey:
  1. Leave a Roblox window with the disconnect popup visible (not minimized).
  2. Focus it (or make it the most-idle window) and choose **Tray -> Calibrate disconnect color...**
  3. Click **Yes** to save the sampled color to `settings.ini`.

## Phone Notifications (ntfy.sh)
1. Install the [ntfy app](https://ntfy.sh) on your phone and subscribe to a **long, random topic name** (topics on `ntfy.sh` are public).
2. Open **Tray -> Open settings.ini**, set `Topic=your-secret-topic-name` under `[Ntfy]`, and choose **Tray -> Reload settings**.
3. Choose **Tray -> Send test notification** to verify. By default, pushes only fire when you've been away from the PC for 2+ minutes (`OnlyWhenAway=1`).

## Running the Tests & Building Installer
```powershell
powershell -ExecutionPolicy Bypass -File .\publish.ps1
```
