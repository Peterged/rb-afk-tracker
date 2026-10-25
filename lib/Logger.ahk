; =============================================================================
; Logger.ahk - Append-only event log with simple size-based rotation.
; Never throws: if the log can't be written the line goes to OutputDebug.
; =============================================================================

class Logger {
    __New(path, maxBytes := 1048576) {
        this.path := path
        this.maxBytes := maxBytes
        SplitPath(path, , &dir)
        if (dir != "" && !DirExist(dir)) {
            try DirCreate(dir)
        }
    }

    Info(msg) => this.Log("INFO", msg)
    Warn(msg) => this.Log("WARN", msg)
    Error(msg) => this.Log("ERROR", msg)

    Log(level, msg) {
        line := FormatTime(, "yyyy-MM-dd HH:mm:ss") " [" level "] " msg "`n"
        try {
            if (this.maxBytes > 0 && FileExist(this.path) && FileGetSize(this.path) >= this.maxBytes)
                FileMove(this.path, this.path ".1", 1)
            FileAppend(line, this.path, "UTF-8")
        } catch as e {
            OutputDebug("Logger failed (" e.Message "): " line)
        }
    }
}
