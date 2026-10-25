; =============================================================================
; Assert.ahk - Minimal assertion and test runner helpers.
; =============================================================================

class TestSuite {
    static Passed := 0
    static Failed := 0
    static Failures := []

    static Run(name, fn) {
        try {
            fn.Call()
            TestSuite.Passed++
            FileAppend("PASS  " name "`n", "*")
        } catch as e {
            TestSuite.Failed++
            msg := "FAIL  " name " -> " e.Message " (" e.File ":" e.Line ")"
            TestSuite.Failures.Push(msg)
            FileAppend(msg "`n", "*")
        }
    }

    static Equal(actual, expected, label := "") {
        if !(actual == expected)
            throw Error(Format("{}expected '{}' but got '{}'", label != "" ? label ": " : "", String(expected), String(actual)), -1)
    }

    static True(cond, label := "expected true") {
        if !cond
            throw Error(label, -1)
    }

    static False(cond, label := "expected false") {
        if cond
            throw Error(label, -1)
    }
}
