; =============================================================================
; WindowApi.ahk - Thin wrapper around the Win32 calls the tracker needs.
; Kept tiny on purpose so tests can swap in FakeWindowApi.
; Read-only except Activate(), which only focuses a window (no input is sent).
; =============================================================================

class WindowApi {
    static CLSID_VirtualDesktopManager := "{AA509086-5CA9-4C25-8F95-589D3C07B48A}"
    static IID_IVirtualDesktopManager := "{A5CD92FF-29BE-454C-8D04-D82879FB3F1B}"

    __New(selector) {
        this.selector := selector
        this.vdm := ""
        try this.vdm := ComObject(WindowApi.CLSID_VirtualDesktopManager, WindowApi.IID_IVirtualDesktopManager)
    }

    ; Lists all matching Roblox windows across ALL Windows 10/11 Virtual Desktops.
    ; Windows hides windows on inactive virtual desktops (WS_VISIBLE = 0), so we
    ; enable DetectHiddenWindows and filter to actual game windows (client >= 100x100
    ; or minimized).
    List() {
        prev := A_DetectHiddenWindows
        DetectHiddenWindows(true)
        try {
            raw := WinGetList(this.selector)
            out := []
            for hwnd in raw {
                if this.IsMinimized(hwnd) {
                    out.Push(hwnd)
                    continue
                }
                rc := Buffer(16, 0)
                if (DllCall("GetClientRect", "ptr", hwnd, "ptr", rc) && NumGet(rc, 8, "int") >= 100 && NumGet(rc, 12, "int") >= 100)
                    out.Push(hwnd)
            }
            return out
        } finally {
            DetectHiddenWindows(prev)
        }
    }

    Exists(hwnd) {
        prev := A_DetectHiddenWindows
        DetectHiddenWindows(true)
        try return WinExist(hwnd) != 0
        finally DetectHiddenWindows(prev)
    }

    Active() => WinActive(this.selector)

    ; Returns true if `hwnd` is on the currently active Windows 10/11 Virtual Desktop.
    IsOnCurrentDesktop(hwnd) {
        if !this.vdm
            return true
        onCurrent := 1
        try {
            if (ComCall(3, this.vdm, "ptr", hwnd, "int*", &onCurrent, "int") = 0)
                return onCurrent != 0
        }
        return true
    }

    IsHung(hwnd) => DllCall("IsHungAppWindow", "ptr", hwnd, "int") != 0

    IsMinimized(hwnd) => DllCall("IsIconic", "ptr", hwnd, "int") != 0

    Pid(hwnd) {
        prev := A_DetectHiddenWindows
        DetectHiddenWindows(true)
        try return WinGetPID(hwnd)
        catch
            return 0
        finally DetectHiddenWindows(prev)
    }

    Activate(hwnd) {
        prev := A_DetectHiddenWindows
        DetectHiddenWindows(true)
        try {
            if this.IsMinimized(hwnd)
                WinRestore(hwnd)
            WinActivate(hwnd)
            return true
        } catch {
            return false
        } finally {
            DetectHiddenWindows(prev)
        }
    }

    ; Restores a minimized window without activating it and places it at the
    ; bottom of the Z-order so Windows DWM keeps rendering its surface for CV.
    RestoreToBackground(hwnd) {
        try {
            ; Never call ShowWindow on a window on another virtual desktop, or Windows
            ; would pull it onto the current desktop.
            if !this.IsOnCurrentDesktop(hwnd)
                return false
            ; SW_SHOWNOACTIVATE = 4, HWND_BOTTOM = 1, SWP_NOSIZE|SWP_NOMOVE|SWP_NOACTIVATE = 0x0013
            DllCall("ShowWindow", "ptr", hwnd, "int", 4)
            DllCall("SetWindowPos", "ptr", hwnd, "ptr", 1, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x0013)
            return true
        }
        return false
    }
}
