; =============================================================================
; Notifier.ahk - Optional ntfy.sh phone push. Disabled while [Ntfy] Topic is empty.
; Rate-limited per event key, optionally only when you're away from the PC.
; Network failures are logged, never thrown.
; =============================================================================

class Notifier {
    __New(cfg, logger, clock, transport := "", idleFn := "") {
        this.cfg := cfg
        this.logger := logger
        this.clock := clock
        this.transport := transport ? transport : WinHttpTransport(logger)
        this.idleFn := idleFn ? idleFn : () => A_TimeIdlePhysical
        this.lastSent := Map()
    }

    Enabled => this.cfg.NtfyTopic != ""

    ; force = skip the away check and cooldown (used by "Send test notification").
    Notify(key, title, message, priority := 3, force := false) {
        if !this.Enabled
            return false
        if !force {
            if (this.cfg.NtfyOnlyWhenAway && this.idleFn.Call() < this.cfg.NtfyAwaySeconds * 1000)
                return false
            now := this.clock.Now()
            if (this.lastSent.Has(key) && now - this.lastSent[key] < this.cfg.NtfyCooldownSeconds * 1000)
                return false
            this.lastSent[key] := now
        }
        url := RTrim(this.cfg.NtfyServer, "/") "/" this.cfg.NtfyTopic
        headers := Map("Title", title, "Priority", String(priority), "Tags", "video_game",
            "Content-Type", "text/plain; charset=utf-8")
        try {
            this.transport.Post(url, message, headers)
            return true
        } catch as e {
            this.logger.Warn("ntfy send failed: " e.Message)
            return false
        }
    }

    Poll() => this.transport.Poll()
}

; Asynchronous WinHTTP POST. Requests are kept alive in `pending` until they
; complete (otherwise COM would release and cancel them) and polled each tick.
class WinHttpTransport {
    static TimeoutMs := 30000

    __New(logger) {
        this.logger := logger
        this.pending := []
    }

    Post(url, body, headers) {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(5000, 5000, 10000, 10000)
        req.Open("POST", url, true)
        for name, value in headers
            req.SetRequestHeader(name, value)
        req.Send(body)
        this.pending.Push({req: req, started: A_TickCount})
    }

    Poll() {
        i := this.pending.Length
        while (i >= 1) {
            item := this.pending[i]
            done := false
            try {
                if item.req.WaitForResponse(0) {
                    done := true
                    if (item.req.Status >= 300)
                        this.logger.Warn("ntfy HTTP " item.req.Status ": " SubStr(item.req.ResponseText, 1, 200))
                }
            } catch as e {
                done := true
                this.logger.Warn("ntfy request failed: " e.Message)
            }
            if (!done && A_TickCount - item.started > WinHttpTransport.TimeoutMs) {
                done := true
                this.logger.Warn("ntfy request timed out")
                try item.req.Abort()
            }
            if done
                this.pending.RemoveAt(i)
            i--
        }
        return this.pending.Length
    }
}
