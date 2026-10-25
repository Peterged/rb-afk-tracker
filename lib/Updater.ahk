; =============================================================================
; Updater.ahk - Atomic SHA-256 verified Over-The-Air (OTA) updater backed by a
; public GitHub repository (raw.githubusercontent.com).
;
; - Fetches `manifest.json` (with cache-busting query string & no-cache headers)
; - Compares semantic version against local `VERSION`
; - Stages changed files into `.update_stage\`, verifies SHA-256 via Windows
;   CNG (`bcrypt.dll`) before touching any live file
; - Atomically swaps staged files into place, preserves `settings.ini` and
;   `state.ini`, and triggers a hot reload.
; =============================================================================

class HttpSync {
    GetBytes(url) {
        req := ComObject("Msxml2.XMLHTTP.6.0")
        sep := InStr(url, "?") ? "&" : "?"
        bustUrl := url sep "_t=" A_TickCount
        req.open("GET", bustUrl, false)
        req.setRequestHeader("Cache-Control", "no-cache, no-store, must-revalidate")
        req.setRequestHeader("Pragma", "no-cache")
        req.send()
        if (req.status != 200)
            throw Error("HTTP " req.status " for " url)
        return Updater.VariantToBuffer(req.responseBody)
    }

    GetText(url) {
        buf := this.GetBytes(url)
        ; Strip UTF-8 BOM if present
        offset := (buf.Size >= 3 && NumGet(buf, 0, "uchar") = 0xEF && NumGet(buf, 1, "uchar") = 0xBB && NumGet(buf, 2, "uchar") = 0xBF) ? 3 : 0
        return StrGet(buf.Ptr + offset, buf.Size - offset, "UTF-8")
    }
}

class Updater {
    __New(cfg, logger, rootDir := "", http := "") {
        this.cfg := cfg
        this.logger := logger
        this.rootDir := (rootDir != "") ? rootDir : A_ScriptDir
        this.http := http ? http : HttpSync()
    }

    ; Returns the local semantic version string (e.g. "1.0.0").
    LocalVersion() {
        vPath := this.rootDir "\VERSION"
        if FileExist(vPath) {
            try return Trim(FileRead(vPath, "UTF-8"), " `t`r`n")
        }
        return "1.0.0"
    }

    ; Resolves the base raw URL from cfg.UpdateRepo and cfg.UpdateBranch.
    ; Accepts either "owner/repo", "https://github.com/owner/repo", or a full raw base URL.
    BaseUrl() {
        repo := Trim(this.cfg.UpdateRepo)
        if (repo = "")
            return ""
        repo := RegExReplace(repo, "/+$", "")
        if RegExMatch(repo, "i)^https?://raw\.githubusercontent\.com/")
            return repo
        if RegExMatch(repo, "i)^https?://github\.com/([^/]+/[^/]+?)(?:\.git)?$", &m)
            repo := m[1]
        if RegExMatch(repo, "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$") {
            branch := (this.cfg.UpdateBranch != "") ? this.cfg.UpdateBranch : "main"
            return "https://raw.githubusercontent.com/" repo "/" branch
        }
        return repo
    }

    ; Checks for an update and stages/applies it atomically.
    ; Returns {status: "up-to-date"|"updated"|"unconfigured"|"error", version: "...", message: "..."}
    CheckAndApply(interactive := false, onBeforeReload := "") {
        base := this.BaseUrl()
        if (base = "") {
            if interactive {
                ib := InputBox(
                    "Enter your public GitHub repository (e.g. username/roblox-afk-monitor):`n`n"
                    . "Once saved, future updates will download automatically.",
                    "Configure Auto-Update Repository", "w380 h150")
                if (ib.Result != "OK" || Trim(ib.Value) = "")
                    return {status: "unconfigured", version: this.LocalVersion(), message: "Update repository not configured."}
                this.cfg.SetUpdateRepo(Trim(ib.Value))
                base := this.BaseUrl()
            } else {
                return {status: "unconfigured", version: this.LocalVersion(), message: "Update repository not configured."}
            }
        }

        try {
            manifestText := this.http.GetText(base "/manifest.json")
            manifest := Updater.ParseManifest(manifestText)
            if (manifest.version = "" || !manifest.files.Length)
                throw Error("Invalid manifest.json format")

            localVer := this.LocalVersion()
            if (Updater.CompareSemver(manifest.version, localVer) <= 0) {
                msg := "You are on the latest version (v" localVer ")."
                if interactive
                    MsgBox(msg, "Check for updates", "Iconi")
                return {status: "up-to-date", version: localVer, message: msg}
            }

            stageDir := this.rootDir "\.update_stage"
            if DirExist(stageDir)
                DirDelete(stageDir, true)
            DirCreate(stageDir)

            staged := []
            for item in manifest.files {
                relPath := StrReplace(item.path, "/", "\")
                ; Security check: reject path traversal or config overwrites
                if (InStr(relPath, "..") || InStr(relPath, ":") || SubStr(relPath, 1, 1) = "\"
                    || StrLower(relPath) = "settings.ini" || StrLower(relPath) = "state.ini")
                    throw Error("Unsafe manifest path: " item.path)

                localPath := this.rootDir "\" relPath
                if FileExist(localPath) {
                    localHash := Updater.Sha256File(localPath)
                    if (StrLower(localHash) = StrLower(item.sha256))
                        continue
                }

                urlPath := StrReplace(relPath, "\", "/")
                bytes := this.http.GetBytes(base "/" urlPath)
                dlHash := Updater.Sha256Buffer(bytes)
                if (StrLower(dlHash) != StrLower(item.sha256))
                    throw Error("SHA-256 mismatch for " item.path " (expected " item.sha256 ", got " dlHash ")")

                stagePath := stageDir "\" relPath
                SplitPath(stagePath, , &stageParent)
                if (stageParent != "" && !DirExist(stageParent))
                    DirCreate(stageParent)
                f := FileOpen(stagePath, "w")
                f.RawWrite(bytes, bytes.Size)
                f.Close()
                staged.Push({stagePath: stagePath, destPath: localPath, relPath: relPath})
            }

            ; All changed files verified -> swap atomically into place
            for s in staged {
                SplitPath(s.destPath, , &destParent)
                if (destParent != "" && !DirExist(destParent))
                    DirCreate(destParent)
                FileMove(s.stagePath, s.destPath, 1)
            }

            ; Update local VERSION and manifest.json
            vFile := FileOpen(this.rootDir "\VERSION", "w", "UTF-8-RAW")
            vFile.Write(manifest.version "`n")
            vFile.Close()
            mFile := FileOpen(this.rootDir "\manifest.json", "w", "UTF-8-RAW")
            mFile.Write(manifestText)
            mFile.Close()

            try DirDelete(stageDir, true)

            this.logger.Info("Auto-updated from v" localVer " to v" manifest.version " (" staged.Length " file(s) updated)")
            if interactive
                MsgBox("Updated to v" manifest.version " (" staged.Length " file(s)). The monitor will now reload.",
                    "Update complete", "Iconi T3")
            if onBeforeReload
                onBeforeReload()
            return {status: "updated", version: manifest.version, count: staged.Length, message: "Updated to v" manifest.version}
        } catch as e {
            try {
                if DirExist(this.rootDir "\.update_stage")
                    DirDelete(this.rootDir "\.update_stage", true)
            }
            this.logger.Warn("Update check failed: " e.Message)
            if interactive
                MsgBox("Update check failed:`n" e.Message, "Check for updates", "Icon!")
            return {status: "error", version: this.LocalVersion(), message: e.Message}
        }
    }

    ; Parses our structured `manifest.json` without external JSON dependencies.
    static ParseManifest(json) {
        ver := ""
        if RegExMatch(json, '"version"\s*:\s*"([^"]+)"', &vm)
            ver := Trim(vm[1])
        files := []
        pos := 1
        while RegExMatch(json, '\{\s*"path"\s*:\s*"([^"]+)"\s*,\s*"sha256"\s*:\s*"([0-9a-fA-F]{64})"(?:\s*,\s*"size"\s*:\s*(\d+))?\s*\}', &fm, pos) {
            files.Push({path: fm[1], sha256: StrLower(fm[2]), size: fm[3] != "" ? Integer(fm[3]) : 0})
            pos := fm.Pos + fm.Len
        }
        return {version: ver, files: files}
    }

    ; Returns 1 if a > b, -1 if a < b, 0 if equal (e.g. "1.2.0" vs "1.1.9").
    static CompareSemver(a, b) {
        a := RegExReplace(Trim(a), "^[vV]", "")
        b := RegExReplace(Trim(b), "^[vV]", "")
        pa := StrSplit(a, ".")
        pb := StrSplit(b, ".")
        loop Max(pa.Length, pb.Length) {
            va := (A_Index <= pa.Length && IsInteger(pa[A_Index])) ? Integer(pa[A_Index]) : 0
            vb := (A_Index <= pb.Length && IsInteger(pb[A_Index])) ? Integer(pb[A_Index]) : 0
            if (va > vb)
                return 1
            if (va < vb)
                return -1
        }
        return 0
    }

    ; Computes lowercase hex SHA-256 of a Buffer using Windows CNG (`bcrypt.dll`).
    static Sha256Buffer(buf) {
        static BCRYPT_SHA256_ALG_HANDLE := 0x00000041   ; pseudo-handle supported on Win10+
        hash := Buffer(32, 0)
        hr := DllCall("bcrypt\BCryptHash", "ptr", BCRYPT_SHA256_ALG_HANDLE, "ptr", 0, "uint", 0,
            "ptr", buf.Ptr, "uint", buf.Size, "ptr", hash.Ptr, "uint", 32, "uint")
        if (hr != 0)
            throw Error("BCryptHash failed: 0x" Format("{:X}", hr))
        hex := ""
        loop 32
            hex .= Format("{:02x}", NumGet(hash, A_Index - 1, "uchar"))
        return hex
    }

    static Sha256File(path) {
        buf := FileRead(path, "RAW")
        return Updater.Sha256Buffer(buf)
    }

    ; Converts a COM SAFEARRAY of VT_UI1 (from XMLHTTP.responseBody) into an AHK Buffer.
    static VariantToBuffer(var) {
        psa := ComObjValue(var)
        len := DllCall("oleaut32\SafeArrayGetElemsize", "ptr", psa, "uint")
        lbound := 0, ubound := -1
        DllCall("oleaut32\SafeArrayGetLBound", "ptr", psa, "uint", 1, "int*", &lbound)
        DllCall("oleaut32\SafeArrayGetUBound", "ptr", psa, "uint", 1, "int*", &ubound)
        cnt := Max(0, ubound - lbound + 1)
        out := Buffer(cnt)
        if (cnt > 0) {
            pData := 0
            DllCall("oleaut32\SafeArrayAccessData", "ptr", psa, "ptr*", &pData)
            DllCall("RtlMoveMemory", "ptr", out.Ptr, "ptr", pData, "uptr", cnt)
            DllCall("oleaut32\SafeArrayUnaccessData", "ptr", psa)
        }
        return out
    }
}
