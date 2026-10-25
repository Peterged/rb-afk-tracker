#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent
#Warn All, OutputDebug

#Include "%A_ScriptDir%\lib\Config.ahk"
#Include "%A_ScriptDir%\lib\Logger.ahk"
#Include "%A_ScriptDir%\lib\WindowApi.ahk"
#Include "%A_ScriptDir%\lib\FrameBuffer.ahk"
#Include "%A_ScriptDir%\lib\RapidOcrBridge.ahk"
#Include "%A_ScriptDir%\lib\WinRtOcr.ahk"
#Include "%A_ScriptDir%\lib\VisionParsers.ahk"
#Include "%A_ScriptDir%\lib\Status.ahk"
#Include "%A_ScriptDir%\lib\WindowTracker.ahk"
#Include "%A_ScriptDir%\lib\InputMonitor.ahk"
#Include "%A_ScriptDir%\lib\DisconnectDetector.ahk"
#Include "%A_ScriptDir%\lib\Hud.ahk"
#Include "%A_ScriptDir%\lib\Alerts.ahk"
#Include "%A_ScriptDir%\lib\Notifier.ahk"
#Include "%A_ScriptDir%\lib\Updater.ahk"
#Include "%A_ScriptDir%\lib\TrayMenu.ahk"

class SystemClock {
    Now() => A_TickCount
}

class App {
    __New() {
        this.settingsPath := A_ScriptDir "\settings.ini"
        this.statePath := A_ScriptDir "\state.ini"
        this.logPath := A_ScriptDir "\logs\events.log"

        this.cfg := Config(this.settingsPath)
        this.logger := Logger(this.logPath, this.cfg.LogMaxBytes)
        for w in this.cfg.Warnings
            this.logger.Warn(w)

        this.clock := SystemClock()
        this.winApi := WindowApi(this.cfg.RobloxSelector)
        this.tracker := WindowTracker(this.cfg, this.winApi, this.clock, this.statePath)
        restored := this.tracker.LoadState()
        this.detector := DisconnectDetector(this.cfg, this.winApi)
        this.ocr := WinRtOcr(this.cfg.RapidOcrEnabled)
        this.updater := Updater(this.cfg, this.logger, A_ScriptDir)
        this.logger.Info("Started Roblox AFK Monitor v" this.updater.LocalVersion() " (restored " restored " slot(s), OCR=" this.ocr.BackendName ")")

        this.sound := SoundPlayer(this.cfg)
        this.notifier := Notifier(this.cfg, this.logger, this.clock)
        this.alerts := Alerts(this.cfg, this.logger, this.sound, this.notifier)
        this.hud := Hud(this.cfg)

        hkList := [this.cfg.HkJump, this.cfg.HkAck, this.cfg.HkRename, this.cfg.HkToggleHud, this.cfg.HkMoveHud]
        this.input := InputMonitor(this.tracker, this.winApi, this.cfg.RobloxSelector, InputMonitor.KeysOf(hkList))
        this.tray := TrayMenu(this)
        this.RegisterHotkeys()

        this.cycleOrder := []
        this.cyclePos := 0
        this.cycleLastTick := 0

        OnError((err, mode) => this.OnUnhandledError(err, mode))
        OnExit((reason, code) => this.OnShutdown(reason))

        this.Tick()
        SetTimer(ObjBindMethod(this, "Tick"), 1000)
        if (this.cfg.DcEnabled || this.cfg.FreezeSeconds > 0 || this.cfg.OcrEnabled)
            SetTimer(ObjBindMethod(this, "ScanOneWindow"), this.cfg.DcScanIntervalMs)
        if (this.cfg.UpdateEnabled && this.cfg.UpdateRepo != "") {
            SetTimer(() => this.CheckForUpdates(false), -3000)
            SetTimer(() => this.CheckForUpdates(false), this.cfg.UpdateIntervalHours * 3600000)
        }
    }

    RegisterHotkeys() {
        this.BindHotkey(this.cfg.HkJump, "JumpToMostIdle")
        this.BindHotkey(this.cfg.HkAck, "Acknowledge")
        this.BindHotkey(this.cfg.HkRename, "RenameCurrent")
        this.BindHotkey(this.cfg.HkToggleHud, "ToggleHud")
        this.BindHotkey(this.cfg.HkMoveHud, "ToggleMoveHud")
    }

    BindHotkey(hk, method) {
        if (hk = "")
            return
        try {
            Hotkey(hk, (*) => this.%method%())
        } catch as e {
            this.logger.Warn("Could not bind hotkey '" hk "' for " method ": " e.Message)
        }
    }

    ; ------------------------------------------------------------------ timers
    Tick() {
        now := this.clock.Now()
        this.input.EnsureRunning()
        this.tracker.Refresh()
        this.notifier.Poll()

        slots := this.tracker.VisibleSlots()
        statuses := Map()
        for slot in slots
            statuses[slot.index] := Status.Evaluate(slot, now, this.cfg)

        this.alerts.Process(slots, statuses, now)

        header := Status.FormatHeader(slots, statuses, now, this.cfg)
        rows := []
        for slot in slots {
            st := statuses[slot.index]
            rows.Push({text: Status.FormatRow(slot, st, now, this.cfg), status: st})
        }
        alarm := this.alerts.HasUnackedProblem(statuses)
        this.hud.Render(header, rows, alarm)
        this.tray.Update(header.text, header.status)
    }

    ScanOneWindow() {
        slot := this.tracker.NextScanTarget()
        if !slot
            return
        ; Windows on another Virtual Desktop have their DWM surface paused by Windows,
        ; so skip pixel/freeze/OCR scans until you switch back to that desktop.
        if slot.otherDesktop
            return
        frame := FrameBuffer.Capture(slot.hwnd, this.winApi)
        if !frame
            return
        now := this.clock.Now()

        ; 1. Disconnect popup pixel classifier
        if this.cfg.DcEnabled {
            result := this.detector.CheckFrame(frame)
            this.tracker.SetDcResult(slot.hwnd, result)
            if (slot.dc && slot.dcReason = "" && this.cfg.OcrEnabled && this.ocr.Available) {
                modalText := this.ocr.RecognizeRegion(frame, this.cfg.VisionModalBox, 2)
                info := VisionParsers.ParseDisconnectReason(modalText)
                this.tracker.SetDcReason(slot.hwnd, info)
            }
        }

        ; 2. 3D viewport render-freeze detector (skip while DC modal covers the viewport)
        if (!slot.dc && this.cfg.FreezeSeconds > 0) {
            hash := frame.ComputeViewportHash(this.cfg.VisionViewportBox)
            this.tracker.UpdateFrameHash(slot.hwnd, hash, now)
        }

        ; 3. In-game HUD OCR (Cash, Friend Boost %, Event/Buff timers)
        if (!slot.dc && this.cfg.OcrEnabled && this.ocr.Available) {
            ocrIntervalMs := this.cfg.OcrStatsIntervalSec * 1000
            if (slot.lastOcrTick = 0 || now - slot.lastOcrTick >= ocrIntervalMs) {
                statsText := this.ocr.RecognizeHudRegion(frame, this.cfg.VisionStatsBox)
                timersText := this.ocr.RecognizeHudRegion(frame, this.cfg.VisionTimersBox)
                stats := VisionParsers.ParseStats(statsText)
                timers := VisionParsers.ParseTimers(timersText)
                this.tracker.UpdateVisionStats(slot.hwnd, stats, timers, now)
            }
        }
    }

    ; ----------------------------------------------------------------- actions
    JumpToMostIdle() {
        now := this.clock.Now()
        if (now - this.cycleLastTick > 3000 || !this.cycleOrder.Length) {
            this.cycleOrder := []
            for slot in this.tracker.UrgencyOrder(now)
                this.cycleOrder.Push(slot.hwnd)
            this.cyclePos := 0
        }
        this.cycleLastTick := now
        loop this.cycleOrder.Length {
            this.cyclePos := Mod(this.cyclePos, this.cycleOrder.Length) + 1
            hwnd := this.cycleOrder[this.cyclePos]
            if this.winApi.Exists(hwnd) {
                this.winApi.Activate(hwnd)
                return
            }
        }
    }

    Acknowledge() {
        this.alerts.Acknowledge()
        this.tracker.ClearMissing()
        this.Tick()
    }

    RenameCurrent() {
        hwnd := this.winApi.Active()
        if !hwnd
            hwnd := this.tracker.lastInputHwnd
        slot := hwnd ? this.tracker.SlotOf(hwnd) : ""
        if !slot {
            MsgBox("Focus a Roblox window (or click in one first), then press " this.cfg.HkRename " to rename its slot.",
                "Rename window", "Iconi")
            return
        }
        ib := InputBox("New label for slot #" slot.index " (max 12 chars):", "Rename " slot.label, "w260 h120", slot.label)
        if (ib.Result = "OK" && Trim(ib.Value) != "") {
            name := this.cfg.SetLabel(slot.index, ib.Value)
            if (name != "") {
                slot.label := name
                this.logger.Info("Renamed slot #" slot.index " to '" name "'")
                this.Tick()
            }
        }
    }

    SetExpectedToCurrent() {
        count := Max(1, this.tracker.LiveCount())
        this.cfg.SetExpected(count)
        this.tracker.ClearMissing()
        this.logger.Info("ExpectedInstances set to " count)
        this.Tick()
    }

    Calibrate() {
        hwnd := this.winApi.Active()
        if !hwnd {
            slots := this.tracker.UrgencyOrder(this.clock.Now())
            if slots.Length
                hwnd := slots[1].hwnd
        }
        if !hwnd {
            MsgBox("No Roblox window found to sample.", "Calibrate disconnect color", "Icon!")
            return
        }
        info := this.detector.Calibrate(hwnd)
        if !info {
            MsgBox("Could not capture the window (is it minimized or hung?).", "Calibrate disconnect color", "Icon!")
            return
        }
        this.logger.Info(Format("Calibrate hwnd 0x{:X}: suggested=0x{:06X} result={}`n{}",
            hwnd, info.suggested, info.result, RTrim(info.text, "`n")))
        prompt := Format("Sampled points (x, y -> color):`n`n{}`nMost common: 0x{:06X}`nCurrent setting: 0x{:06X} (+/-{}) -> {}`n`nSave 0x{:06X} as Disconnect.Color?",
            info.text, info.suggested, this.cfg.DcColor, this.cfg.DcTolerance, info.result, info.suggested)
        if (MsgBox(prompt, "Calibrate disconnect color", "YesNo Icon?") = "Yes") {
            this.cfg.SetDcColor(info.suggested)
            this.logger.Info(Format("Disconnect.Color updated to 0x{:06X}", info.suggested))
        }
    }

    ToggleHud() {
        this.hud.ToggleVisible()
        this.tray.SyncChecks()
    }

    ToggleMoveHud() {
        this.hud.ToggleMoveMode()
        this.tray.SyncChecks()
        if !this.hud.moveMode
            this.Tick()
    }

    ToggleMute() {
        this.cfg.SetSoundsEnabled(!this.cfg.SoundsEnabled)
        this.tray.SyncChecks()
    }

    ToggleKeepRenderable() {
        this.cfg.SetKeepRenderable(!this.cfg.KeepRenderable)
        this.tray.SyncChecks()
        this.Tick()
    }

    StartupShortcutPath() => A_Startup "\Roblox AFK Monitor.lnk"

    IsStartWithWindowsEnabled() => FileExist(this.StartupShortcutPath()) != ""

    ToggleStartWithWindows() {
        lnkPath := this.StartupShortcutPath()
        if FileExist(lnkPath) {
            try FileDelete(lnkPath)
            this.logger.Info("Removed Start with Windows shortcut")
        } else {
            target := FileExist(A_ScriptDir "\RobloxAfkMonitor.exe") ? (A_ScriptDir "\RobloxAfkMonitor.exe") : A_ScriptFullPath
            try {
                FileCreateShortcut(target, lnkPath, A_ScriptDir, "", "Roblox Multi-Instance AFK Monitor")
                this.logger.Info("Created Start with Windows shortcut -> " target)
            } catch as e {
                MsgBox("Could not create Startup shortcut:`n" e.Message, "Start with Windows", "Icon!")
            }
        }
        this.tray.SyncChecks()
    }

    CheckForUpdates(interactive := false) {
        this.updater.CheckAndApply(interactive, () => (this.tracker.SaveState(), Reload()))
    }

    InspectVision() {
        hwnd := this.winApi.Active()
        if !hwnd {
            slots := this.tracker.UrgencyOrder(this.clock.Now())
            if slots.Length
                hwnd := slots[1].hwnd
        }
        if !hwnd {
            MsgBox("No Roblox window found to inspect.", "Inspect window CV", "Icon!")
            return
        }
        frame := FrameBuffer.Capture(hwnd, this.winApi)
        if !frame {
            MsgBox("Could not capture the window (is it minimized or hung?).", "Inspect window CV", "Icon!")
            return
        }
        dcRes := this.detector.CheckFrame(frame)
        vpHash := frame.ComputeViewportHash(this.cfg.VisionViewportBox)
        cashBand := frame.AutoLocateCashBand(this.cfg.VisionStatsBox)
        bandStr := (cashBand is Array) ? Format("[{:.2f}, {:.2f}, {:.2f}, {:.2f}]", cashBand[1], cashBand[2], cashBand[3], cashBand[4]) : "(none found)"
        statsRaw := this.ocr.Available ? this.ocr.RecognizeHudRegion(frame, this.cfg.VisionStatsBox) : "(OCR unavailable)"
        timersRaw := this.ocr.Available ? this.ocr.RecognizeHudRegion(frame, this.cfg.VisionTimersBox) : "(OCR unavailable)"
        modalRaw := this.ocr.Available ? this.ocr.RecognizeRegion(frame, this.cfg.VisionModalBox, 2) : "(OCR unavailable)"
        stats := VisionParsers.ParseStats(statsRaw)
        timers := VisionParsers.ParseTimers(timersRaw)
        dcInfo := VisionParsers.ParseDisconnectReason(modalRaw)

        report := Format(
            "Window: 0x{:X} ({}x{})  OCR Backend: {}`n"
            . "Disconnect pixel check: {}`n"
            . "Viewport 64-bit hash: 0x{:016X}`n"
            . "Auto-located Cash Band: {}`n`n"
            . "--- Bottom-Left Stats OCR ---`nRaw: {}`nParsed: Cash='{}'  Boost={}%  Income='{}'`n`n"
            . "--- Bottom-Right Timers OCR ---`nRaw: {}`nParsed: NextEvent='{}'  ActiveBuff='{}'`n`n"
            . "--- Center Modal OCR ---`nRaw: {}`nParsed: Code='{}'  Detail='{}'",
            hwnd, frame.width, frame.height, this.ocr.BackendName, dcRes, vpHash, bandStr,
            Trim(statsRaw), stats.cash, stats.boost, stats.income,
            Trim(timersRaw), timers.nextEvent, timers.activeBuff,
            Trim(modalRaw), dcInfo.code, dcInfo.detail
        )
        this.logger.Info("CV Inspect:`n" report)
        MsgBox(report, "Inspect current window CV", "Iconi")
    }

    TestNotify() {
        if !this.notifier.Enabled {
            MsgBox("Set [Ntfy] Topic in settings.ini first, then choose Reload settings.",
                "ntfy push not configured", "Iconi")
            return
        }
        this.notifier.Notify("test", "Roblox AFK Monitor", "Test notification from Roblox AFK Monitor", 3, true)
    }

    OpenSettings() {
        if !FileExist(this.settingsPath)
            this.cfg.WriteDefaults()
        try Run('notepad.exe "' this.settingsPath '"')
    }

    OpenLog() {
        if !FileExist(this.logPath)
            this.logger.Info("Log opened")
        try Run('notepad.exe "' this.logPath '"')
    }

    OnUnhandledError(err, mode) {
        this.logger.Error(Format("Unhandled error: {} at {}:{} ({})", err.Message, err.File, err.Line, err.What))
        return 1   ; suppress default popup and keep running
    }

    OnShutdown(reason) {
        this.tracker.SaveState()
        this.logger.Info("Stopped (" reason ")")
    }
}

; Support `--exit-after=N` for automated startup smoke testing.
for arg in A_Args {
    if RegExMatch(arg, "^--exit-after=(\d+)$", &m)
        SetTimer(() => ExitApp(0), Max(1, Integer(m[1])) * 1000)
}

global gApp := App()
