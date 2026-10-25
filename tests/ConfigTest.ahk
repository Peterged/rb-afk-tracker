; =============================================================================
; ConfigTest.ahk - Unit tests for Config loading, validation, and persistence.
; =============================================================================

RunConfigTests() {
    tmpDir := A_ScriptDir "\.tmp"
    if !DirExist(tmpDir)
        DirCreate(tmpDir)

    TestSuite.Run("Config: creates default settings.ini and loads defaults", (*) => Test_ConfigDefaults(tmpDir))
    TestSuite.Run("Config: invalid values fall back to defaults and record warnings", (*) => Test_ConfigBadValues(tmpDir))
    TestSuite.Run("Config: enforces Warn < Urgent < Kick ordering", (*) => Test_ConfigOrdering(tmpDir))
    TestSuite.Run("Config: strips inline comments and sanitizes labels", (*) => Test_ConfigComments(tmpDir))
}

Test_ConfigDefaults(tmpDir) {
    path := tmpDir "\cfg_defaults.ini"
    if FileExist(path)
        FileDelete(path)
    cfg := Config(path)
    TestSuite.True(FileExist(path), "settings.ini should be created")
    TestSuite.Equal(cfg.ExpectedInstances, 5)
    TestSuite.Equal(cfg.WarnSeconds, 900)
    TestSuite.Equal(cfg.UrgentSeconds, 1080)
    TestSuite.Equal(cfg.KickSeconds, 1200)
    TestSuite.Equal(cfg.DcColor, 0x393B3D)
    TestSuite.Equal(cfg.DcSampleX.Length, 5)
    TestSuite.Equal(cfg.DcSampleY.Length, 2)
    TestSuite.Equal(cfg.LabelFor(1), "Main")
    TestSuite.Equal(cfg.LabelFor(2), "Alt1")
    TestSuite.Equal(cfg.Warnings.Length, 0)
}

Test_ConfigBadValues(tmpDir) {
    path := tmpDir "\cfg_bad.ini"
    if FileExist(path)
        FileDelete(path)
    FileAppend("[General]`nExpectedInstances=999`nWarnSeconds=abc`n[Disconnect]`nSampleX=1.5,bad`nColor=notacolor`n", path, "UTF-16")
    cfg := Config(path)
    TestSuite.Equal(cfg.ExpectedInstances, 5)
    TestSuite.Equal(cfg.WarnSeconds, 900)
    TestSuite.Equal(cfg.DcSampleX.Length, 5)
    TestSuite.Equal(cfg.DcColor, 0x393B3D)
    TestSuite.True(cfg.Warnings.Length >= 4, "should record warnings for bad entries")
}

Test_ConfigOrdering(tmpDir) {
    path := tmpDir "\cfg_order.ini"
    if FileExist(path)
        FileDelete(path)
    FileAppend("[General]`nWarnSeconds=1100`nUrgentSeconds=1000`nKickSeconds=1200`n", path, "UTF-16")
    cfg := Config(path)
    TestSuite.Equal(cfg.WarnSeconds, 900)
    TestSuite.Equal(cfg.UrgentSeconds, 1080)
    TestSuite.Equal(cfg.KickSeconds, 1200)
    TestSuite.True(cfg.Warnings.Length >= 1)
}

Test_ConfigComments(tmpDir) {
    path := tmpDir "\cfg_comments.ini"
    if FileExist(path)
        FileDelete(path)
    semi := Chr(59)
    FileAppend("[General]`nRepeatAlertSeconds=45 " semi " inline comment`n[Labels]`nSlot1=MyMain=Bad" semi "Chars_ExtraLong`n", path, "UTF-16")
    cfg := Config(path)
    TestSuite.Equal(cfg.RepeatAlertSeconds, 45)
    TestSuite.Equal(cfg.LabelFor(1), "MyMainBadCha")
}
