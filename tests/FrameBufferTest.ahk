; =============================================================================
; FrameBufferTest.ahk - Tests for FrameBuffer pixel access, viewport hash,
; cropping, and end-to-end WinRT OCR on a rendered GDI bitmap.
; =============================================================================

RunFrameBufferTests() {
    TestSuite.Run("FrameBuffer: pixel read/write, viewport hash, and 1-LSB noise immunity", Test_FbPixelsAndHash)
    TestSuite.Run("FrameBuffer: AutoLocateCashBand isolates bottom-most #AAFF00 cash row", Test_FbAutoLocateCashBand)
    TestSuite.Run("FrameBuffer + WinRtOcr: end-to-end OCR on rendered HUD text and multi-resolution cash", Test_FbWinRtOcrEndToEnd)
}

Test_FbPixelsAndHash() {
    ; All-black frame returns hash 0 (treated as blank/unrendered)
    black := FrameBuffer.CreateSolid(200, 100, 0x000000)
    box := [0.25, 0.15, 0.75, 0.65]
    TestSuite.Equal(black.ComputeViewportHash(box), 0)

    ; Non-black frame returns deterministic non-zero hash
    fb1 := FrameBuffer.CreateSolid(200, 100, 0x385828)
    TestSuite.Equal(fb1.GetPixelXY(10, 10), 0x385828)
    h1 := fb1.ComputeViewportHash(box)
    TestSuite.True(h1 != 0, "non-black viewport hash should be non-zero")

    ; 1-LSB dither change produces identical quantized hash
    fbDither := FrameBuffer.CreateSolid(200, 100, 0x395929)
    TestSuite.Equal(fbDither.ComputeViewportHash(box), h1, "1-LSB noise should not change hash")

    ; Significant color change produces a different hash
    fb2 := FrameBuffer.CreateSolid(200, 100, 0x802040)
    TestSuite.True(fb2.ComputeViewportHash(box) != h1, "different frame should change hash")

    ; CropBgra scales dimensions by `scale`
    crop := fb1.CropBgra([0.0, 0.0, 0.5, 0.5], 2)
    TestSuite.Equal(crop.width, 200)
    TestSuite.Equal(crop.height, 100)
}

Test_FbAutoLocateCashBand() {
    ; Synthetic 600x400 frame with dark green grass background (0x007000)
    ; and two #AAFF00 rows: floating popup at y=300..315, main cash at y=355..385, x=60..190
    w := 600, h := 400
    fb := FrameBuffer.CreateSolid(w, h, 0x007000)
    ; Paint floating popup row (y=302..312, x=75..150)
    loop 10 {
        rowY := 301 + A_Index
        rowOff := (rowY * w) * 4
        loop 75 {
            colX := 74 + A_Index
            NumPut("uint", 0xFFAAFF00, fb.pixels, rowOff + colX * 4)
        }
    }
    ; Paint main bottom cash row (y=355..382, x=60..190)
    loop 27 {
        rowY := 354 + A_Index
        rowOff := (rowY * w) * 4
        loop 130 {
            colX := 59 + A_Index
            NumPut("uint", 0xFFAAFF00, fb.pixels, rowOff + colX * 4)
        }
    }
    band := fb.AutoLocateCashBand()
    TestSuite.True(IsObject(band), "AutoLocateCashBand should find the #AAFF00 cash row")
    ; Should lock onto the bottom-most cluster (y around 355..382 -> 0.88..0.95), not the popup at y=302 (0.75)
    TestSuite.True(band[2] > 0.84, "band top should be below the floating popup (got " band[2] ")")
    TestSuite.True(band[3] >= 0.30, "band right should cover x=190/600 (got " band[3] ")")

    softCrop := fb.CropCashSoftMask(band, 96, 20)
    TestSuite.True(softCrop.width > 300 && softCrop.height >= 120, "soft mask crop should be upscaled + padded")
}

Test_FbWinRtOcrEndToEnd() {
    ocr := WinRtOcr()
    if !ocr.Available
        return   ; skip only if Windows OCR language pack is absent

    ; Render "Friend Boost: +40% 3.56M" onto an off-screen GDI bitmap
    w := 520, h := 100
    hdcScreen := DllCall("GetDC", "ptr", 0, "ptr")
    hdc := DllCall("CreateCompatibleDC", "ptr", hdcScreen, "ptr")
    hbm := DllCall("CreateCompatibleBitmap", "ptr", hdcScreen, "int", w, "int", h, "ptr")
    oldBm := DllCall("SelectObject", "ptr", hdc, "ptr", hbm, "ptr")

    hBrush := DllCall("CreateSolidBrush", "uint", 0x1E1E1E, "ptr")
    rc := Buffer(16, 0), NumPut("int", w, rc, 8), NumPut("int", h, rc, 12)
    DllCall("FillRect", "ptr", hdc, "ptr", rc, "ptr", hBrush)
    DllCall("DeleteObject", "ptr", hBrush)

    hFont := DllCall("CreateFontW", "int", -28, "int", 0, "int", 0, "int", 0, "int", 700,
        "uint", 0, "uint", 0, "uint", 0, "uint", 1, "uint", 0, "uint", 0, "uint", 5, "uint", 0, "wstr", "Segoe UI", "ptr")
    oldFont := DllCall("SelectObject", "ptr", hdc, "ptr", hFont, "ptr")
    DllCall("SetBkMode", "ptr", hdc, "int", 1)
    DllCall("SetTextColor", "ptr", hdc, "uint", 0xFFFFFF)
    txt := "Friend Boost: +40%  3.56M"
    DllCall("TextOutW", "ptr", hdc, "int", 16, "int", 32, "wstr", txt, "int", StrLen(txt))

    bi := Buffer(40, 0)
    NumPut("uint", 40, bi, 0), NumPut("int", w, bi, 4), NumPut("int", -h, bi, 8)
    NumPut("ushort", 1, bi, 12), NumPut("ushort", 32, bi, 14)
    pixels := Buffer(w * h * 4)
    DllCall("GetDIBits", "ptr", hdc, "ptr", hbm, "uint", 0, "uint", h, "ptr", pixels, "ptr", bi, "uint", 0)

    DllCall("SelectObject", "ptr", hdc, "ptr", oldFont), DllCall("DeleteObject", "ptr", hFont)
    DllCall("SelectObject", "ptr", hdc, "ptr", oldBm), DllCall("DeleteObject", "ptr", hbm)
    DllCall("DeleteDC", "ptr", hdc), DllCall("ReleaseDC", "ptr", 0, "ptr", hdcScreen)

    fb := FrameBuffer(w, h, pixels)
    rawText := ocr.RecognizeRegion(fb, [0.0, 0.0, 1.0, 1.0], 1)
    parsed := VisionParsers.ParseStats(rawText)
    TestSuite.Equal(parsed.boost, 40, "OCR should read +40% boost from rendered bitmap (got raw: " rawText ")")
    TestSuite.Equal(parsed.cash, "3.56M", "OCR should read 3.56M cash from rendered bitmap (got raw: " rawText ")")
}
