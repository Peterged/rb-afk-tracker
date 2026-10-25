; =============================================================================
; StatusTest.ahk - Unit tests for Status threshold boundaries, priority order,
; and row/header formatting.
; =============================================================================

RunStatusTests() {
    cfg := Config("")
    TestSuite.Run("Status: threshold boundaries (899/900/1079/1080s)", (*) => Test_StatusThresholds(cfg))
    TestSuite.Run("Status: priority order MISSING > HUNG > DC > URGENT", (*) => Test_StatusPriority(cfg))
    TestSuite.Run("Status: FormatRow includes ~ before first input and MIN when minimized", (*) => Test_StatusFormatRow(cfg))
    TestSuite.Run("Status: FormatHeader reports problem slot or next kick", (*) => Test_StatusFormatHeader(cfg))
}

Test_StatusThresholds(cfg) {
    slot := TrackedSlot(1, "Main")
    slot.hwnd := 101
    slot.lastInput := 0
    TestSuite.Equal(Status.Evaluate(slot, 899000, cfg), "OK")
    TestSuite.Equal(Status.Evaluate(slot, 900000, cfg), "WARN")
    TestSuite.Equal(Status.Evaluate(slot, 1079000, cfg), "WARN")
    TestSuite.Equal(Status.Evaluate(slot, 1080000, cfg), "URGENT")
}

Test_StatusPriority(cfg) {
    slot := TrackedSlot(1, "Alt1")
    TestSuite.Equal(Status.Evaluate(slot, 1000, cfg), "EMPTY")
    slot.missingSince := 500
    TestSuite.Equal(Status.Evaluate(slot, 1000, cfg), "MISSING")
    slot.hwnd := 101
    slot.lastInput := 0
    slot.dc := true
    slot.hung := true
    TestSuite.Equal(Status.Evaluate(slot, 1100000, cfg), "HUNG")
    slot.hung := false
    TestSuite.Equal(Status.Evaluate(slot, 1100000, cfg), "DC")
}

Test_StatusFormatRow(cfg) {
    slot := TrackedSlot(2, "Alt1")
    slot.hwnd := 102
    slot.lastInput := 0
    slot.minimized := true
    row := Status.FormatRow(slot, "OK", 125000, cfg)
    TestSuite.True(InStr(row, "OK~") > 0, "should show ~ before first input")
    TestSuite.True(InStr(row, "02:05") > 0, "should show idle 02:05")
    TestSuite.True(InStr(row, "kick 17:55") > 0, "should show kick countdown")
    TestSuite.True(InStr(row, "MIN") > 0, "should show MIN tag")
    slot.hasInput := true
    slot.minimized := false
    row2 := Status.FormatRow(slot, "OK", 125000, cfg)
    TestSuite.False(InStr(row2, "OK~") > 0, "should drop ~ after input")
}

Test_StatusFormatHeader(cfg) {
    s1 := TrackedSlot(1, "Main"), s1.hwnd := 1, s1.lastInput := 0
    s2 := TrackedSlot(2, "Alt1"), s2.hwnd := 2, s2.lastInput := 0
    statuses := Map(1, "OK", 2, "WARN")
    hdr := Status.FormatHeader([s1, s2], statuses, 900000, cfg)
    TestSuite.True(InStr(hdr.text, "next:") > 0)
    statuses[2] := "DC"
    hdr2 := Status.FormatHeader([s1, s2], statuses, 900000, cfg)
    TestSuite.True(InStr(hdr2.text, "ALT1 DC") > 0)
    TestSuite.Equal(hdr2.status, "DC")
}
