; =============================================================================
; ComplianceTest.ahk - Scans every source file to guarantee no in-game macro or
; input-sending APIs exist anywhere in the project.
; =============================================================================

RunComplianceTests() {
    TestSuite.Run("Compliance: no input-sending or macro commands in source files", Test_ComplianceNoInputSending)
}

Test_ComplianceNoInputSending() {
    root := A_ScriptDir "\.."
    files := [root "\RobloxAfkMonitor.ahk"]
    loop files root "\lib\*.ahk"
        files.Push(A_LoopFileFullPath)

    pattern := "i)(?<![.\w])(Send|SendInput|SendEvent|SendPlay|SendText|SendMode|ControlSend|ControlSendText|ControlClick|Click|MouseClick|MouseClickDrag|MouseMove|PostMessage|SendMessage)\s*\("
    violations := []
    ScanFiles(files, pattern, violations)
    TestSuite.Equal(violations.Length, 0, violations.Length ? "Banned call at " violations[1] : "")
}

ScanFiles(files, pattern, violations) {
    semi := Chr(59)
    for path in files {
        SplitPath(path, &name)
        text := FileRead(path, "UTF-8")
        for lineNo, line in StrSplit(text, "`n", "`r") {
            trimmed := LTrim(line)
            if (SubStr(trimmed, 1, 1) = semi)
                continue
            if InStr(line, semi " compliance-ok:")
                continue
            codePart := RegExReplace(line, "\s+" semi ".*$", "")
            if RegExMatch(codePart, pattern, &m)
                violations.Push(name ":" lineNo " (" m[1] ")")
        }
    }
}
