#Requires AutoHotkey v2.0
#Warn All, OutputDebug

#Include "%A_ScriptDir%\..\lib\Config.ahk"
#Include "%A_ScriptDir%\..\lib\Logger.ahk"
#Include "%A_ScriptDir%\..\lib\WindowApi.ahk"
#Include "%A_ScriptDir%\..\lib\FrameBuffer.ahk"
#Include "%A_ScriptDir%\..\lib\RapidOcrBridge.ahk"
#Include "%A_ScriptDir%\..\lib\WinRtOcr.ahk"
#Include "%A_ScriptDir%\..\lib\VisionParsers.ahk"
#Include "%A_ScriptDir%\..\lib\Status.ahk"
#Include "%A_ScriptDir%\..\lib\WindowTracker.ahk"
#Include "%A_ScriptDir%\..\lib\InputMonitor.ahk"
#Include "%A_ScriptDir%\..\lib\DisconnectDetector.ahk"
#Include "%A_ScriptDir%\..\lib\Alerts.ahk"
#Include "%A_ScriptDir%\..\lib\Notifier.ahk"
#Include "%A_ScriptDir%\..\lib\Updater.ahk"

#Include "%A_ScriptDir%\Assert.ahk"
#Include "%A_ScriptDir%\Fakes.ahk"
#Include "%A_ScriptDir%\ConfigTest.ahk"
#Include "%A_ScriptDir%\WindowTrackerTest.ahk"
#Include "%A_ScriptDir%\StatusTest.ahk"
#Include "%A_ScriptDir%\DisconnectClassifierTest.ahk"
#Include "%A_ScriptDir%\VisionParsersTest.ahk"
#Include "%A_ScriptDir%\FrameBufferTest.ahk"
#Include "%A_ScriptDir%\AlertsTest.ahk"
#Include "%A_ScriptDir%\NotifierTest.ahk"
#Include "%A_ScriptDir%\UpdaterTest.ahk"
#Include "%A_ScriptDir%\ComplianceTest.ahk"

RunConfigTests()
RunWindowTrackerTests()
RunStatusTests()
RunDisconnectClassifierTests()
RunVisionParsersTests()
RunFrameBufferTests()
RunAlertsTests()
RunNotifierTests()
RunUpdaterTests()
RunComplianceTests()

; Clean up scratch test files
try DirDelete(A_ScriptDir "\.tmp", true)

FileAppend(Format("`n{} passed, {} failed`n", TestSuite.Passed, TestSuite.Failed), "*")
ExitApp(TestSuite.Failed)
