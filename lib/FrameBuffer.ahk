; =============================================================================
; FrameBuffer.ahk - Single-pass off-screen window capture (PrintWindow +
; GetDIBits), O(1) pixel sampling, 64-bit viewport gradient hash (dHash) for
; render-freeze detection, auto-locating color-band detection for Roblox's
; #AAFF00 cash text, and GDI+ HighQualityBicubic upscaling with soft color-
; distance masking for high-accuracy OCR across all window sizes.
;
; Read-only: never sends messages or input to the target window.
; =============================================================================

class FrameBuffer {
    static gdiToken := 0

    __New(width, height, pixels) {
        this.width := width
        this.height := height
        this.stride := width * 4
        this.pixels := pixels   ; Buffer of top-down 32-bit BGRA pixels
    }

    static EnsureGdiPlus() {
        if FrameBuffer.gdiToken
            return true
        try {
            if !DllCall("GetModuleHandle", "str", "gdiplus", "ptr")
                DllCall("LoadLibrary", "str", "gdiplus", "ptr")
            si := Buffer(24, 0), NumPut("uint", 1, si, 0)
            token := 0
            if (DllCall("gdiplus\GdiplusStartup", "ptr*", &token, "ptr", si, "ptr", 0) = 0)
                FrameBuffer.gdiToken := token
        }
        return FrameBuffer.gdiToken != 0
    }

    ; Captures hwnd off-screen into a FrameBuffer, or returns "" if the window
    ; cannot be captured (hung, minimized, too small, or PrintWindow failed).
    static Capture(hwnd, winApi) {
        if (winApi.IsHung(hwnd) || winApi.IsMinimized(hwnd))
            return ""
        Critical("On")
        prevCtx := 0
        try prevCtx := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")   ; per-monitor v2
        try {
            rc := Buffer(16, 0)
            if !DllCall("GetClientRect", "ptr", hwnd, "ptr", rc)
                return ""
            w := NumGet(rc, 8, "int"), h := NumGet(rc, 12, "int")
            if (w < 150 || h < 150)
                return ""
            hdcWin := DllCall("GetDC", "ptr", hwnd, "ptr")
            if !hdcWin
                return ""
            hdcMem := DllCall("CreateCompatibleDC", "ptr", hdcWin, "ptr")
            hbm := DllCall("CreateCompatibleBitmap", "ptr", hdcWin, "int", w, "int", h, "ptr")
            old := DllCall("SelectObject", "ptr", hdcMem, "ptr", hbm, "ptr")
            try {
                if !DllCall("PrintWindow", "ptr", hwnd, "ptr", hdcMem, "uint", 3)
                    return ""
                bi := Buffer(40, 0)
                NumPut("uint", 40, bi, 0)
                NumPut("int", w, bi, 4)
                NumPut("int", -h, bi, 8)   ; negative height = top-down DIB
                NumPut("ushort", 1, bi, 12)
                NumPut("ushort", 32, bi, 14)
                pixels := Buffer(w * h * 4)
                lines := DllCall("GetDIBits", "ptr", hdcMem, "ptr", hbm, "uint", 0, "uint", h,
                    "ptr", pixels, "ptr", bi, "uint", 0, "int")
                if (lines != h)
                    return ""
                return FrameBuffer(w, h, pixels)
            } finally {
                DllCall("SelectObject", "ptr", hdcMem, "ptr", old)
                DllCall("DeleteObject", "ptr", hbm)
                DllCall("DeleteDC", "ptr", hdcMem)
                DllCall("ReleaseDC", "ptr", hwnd, "ptr", hdcWin)
            }
        } finally {
            if prevCtx
                try DllCall("SetThreadDpiAwarenessContext", "ptr", prevCtx, "ptr")
            Critical("Off")
        }
    }

    ; Creates a synthetic FrameBuffer filled with a 0xRRGGBB color (used in tests).
    static CreateSolid(w, h, rgb) {
        argb := (rgb & 0xFFFFFF) | 0xFF000000
        pixels := Buffer(w * h * 4)
        ptr := pixels.Ptr
        loop w * h
            NumPut("uint", argb, ptr + (A_Index - 1) * 4)
        return FrameBuffer(w, h, pixels)
    }

    ; Sets a pixel at integer (x, y) to 0xRRGGBB.
    SetPixelXY(x, y, rgb) {
        if (x < 0 || x >= this.width || y < 0 || y >= this.height)
            return
        argb := (rgb & 0xFFFFFF) | 0xFF000000
        NumPut("uint", argb, this.pixels, y * this.stride + x * 4)
    }

    ; Returns 0xRRGGBB at integer coordinates (x, y).
    GetPixelXY(x, y) {
        x := Max(0, Min(this.width - 1, Integer(x)))
        y := Max(0, Min(this.height - 1, Integer(y)))
        bgr := NumGet(this.pixels, y * this.stride + x * 4, "uint")
        return bgr & 0xFFFFFF
    }

    ; Returns 0xRRGGBB at normalized coordinates (0..1, 0..1).
    GetPixelNorm(nx, ny) {
        return this.GetPixelXY(Round(this.width * nx), Round(this.height * ny))
    }

    ; Computes a 64-bit FNV-1a hash over an 8x8 grid of pixels inside normalized
    ; box [x1, y1, x2, y2]. Returns 0 if the sampled grid is completely black.
    ComputeViewportHash(box) {
        x1 := box[1], y1 := box[2], x2 := box[3], y2 := box[4]
        hash := 2166136261
        nonZero := 0
        loop 8 {
            gy := y1 + (y2 - y1) * ((A_Index - 0.5) / 8.0)
            loop 8 {
                gx := x1 + (x2 - x1) * ((A_Index - 0.5) / 8.0)
                c := this.GetPixelNorm(gx, gy)
                if (c != 0)
                    nonZero++
                qc := c & 0xFCFCFC
                hash := ((hash ^ qc) * 16777619) & 0x7FFFFFFFFFFFFFFF
            }
        }
        return nonZero ? (hash ? hash : 1) : 0
    }

    ; Returns true if 32-bit pixel `px` (0xAARRGGBB) matches either:
    ;   1. Unoccluded #AAFF00 lime cash text (g >= 175, b <= 16, r/g ~ 0.667), or
    ;   2. Hotbar-dimmed #AAFF00 cash text under Roblox's 60%-alpha dark hotbar
    ;      slot background (rgb(68,95,20): g 82..120, r 58..86, b 16..24).
    ; Rejects green plant icons (which have b >= 18 at high g) and the dollar-
    ; bill icon (which has b >= 40).
    static IsLimeCashPixel(px) {
        r := (px >> 16) & 0xFF, g := (px >> 8) & 0xFF, b := px & 0xFF
        if (g >= 175 && r >= 110 && r <= 195 && b <= 16 && Abs(r - Round(g * 0.667)) <= 28)
            return true
        if (g >= 82 && g <= 120 && r >= 58 && r <= 86 && b >= 16 && b <= 24 && Abs((r - b) - Round((g - b) * 0.64)) <= 6)
            return true
        return false
    }

    ; Scans `searchBox` (default bottom-left quadrant [0.06, 0.68, 0.55, 0.99])
    ; for horizontal rows containing Roblox's #AAFF00 lime-green cash font
    ; (including cash text overlapped by the translucent dark inventory hotbar).
    ; Isolates the cash digits from the floating +$income popup, dollar-bill icon,
    ; and hotbar item icons. Returns "" if no lime band is found.
    AutoLocateCashBand(searchBox := "") {
        if !(searchBox is Array) || searchBox.Length < 4
            searchBox := [0.06, 0.68, 0.55, 0.99]
        xMinScan := Max(0, Round(this.width * Max(0.055, searchBox[1])))
        xMaxScan := Min(this.width, Round(this.width * searchBox[3]))
        yMinScan := Max(0, Round(this.height * searchBox[2]))
        yMaxScan := Min(this.height, Round(this.height * searchBox[4]))
        if (xMaxScan <= xMinScan || yMaxScan <= yMinScan)
            return ""

        bands := []
        inBand := false, bTop := 0, bBot := 0, bLeft := xMaxScan, bRight := xMinScan, gap := 0, bHits := 0
        minBandH := Max(4, Round(this.height * 0.015))
        maxGap := Max(1, Round(this.height * 0.004))

        y := yMinScan
        while (y < yMaxScan) {
            rowHits := 0, rLeft := xMaxScan, rRight := xMinScan
            rowPtr := this.pixels.Ptr + y * this.stride
            x := xMinScan
            while (x < xMaxScan) {
                if FrameBuffer.IsLimeCashPixel(NumGet(rowPtr + x * 4, "uint")) {
                    rowHits++
                    if (x < rLeft)
                        rLeft := x
                    if (x > rRight)
                        rRight := x
                }
                x++
            }
            if (rowHits >= 2) {
                if !inBand {
                    inBand := true, bTop := y, bLeft := rLeft, bRight := rRight, bHits := rowHits
                } else {
                    if (rLeft < bLeft)
                        bLeft := rLeft
                    if (rRight > bRight)
                        bRight := rRight
                    bHits += rowHits
                }
                bBot := y, gap := 0
            } else if inBand {
                gap++
                if (gap >= maxGap) {
                    if (bBot - bTop >= minBandH && (bRight - bLeft) >= (bBot - bTop) * 1.4)
                        bands.Push({box: [bLeft, bTop, bRight, bBot], w: bRight - bLeft, hits: bHits})
                    inBand := false
                }
            }
            y++
        }
        if (inBand && bBot - bTop >= minBandH && (bRight - bLeft) >= (bBot - bTop) * 1.4)
            bands.Push({box: [bLeft, bTop, bRight, bBot], w: bRight - bLeft, hits: bHits})

        if !bands.Length
            return ""
        best := bands[bands.Length]
        for b in bands {
            if (b.w > best.w * 1.35 || b.hits > best.hits * 1.5)
                best := b
        }
        last := best.box
        bandH := last[4] - last[2]

        ; 1. Horizontal cluster refinement: split across empty column gaps >= 0.42 * bandH
        ;    and pick the widest cluster (cleanly drops any left-side dollar-bill icon edge).
        hClusters := []
        inC := false, c0 := 0, c1 := 0, cGap := 0, maxCGap := Max(4, Round(bandH * 0.42))
        x := last[1]
        while (x <= last[3]) {
            colHits := 0
            y := last[2]
            while (y <= last[4]) {
                if FrameBuffer.IsLimeCashPixel(NumGet(this.pixels.Ptr + y * this.stride + x * 4, "uint"))
                    colHits++
                y++
            }
            if (colHits >= 2) {
                if !inC
                    inC := true, c0 := x
                c1 := x, cGap := 0
            } else if inC {
                cGap++
                if (cGap >= maxCGap) {
                    hClusters.Push([c0, c1])
                    inC := false
                }
            }
            x++
        }
        if inC
            hClusters.Push([c0, c1])
        if hClusters.Length {
            bestC := hClusters[hClusters.Length]
            for hc in hClusters
                if ((hc[2] - hc[1]) > (bestC[2] - bestC[1]))
                    bestC := hc
            last[1] := bestC[1], last[3] := bestC[2]
        }

        ; 2. Recompute tight vertical bounds strictly inside the horizontal cluster
        newTop := last[4], newBot := last[2]
        y := last[2]
        while (y <= last[4]) {
            cHits := 0
            x := last[1]
            while (x <= last[3]) {
                if FrameBuffer.IsLimeCashPixel(NumGet(this.pixels.Ptr + y * this.stride + x * 4, "uint"))
                    cHits++
                x++
            }
            if (cHits >= 4) {
                if (y < newTop)
                    newTop := y
                if (y > newBot)
                    newBot := y
            }
            y++
        }
        if (newBot > newTop)
            last[2] := newTop, last[4] := newBot

        bandH := Max(4, last[4] - last[2])
        padX := Max(2, Round(bandH * 0.12))
        padTop := Max(1, Round(bandH * 0.08))
        padBot := 0
        return [
            Max(0.0, (last[1] - padX) / this.width),
            Max(0.0, (last[2] - padTop) / this.height),
            Min(1.0, (last[3] + padX) / this.width),
            Min(1.0, (last[4] + padBot) / this.height)
        ]
    }

    ; Segments individual characters in `band` and checks upper-right loop density
    ; on a 12x16 grid to disambiguate '6' (open top-right <= 28%) vs '8' (closed top-right >= 42%).
    VerifyCashDigits(band, parsedCash) {
        if !(band is Array) || (parsedCash = "")
            return parsedCash
        x0 := Max(0, Round(this.width * band[1]))
        y0 := Max(0, Round(this.height * band[2]))
        x1 := Min(this.width - 1, Round(this.width * band[3]))
        y1 := Min(this.height - 1, Round(this.height * band[4]))

        segs := []
        inSeg := false, s0 := 0, s1 := 0
        x := x0
        while (x <= x1) {
            hits := 0
            y := y0
            while (y <= y1) {
                if FrameBuffer.IsLimeCashPixel(this.GetPixelXY(x, y))
                    hits++
                y++
            }
            if (hits >= 2) {
                if !inSeg
                    inSeg := true, s0 := x
                s1 := x
            } else if inSeg {
                if (s1 - s0 >= 2)
                    segs.Push([s0, s1])
                inSeg := false
            }
            x++
        }
        if (inSeg && s1 - s0 >= 2)
            segs.Push([s0, s1])

        fullSegs := []
        for seg in segs {
            ty0 := y1, ty1 := y0
            y := y0
            while (y <= y1) {
                sx := seg[1]
                while (sx <= seg[2]) {
                    if FrameBuffer.IsLimeCashPixel(this.GetPixelXY(sx, y)) {
                        if (y < ty0)
                            ty0 := y
                        if (y > ty1)
                            ty1 := y
                    }
                    sx++
                }
                y++
            }
            if (ty1 - ty0 >= (y1 - y0) * 0.45)
                fullSegs.Push({x0: seg[1], x1: seg[2], y0: ty0, y1: ty1})
        }

        noDot := StrReplace(parsedCash, ".", "")
        if (StrLen(noDot) != fullSegs.Length)
            return parsedCash

        chars := StrSplit(parsedCash)
        segIdx := 0
        out := ""
        for ch in chars {
            if (ch = ".") {
                out .= "."
                continue
            }
            segIdx++
            seg := fullSegs[segIdx]
            trHits := 0, trCnt := 0
            gy := 3
            while (gy <= 6) {
                sy := seg.y0 + Round((seg.y1 - seg.y0) * (gy / 15.0))
                gx := 7
                while (gx <= 11) {
                    sx := seg.x0 + Round((seg.x1 - seg.x0) * (gx / 11.0))
                    if FrameBuffer.IsLimeCashPixel(this.GetPixelXY(sx, sy))
                        trHits++
                    trCnt++
                    gx++
                }
                gy++
            }
            tr := Round((trHits / trCnt) * 100)
            if (ch = "6" && tr >= 42)
                ch := "8"
            else if (ch = "8" && tr <= 28)
                ch := "6"
            out .= ch
        }
        return out
    }

    ; Upscales normalized `box` using GDI+ HighQualityBicubic so the output
    ; text height is at least `minHeight` px, surrounded by `pad` px of solid
    ; `bgRgb` border so glyphs never touch the bitmap edge.
    CropBicubicPadded(box, minHeight := 96, pad := 20, bgRgb := 0x181818) {
        x0 := Max(0, Min(this.width - 1, Round(this.width * box[1])))
        y0 := Max(0, Min(this.height - 1, Round(this.height * box[2])))
        x1 := Max(x0 + 1, Min(this.width, Round(this.width * box[3])))
        y1 := Max(y0 + 1, Min(this.height, Round(this.height * box[4])))
        sw := x1 - x0, sh := y1 - y0
        scale := Max(2, Ceil(minHeight / sh))
        if !FrameBuffer.EnsureGdiPlus()
            return this.CropBgra(box, scale)

        dw := sw * scale + pad * 2, dh := sh * scale + pad * 2
        pSrcBmp := 0
        ; PixelFormat32bppRGB (0x00022009) ignores the high byte (which GDI GetDIBits leaves 0)
        DllCall("gdiplus\GdipCreateBitmapFromScan0", "int", this.width, "int", this.height,
            "int", this.stride, "int", 0x00022009, "ptr", this.pixels.Ptr, "ptr*", &pSrcBmp)
        if !pSrcBmp
            return this.CropBgra(box, scale)

        hdcScreen := DllCall("GetDC", "ptr", 0, "ptr")
        hdc := DllCall("CreateCompatibleDC", "ptr", hdcScreen, "ptr")
        hbm := DllCall("CreateCompatibleBitmap", "ptr", hdcScreen, "int", dw, "int", dh, "ptr")
        oldBm := DllCall("SelectObject", "ptr", hdc, "ptr", hbm, "ptr")
        try {
            colorRef := ((bgRgb & 0xFF) << 16) | (bgRgb & 0xFF00) | ((bgRgb >> 16) & 0xFF)
            hBrush := DllCall("CreateSolidBrush", "uint", colorRef, "ptr")
            rc := Buffer(16, 0), NumPut("int", dw, rc, 8), NumPut("int", dh, rc, 12)
            DllCall("FillRect", "ptr", hdc, "ptr", rc, "ptr", hBrush)
            DllCall("DeleteObject", "ptr", hBrush)

            pGfx := 0
            DllCall("gdiplus\GdipCreateFromHDC", "ptr", hdc, "ptr*", &pGfx)
            if pGfx {
                DllCall("gdiplus\GdipSetInterpolationMode", "ptr", pGfx, "int", 7) ; HighQualityBicubic
                DllCall("gdiplus\GdipSetPixelOffsetMode", "ptr", pGfx, "int", 4)   ; Half
                DllCall("gdiplus\GdipDrawImageRectRectI", "ptr", pGfx, "ptr", pSrcBmp,
                    "int", pad, "int", pad, "int", sw * scale, "int", sh * scale,
                    "int", x0, "int", y0, "int", sw, "int", sh, "int", 2, "ptr", 0, "ptr", 0, "ptr", 0)
                DllCall("gdiplus\GdipDeleteGraphics", "ptr", pGfx)
            }
            bi := Buffer(40, 0)
            NumPut("uint", 40, bi, 0), NumPut("int", dw, bi, 4), NumPut("int", -dh, bi, 8)
            NumPut("ushort", 1, bi, 12), NumPut("ushort", 32, bi, 14)
            out := Buffer(dw * dh * 4)
            DllCall("GetDIBits", "ptr", hdc, "ptr", hbm, "uint", 0, "uint", dh, "ptr", out, "ptr", bi, "uint", 0)
            return {width: dw, height: dh, pixels: out}
        } finally {
            DllCall("gdiplus\GdipDisposeImage", "ptr", pSrcBmp)
            DllCall("SelectObject", "ptr", hdc, "ptr", oldBm)
            DllCall("DeleteObject", "ptr", hbm)
            DllCall("DeleteDC", "ptr", hdc)
            DllCall("ReleaseDC", "ptr", 0, "ptr", hdcScreen)
        }
    }

    ; Upscales `box` with GDI+ Bicubic and converts both unoccluded #AAFF00 and
    ; hotbar-dimmed (rgb(68,95,20)) lime cash pixels into smooth anti-aliased
    ; black text on a pure white background, while rejecting green plant icons.
    CropCashSoftMask(box, minHeight := 110, pad := 24) {
        c := this.CropBicubicPadded(box, minHeight, pad, 0x004F00)
        ptr := c.pixels.Ptr
        loop c.width * c.height {
            off := (A_Index - 1) * 4
            px := NumGet(ptr + off, "uint")
            r := (px >> 16) & 0xFF, g := (px >> 8) & 0xFF, b := px & 0xFF
            chroma := g - b, rb := r - b
            val := 255
            if (chroma >= 44 && rb >= 26 && ((g >= 140 && b <= 18) || (g < 140 && b <= 28))) {
                ratioDiff := Abs(rb - Round(chroma * 0.65))
                if (ratioDiff <= Round(chroma * 0.20) + 5)
                    val := Max(0, 255 - (chroma - 42) * 8)
            }
            NumPut("uint", 0xFF000000 | (val << 16) | (val << 8) | val, ptr + off)
        }
        return c
    }

    ; Upscales `box` with GDI+ Bicubic and converts bright white/lime HUD text
    ; into smooth anti-aliased black text on a pure white background.
    CropWhiteSoftMask(box, minHeight := 90, pad := 20) {
        c := this.CropBicubicPadded(box, minHeight, pad, 0x181818)
        ptr := c.pixels.Ptr
        loop c.width * c.height {
            off := (A_Index - 1) * 4
            px := NumGet(ptr + off, "uint")
            r := (px >> 16) & 0xFF, g := (px >> 8) & 0xFF, b := px & 0xFF
            minCh := Min(r, Min(g, b))
            limeStrength := Max(0, Min(255, (g - b) - Abs(r - Round(g * 0.66))))
            strength := Max(minCh, limeStrength)
            val := (strength > 145) ? Max(0, 255 - (strength - 145) * 3) : 255
            NumPut("uint", 0xFF000000 | (val << 16) | (val << 8) | val, ptr + off)
        }
        return c
    }

    ; Crops normalized box [x1, y1, x2, y2] into a top-down 32-bit BGRA Buffer
    ; using integer nearest-neighbor scaling. Returns {width, height, pixels}.
    CropBgra(box, scale := 2) {
        x0 := Max(0, Min(this.width - 1, Round(this.width * box[1])))
        y0 := Max(0, Min(this.height - 1, Round(this.height * box[2])))
        x1 := Max(x0 + 1, Min(this.width, Round(this.width * box[3])))
        y1 := Max(y0 + 1, Min(this.height, Round(this.height * box[4])))
        srcW := x1 - x0, srcH := y1 - y0
        scale := Max(1, Integer(scale))
        dstW := srcW * scale, dstH := srcH * scale
        dstStride := dstW * 4
        out := Buffer(dstStride * dstH)

        srcPtr := this.pixels.Ptr
        srcStride := this.stride
        dstPtr := out.Ptr

        if (scale = 1) {
            loop srcH {
                sy := y0 + A_Index - 1
                DllCall("RtlMoveMemory", "ptr", dstPtr + (A_Index - 1) * dstStride,
                    "ptr", srcPtr + sy * srcStride + x0 * 4, "uptr", dstStride)
            }
        } else {
            loop dstH {
                dy := A_Index - 1
                sy := y0 + (dy // scale)
                rowSrc := srcPtr + sy * srcStride
                rowDst := dstPtr + dy * dstStride
                loop srcW {
                    px := NumGet(rowSrc + (x0 + A_Index - 1) * 4, "uint") | 0xFF000000
                    base := rowDst + (A_Index - 1) * scale * 4
                    loop scale
                        NumPut("uint", px, base + (A_Index - 1) * 4)
                }
            }
        }
        return {width: dstW, height: dstH, pixels: out}
    }

    ; Kept for backward compatibility with tests/callers.
    CropBgraHighContrast(box, scale := 3, thresh := 170) => this.CropWhiteSoftMask(box, 90, 20)
}
