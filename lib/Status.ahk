; =============================================================================
; Status.ahk - Pure status rules and text formatting (no Win32, fully testable).
;
; Status priority (highest wins):
;   MISSING > HUNG > FROZEN > DC > URGENT > WARN > OK > EMPTY
; =============================================================================

class Status {
    static Priority := Map("EMPTY", 0, "OK", 1, "WARN", 2, "URGENT", 3, "DC", 4, "FROZEN", 5, "HUNG", 6, "MISSING", 7)

    static Colors := Map(
        "EMPTY", "6C7086",
        "OK", "A6E3A1",
        "WARN", "F9E2AF",
        "URGENT", "F38BA8",
        "DC", "F38BA8",
        "FROZEN", "F38BA8",
        "HUNG", "F38BA8",
        "MISSING", "F38BA8"
    )

    static Evaluate(slot, now, cfg) {
        if !slot.hwnd
            return slot.missingSince ? "MISSING" : "EMPTY"
        if slot.hung
            return "HUNG"
        if slot.frozen
            return "FROZEN"
        if slot.dc
            return "DC"
        idle := Status.IdleSeconds(slot, now)
        if (idle >= cfg.UrgentSeconds)
            return "URGENT"
        if (idle >= cfg.WarnSeconds)
            return "WARN"
        return "OK"
    }

    ; URGENT, DC, HUNG and MISSING need attention (flashing HUD, repeating alerts).
    static IsProblem(st) => Status.Priority.Get(st, 0) >= 3

    static Color(st) => Status.Colors.Get(st, "CDD6F4")

    static IdleSeconds(slot, now) => slot.hwnd ? Max(0, (now - slot.lastInput) // 1000) : 0

    static FormatDuration(seconds) {
        seconds := Max(0, Integer(seconds))
        return Format("{:02}:{:02}", seconds // 60, Mod(seconds, 60))
    }

    static FormatRow(slot, st, now, cfg) {
        label := SubStr(slot.label, 1, 8)
        if (st = "EMPTY")
            return Format("{:-8} {:-7} not running", label, "-")
        if (st = "MISSING")
            return Format("{:-8} {:-7} gone {}", label, "MISSING", Status.FormatDuration((now - slot.missingSince) // 1000))

        idle := Status.IdleSeconds(slot, now)
        kickIn := cfg.KickSeconds - idle
        tag := st (slot.hasInput ? "" : "~")
        text := Format("{:-8} {:-7} {}  kick {}", label, tag, Status.FormatDuration(idle),
            kickIn > 0 ? Status.FormatDuration(kickIn) : "NOW")
        if (st = "DC" && slot.dcReason != "")
            text .= " [" slot.dcReason "]"
        else if (cfg.ShowStatsInHud && (slot.cash != "" || slot.boost >= 0)) {
            statStr := (slot.cash != "") ? "$" slot.cash : ""
            if (slot.boost >= 0)
                statStr .= (statStr != "" ? " " : "") "+" slot.boost "%"
            text .= "  " statStr
        }
        if slot.otherDesktop
            text .= " VD"
        if slot.minimized
            text .= " MIN"
        return text
    }

    ; Returns {text, status}. status is used to color the header.
    static FormatHeader(slots, statuses, now, cfg) {
        live := 0, worst := "EMPTY", worstSlot := "", problems := 0
        nextSlot := "", nextKick := 0, evtTimer := ""
        for slot in slots {
            st := statuses[slot.index]
            if slot.hwnd {
                live++
                if (evtTimer = "" && slot.eventTimer != "")
                    evtTimer := slot.eventTimer
            }
            if Status.IsProblem(st)
                problems++
            if (Status.Priority[st] > Status.Priority[worst]) {
                worst := st
                worstSlot := slot
            }
            if (slot.hwnd && !Status.IsProblem(st)) {
                kick := cfg.KickSeconds - Status.IdleSeconds(slot, now)
                if (nextSlot = "" || kick < nextKick) {
                    nextSlot := slot
                    nextKick := kick
                }
            }
        }
        expected := cfg.ExpectedInstances
        prefix := Format("{}/{}  ", live, expected)

        if Status.IsProblem(worst) {
            reasonSuffix := (worst = "DC" && worstSlot.dcReason != "") ? " (" worstSlot.dcReason ")" : ""
            text := prefix StrUpper(worstSlot.label) " " worst reasonSuffix
            if (problems > 1)
                text .= Format(" (+{} more)", problems - 1)
            return {text: text, status: worst}
        }
        if (live = 0)
            return {text: prefix "waiting for Roblox...", status: "EMPTY"}
        color := (live < expected && worst = "OK") ? "WARN" : worst
        if (nextSlot = "")
            return {text: prefix "no active windows", status: color}
        evtSuffix := (evtTimer != "") ? " | evt " evtTimer : ""
        return {text: prefix "next: " nextSlot.label " kick " Status.FormatDuration(nextKick) evtSuffix, status: color}
    }
}
