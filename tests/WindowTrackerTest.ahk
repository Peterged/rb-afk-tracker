; =============================================================================
; WindowTrackerTest.ahk - Unit tests for slot assignment, missing/restart reuse,
; hung grace period, DC streak confirmation, state persistence, and urgency sort.
; =============================================================================

RunWindowTrackerTests() {
    tmpDir := A_ScriptDir "\.tmp"
    if !DirExist(tmpDir)
        DirCreate(tmpDir)

    TestSuite.Run("WindowTracker: assigns lowest free slot and reuses MISSING slot on restart", Test_WtSlotsAndReuse)
    TestSuite.Run("WindowTracker: RecordInput ignores unknown hwnd and resets idle clock", Test_WtRecordInput)
    TestSuite.Run("WindowTracker: hung flag respects HungGraceSeconds", Test_WtHungGrace)
    TestSuite.Run("WindowTracker: DC requires ConfirmScans consecutive hits", Test_WtDcConfirm)
    TestSuite.Run("WindowTracker: UrgencyOrder sorts by status priority then idle time", Test_WtUrgencyOrder)
    TestSuite.Run("WindowTracker: saves and restores slot assignments via state.ini", (*) => Test_WtStatePersistence(tmpDir))
    TestSuite.Run("WindowTracker: detects FROZEN viewport after FreezeSeconds and recovers on frame change", Test_WtFreezeDetection)
    TestSuite.Run("WindowTracker: KeepRenderable restores minimized windows to background", Test_WtKeepRenderable)
    TestSuite.Run("WindowTracker: Virtual Desktop windows stay OK (not MISSING) and show VD tag", Test_WtVirtualDesktop)
    TestSuite.Run("WindowTracker: UpdateVisionStats filters single-frame unsuffixed OCR glitches", Test_WtVisionStatsGlitchFilter)
}

Test_WtSlotsAndReuse() {
    cfg := Config("")
    cfg.ExpectedInstances := 3
    api := FakeWindowApi()
    clock := FakeClock(10000)
    wt := WindowTracker(cfg, api, clock)
    api.Add(101, 1), api.Add(102, 2), api.Add(103, 3)
    wt.Refresh()
    TestSuite.Equal(wt.SlotOf(101).label, "Main")
    TestSuite.Equal(wt.SlotOf(102).label, "Alt1")
    TestSuite.Equal(wt.SlotOf(103).label, "Alt2")

    ; Client 2 crashes -> slot 2 becomes MISSING
    api.Remove(102)
    clock.AdvanceSec(5)
    wt.Refresh()
    TestSuite.Equal(Status.Evaluate(wt.slots[2], clock.Now(), cfg), "MISSING")

    ; Replacement client 202 launches -> lands back in slot 2 ("Alt1")
    api.Add(202, 99)
    clock.AdvanceSec(2)
    wt.Refresh()
    TestSuite.Equal(wt.SlotOf(202).index, 2)
    TestSuite.Equal(wt.SlotOf(202).label, "Alt1")
    TestSuite.Equal(Status.Evaluate(wt.slots[2], clock.Now(), cfg), "OK")
}

Test_WtRecordInput() {
    cfg := Config("")
    api := FakeWindowApi()
    clock := FakeClock(50000)
    wt := WindowTracker(cfg, api, clock)
    api.Add(101)
    wt.Refresh()
    TestSuite.False(wt.slots[1].hasInput)
    clock.AdvanceSec(300)
    TestSuite.False(wt.RecordInput(999))
    TestSuite.True(wt.RecordInput(101))
    TestSuite.True(wt.slots[1].hasInput)
    TestSuite.Equal(Status.IdleSeconds(wt.slots[1], clock.Now()), 0)
}

Test_WtHungGrace() {
    cfg := Config("")
    cfg.HungGraceSeconds := 10
    api := FakeWindowApi()
    clock := FakeClock(10000)
    wt := WindowTracker(cfg, api, clock)
    api.Add(101)
    wt.Refresh()
    api.hung[101] := true
    wt.Refresh()
    TestSuite.False(wt.slots[1].hung, "not hung at t=0 of freeze")
    clock.AdvanceSec(9)
    wt.Refresh()
    TestSuite.False(wt.slots[1].hung, "not hung before grace expires")
    clock.AdvanceSec(1)
    wt.Refresh()
    TestSuite.True(wt.slots[1].hung, "hung at 10s")
    api.hung[101] := false
    wt.Refresh()
    TestSuite.False(wt.slots[1].hung, "recovers immediately when responsive")
}

Test_WtDcConfirm() {
    cfg := Config("")
    cfg.DcConfirmScans := 2
    api := FakeWindowApi()
    clock := FakeClock(10000)
    wt := WindowTracker(cfg, api, clock)
    api.Add(101)
    wt.Refresh()
    wt.SetDcResult(101, "dc")
    TestSuite.False(wt.slots[1].dc, "1st scan should not trigger DC")
    wt.SetDcResult(101, "unknown")
    TestSuite.Equal(wt.slots[1].dcStreak, 1, "unknown keeps streak")
    wt.SetDcResult(101, "dc")
    TestSuite.True(wt.slots[1].dc, "2nd dc scan confirms DC")
    wt.SetDcResult(101, "ok")
    TestSuite.False(wt.slots[1].dc, "ok clears DC")
}

Test_WtUrgencyOrder() {
    cfg := Config("")
    api := FakeWindowApi()
    clock := FakeClock(10000)
    wt := WindowTracker(cfg, api, clock)
    api.Add(101, 1), api.Add(102, 2), api.Add(103, 3)
    wt.Refresh()
    clock.AdvanceSec(950)
    wt.RecordInput(101)
    clock.AdvanceSec(10)
    wt.SetDcResult(101, "dc")
    wt.SetDcResult(101, "dc")
    order := wt.UrgencyOrder(clock.Now())
    TestSuite.Equal(order[1].hwnd, 101, "DC window first despite low idle")
}

Test_WtStatePersistence(tmpDir) {
    statePath := tmpDir "\state_test.ini"
    if FileExist(statePath)
        FileDelete(statePath)
    cfg := Config("")
    api := FakeWindowApi()
    clock := FakeClock(50000)
    wt1 := WindowTracker(cfg, api, clock, statePath)
    api.Add(101, 1), api.Add(102, 2)
    wt1.Refresh()
    clock.AdvanceSec(120)
    wt1.RecordInput(102)
    wt1.SaveState()
    clock.AdvanceSec(60)
    wt2 := WindowTracker(cfg, api, clock, statePath)
    restored := wt2.LoadState()
    TestSuite.Equal(restored, 2)
    TestSuite.Equal(wt2.SlotOf(102).index, 2)
    TestSuite.True(wt2.SlotOf(102).hasInput)
    TestSuite.Equal(Status.IdleSeconds(wt2.SlotOf(102), clock.Now()), 60)
}

Test_WtFreezeDetection() {
    cfg := Config("")
    cfg.FreezeSeconds := 45
    api := FakeWindowApi()
    clock := FakeClock(10000)
    wt := WindowTracker(cfg, api, clock)
    api.Add(101)
    wt.Refresh()

    wt.UpdateFrameHash(101, 0xABCD1234, clock.Now())
    TestSuite.False(wt.slots[1].frozen)
    clock.AdvanceSec(44)
    wt.UpdateFrameHash(101, 0xABCD1234, clock.Now())
    TestSuite.False(wt.slots[1].frozen, "not frozen at 44s")
    clock.AdvanceSec(1)
    wt.UpdateFrameHash(101, 0xABCD1234, clock.Now())
    TestSuite.True(wt.slots[1].frozen, "frozen at 45s of static hash")
    TestSuite.Equal(Status.Evaluate(wt.slots[1], clock.Now(), cfg), "FROZEN")

    ; Frame changes -> recovers immediately
    clock.AdvanceSec(1)
    wt.UpdateFrameHash(101, 0xABCD9999, clock.Now())
    TestSuite.False(wt.slots[1].frozen, "recovers when viewport hash changes")
    TestSuite.Equal(Status.Evaluate(wt.slots[1], clock.Now(), cfg), "OK")
}

Test_WtKeepRenderable() {
    cfg := Config("")
    cfg.KeepRenderable := 1
    api := FakeWindowApi()
    clock := FakeClock(10000)
    wt := WindowTracker(cfg, api, clock)
    api.Add(101)
    api.minimized[101] := true
    wt.Refresh()
    TestSuite.Equal(api.restoredToBg.Length, 1)
    TestSuite.False(wt.slots[1].minimized, "window should be un-minimized to background")
}

Test_WtVirtualDesktop() {
    cfg := Config("")
    cfg.KeepRenderable := 1
    api := FakeWindowApi()
    clock := FakeClock(10000)
    wt := WindowTracker(cfg, api, clock)
    api.Add(101)
    api.otherDesktop[101] := true
    api.minimized[101] := true
    wt.Refresh()
    TestSuite.Equal(Status.Evaluate(wt.slots[1], clock.Now(), cfg), "OK", "window on another virtual desktop must not trigger MISSING")
    TestSuite.True(wt.slots[1].otherDesktop, "otherDesktop flag should be true")
    TestSuite.Equal(api.restoredToBg.Length, 0, "must not call RestoreToBackground on another virtual desktop")
    row := Status.FormatRow(wt.slots[1], "OK", clock.Now(), cfg)
    TestSuite.True(InStr(row, " VD") > 0, "HUD row should show VD indicator")
}

Test_WtVisionStatsGlitchFilter() {
    cfg := Config("")
    api := FakeWindowApi()
    clock := FakeClock(10000)
    wt := WindowTracker(cfg, api, clock)
    api.Add(101)
    wt.Refresh()

    ; Valid suffixed cash reading is recorded immediately
    wt.UpdateVisionStats(101, {cash: "3.56M", boost: 40, income: "19,276"})
    TestSuite.Equal(wt.slots[1].cash, "3.56M")
    TestSuite.Equal(wt.slots[1].boost, 40)

    ; Single-frame unsuffixed glitch (e.g., floating popup number "19,276" misread as cash) is ignored
    wt.UpdateVisionStats(101, {cash: "19,276", boost: -1, income: ""})
    TestSuite.Equal(wt.slots[1].cash, "3.56M", "1st unsuffixed frame should not overwrite suffixed cash")

    ; 2nd consecutive unsuffixed reading is accepted (in case player spent down below 1,000)
    wt.UpdateVisionStats(101, {cash: "850", boost: -1, income: ""})
    TestSuite.Equal(wt.slots[1].cash, "850", "2nd consecutive unsuffixed frame updates cash")
}
