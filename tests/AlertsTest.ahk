; =============================================================================
; AlertsTest.ahk - Unit tests for transition alerts, repeats, and Acknowledge.
; =============================================================================

RunAlertsTests() {
    TestSuite.Run("Alerts: fires on transitions, repeats on interval, and respects Acknowledge", Test_AlertsLifecycle)
}

Test_AlertsLifecycle() {
    cfg := Config("")
    cfg.RepeatAlertSeconds := 30
    logger := FakeLogger()
    sound := FakeSound()
    notifier := FakeNotifier()
    al := Alerts(cfg, logger, sound, notifier)
    s1 := TrackedSlot(1, "Main"), s1.hwnd := 101, s1.lastInput := 0
    s2 := TrackedSlot(2, "Alt1"), s2.hwnd := 102, s2.lastInput := 0
    slots := [s1, s2]

    ; Initial OK detection
    st := Map(1, "OK", 2, "OK")
    al.Process(slots, st, 1000)
    TestSuite.Equal(sound.played.Length, 0)

    ; Slot 1 -> WARN (sound, no push)
    st[1] := "WARN"
    al.Process(slots, st, 900000)
    TestSuite.Equal(sound.played.Length, 1)
    TestSuite.Equal(sound.played[1], "Warn")
    TestSuite.Equal(notifier.sent.Length, 0)

    ; Slot 1 -> URGENT (sound + push)
    st[1] := "URGENT"
    al.Process(slots, st, 1080000)
    TestSuite.Equal(sound.played.Length, 2)
    TestSuite.Equal(sound.played[2], "Urgent")
    TestSuite.Equal(notifier.sent.Length, 1)
    TestSuite.True(al.HasUnackedProblem(st))

    ; 20s later: no repeat yet
    al.Process(slots, st, 1100000)
    TestSuite.Equal(sound.played.Length, 2)

    ; 30s later: repeat sound fires
    al.Process(slots, st, 1110000)
    TestSuite.Equal(sound.played.Length, 3)

    ; Acknowledge silences slot 1 repeats and alarm
    al.Acknowledge()
    TestSuite.False(al.HasUnackedProblem(st))
    al.Process(slots, st, 1150000)
    TestSuite.Equal(sound.played.Length, 3, "no repeat while acknowledged")

    ; A NEW problem on slot 2 still alerts and flashes
    st[2] := "DC"
    al.Process(slots, st, 1155000)
    TestSuite.Equal(sound.played.Length, 4)
    TestSuite.Equal(sound.played[4], "Disconnect")
    TestSuite.True(al.HasUnackedProblem(st))

    ; Slot 1 recovers -> Refreshed chime
    st[1] := "OK"
    al.Process(slots, st, 1160000)
    TestSuite.Equal(sound.played[sound.played.Length], "Refreshed")
}
