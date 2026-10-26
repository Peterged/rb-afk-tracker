; =============================================================================
; EggDetectorTest.ahk - Unit tests for EggDetector, WindowTracker egg scan
; confirmation streaks, and DiscordNotifier webhook JSON formatting.
; =============================================================================

RunEggDetectorTests() {
    TestSuite.Run("EggDetector: returns indexOpen=false when Index parchment is not present", Test_EggDetectorClosed)
    TestSuite.Run("EggDetector: locates 4 cyan-purple gradient eggs and detects black silhouettes vs spawned", Test_EggDetectorSilhouettesAndSpawn)
    TestSuite.Run("EggDetector: tracks optional 210B dark-background egg when Track210B=1", Test_EggDetectorTrack210B)
    TestSuite.Run("WindowTracker: requires EggsConfirmScans consecutive scans before reporting newly spawned egg", Test_WindowTrackerEggConfirmStreak)
    TestSuite.Run("DiscordNotifier: builds SenZ V2 rich embed JSON with role mention, timestamps, and cooldown", Test_DiscordNotifierPayloadAndCooldown)
}

; Builds a synthetic 800x480 Index grid frame matching the bottom-scrolled layout:
;   Row 1: Col 1 = 210B (dark #0E1616), Col 2 = 363B (cyan-purple), Col 3 = 1T (cyan-purple)
;   Row 2: Col 1 = 2.5T (cyan-purple),  Col 2 = 3T (cyan-purple),   Col 3 = empty parchment
BuildSyntheticIndexFrame(spawnedKey := "") {
    frame := FrameBuffer.CreateSolid(800, 480, 0xFCEEBD)
    cols := [{x0: 40, x1: 209}, {x0: 320, x1: 489}, {x0: 600, x1: 769}]
    rows := [{y0: 25, y1: 205}, {y0: 265, y1: 445}]

    ; Card (1,1): 210B dark background
    PaintCard(frame, cols[1].x0, rows[1].y0, cols[1].x1, rows[1].y1, 0x0E1616, 0x0C090D, spawnedKey = "210B")
    ; Card (1,2): 363B cyan-purple gradient
    PaintCard(frame, cols[2].x0, rows[1].y0, cols[2].x1, rows[1].y1, 0x5D8D8D, 0x896D91, spawnedKey = "363B")
    ; Card (1,3): 1T cyan-purple gradient
    PaintCard(frame, cols[3].x0, rows[1].y0, cols[3].x1, rows[1].y1, 0x5D8D8D, 0x896D91, spawnedKey = "1T")
    ; Card (2,1): 2.5T cyan-purple gradient
    PaintCard(frame, cols[1].x0, rows[2].y0, cols[1].x1, rows[2].y1, 0x5D8D8D, 0x896D91, spawnedKey = "2.5T")
    ; Card (2,2): 3T cyan-purple gradient
    PaintCard(frame, cols[2].x0, rows[2].y0, cols[2].x1, rows[2].y1, 0x5D8D8D, 0x896D91, spawnedKey = "3T")

    return frame
}

PaintCard(frame, x0, y0, x1, y1, topRgb, botRgb, isSpawned) {
    cw := x1 - x0, ch := y1 - y0
    y := y0
    while (y <= y1) {
        rgb := (y - y0 < ch // 2) ? topRgb : botRgb
        x := x0
        while (x <= x1) {
            frame.SetPixelXY(x, y, rgb)
            x++
        }
        y++
    }
    ; Paint center egg region (X: 30%..70%, Y: 25%..65%)
    centerRgb := isSpawned ? 0xEB5E1A : 0x020202
    cy0 := y0 + Round(ch * 0.25), cy1 := y0 + Round(ch * 0.65)
    cx0 := x0 + Round(cw * 0.30), cx1 := x0 + Round(cw * 0.70)
    y := cy0
    while (y <= cy1) {
        x := cx0
        while (x <= cx1) {
            frame.SetPixelXY(x, y, centerRgb)
            x++
        }
        y++
    }
}

Test_EggDetectorClosed() {
    cfg := Config("")
    det := EggDetector(cfg)
    frame := FrameBuffer.CreateSolid(800, 480, 0x226622)
    res := det.ScanFrame(frame)
    TestSuite.False(res.indexOpen, "indexOpen should be false on normal 3D gameplay frame")
    TestSuite.Equal(res.eggs.Length, 0)
}

Test_EggDetectorSilhouettesAndSpawn() {
    cfg := Config("")
    cfg.EggsTrack210B := 0
    det := EggDetector(cfg)

    ; 1. All 4 gradient eggs silhouetted
    frame1 := BuildSyntheticIndexFrame("")
    res1 := det.ScanFrame(frame1)
    TestSuite.True(res1.indexOpen, "indexOpen should be true")
    TestSuite.Equal(res1.eggs.Length, 4, "should find 4 gradient eggs")
    TestSuite.Equal(res1.eggs[1].key, "363B")
    TestSuite.Equal(res1.eggs[2].key, "1T")
    TestSuite.Equal(res1.eggs[3].key, "2.5T")
    TestSuite.Equal(res1.eggs[4].key, "3T")
    for item in res1.eggs
        TestSuite.False(item.spawned, item.key " should be unspawned silhouette")

    ; 2. Spawn 1T egg only
    frame2 := BuildSyntheticIndexFrame("1T")
    res2 := det.ScanFrame(frame2)
    TestSuite.Equal(res2.eggs.Length, 4)
    TestSuite.False(res2.eggs[1].spawned, "363B still silhouette")
    TestSuite.True(res2.eggs[2].spawned, "1T should be detected as spawned")
    TestSuite.False(res2.eggs[3].spawned, "2.5T still silhouette")
    TestSuite.False(res2.eggs[4].spawned, "3T still silhouette")
}

Test_EggDetectorTrack210B() {
    cfg := Config("")
    cfg.EggsTrack210B := 1
    det := EggDetector(cfg)

    frame := BuildSyntheticIndexFrame("210B")
    res := det.ScanFrame(frame)
    TestSuite.Equal(res.eggs.Length, 5, "should include 210B plus 4 gradient eggs")
    TestSuite.Equal(res.eggs[1].key, "210B")
    TestSuite.True(res.eggs[1].spawned, "210B should be detected as spawned")
    TestSuite.False(res.eggs[2].spawned, "363B still silhouette")
}

Test_WindowTrackerEggConfirmStreak() {
    cfg := Config("")
    cfg.EggsConfirmScans := 2
    api := FakeWindowApi()
    api.Add(101)
    clock := FakeClock(10000)
    tracker := WindowTracker(cfg, api, clock)
    tracker.Refresh()

    det := EggDetector(cfg)
    frameSil := BuildSyntheticIndexFrame("")
    frameSpawn := BuildSyntheticIndexFrame("2.5T")

    ; First positive scan -> streak=1, not confirmed yet
    r1 := tracker.UpdateEggScan(101, det.ScanFrame(frameSpawn))
    TestSuite.Equal(r1.Length, 0, "first scan should not fire yet when ConfirmScans=2")

    ; Second consecutive positive scan -> streak=2, fires "2.5T"
    r2 := tracker.UpdateEggScan(101, det.ScanFrame(frameSpawn))
    TestSuite.Equal(r2.Length, 1, "second scan should confirm spawn")
    TestSuite.Equal(r2[1], "2.5T")

    ; Third positive scan while still spawned -> does not re-fire
    r3 := tracker.UpdateEggScan(101, det.ScanFrame(frameSpawn))
    TestSuite.Equal(r3.Length, 0, "already spawned egg should not re-fire")

    ; Egg despawns back to silhouette -> resets state
    tracker.UpdateEggScan(101, det.ScanFrame(frameSil))
    tracker.UpdateEggScan(101, det.ScanFrame(frameSpawn))
    r4 := tracker.UpdateEggScan(101, det.ScanFrame(frameSpawn))
    TestSuite.Equal(r4.Length, 1, "should fire again after despawning and respawning")
}

Test_DiscordNotifierPayloadAndCooldown() {
    cfg := Config("")
    cfg.DiscordWebhookUrl := "https://discord.com/api/webhooks/123/abc"
    cfg.DiscordCooldownSeconds := 300
    cfg.DiscordJoinGameUrl := "https://www.roblox.com/games/999"
    cfg.Egg363B_Name := "Solaris Egg"
    cfg.Egg363B_Rarity := "Ethereal"
    cfg.Egg363B_Luck := "300B"
    cfg.Egg363B_RoleId := "9876543210"
    cfg.Egg363B_Emoji := "🔥"
    cfg.Egg363B_ThumbnailUrl := "https://example.com/solaris.png"

    logger := FakeLogger()
    clock := FakeClock(50000)
    tx := FakeTransport()
    dn := DiscordNotifier(cfg, logger, clock, tx, () => 1700000000)

    TestSuite.True(dn.NotifyEggSpawn("363B", "Main"))
    TestSuite.Equal(tx.posts.Length, 1)
    body := tx.posts[1].body
    TestSuite.True(InStr(body, '"content":"<@&9876543210> spawned!"') > 0, "should ping role ID")
    TestSuite.True(InStr(body, 'Solaris Egg Spawned!! - <t:1700000000:t>') > 0, "should include title with timestamp")
    TestSuite.True(InStr(body, '<t:1700000000:R>') > 0, "should include relative timestamp")
    TestSuite.True(InStr(body, '[Click Here](https://www.roblox.com/games/999)') > 0, "should include Join Game link")
    TestSuite.True(InStr(body, '"thumbnail":{"url":"https://example.com/solaris.png"}') > 0, "should include thumbnail")

    ; Cooldown blocks duplicate within 300s unless forced
    TestSuite.False(dn.NotifyEggSpawn("363B", "Main"), "blocked by cooldown")
    TestSuite.True(dn.NotifyEggSpawn("363B", "Main", true), "force bypasses cooldown")
    clock.AdvanceSec(301)
    TestSuite.True(dn.NotifyEggSpawn("363B", "Main"), "allowed after cooldown expires")
}
