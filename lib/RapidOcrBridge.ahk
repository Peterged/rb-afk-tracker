; =============================================================================
; RapidOcrBridge.ahk - Optional persistent bridge to `rapidocr_worker.py`
; (PaddleOCR v4 ONNX via rapidocr_onnxruntime).
;
; Probes installed Python runtimes (`py -3.12`, `py -3.11`, `py -3.13`, `py`)
; once at startup with CREATE_NO_WINDOW. If `rapidocr_onnxruntime` is installed,
; keeps the worker alive for fast (~25ms) scene-text OCR; otherwise sets
; `this.Available := false` so WinRtOcr handles all OCR natively.
; =============================================================================

class RapidOcrBridge {
    __New(workerPath := "") {
        this.Available := false
        this.proc := ""
        this.stdin := ""
        this.stdout := ""
        if (workerPath = "")
            workerPath := A_ScriptDir "\lib\rapidocr_worker.py"
        if !FileExist(workerPath)
            return
        this.TryStart(workerPath)
    }

    __Delete() {
        this.Stop()
    }

    TryStart(workerPath) {
        try {
            shell := ComObject("WScript.Shell")
            ; Probe standard Python versions with onnxruntime wheels (`cp310`..`cp313`)
            for pyCmd in ['py -3.12', 'py -3.11', 'py -3.13', 'py -3.10', 'py'] {
                code := shell.Run('cmd.exe /c ' pyCmd ' -c "import rapidocr_onnxruntime" >nul 2>&1', 0, true)
                if (code != 0)
                    continue
                exec := shell.Exec(pyCmd ' -u "' workerPath '"')
                line := exec.StdOut.ReadLine()
                if (InStr(line, "READY") = 1) {
                    this.proc := exec
                    this.stdin := exec.StdIn
                    this.stdout := exec.StdOut
                    this.Available := true
                    return
                }
                try exec.Terminate()
            }
        }
    }

    ; Recognizes text from a {width, height, pixels} BGRA crop object.
    RecognizeCrop(crop) {
        if (!this.Available || !crop)
            return ""
        try {
            bmp := RapidOcrBridge.PackBmp(crop.width, crop.height, crop.pixels)
            b64 := RapidOcrBridge.ToBase64(bmp)
            this.stdin.WriteLine(b64)
            resp := this.stdout.ReadLine()
            if (SubStr(resp, 1, 3) = "OK`t")
                return SubStr(resp, 4)
        } catch {
            this.Available := false
        }
        return ""
    }

    Stop() {
        if this.Available {
            try this.stdin.WriteLine("EXIT")
            try this.proc.Terminate()
            this.Available := false
        }
    }

    static PackBmp(w, h, pixels) {
        imgSize := w * h * 4
        bmp := Buffer(54 + imgSize, 0)
        NumPut("ushort", 0x4D42, bmp, 0)
        NumPut("uint", 54 + imgSize, bmp, 2)
        NumPut("uint", 54, bmp, 10)
        NumPut("uint", 40, bmp, 14)
        NumPut("int", w, bmp, 18)
        NumPut("int", -h, bmp, 22)
        NumPut("ushort", 1, bmp, 26)
        NumPut("ushort", 32, bmp, 28)
        NumPut("uint", imgSize, bmp, 34)
        DllCall("RtlMoveMemory", "ptr", bmp.Ptr + 54, "ptr", pixels.Ptr, "uptr", imgSize)
        return bmp
    }

    static ToBase64(buf) {
        chars := 0
        ; CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF = 0x40000001
        DllCall("crypt32\CryptBinaryToStringW", "ptr", buf.Ptr, "uint", buf.Size, "uint", 0x40000001, "ptr", 0, "uint*", &chars)
        out := Buffer(chars * 2)
        DllCall("crypt32\CryptBinaryToStringW", "ptr", buf.Ptr, "uint", buf.Size, "uint", 0x40000001, "ptr", out.Ptr, "uint*", &chars)
        return StrGet(out.Ptr, chars, "UTF-16")
    }
}
