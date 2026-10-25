; =============================================================================
; UpdaterTest.ahk - Unit tests for semantic version comparison, CNG SHA-256
; hashing, atomic multi-file staging, settings.ini preservation, and rollback
; on SHA-256 checksum mismatch.
; =============================================================================

class FakeUpdateHttp {
    __New() {
        this.files := Map()
    }

    SetText(url, text) {
        bytes := Buffer(StrPut(text, "UTF-8") - 1)
        StrPut(text, bytes, "UTF-8")
        this.files[url] := bytes
    }

    GetBytes(url) {
        if !this.files.Has(url)
            throw Error("404 Not Found: " url)
        return this.files[url]
    }

    GetText(url) {
        buf := this.GetBytes(url)
        return StrGet(buf.Ptr, buf.Size, "UTF-8")
    }
}

RunUpdaterTests() {
    tmpDir := A_ScriptDir "\.tmp\updater"
    if DirExist(tmpDir)
        DirDelete(tmpDir, true)
    DirCreate(tmpDir)

    TestSuite.Run("Updater: semantic version comparison handles multi-digit parts", Test_UpdSemver)
    TestSuite.Run("Updater: CNG BCrypt SHA-256 matches standard test vector", Test_UpdSha256)
    TestSuite.Run("Updater: atomic update swaps verified files and preserves settings.ini", (*) => Test_UpdAtomicApply(tmpDir))
    TestSuite.Run("Updater: SHA-256 mismatch aborts update and leaves existing files intact", (*) => Test_UpdChecksumRollback(tmpDir))
}

Test_UpdSemver() {
    TestSuite.Equal(Updater.CompareSemver("1.0.0", "1.0.0"), 0)
    TestSuite.Equal(Updater.CompareSemver("1.0.1", "1.0.0"), 1)
    TestSuite.Equal(Updater.CompareSemver("1.0.0", "1.0.1"), -1)
    TestSuite.Equal(Updater.CompareSemver("1.10.0", "1.2.0"), 1)
    TestSuite.Equal(Updater.CompareSemver("v2.0.0", "1.99.99"), 1)
}

Test_UpdSha256() {
    ; SHA-256("abc") = ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
    buf := Buffer(3)
    NumPut("uchar", 0x61, buf, 0), NumPut("uchar", 0x62, buf, 1), NumPut("uchar", 0x63, buf, 2)
    TestSuite.Equal(Updater.Sha256Buffer(buf), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
}

Test_UpdAtomicApply(tmpDir) {
    appDir := tmpDir "\app1"
    DirCreate(appDir "\lib")
    FileAppend("1.0.0`n", appDir "\VERSION", "UTF-8-RAW")
    FileAppend("old_code := 1`n", appDir "\lib\Sample.ahk", "UTF-8-RAW")
    FileAppend("my_custom_setting=42`n", appDir "\settings.ini", "UTF-8-RAW")

    newCode := "new_code := 2`n"
    newBytes := Buffer(StrPut(newCode, "UTF-8") - 1)
    StrPut(newCode, newBytes, "UTF-8")
    newHash := Updater.Sha256Buffer(newBytes)

    manifest := '{ "version": "1.1.0", "files": [ { "path": "lib/Sample.ahk", "sha256": "' newHash '", "size": ' newBytes.Size ' } ] }'
    http := FakeUpdateHttp()
    base := "https://raw.githubusercontent.com/testuser/testrepo/main"
    http.SetText(base "/manifest.json", manifest)
    http.SetText(base "/lib/Sample.ahk", newCode)

    cfg := Config("")
    cfg.UpdateRepo := "testuser/testrepo"
    cfg.UpdateBranch := "main"
    logger := FakeLogger()
    upd := Updater(cfg, logger, appDir, http)

    reloaded := false
    res := upd.CheckAndApply(false, () => (reloaded := true))
    TestSuite.Equal(res.status, "updated")
    TestSuite.Equal(res.version, "1.1.0")
    TestSuite.True(reloaded, "onBeforeReload callback should fire")
    TestSuite.Equal(upd.LocalVersion(), "1.1.0")
    TestSuite.Equal(FileRead(appDir "\lib\Sample.ahk", "UTF-8"), newCode)
    TestSuite.Equal(FileRead(appDir "\settings.ini", "UTF-8"), "my_custom_setting=42`n", "settings.ini must be preserved")
}

Test_UpdChecksumRollback(tmpDir) {
    appDir := tmpDir "\app2"
    DirCreate(appDir "\lib")
    FileAppend("1.0.0`n", appDir "\VERSION", "UTF-8-RAW")
    FileAppend("original_safe_code`n", appDir "\lib\Sample.ahk", "UTF-8-RAW")

    ; Manifest claims hash A, but server returns tampered content
    badHash := "0000000000000000000000000000000000000000000000000000000000000000"
    manifest := '{ "version": "1.2.0", "files": [ { "path": "lib/Sample.ahk", "sha256": "' badHash '", "size": 10 } ] }'
    http := FakeUpdateHttp()
    base := "https://raw.githubusercontent.com/testuser/testrepo/main"
    http.SetText(base "/manifest.json", manifest)
    http.SetText(base "/lib/Sample.ahk", "tampered_code`n")

    cfg := Config("")
    cfg.UpdateRepo := "testuser/testrepo"
    logger := FakeLogger()
    upd := Updater(cfg, logger, appDir, http)

    res := upd.CheckAndApply(false)
    TestSuite.Equal(res.status, "error")
    TestSuite.Equal(upd.LocalVersion(), "1.0.0", "version must remain 1.0.0 on checksum failure")
    TestSuite.Equal(FileRead(appDir "\lib\Sample.ahk", "UTF-8"), "original_safe_code`n", "existing file must not be touched")
    TestSuite.False(DirExist(appDir "\.update_stage"), "staging directory must be cleaned up")
}
