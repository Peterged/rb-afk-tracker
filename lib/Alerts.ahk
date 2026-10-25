; =============================================================================
; Alerts.ahk - Turns status transitions into sounds, log lines and push alerts.
;
; - One alert when a slot ENTERS a state.
; - Problems (URGENT/DC/HUNG/MISSING) repeat their sound every
;   RepeatAlertSeconds until resolved or acknowledged.
; - Acknowledge silences the problems that exist right now; a new or different
;   problem alerts again.
; =============================================================================

class Alerts {
    static Rules := Map(
        "WARN", {sound: "Warn", level: "INFO", push: 0},
        "URGENT", {sound: "Urgent", level: "WARN", push: 4},
        "DC", {sound: "Disconnect", level: "ERROR", push: 5},
        "FROZEN", {sound: "Disconnect", level: "ERROR", push: 4},
        "HUNG", {sound: "Disconnect", level: "ERROR", push: 4},
        "MISSING", {sound: "Missing", level: "ERROR", push: 5}
    )

    __New(cfg, logger, sound, notifier) {
        this.cfg := cfg
        this.logger := logger
        this.sound := sound
        this.notifier := notifier
        this.prev := Map()        ; slot index -> last status
        this.lastSound := Map()   ; slot index -> tick of last alert sound
        this.acked := Map()       ; slot index -> acknowledged status
    }

    ; slots: Array of TrackedSlot; statuses: Map(slot index -> status)
    Process(slots, statuses, now) {
        repeatMs := this.cfg.RepeatAlertSeconds * 1000
        for slot in slots {
            i := slot.index
            cur := statuses[i]
            old := this.prev.Get(i, "")
            if (cur != old) {
                this.prev[i] := cur
                if (this.acked.Has(i) && this.acked[i] != cur)
                    this.acked.Delete(i)
                this.OnTransition(slot, old, cur, now)
            } else if (Status.IsProblem(cur) && repeatMs > 0 && !this.acked.Has(i)
                && now - this.lastSound.Get(i, 0) >= repeatMs) {
                this.sound.Play(Alerts.Rules[cur].sound)
                this.lastSound[i] := now
            }

            if slot.boostDropped {
                slot.boostDropped := false
                if this.cfg.AlertOnBoostDrop {
                    msg := Format("{} Friend Boost dropped ({}% -> {}%)", slot.label, slot.prevBoost, slot.boost)
                    this.logger.Warn(msg)
                    this.sound.Play("Warn")
                }
            }
        }
    }

    OnTransition(slot, old, cur, now) {
        if Alerts.Rules.Has(cur) {
            rule := Alerts.Rules[cur]
            msg := slot.label " " Alerts.Describe(cur, slot, now)
            this.logger.Log(rule.level, msg)
            this.sound.Play(rule.sound)
            this.lastSound[slot.index] := now
            if rule.push
                this.notifier.Notify(cur ":" slot.index, "Roblox: " slot.label " " cur, msg, rule.push)
            return
        }
        if (cur = "OK") {
            switch old {
                case "WARN", "URGENT":
                    this.logger.Info(slot.label " refreshed")
                    this.sound.Play("Refreshed")
                case "DC", "FROZEN", "HUNG", "MISSING":
                    this.logger.Info(slot.label " recovered from " old)
                    this.sound.Play("Refreshed")
                default:
                    this.logger.Info(Format("{} detected (hwnd 0x{:X})", slot.label, slot.hwnd))
            }
        } else if (cur = "EMPTY" && old = "MISSING") {
            this.logger.Info(slot.label " missing alert cleared")
        }
    }

    static Describe(st, slot, now) {
        idleMin := slot.hwnd ? (now - slot.lastInput) // 60000 : 0
        switch st {
            case "WARN": return Format("idle {} min (warning)", idleMin)
            case "URGENT": return Format("idle {} min - about to be kicked!", idleMin)
            case "DC":
                reason := (slot.dcDetail != "") ? slot.dcDetail : (slot.dcReason != "") ? slot.dcReason : "error dialog detected"
                return "disconnected (" reason ")"
            case "FROZEN": return "3D viewport frozen (static frame)"
            case "HUNG": return "is not responding"
            case "MISSING": return Format("window closed or crashed (was hwnd 0x{:X})", slot.lastHwnd)
        }
        return st
    }

    Acknowledge() {
        count := 0
        for i, st in this.prev {
            if Status.IsProblem(st) {
                this.acked[i] := st
                count++
            }
        }
        return count
    }

    IsAcked(index) => this.acked.Has(index)

    HasUnackedProblem(statuses) {
        for i, st in statuses
            if (Status.IsProblem(st) && this.acked.Get(i, "") != st)
                return true
        return false
    }
}

; Plays configured WAV files asynchronously (SoundPlay doesn't block the HUD).
class SoundPlayer {
    static FallbackHz := Map("Warn", 880, "Urgent", 1200, "Disconnect", 400, "Missing", 500, "Refreshed", 1500)

    __New(cfg) {
        this.cfg := cfg
    }

    Play(name) {
        if !this.cfg.SoundsEnabled
            return
        file := this.cfg.SoundFile(name)
        if (file != "" && FileExist(file)) {
            try {
                SoundPlay(file)
                return
            }
        }
        try SoundBeep(SoundPlayer.FallbackHz.Get(name, 800), 120)
    }
}
