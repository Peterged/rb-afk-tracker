; =============================================================================
; Config.ahk - Loads, validates and persists settings.ini.
;
; Every setting is described once in Config.Schema. Invalid values never crash
; the script: they fall back to the default and a warning is collected in
; Config.Warnings (the app logs them once the Logger exists).
; =============================================================================

class Config {
    static MISSING := Chr(1) "missing"
    static DefaultLabels := ["Main", "Alt1", "Alt2", "Alt3", "Alt4"]
    static MaxSlots := 20

    ; [section, key, property, type, default, min, max]
    ; Types: int, num, bool, color, list (comma separated 0..1 floats),
    ;        str (non-empty), str? (may be empty), hotkey (may be empty)
    static Schema := [
        ["General", "ExpectedInstances", "ExpectedInstances", "int", 5, 1, 20],
        ["General", "RobloxSelector", "RobloxSelector", "str", "ahk_class WINDOWSCLIENT ahk_exe RobloxPlayerBeta.exe"],
        ["General", "KickSeconds", "KickSeconds", "int", 1200, 60, 86400],
        ["General", "WarnSeconds", "WarnSeconds", "int", 900, 10, 86400],
        ["General", "UrgentSeconds", "UrgentSeconds", "int", 1080, 20, 86400],
        ["General", "HungGraceSeconds", "HungGraceSeconds", "int", 10, 0, 3600],
        ["General", "RepeatAlertSeconds", "RepeatAlertSeconds", "int", 30, 0, 3600],
        ["General", "SoundsEnabled", "SoundsEnabled", "bool", 1],
        ["Hud", "Visible", "HudVisible", "bool", 1],
        ["Hud", "X", "HudX", "int", -1, -100000, 100000],
        ["Hud", "Y", "HudY", "int", 15, -100000, 100000],
        ["Hud", "Opacity", "HudOpacity", "int", 215, 50, 255],
        ["Hud", "FontSize", "HudFontSize", "int", 10, 6, 32],
        ["Hotkeys", "JumpToMostIdle", "HkJump", "hotkey", "F7"],
        ["Hotkeys", "Acknowledge", "HkAck", "hotkey", "+F7"],
        ["Hotkeys", "RenameCurrent", "HkRename", "hotkey", "F8"],
        ["Hotkeys", "ToggleHud", "HkToggleHud", "hotkey", "F9"],
        ["Hotkeys", "MoveHud", "HkMoveHud", "hotkey", "+F9"],
        ["Disconnect", "Enabled", "DcEnabled", "bool", 1],
        ["Disconnect", "ScanIntervalMs", "DcScanIntervalMs", "int", 1000, 250, 60000],
        ["Disconnect", "Color", "DcColor", "color", 0x393B3D],
        ["Disconnect", "Tolerance", "DcTolerance", "int", 8, 0, 64],
        ["Disconnect", "SampleX", "DcSampleX", "list", "0.40,0.45,0.50,0.55,0.60"],
        ["Disconnect", "SampleY", "DcSampleY", "list", "0.42,0.50"],
        ["Disconnect", "MinMatchRatio", "DcMinMatchRatio", "num", 0.8, 0.1, 1.0],
        ["Disconnect", "ConfirmScans", "DcConfirmScans", "int", 2, 1, 20],
        ["Vision", "ShowStatsInHud", "ShowStatsInHud", "bool", 0],
        ["Vision", "KeepRenderable", "KeepRenderable", "bool", 1],
        ["Vision", "OcrEnabled", "OcrEnabled", "bool", 0],
        ["Vision", "RapidOcrEnabled", "RapidOcrEnabled", "bool", 0],
        ["Vision", "OcrStatsIntervalSec", "OcrStatsIntervalSec", "int", 4, 2, 600],
        ["Vision", "AlertOnBoostDrop", "AlertOnBoostDrop", "bool", 1],
        ["Vision", "FreezeSeconds", "FreezeSeconds", "int", 45, 0, 3600],
        ["Vision", "StatsBox", "VisionStatsBox", "box", "0.00,0.68,0.52,0.99"],
        ["Vision", "TimersBox", "VisionTimersBox", "box", "0.76,0.70,0.99,0.98"],
        ["Vision", "ModalBox", "VisionModalBox", "box", "0.25,0.25,0.75,0.75"],
        ["Vision", "ViewportBox", "VisionViewportBox", "box", "0.25,0.15,0.75,0.65"],
        ["Sounds", "Warn", "SoundWarn", "str?", "C:\Windows\Media\Windows Notify System Generic.wav"],
        ["Sounds", "Urgent", "SoundUrgent", "str?", "C:\Windows\Media\Windows Critical Stop.wav"],
        ["Sounds", "Disconnect", "SoundDisconnect", "str?", "C:\Windows\Media\Windows Hardware Fail.wav"],
        ["Sounds", "Missing", "SoundMissing", "str?", "C:\Windows\Media\Windows Hardware Remove.wav"],
        ["Sounds", "Refreshed", "SoundRefreshed", "str?", "C:\Windows\Media\Windows Navigation Start.wav"],
        ["Ntfy", "Server", "NtfyServer", "str", "https://ntfy.sh"],
        ["Ntfy", "Topic", "NtfyTopic", "str?", ""],
        ["Ntfy", "OnlyWhenAway", "NtfyOnlyWhenAway", "bool", 1],
        ["Ntfy", "AwaySeconds", "NtfyAwaySeconds", "int", 120, 0, 86400],
        ["Ntfy", "CooldownSeconds", "NtfyCooldownSeconds", "int", 300, 0, 86400],
        ["Update", "Enabled", "UpdateEnabled", "bool", 1],
        ["Update", "Repo", "UpdateRepo", "str?", "Peterged/rb-afk-tracker"],
        ["Update", "Branch", "UpdateBranch", "str", "main"],
        ["Update", "CheckIntervalHours", "UpdateIntervalHours", "int", 6, 1, 168],
        ["Log", "MaxBytes", "LogMaxBytes", "int", 1048576, 0, 104857600]
    ]

    static Notes := Map(
        "General.ExpectedInstances", "How many Roblox clients you normally run.",
        "General.RobloxSelector", "AutoHotkey WinTitle used to find Roblox game windows.",
        "General.KickSeconds", "Roblox kicks idle players after 20 minutes (1200 s). Warn < Urgent < Kick.",
        "General.WarnSeconds", "Idle seconds before a window turns yellow (WARN).",
        "General.UrgentSeconds", "Idle seconds before a window turns red and alerts repeat (URGENT).",
        "General.HungGraceSeconds", "A window must be 'Not Responding' this long before it is reported.",
        "General.RepeatAlertSeconds", "Repeat sound for unacknowledged problems every N seconds (0 = never).",
        "Hud.X", "-1 = top-right corner of the primary monitor. Use Shift+F9 to drag the HUD.",
        "Hotkeys.JumpToMostIdle", "AutoHotkey hotkey syntax: + Shift, ^ Ctrl, ! Alt, # Win. Empty = disabled.",
        "Hotkeys.ToggleHud", "Note: F9 also opens the Roblox developer console; this hotkey blocks it.",
        "Disconnect.Color", "RGB color of Roblox's grey error dialog. Use Tray > Calibrate to measure yours.",
        "Disconnect.SampleX", "Sample points as fractions of the window's width/height.",
        "Disconnect.ConfirmScans", "Consecutive positive scans needed before a window is marked DC.",
        "Vision.ShowStatsInHud", "1 = show OCR'd $Cash and +Boost% on HUD rows (0 = clean AFK timer HUD).",
        "Vision.KeepRenderable", "1 = auto un-minimize windows to the background so CV can see all clients.",
        "Vision.OcrEnabled", "1 = use OCR to read HUD stats, timers and disconnect reasons.",
        "Vision.RapidOcrEnabled", "1 = use optional Python rapidocr_onnxruntime worker if installed (0 = native WinRT-Bicubic).",
        "Vision.OcrStatsIntervalSec", "How often each window's in-game HUD stats are OCR'd (seconds).",
        "Vision.AlertOnBoostDrop", "1 = warn if a window's Friend Boost % drops.",
        "Vision.FreezeSeconds", "Mark a window FROZEN if its 3D viewport is 100% static this long (0 = off).",
        "Vision.StatsBox", "Normalized x1,y1,x2,y2 box for bottom-left Cash and Friend Boost.",
        "Vision.TimersBox", "Normalized x1,y1,x2,y2 box for bottom-right event/weather timers.",
        "Sounds.Warn", "WAV files played asynchronously. Empty or missing file = short beep.",
        "Ntfy.Topic", "Empty = phone push disabled. Topics are public: use a long random name.",
        "Ntfy.OnlyWhenAway", "1 = only push when you have not touched keyboard/mouse for AwaySeconds.",
        "Update.Enabled", "1 = automatically check GitHub for updates on startup and every CheckIntervalHours.",
        "Update.Repo", "Public GitHub repo (e.g. username/roblox-afk-monitor) used for zero-reinstall updates.",
        "Update.Branch", "Git branch to pull updates from (default: main).",
        "Log.MaxBytes", "Rotate logs\events.log to events.log.1 when it grows past this size."
    )

    __New(path := "") {
        this.path := path
        this.Load()
    }

    ; ---------------------------------------------------------------- loading
    Load() {
        this.Warnings := []
        if (this.path != "" && !FileExist(this.path)) {
            try {
                this.WriteDefaults()
            } catch as e {
                this.Warnings.Push("Could not create " this.path ": " e.Message)
            }
        }
        for entry in Config.Schema {
            raw := Config.MISSING
            if (this.path != "" && FileExist(this.path))
                raw := IniRead(this.path, entry[1], entry[2], Config.MISSING)
            if (raw == Config.MISSING)
                this.%entry[3]% := Config.DefaultValue(entry)
            else
                this.%entry[3]% := this.ParseEntry(entry, raw)
        }
        this.Validate()
        this.LoadLabels()
    }

    Validate() {
        if !(this.WarnSeconds < this.UrgentSeconds && this.UrgentSeconds < this.KickSeconds) {
            this.Warnings.Push(Format("WarnSeconds ({}) < UrgentSeconds ({}) < KickSeconds ({}) is required; using 900/1080/1200.",
                this.WarnSeconds, this.UrgentSeconds, this.KickSeconds))
            this.WarnSeconds := 900
            this.UrgentSeconds := 1080
            this.KickSeconds := 1200
        }
        ; Automatically widen legacy narrow StatsBox (0.00,0.75,0.25,0.98) so
        ; windowed Roblox clients don't clip the cash text at x=0.25.
        b := this.VisionStatsBox
        if (b is Array && b.Length = 4 && Abs(b[3] - 0.25) < 0.001) {
            this.VisionStatsBox := [0.00, 0.68, 0.52, 0.99]
            this.Write("Vision", "StatsBox", "0.00,0.68,0.52,0.99")
        }
    }

    LoadLabels() {
        this.Labels := Map()
        if (this.path = "" || !FileExist(this.path)) {
            for i, name in Config.DefaultLabels
                this.Labels[i] := name
            return
        }
        loop Config.MaxSlots {
            value := Config.SanitizeLabel(Config.StripComment(IniRead(this.path, "Labels", "Slot" A_Index, "")))
            if (value != "")
                this.Labels[A_Index] := value
        }
    }

    ParseEntry(entry, raw) {
        value := Config.TryParse(entry, Config.StripComment(raw), &ok)
        if ok
            return value
        this.Warnings.Push(Format("settings.ini [{}] {}={} is invalid; using default {}.",
            entry[1], entry[2], raw, Config.FormatValue(entry[4], entry[5])))
        return Config.DefaultValue(entry)
    }

    static DefaultValue(entry) {
        return Config.TryParse(entry, Config.FormatValue(entry[4], entry[5]), &ok)
    }

    static FormatValue(type, value) {
        return (type = "color") ? Format("0x{:06X}", value) : String(value)
    }

    ; Windows' INI reader does not strip inline comments, so do it here.
    static StripComment(raw) {
        p := InStr(raw, " `;")
        if !p
            p := InStr(raw, "`t`;")
        if p
            raw := SubStr(raw, 1, p - 1)
        return Trim(raw, " `t")
    }

    static TryParse(entry, s, &ok) {
        ok := true
        switch entry[4] {
            case "int":
                if (IsInteger(s) && Integer(s) >= entry[6] && Integer(s) <= entry[7])
                    return Integer(s)
            case "num":
                if (IsNumber(s) && s + 0 >= entry[6] && s + 0 <= entry[7])
                    return Float(s)
            case "bool":
                if (s = "1" || s = "true" || s = "yes" || s = "on")
                    return 1
                if (s = "0" || s = "false" || s = "no" || s = "off")
                    return 0
            case "color":
                s := RegExReplace(s, "^#", "")
                if RegExMatch(s, "i)^[0-9a-f]{6}$")
                    s := "0x" s
                if (IsInteger(s) && Integer(s) >= 0 && Integer(s) <= 0xFFFFFF)
                    return Integer(s)
            case "list":
                result := []
                for part in StrSplit(s, ",", " `t") {
                    if !(IsNumber(part) && part + 0 >= 0 && part + 0 <= 1) {
                        result := ""
                        break
                    }
                    result.Push(Float(part))
                }
                if (result is Array && result.Length)
                    return result
            case "box":
                box := []
                for part in StrSplit(s, ",", " `t") {
                    if !(IsNumber(part) && part + 0 >= 0 && part + 0 <= 1) {
                        box := ""
                        break
                    }
                    box.Push(Float(part))
                }
                if (box is Array && box.Length = 4 && box[1] < box[3] && box[2] < box[4])
                    return box
            case "str":
                if (s != "")
                    return s
            case "str?", "hotkey":
                return s
        }
        ok := false
        return ""
    }

    static SanitizeLabel(s) {
        s := Trim(RegExReplace(s, "[\r\n=\[\];]", ""))
        return SubStr(s, 1, 12)
    }

    ; ---------------------------------------------------------------- writing
    WriteDefaults() {
        semi := Chr(59)
        text := semi " Roblox AFK Monitor settings`n"
        text .= semi " Lines starting with " semi " are comments. After editing use Tray > Reload settings.`n"
        section := ""
        for entry in Config.Schema {
            if (entry[1] != section) {
                section := entry[1]
                text .= "`n[" section "]`n"
            }
            note := entry[1] "." entry[2]
            if Config.Notes.Has(note)
                text .= semi " " Config.Notes[note] "`n"
            text .= entry[2] "=" Config.FormatValue(entry[4], entry[5]) "`n"
        }
        text .= "`n[Labels]`n" semi " Display names per slot. Rename the active window with F8.`n"
        for i, name in Config.DefaultLabels
            text .= "Slot" i "=" name "`n"
        ; UTF-16 so the Windows INI API reads/writes non-ASCII labels correctly.
        FileAppend(text, this.path, "UTF-16")
    }

    Write(section, key, value) {
        if (this.path = "")
            return true
        try {
            IniWrite(value, this.path, section, key)
            return true
        } catch {
            return false
        }
    }

    LabelFor(index) => this.Labels.Get(index, "#" index)

    SetLabel(index, name) {
        name := Config.SanitizeLabel(name)
        if (name = "")
            return ""
        this.Labels[index] := name
        this.Write("Labels", "Slot" index, name)
        return name
    }

    SetExpected(n) {
        this.ExpectedInstances := n
        this.Write("General", "ExpectedInstances", n)
    }

    SetHudPos(x, y) {
        this.HudX := x, this.HudY := y
        this.Write("Hud", "X", x)
        this.Write("Hud", "Y", y)
    }

    SetHudVisible(visible) {
        this.HudVisible := visible ? 1 : 0
        this.Write("Hud", "Visible", this.HudVisible)
    }

    SetSoundsEnabled(enabled) {
        this.SoundsEnabled := enabled ? 1 : 0
        this.Write("General", "SoundsEnabled", this.SoundsEnabled)
    }

    SetKeepRenderable(enabled) {
        this.KeepRenderable := enabled ? 1 : 0
        this.Write("Vision", "KeepRenderable", this.KeepRenderable)
    }

    SetDcColor(color) {
        this.DcColor := color
        this.Write("Disconnect", "Color", Format("0x{:06X}", color))
    }

    SetUpdateRepo(repo) {
        this.UpdateRepo := repo
        this.Write("Update", "Repo", repo)
    }

    SoundFile(name) => this.HasOwnProp("Sound" name) ? this.%"Sound" name% : ""
}
