; =============================================================================
; InputMonitor.ahk - Observes YOUR physical input while a Roblox window is active
; and tells the tracker. Nothing is blocked, nothing is sent.
;
; Keyboard: one InputHook in visible mode ("V") sees every key, with or without
; modifiers. Modifier keys on their own and the app's own hotkey keys don't count.
; Mouse: buttons + wheel via pass-through (~) hotkeys, only while Roblox is active.
; Mouse *movement* is intentionally NOT counted (conservative: never report a
; window as safe when Roblox might disagree).
; =============================================================================

class InputMonitor {
    static MouseKeys := ["~*LButton", "~*RButton", "~*MButton", "~*XButton1", "~*XButton2", "~*WheelUp", "~*WheelDown", "~*WheelLeft", "~*WheelRight"]

    __New(tracker, winApi, selector, excludedKeys := "") {
        this.tracker := tracker
        this.winApi := winApi
        this.restarts := 0
        callback := ObjBindMethod(this, "OnInput")

        this.ih := InputHook("V L0")
        this.ih.KeyOpt("{All}", "N")
        this.ih.KeyOpt("{LShift}{RShift}{LControl}{RControl}{LAlt}{RAlt}{LWin}{RWin}", "-N")
        if (excludedKeys is Array) {
            for key in excludedKeys {
                try this.ih.KeyOpt("{" key "}", "-N")
            }
        }
        this.ih.OnKeyDown := (ih, vk, sc) => callback()
        this.ih.Start()

        HotIfWinActive(selector)
        for key in InputMonitor.MouseKeys
            Hotkey(key, (*) => callback())
        HotIfWinActive()
    }

    OnInput() {
        hwnd := this.winApi.Active()
        if hwnd
            this.tracker.RecordInput(hwnd)
    }

    ; Called every tick: restarts the hook if something stopped it.
    EnsureRunning() {
        if !this.ih.InProgress {
            this.ih.Start()
            this.restarts++
            return false
        }
        return true
    }

    ; Strips modifiers/prefixes from hotkey strings, e.g. "+F7" -> "F7", "~^a up" -> "a".
    static KeysOf(hotkeys) {
        keys := []
        for hk in hotkeys {
            if (hk = "")
                continue
            hk := RegExReplace(hk, "i)\s+up$", "")
            for part in StrSplit(hk, "&", " `t") {
                key := RegExReplace(part, "^[~*$<>^!+#]+", "")
                if (key != "")
                    keys.Push(key)
            }
        }
        return keys
    }
}
