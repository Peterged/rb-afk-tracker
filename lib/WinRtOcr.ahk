; =============================================================================
; WinRtOcr.ahk - OCR engine router combining:
;   1. Auto-locating #AAFF00 color-band detection + GDI+ HighQualityBicubic
;      upscaling + soft color-distance anti-aliased masking (FrameBuffer.ahk)
;   2. Optional RapidOcrBridge (PaddleOCR v4 ONNX) when installed
;   3. Built-in Windows 10/11 Windows.Media.Ocr.OcrEngine (zero-dependency)
; =============================================================================

class WinRtOcr {
    static IID_IOcrEngineStatics := "{5BFFA85A-3384-3540-9940-699120D428A8}"
    static IID_ISoftwareBitmapStatics := "{DF0385DB-672F-4A9D-806E-C2442F343E86}"
    static IID_IBufferFactory := "{71AF914D-C10F-484B-BC50-14BC623B3A27}"
    static IID_IBufferByteAccess := "{905A0FEF-BC53-11DF-8C49-001E4FC686DA}"
    static IID_IAsyncInfo := "{00000036-0000-0000-C000-000000000046}"

    __New(enableRapidOcr := false) {
        this.pEngine := 0
        this.pSwStatics := 0
        this.pBufFactory := 0
        this.rapid := enableRapidOcr ? RapidOcrBridge() : ""
        try {
            pOcrStatics := WinRtOcr.RoFactory("Windows.Media.Ocr.OcrEngine", WinRtOcr.IID_IOcrEngineStatics)
            if pOcrStatics {
                ComCall(10, pOcrStatics, "ptr*", &pEngine := 0)   ; TryCreateFromUserProfileLanguages
                ObjRelease(pOcrStatics)
                this.pEngine := pEngine
            }
            this.pSwStatics := WinRtOcr.RoFactory("Windows.Graphics.Imaging.SoftwareBitmap", WinRtOcr.IID_ISoftwareBitmapStatics)
            this.pBufFactory := WinRtOcr.RoFactory("Windows.Storage.Streams.Buffer", WinRtOcr.IID_IBufferFactory)
        }
    }

    __Delete() {
        if this.rapid
            this.rapid.Stop()
        if this.pEngine
            ObjRelease(this.pEngine), this.pEngine := 0
        if this.pSwStatics
            ObjRelease(this.pSwStatics), this.pSwStatics := 0
        if this.pBufFactory
            ObjRelease(this.pBufFactory), this.pBufFactory := 0
    }

    Available => ((this.rapid && this.rapid.Available) || (this.pEngine != 0 && this.pSwStatics != 0 && this.pBufFactory != 0))

    BackendName => (this.rapid && this.rapid.Available) ? "RapidOCR+WinRT" : this.Available ? "WinRT-Bicubic" : "unavailable"

    ; Crops `box` ([x1, y1, x2, y2]) from `frame` (FrameBuffer) and returns the
    ; recognized text, or "" on failure.
    RecognizeRegion(frame, box, scale := 2) {
        if (!this.Available || !frame)
            return ""
        srcH := Max(1, Round(frame.height * (box[4] - box[2])))
        crop := frame.CropBicubicPadded(box, Max(72, srcH * scale), 16)
        return this.RecognizeCrop(crop)
    }

    ; High-accuracy bottom-left HUD recognizer that works at any window size or
    ; aspect ratio:
    ;   1. Auto-locates the exact #AAFF00 lime Cash band (e.g. "3.56M") anywhere
    ;      inside `searchBox` (skipping the dollar-bill icon and separating it
    ;      from the floating +$income tick above it).
    ;   2. Runs Pass A (soft #AAFF00 color-distance mask) and Pass B (GDI+
    ;      HighQualityBicubic padded crop) on the tight cash band.
    ;   3. Runs white/lime HUD text recognition on `searchBox` for Friend Boost %.
    RecognizeHudRegion(frame, searchBox) {
        if (!this.Available || !frame)
            return ""
        parts := []
        cashBand := frame.AutoLocateCashBand(searchBox)
        if (cashBand is Array) {
            maskCrop := frame.CropCashSoftMask(cashBand, 110, 24)
            tMask := Trim(this.RecognizeCrop(maskCrop))
            if (tMask != "") {
                stMask := VisionParsers.ParseStats(tMask)
                if (stMask.cash != "") {
                    verified := frame.VerifyCashDigits(cashBand, stMask.cash)
                    parts.Push(verified)
                } else {
                    parts.Push(tMask)
                }
            }

            rawCrop := frame.CropBicubicPadded(cashBand, 108, 24)
            tRaw := Trim(this.RecognizeCrop(rawCrop))
            if (tRaw != "" && tRaw != tMask)
                parts.Push(tRaw)
        }
        fullMask := frame.CropWhiteSoftMask(searchBox, 90, 20)
        tFull := Trim(this.RecognizeCrop(fullMask))
        if (tFull != "")
            parts.Push(tFull)

        out := ""
        for p in parts
            out .= (out != "" ? "`n" : "") p
        return out
    }

    RecognizeCrop(crop) {
        if (this.rapid && this.rapid.Available) {
            res := this.rapid.RecognizeCrop(crop)
            if (res != "")
                return res
        }
        return this.RecognizeBgra(crop.pixels, crop.width, crop.height)
    }

    ; Runs Windows.Media.Ocr on a top-down 32-bit BGRA Buffer of dimensions w x h.
    RecognizeBgra(pixels, w, h) {
        if (!this.pEngine || w <= 0 || h <= 0)
            return ""
        imgSize := w * h * 4
        if (pixels.Size < imgSize)
            return ""
        pWinBuf := 0, pByteAccess := 0, pSwBmp := 0, pResult := 0, hText := 0
        try {
            ComCall(6, this.pBufFactory, "uint", imgSize, "ptr*", &pWinBuf)
            ComCall(8, pWinBuf, "uint", imgSize)   ; put_Length
            iidBA := WinRtOcr.Guid(WinRtOcr.IID_IBufferByteAccess)
            ComCall(0, pWinBuf, "ptr", iidBA, "ptr*", &pByteAccess)
            ComCall(3, pByteAccess, "ptr*", &pRaw := 0)
            DllCall("RtlMoveMemory", "ptr", pRaw, "ptr", pixels.Ptr, "uptr", imgSize)
            ObjRelease(pByteAccess), pByteAccess := 0

            ComCall(9, this.pSwStatics, "ptr", pWinBuf, "int", 87, "int", w, "int", h, "ptr*", &pSwBmp)
            ObjRelease(pWinBuf), pWinBuf := 0

            ComCall(6, this.pEngine, "ptr", pSwBmp, "ptr*", &pAsyncOcr := 0)
            pResult := WinRtOcr.Await(pAsyncOcr)
            if !pResult
                return ""

            ComCall(8, pResult, "ptr*", &hText)
            if !hText
                return ""
            rawPtr := DllCall("combase\WindowsGetStringRawBuffer", "ptr", hText, "uint*", &len := 0, "ptr")
            return rawPtr ? StrGet(rawPtr, len, "UTF-16") : ""
        } catch {
            return ""
        } finally {
            if hText
                DllCall("combase\WindowsDeleteString", "ptr", hText)
            if pResult
                ObjRelease(pResult)
            if pSwBmp
                ObjRelease(pSwBmp)
            if pByteAccess
                ObjRelease(pByteAccess)
            if pWinBuf
                ObjRelease(pWinBuf)
        }
    }

    static RoFactory(className, iidStr) {
        hStr := 0
        DllCall("combase\WindowsCreateString", "wstr", className, "uint", StrLen(className), "ptr*", &hStr)
        iid := WinRtOcr.Guid(iidStr)
        pOut := 0
        hr := DllCall("combase\RoGetActivationFactory", "ptr", hStr, "ptr", iid, "ptr*", &pOut, "uint")
        DllCall("combase\WindowsDeleteString", "ptr", hStr)
        return (hr = 0) ? pOut : 0
    }

    static Await(pAsync, maxWaitMs := 1000) {
        if !pAsync
            return 0
        iidInfo := WinRtOcr.Guid(WinRtOcr.IID_IAsyncInfo)
        pInfo := 0
        try {
            ComCall(0, pAsync, "ptr", iidInfo, "ptr*", &pInfo)
            status := 0
            iters := Max(1, maxWaitMs // 5)
            loop iters {
                ComCall(7, pInfo, "int*", &status)
                if (status != 0)
                    break
                Sleep(5)
            }
            res := 0
            if (status = 1)
                ComCall(8, pAsync, "ptr*", &res)
            return res
        } finally {
            if pInfo
                ObjRelease(pInfo)
            ObjRelease(pAsync)
        }
    }

    static Guid(iidStr) {
        buf := Buffer(16, 0)
        DllCall("ole32\CLSIDFromString", "wstr", iidStr, "ptr", buf)
        return buf
    }
}
