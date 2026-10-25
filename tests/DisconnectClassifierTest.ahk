; =============================================================================
; DisconnectClassifierTest.ahk - Unit tests for DisconnectDetector.Classify.
; =============================================================================

RunDisconnectClassifierTests() {
    cfg := Config("")
    cfg.DcColor := 0x393B3D
    cfg.DcTolerance := 8
    cfg.DcMinMatchRatio := 0.8

    TestSuite.Run("DisconnectClassifier: exact and near-tolerance matches return dc", (*) => Test_DcMatch(cfg))
    TestSuite.Run("DisconnectClassifier: below ratio or outside tolerance returns ok", (*) => Test_DcNoMatch(cfg))
    TestSuite.Run("DisconnectClassifier: all-black or empty returns unknown", (*) => Test_DcUnknown(cfg))
}

Test_DcMatch(cfg) {
    exact := [0x393B3D, 0x393B3D, 0x393B3D, 0x393B3D, 0x393B3D]
    TestSuite.Equal(DisconnectDetector.Classify(exact, cfg), "dc")
    near := [0x414345, 0x313335, 0x393B3D, 0x3A3C3E, 0x102030]
    TestSuite.Equal(DisconnectDetector.Classify(near, cfg), "dc")
}

Test_DcNoMatch(cfg) {
    below := [0x393B3D, 0x393B3D, 0x393B3D, 0x112233, 0x445566]
    TestSuite.Equal(DisconnectDetector.Classify(below, cfg), "ok")
    outside := [0x424446, 0x424446, 0x424446, 0x424446, 0x424446]
    TestSuite.Equal(DisconnectDetector.Classify(outside, cfg), "ok")
}

Test_DcUnknown(cfg) {
    TestSuite.Equal(DisconnectDetector.Classify("", cfg), "unknown")
    TestSuite.Equal(DisconnectDetector.Classify([], cfg), "unknown")
    TestSuite.Equal(DisconnectDetector.Classify([0, 0, 0, 0, 0], cfg), "unknown")
}
