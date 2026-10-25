; =============================================================================
; Fakes.ahk - Test doubles for Clock, WindowApi, Logger, Sound, and HTTP.
; =============================================================================

class FakeClock {
    __New(t := 100000) => this.t := t
    Now() => this.t
    Advance(ms) => this.t += ms
    AdvanceSec(s) => this.t += s * 1000
}

class FakeWindowApi {
    __New() {
        this.windows := []
        this.hung := Map()
        this.minimized := Map()
        this.otherDesktop := Map()
        this.pids := Map()
        this.activeHwnd := 0
        this.activated := []
        this.restoredToBg := []
    }

    Add(hwnd, pid := 0) {
        for h in this.windows
            if (h = hwnd)
                return
        this.windows.Push(hwnd)
        this.pids[hwnd] := pid ? pid : hwnd
    }

    Remove(hwnd) {
        for i, h in this.windows {
            if (h = hwnd) {
                this.windows.RemoveAt(i)
                return
            }
        }
    }

    List() => this.windows.Clone()
    Exists(hwnd) {
        for h in this.windows
            if (h = hwnd)
                return true
        return false
    }
    Active() => this.activeHwnd
    IsHung(hwnd) => this.hung.Get(hwnd, false)
    IsMinimized(hwnd) => this.minimized.Get(hwnd, false)
    IsOnCurrentDesktop(hwnd) => !this.otherDesktop.Get(hwnd, false)
    Pid(hwnd) => this.pids.Get(hwnd, hwnd)
    Activate(hwnd) {
        this.activated.Push(hwnd)
        this.activeHwnd := hwnd
        return true
    }
    RestoreToBackground(hwnd) {
        this.restoredToBg.Push(hwnd)
        this.minimized[hwnd] := false
        return true
    }
}

class FakeLogger {
    __New() => this.entries := []
    Log(level, msg) => this.entries.Push({level: level, msg: msg})
    Info(msg) => this.Log("INFO", msg)
    Warn(msg) => this.Log("WARN", msg)
    Error(msg) => this.Log("ERROR", msg)
}

class FakeSound {
    __New() => this.played := []
    Play(name) => this.played.Push(name)
}

class FakeNotifier {
    __New() => this.sent := []
    Notify(key, title, message, priority := 3, force := false) {
        this.sent.Push({key: key, title: title, message: message, priority: priority, force: force})
        return true
    }
}

class FakeTransport {
    __New() {
        this.posts := []
        this.shouldFail := false
    }
    Post(url, body, headers) {
        if this.shouldFail
            throw Error("simulated network failure")
        this.posts.Push({url: url, body: body, headers: headers})
    }
    Poll() => 0
}
