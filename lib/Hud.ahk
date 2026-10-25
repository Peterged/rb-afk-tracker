; =============================================================================
; Hud.ahk - Click-through, always-on-top overlay with one row per slot.
; Only redraws what changed (no flicker). Move mode lets you drag it.
; =============================================================================

class Hud {
    static MaxRows := 12
    static BgNormal := "1E1E2E"
    static BgFlashA := "B41E38"
    static BgFlashB := "5A101D"
    static BgMove := "313244"

    __New(cfg) {
        this.cfg := cfg
        this.visible := cfg.HudVisible
        this.moveMode := false
        this.flash := false
        this.bg := Hud.BgNormal
        this.shownRows := -1
        this.textCache := Map()
        this.colorCache := Map()
        this.dragFn := ObjBindMethod(this, "OnLButtonDown")

        g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "Roblox AFK Monitor HUD")
        g.BackColor := Hud.BgNormal
        g.MarginX := 10, g.MarginY := 6
        g.SetFont("s" cfg.HudFontSize " cCDD6F4 Bold", "Consolas")
        this.header := g.Add("Text", "w440", "Roblox AFK Monitor")
        g.SetFont("s" cfg.HudFontSize " Norm", "Consolas")
        this.rows := []
        loop Hud.MaxRows
            this.rows.Push(g.Add("Text", "xm y+2 w440 Hidden", ""))
        this.gui := g
        this.PlaceInitial()
    }

    PlaceInitial() {
        g := this.gui
        g.Show("Hide AutoSize")
        WinGetPos(, , &w, &h, g.Hwnd)
        x := this.cfg.HudX, y := this.cfg.HudY
        if (x = -1 || !Hud.OnScreen(x, y, w, h)) {
            MonitorGetWorkArea(MonitorGetPrimary(), &left, &top, &right, &bottom)
            x := right - w - 20
            y := top + 15
        }
        WinMove(x, y, , , g.Hwnd)
        WinSetTransparent(this.cfg.HudOpacity, g.Hwnd)
        if this.visible
            g.Show("NoActivate")
    }

    static OnScreen(x, y, w, h) {
        cx := x + w // 2, cy := y + Min(h, 20) // 2
        loop MonitorGetCount() {
            MonitorGetWorkArea(A_Index, &left, &top, &right, &bottom)
            if (cx >= left && cx < right && cy >= top && cy < bottom)
                return true
        }
        return false
    }

    ; header: {text, status}; rows: Array of {text, status}; alarm: flash background.
    Render(header, rows, alarm) {
        if this.moveMode
            bg := Hud.BgMove
        else if alarm {
            this.flash := !this.flash
            bg := this.flash ? Hud.BgFlashA : Hud.BgFlashB
        } else {
            this.flash := false
            bg := Hud.BgNormal
        }
        if (bg != this.bg) {
            this.gui.BackColor := bg
            this.bg := bg
        }

        this.SetCtrl(this.header, header.text, alarm ? "FFFFFF" : Status.Color(header.status))
        count := Min(rows.Length, Hud.MaxRows)
        loop count {
            r := rows[A_Index]
            color := (alarm && Status.IsProblem(r.status)) ? "FFFFFF" : Status.Color(r.status)
            this.SetCtrl(this.rows[A_Index], r.text, color)
        }
        if (count != this.shownRows) {
            loop Hud.MaxRows
                this.rows[A_Index].Visible := A_Index <= count
            this.shownRows := count
            this.gui.Show((this.visible ? "" : "Hide ") "AutoSize NoActivate")
        }
    }

    SetCtrl(ctrl, text, color) {
        key := ctrl.Hwnd
        if (this.colorCache.Get(key, "") != color) {
            ctrl.SetFont("c" color)
            this.colorCache[key] := color
        }
        if !(this.textCache.Get(key, Chr(1)) == text) {
            ctrl.Value := text
            this.textCache[key] := text
        }
    }

    SetVisible(visible) {
        this.visible := visible
        if visible
            this.gui.Show("NoActivate")
        else
            this.gui.Hide()
        this.cfg.SetHudVisible(visible)
    }

    ToggleVisible() => this.SetVisible(!this.visible)

    ; Move mode: HUD becomes clickable/draggable; leaving it saves the position.
    ToggleMoveMode() {
        this.moveMode := !this.moveMode
        if this.moveMode {
            if !this.visible
                this.SetVisible(true)
            this.gui.Opt("-E0x20")
            this.gui.BackColor := Hud.BgMove
            this.bg := Hud.BgMove
            this.SetCtrl(this.header, "MOVE MODE: drag me, then Shift+F9", "89B4FA")
            OnMessage(0x201, this.dragFn)   ; WM_LBUTTONDOWN
        } else {
            OnMessage(0x201, this.dragFn, 0)
            this.gui.Opt("+E0x20")
            WinGetPos(&x, &y, , , this.gui.Hwnd)
            this.cfg.SetHudPos(x, y)
        }
        return this.moveMode
    }

    OnLButtonDown(wParam, lParam, msg, hwnd) {
        if !this.moveMode
            return
        if (hwnd = this.gui.Hwnd || DllCall("GetAncestor", "ptr", hwnd, "uint", 2, "ptr") = this.gui.Hwnd) {
            PostMessage(0xA1, 2, 0, , this.gui.Hwnd)   ; compliance-ok: WM_NCLBUTTONDOWN drag of our own HUD window
            return 0
        }
    }
}
