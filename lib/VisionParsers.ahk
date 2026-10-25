; =============================================================================
; VisionParsers.ahk - Pure text parsers for OCR output from:
;   1. Bottom-left HUD stats ("Friend Boost: +40%", "+$19,276", "3.56M")
;   2. Bottom-right event/buff timers ("2m 29s", "in 3m 9s")
;   3. Center Roblox disconnect modal ("idle 20 minutes", "Error Code: 277", ...)
;
; Includes stylized-font digit recovery (O->0, I/l/i->1, S->5, B->8, Z->2)
; and multi-candidate scoring.
; =============================================================================

class VisionParsers {
    static DigitChars := "0-9OQoIli|SsBZzAa"

    ; Parses bottom-left HUD OCR text (may contain multiple candidate lines).
    ; Returns {cash: "3.56M", boost: 40, income: "19,276"} (missing fields are "" or -1).
    static ParseStats(text) {
        result := {cash: "", boost: -1, income: ""}
        if (text = "")
            return result

        norm := RegExReplace(text, "[\r\n]+", " `n ")
        dc := VisionParsers.DigitChars

        ; 1. Friend Boost: +40% (tolerant of "Friend Boost +4O%", "Boost: 40%", etc.)
        if RegExMatch(norm, "i)(?:Friend\s*)?Boost[:\s+]*([0-9OQoIli|SsBZz]{1,3})\s*%", &m) {
            digits := VisionParsers.CleanDigits(m[1])
            if IsInteger(digits)
                result.boost := Integer(digits)
        }

        ; 2. Strip all floating income ticks: +$19,276 / +$i9,276 / +$1.2K
        while RegExMatch(norm, "i)\+\s*\$\s*([" dc "][" dc ",\.]*\s*[KMBT]?)", &m) {
            if (result.income = "")
                result.income := VisionParsers.CleanNumberToken(m[1])
            norm := StrReplace(norm, m[0], " ", , , 1)
        }

        ; Remove Friend Boost substring and hotbar item quantities/weights ("x16471", "90.48 KG")
        norm := RegExReplace(norm, "i)(?:Friend\s*)?Boost[:\s+]*[" dc "]{1,3}\s*%", " ")
        norm := RegExReplace(norm, "i)\bx\s*[" dc ",\.]+\b", " ")
        norm := RegExReplace(norm, "i)\b[" dc ",\.]+\s*KG\b", " ")

        ; Repair hotbar-occluded decimal point: e.g. "085 98T" -> "085.98T"
        norm := RegExReplace(norm, "i)(?<![a-zA-Z0-9])([" dc "]{1,3})\s+([" dc "]{2})\s*([KMBT])(?![a-zA-Z])", "$1.$2$3")

        ; 3. Cash balance: prefer numbers with a K/M/B/T suffix (3.56M, 985.98T, 85OK)
        pos := 1
        while RegExMatch(norm, "i)(?<![a-zA-Z0-9])\$?\s*([" dc "]+(?:[\.,][" dc "]+)*\s*[KMBT])(?:[^a-zA-Z0-9]|u|$)", &m, pos) {
            pos := m.Pos + m.Len
            rawTok := RegExReplace(m[1], "[Aa]", "8")
            candidate := VisionParsers.CleanNumberToken(rawTok)
            if RegExMatch(candidate, "^(\d+)(?:[\.,](\d+))?([KMBT])$", &cm) {
                intPart := cm[1], decPart := cm[2], suf := cm[3]
                ; Reject 4+ digit unsuffixed corruption like "8005T" (abbreviated cash has 1..3 integer digits)
                if (StrLen(intPart) > 3)
                    continue
                ; A multi-digit integer part never starts with '0' (085 -> 985 when hotbar Backpack icon occludes 9's tail)
                if (StrLen(intPart) >= 2 && SubStr(intPart, 1, 1) = "0")
                    intPart := "9" SubStr(intPart, 2)
                result.cash := intPart (decPart != "" ? "." decPart : "") suf
                break
            }
        }
        if (result.cash = "") && RegExMatch(norm, "(?<![a-zA-Z0-9%+])\$?\s*(\d{1,3}(?:,\d{3})+|\d{3,})\b", &m) {
            result.cash := VisionParsers.CleanNumberToken(m[1])
        }
        return result
    }

    ; Parses bottom-right event/weather timers ("2m 29s", "in 3m 9s").
    ; Tolerates OCR reading the trailing 's' on outlined fonts as '5' or '3'.
    ; Returns {nextEvent: "3m 9s", activeBuff: "2m 29s"}.
    static ParseTimers(text) {
        result := {nextEvent: "", activeBuff: ""}
        if (text = "")
            return result
        norm := RegExReplace(text, "[\r\n]+", " ")

        ; "in 3m 9s" / "in 3m 95" / "in 45s" / "in 4m"
        if RegExMatch(norm, "i)\bin\s+(\d{1,2})\s*m(?:\s*(\d{1,2})\s*[sS53])?\b", &m) {
            result.nextEvent := m[1] "m" (m[2] != "" ? " " m[2] "s" : "")
            norm := StrReplace(norm, m[0], " ")
        } else if RegExMatch(norm, "i)\bin\s+(\d{1,2})\s*[sS]\b", &m) {
            result.nextEvent := m[1] "s"
            norm := StrReplace(norm, m[0], " ")
        }

        ; Remaining standalone "2m 29s" / "2m 295" buff timer
        if RegExMatch(norm, "i)\b(\d{1,2})\s*m\s*(\d{1,2})\s*[sS53]\b", &m) {
            result.activeBuff := m[1] "m " m[2] "s"
        }
        return result
    }

    ; Parses the center Roblox disconnect popup.
    ; Returns {code: "IDLE20"|"SAME_ACCT"|"SHUTDOWN"|"NET"|"KICKED"|"ERR_NNN"|"", detail: "..."}
    static ParseDisconnectReason(text) {
        if (text = "")
            return {code: "", detail: ""}
        clean := Trim(RegExReplace(text, "\s+", " "))

        if RegExMatch(clean, "i)idle\s*20\s*min|being\s+idle|20\s*minutes", &m)
            return {code: "IDLE20", detail: "Idle 20 minutes"}
        if RegExMatch(clean, "i)same\s+account\s+launched|different\s+device", &m)
            return {code: "SAME_ACCT", detail: "Same account launched elsewhere"}
        if RegExMatch(clean, "i)shut\s*down|restarting|maintenance|update", &m)
            return {code: "SHUTDOWN", detail: "Server shut down"}
        if RegExMatch(clean, "i)lost\s+connection|internet\s+connection|reconnect\s+was\s+unsuccessful|please\s+check\s+your", &m)
            return {code: "NET", detail: "Lost connection"}
        if RegExMatch(clean, "i)error\s*code[:\s]*(\d{3})", &m)
            return {code: "ERR_" m[1], detail: "Error Code " m[1]}
        if RegExMatch(clean, "i)kicked|moderator|experience", &m)
            return {code: "KICKED", detail: "Kicked by server"}
        return {code: "", detail: SubStr(clean, 1, 60)}
    }

    static CleanDigits(s) {
        s := RegExReplace(s, "[OoQ]", "0")
        s := RegExReplace(s, "[Ili\|]", "1")
        s := RegExReplace(s, "[Ss]", "5")
        s := RegExReplace(s, "B", "8")
        s := RegExReplace(s, "[Zz]", "2")
        return s
    }

    static CleanNumberToken(s) {
        s := RegExReplace(s, "\s+", "")
        suffix := ""
        if RegExMatch(s, "i)([KMBT])$", &m) {
            suffix := StrUpper(m[1])
            s := SubStr(s, 1, StrLen(s) - 1)
        }
        return VisionParsers.CleanDigits(s) suffix
    }

    static CompactDuration(s) {
        s := StrLower(Trim(RegExReplace(s, "\s+", "")))
        return RegExReplace(s, "m(?=\d)", "m ")
    }
}
