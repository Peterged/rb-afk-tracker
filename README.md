# Roblox Multi-Instance AFK Monitor

A lightweight Windows overlay that tracks the 20-minute idle timer across multiple Roblox windows and warns you before an account gets kicked.

![HUD Preview](assets/hud-preview.png)

It never sends keys, mouse clicks, or messages to Roblox. Instead, it watches your own keyboard and mouse input, keeps a separate countdown for each client, checks for disconnect popups or frozen screens, and lets you jump straight to whichever window needs attention next.

## Install

Download and run **`Setup-RobloxAfkMonitor.exe`** (built into `dist\Setup-RobloxAfkMonitor.exe`).

- **No dependencies:** AutoHotkey v2 is bundled inside `bin\AutoHotkey64.exe`, so you don't need to install anything else.
- **No admin prompt:** Installs to `%LOCALAPPDATA%\Programs\RobloxAfkMonitor` and adds shortcuts to your Desktop and Start Menu.
- **Automatic updates:** On launch (and every 6 hours), the app checks this repo's `manifest.json`, verifies file SHA-256 hashes, and reloads in place without touching your `settings.ini` or saved window slots. You can also trigger a check manually from **Tray -> Check for updates...**

If you cloned the repo directly, double-click **`RobloxAfkMonitor.exe`** (or `Start Roblox AFK Monitor.bat`). On first run, it generates `settings.ini` and sits in your system tray.

## Hotkeys

All shortcuts can be changed in `settings.ini`:

| Key | Action |
|---|---|
| `F7` | Focus the most urgent or longest-idle Roblox window. Press `F7` again within 3 seconds to cycle through the rest in urgency order. |
| `Shift+F7` | Acknowledge current alerts. Stops the flashing HUD and repeat sounds for existing issues, and clears `MISSING` rows. |
| `F8` | Rename the active Roblox window (`Main`, `Alt1`, etc.). |
| `F9` | Show or hide the HUD. *(Note: `F9` also opens Roblox's Developer Console; change `ToggleHud` in `settings.ini` if you use it.)* |
| `Shift+F9` | Unlock the HUD so you can drag it anywhere on screen. Press `Shift+F9` again to lock and save its position. |

## Reading the HUD

```text
1/1  next: Main Acc kick 16:23
Main Acc OK      03:37  kick 16:23 MIN
```

- **`OK` / `WARN` (15m) / `URGENT` (18m)**: How close the window is to Roblox's 20-minute idle kick.
- **`~` (`OK~`)**: You haven't pressed a key or clicked inside this window since the monitor started, so its real in-game idle time may be older than shown.
- **`VD` (Virtual Desktops)**: You can keep Roblox clients on a separate Windows 10/11 Virtual Desktop (`Win+Tab`). They won't trigger false `MISSING` or `FROZEN` alerts while you're on another desktop, and pressing `F7` switches right over to them when it's time to check in.
- **`MIN` (Minimized)**: Shows when a client is minimized. When **Keep windows renderable** (`KeepRenderable=1`) is enabled in the tray menu, minimized clients are quietly restored behind your active window so pixel and disconnect checks can still see them.
- **`DC [REASON]`**: The grey disconnect dialog was detected on two consecutive scans. When OCR is enabled, it tags the reason (`[IDLE20]`, `[SAME_ACCT]`, `[NET]`, `[SHUTDOWN]`, `[KICKED]`, `[ERR_277]`).
- **`FROZEN`**: The 3D viewport hasn't changed a single pixel for `FreezeSeconds` (default 45 s), catching silent freezes where Windows still thinks the process is responding.
- **`HUNG`**: Windows reports the window as "Not Responding" for longer than `HungGraceSeconds`.
- **`MISSING`**: A tracked client closed or crashed. Opening a new Roblox window reclaims that slot and keeps its label.

## Phone Notifications (ntfy.sh)

If you step away from your desk, the monitor can push alerts to your phone through [ntfy.sh](https://ntfy.sh):

1. Install the ntfy app on your phone and subscribe to a long, random topic name (public topics aren't password-protected, so make the name hard to guess).
2. Click **Tray -> Open settings.ini**, set `Topic=your-topic-name` under `[Ntfy]`, and click **Tray -> Reload settings**.
3. Click **Tray -> Send test notification** to make sure it reaches your phone. By default, notifications only send when you haven't touched the keyboard or mouse for 2 minutes (`OnlyWhenAway=1`).

## Calibrating Disconnect Detection

If a custom shader, Bloxstrap theme, or Roblox update changes the color of the grey disconnect box:

1. Leave a Roblox window open with the disconnect popup visible.
2. Focus that window and select **Tray -> Calibrate disconnect color...**
3. Click **Yes** to save the sampled RGB value to `settings.ini`.

## Publishing Updates

To run the test suite, update `manifest.json`, rebuild `RobloxAfkMonitor.exe` and `dist\Setup-RobloxAfkMonitor.exe`, and push a new release to GitHub:

```powershell
powershell -ExecutionPolicy Bypass -File .\publish.ps1 -BumpPatch -Push -Message "Describe your change"
```
