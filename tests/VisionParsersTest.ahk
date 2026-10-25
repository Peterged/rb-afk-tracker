; =============================================================================
; VisionParsersTest.ahk - Unit tests for OCR text parsers (Stats, Timers, DC).
; =============================================================================

RunVisionParsersTests() {
    TestSuite.Run("VisionParsers: extracts Cash, Friend Boost %, and Income from screenshot text", Test_VpStats)
    TestSuite.Run("VisionParsers: tolerates OCR digit quirks (O->0, l/i->1, S->5, B->8, Z->2) in stats", Test_VpStatsQuirks)
    TestSuite.Run("VisionParsers: repairs hotbar-occluded cash (085 98T -> 985.98T) and rejects hotbar items/8005T", Test_VpHotbarOcclusion)
    TestSuite.Run("VisionParsers: extracts NextEvent and ActiveBuff timers from bottom-right HUD", Test_VpTimers)
    TestSuite.Run("VisionParsers: classifies Roblox disconnect modal reasons", Test_VpDisconnectReasons)
}

Test_VpStats() {
    raw := "Friend Boost: +40%`n+$19,276`n3.56M"
    s := VisionParsers.ParseStats(raw)
    TestSuite.Equal(s.boost, 40)
    TestSuite.Equal(s.income, "19,276")
    TestSuite.Equal(s.cash, "3.56M")
}

Test_VpStatsQuirks() {
    raw := "Friend Boost +4O%  +$1,2OO  85OK"
    s := VisionParsers.ParseStats(raw)
    TestSuite.Equal(s.boost, 40)
    TestSuite.Equal(s.income, "1,200")
    TestSuite.Equal(s.cash, "850K")

    ; Stylized game font confusions: 'S' for '5', 'i' for '1', 'B' for '8'
    s2 := VisionParsers.ParseStats("Friend Boost: +4O%`n+$i9,276`n3.S6M")
    TestSuite.Equal(s2.boost, 40)
    TestSuite.Equal(s2.income, "19,276")
    TestSuite.Equal(s2.cash, "3.56M")

    s3 := VisionParsers.ParseStats("12.BM")
    TestSuite.Equal(s3.cash, "12.8M")
}

Test_VpHotbarOcclusion() {
    ; Hotbar slot 1 covering '.' and Backpack icon covering bottom tail of leading '9':
    ; plus hotbar item text "90.48 KG", "x16471", "x4256"
    s1 := VisionParsers.ParseStats("085 98T`n90.48 KG x16471 x4256")
    TestSuite.Equal(s1.cash, "985.98T")

    ; Corrupted 4-digit unsuffixed "8005T" is rejected in favor of valid cash or empty
    s2 := VisionParsers.ParseStats("8005T")
    TestSuite.Equal(s2.cash, "")

    ; Pure hotbar item quantities and weights are ignored when no cash is present
    s3 := VisionParsers.ParseStats("90.48 KG  x16471  x4256")
    TestSuite.Equal(s3.cash, "")
}

Test_VpTimers() {
    raw := "2m 29s`nx10  in 3m 9s"
    t := VisionParsers.ParseTimers(raw)
    TestSuite.Equal(t.nextEvent, "3m 9s")
    TestSuite.Equal(t.activeBuff, "2m 29s")

    ; Also test OCR reading trailing 's' as '5' on outlined game text
    t2 := VisionParsers.ParseTimers("2m 295 in 3m 95")
    TestSuite.Equal(t2.nextEvent, "3m 9s")
    TestSuite.Equal(t2.activeBuff, "2m 29s")
}

Test_VpDisconnectReasons() {
    r1 := VisionParsers.ParseDisconnectReason("Disconnected`nYou were disconnected for being idle 20 minutes. (Error Code: 267)")
    TestSuite.Equal(r1.code, "IDLE20")

    r2 := VisionParsers.ParseDisconnectReason("Same account launched experience from different device. Reconnect if you prefer to use this device.")
    TestSuite.Equal(r2.code, "SAME_ACCT")

    r3 := VisionParsers.ParseDisconnectReason("Please check your internet connection and try again. (Error Code: 277)")
    TestSuite.Equal(r3.code, "NET")

    r4 := VisionParsers.ParseDisconnectReason("This experience has shut down for maintenance.")
    TestSuite.Equal(r4.code, "SHUTDOWN")

    r5 := VisionParsers.ParseDisconnectReason("An unknown error occurred. (Error Code: 529)")
    TestSuite.Equal(r5.code, "ERR_529")
}
