; =============================================================================
; TrayMenu.ahk - Tray menu, tooltip and status icon.
; `app` is the RobloxAfkMonitor App object; menu items just call its actions.
; =============================================================================

class TrayMenu {
    static Items := Map(
        "hud", "Show/Hide HUD",
        "move", "Move HUD",
        "keepRender", "Keep windows renderable (no MIN)",
        "startup", "Start with Windows",
        "ack", "Acknowledge alerts",
        "rename", "Rename current window...",
        "expected", "Set expected = current count",
        "inspectCv", "Inspect current window CV...",
        "calibrate", "Calibrate disconnect color...",
        "mute", "Mute sounds",
        "test", "Send test notification",
        "testDiscord", "Send test Discord egg alert",
        "update", "Check for updates...",
        "settings", "Open settings.ini",
        "reload", "Reload settings",
        "log", "Open log",
        "exit", "Exit"
    )

    __New(app) {
        this.app := app
        this.level := ""
        n := TrayMenu.Items
        m := A_TrayMenu
        m.Delete()
        m.Add(n["hud"], (*) => app.ToggleHud())
        m.Add(n["move"], (*) => app.ToggleMoveHud())
        m.Add(n["keepRender"], (*) => app.ToggleKeepRenderable())
        m.Add(n["startup"], (*) => app.ToggleStartWithWindows())
        m.Add()
        m.Add(n["ack"], (*) => app.Acknowledge())
        m.Add(n["rename"], (*) => app.RenameCurrent())
        m.Add(n["expected"], (*) => app.SetExpectedToCurrent())
        m.Add(n["inspectCv"], (*) => app.InspectVision())
        m.Add(n["calibrate"], (*) => app.Calibrate())
        m.Add(n["mute"], (*) => app.ToggleMute())
        m.Add(n["test"], (*) => app.TestNotify())
        m.Add(n["testDiscord"], (*) => app.TestDiscordNotify())
        m.Add()
        m.Add(n["update"], (*) => app.CheckForUpdates(true))
        m.Add(n["settings"], (*) => app.OpenSettings())
        m.Add(n["reload"], (*) => Reload())
        m.Add(n["log"], (*) => app.OpenLog())
        m.Add()
        m.Add(n["exit"], (*) => ExitApp())
        m.Default := n["hud"]
        this.SyncChecks()
    }

    SyncChecks() {
        m := A_TrayMenu, n := TrayMenu.Items
        if this.app.hud.visible
            m.Check(n["hud"])
        else
            m.Uncheck(n["hud"])
        if this.app.hud.moveMode
            m.Check(n["move"])
        else
            m.Uncheck(n["move"])
        if this.app.cfg.KeepRenderable
            m.Check(n["keepRender"])
        else
            m.Uncheck(n["keepRender"])
        if this.app.IsStartWithWindowsEnabled()
            m.Check(n["startup"])
        else
            m.Uncheck(n["startup"])
        if this.app.cfg.SoundsEnabled
            m.Uncheck(n["mute"])
        else
            m.Check(n["mute"])
    }

    Update(headerText, worst) {
        ver := this.app.updater ? " v" this.app.updater.LocalVersion() : ""
        A_IconTip := SubStr("Roblox AFK Monitor" ver "`n" headerText, 1, 127)
        level := Status.IsProblem(worst) ? "error" : (worst = "WARN") ? "warn" : "ok"
        if (level = this.level)
            return
        this.level := level
        try {
            switch level {
                case "ok": TraySetIcon("*")
                case "warn": TraySetIcon("user32.dll", 2)    ; exclamation
                case "error": TraySetIcon("user32.dll", 4)   ; error
            }
        }
    }
}
