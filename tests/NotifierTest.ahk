; =============================================================================
; NotifierTest.ahk - Unit tests for ntfy push gating (disabled, away, cooldown).
; =============================================================================

RunNotifierTests() {
    TestSuite.Run("Notifier: disabled when Topic is empty", Test_NotifierDisabled)
    TestSuite.Run("Notifier: enforces OnlyWhenAway and per-key cooldown, unless forced", Test_NotifierGating)
}

Test_NotifierDisabled() {
    cfg := Config("")
    cfg.NtfyTopic := ""
    logger := FakeLogger()
    clock := FakeClock(10000)
    tx := FakeTransport()
    n := Notifier(cfg, logger, clock, tx, () => 999999)
    TestSuite.False(n.Notify("DC:1", "Title", "Body", 5))
    TestSuite.Equal(tx.posts.Length, 0)
}

Test_NotifierGating() {
    cfg := Config("")
    cfg.NtfyTopic := "secret-test-topic"
    cfg.NtfyOnlyWhenAway := 1
    cfg.NtfyAwaySeconds := 120
    cfg.NtfyCooldownSeconds := 300
    logger := FakeLogger()
    clock := FakeClock(10000)
    tx := FakeTransport()
    idleMs := 5000
    n := Notifier(cfg, logger, clock, tx, () => idleMs)

    TestSuite.False(n.Notify("DC:1", "Title", "Body", 5), "blocked while user is active")
    TestSuite.True(n.Notify("test", "Title", "Body", 3, true), "force bypasses away check")
    TestSuite.Equal(tx.posts.Length, 1)

    idleMs := 150000
    TestSuite.True(n.Notify("DC:1", "Title", "Body", 5), "sends when away")
    TestSuite.Equal(tx.posts.Length, 2)
    TestSuite.False(n.Notify("DC:1", "Title", "Body", 5), "blocked by cooldown")
    TestSuite.True(n.Notify("DC:2", "Title", "Body", 5), "different key not blocked")
    clock.AdvanceSec(301)
    TestSuite.True(n.Notify("DC:1", "Title", "Body", 5), "sends again after cooldown")
}
