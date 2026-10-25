; =============================================================================
; DisconnectDetector.ahk - Detects Roblox's grey "Disconnected" dialog.
;
; Capture(): renders the window off-screen with PrintWindow(PW_CLIENTONLY |
;   PW_RENDERFULLCONTENT) so covered windows can be checked, then reads only the
;   sample pixels. Read-only: nothing is sent to the window's input queue.
; Classify(): pure decision function, unit-tested with synthetic colors.
; =============================================================================

class DisconnectDetector {
    __New(cfg, winApi) {
        this.cfg := cfg
        this.winApi := winApi
        this.RebuildPoints()
    }

    RebuildPoints() {
        this.points := []
        for y in this.cfg.DcSampleY
            for x in this.cfg.DcSampleX
                this.points.Push([x, y])
    }

    Check(hwnd) => DisconnectDetector.Classify(this.Capture(hwnd), this.cfg)

    CheckFrame(frame) => DisconnectDetector.Classify(this.SampleFrame(frame), this.cfg)

    ; Reads the sample points directly from an already-captured FrameBuffer.
    SampleFrame(frame) {
        if !frame
            return ""
        colors := []
        for p in this.points
            colors.Push(frame.GetPixelNorm(p[1], p[2]))
        return colors
    }

    ; Returns an Array of 0xRRGGBB colors (one per sample point), or "" if the
    ; window can't be captured (hung, minimized, too small, capture failed).
    Capture(hwnd) {
        frame := FrameBuffer.Capture(hwnd, this.winApi)
        return frame ? this.SampleFrame(frame) : ""
    }

    ; Returns {text, suggested, result} for the tray "Calibrate" action, or "".
    Calibrate(hwnd) {
        colors := this.Capture(hwnd)
        if !(colors is Array)
            return ""
        counts := Map(), best := 0, bestCount := 0, text := ""
        for i, c in colors {
            p := this.points[i]
            text .= Format("({:.2f}, {:.2f})   0x{:06X}`n", p[1], p[2], c)
            n := counts[c] := counts.Get(c, 0) + 1
            if (n > bestCount) {
                best := c
                bestCount := n
            }
        }
        return {text: text, suggested: best, result: DisconnectDetector.Classify(colors, this.cfg)}
    }

    ; "dc" | "ok" | "unknown"
    static Classify(colors, cfg) {
        if !(colors is Array) || !colors.Length
            return "unknown"
        black := 0, match := 0
        for c in colors {
            if (c = 0)
                black++
            if DisconnectDetector.ColorNear(c, cfg.DcColor, cfg.DcTolerance)
                match++
        }
        if (black = colors.Length)
            return "unknown"   ; nothing rendered (capture failed / window not drawn)
        return (match / colors.Length >= cfg.DcMinMatchRatio) ? "dc" : "ok"
    }

    static ColorNear(c, target, tolerance) {
        return Abs(((c >> 16) & 0xFF) - ((target >> 16) & 0xFF)) <= tolerance
            && Abs(((c >> 8) & 0xFF) - ((target >> 8) & 0xFF)) <= tolerance
            && Abs((c & 0xFF) - (target & 0xFF)) <= tolerance
    }
}
