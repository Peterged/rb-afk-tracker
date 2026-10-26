; =============================================================================
; WindowTracker.ahk - Assigns Roblox windows to stable, labelled slots and keeps
; per-window state (idle clock, hung, disconnect streak, missing).
;
; Slots keep labels stable across client restarts: a new window always takes the
; lowest free slot, and a slot whose window vanished (MISSING) counts as free.
; The clock and window API are injected so everything here is unit-testable.
; =============================================================================

class TrackedSlot {
    __New(index, label) {
        this.index := index
        this.label := label
        this.Reset()
        this.missingSince := 0
        this.lastHwnd := 0
    }

    Reset() {
        this.hwnd := 0
        this.lastInput := 0
        this.firstSeen := 0
        this.hasInput := false
        this.hungSince := 0
        this.hung := false
        this.dcStreak := 0
        this.dc := false
        this.dcReason := ""
        this.dcDetail := ""
        this.minimized := false
        this.otherDesktop := false
        this.lastHash := 0
        this.sameHashSince := 0
        this.frozen := false
        this.cash := ""
        this.unsuffixedStreak := 0
        this.boost := -1
        this.prevBoost := -1
        this.boostDropped := false
        this.eventTimer := ""
        this.lastOcrTick := 0
        this.lastRestoreTick := 0
        this.indexOpen := false
        this.eggStreaks := Map()
        this.eggSpawned := Map()
    }
}

class WindowTracker {
    __New(cfg, winApi, clock, statePath := "") {
        this.cfg := cfg
        this.winApi := winApi
        this.clock := clock
        this.statePath := statePath
        this.slots := []
        this.byHwnd := Map()
        this.scanIndex := 0
        this.lastInputHwnd := 0
        this.EnsureSlots(cfg.ExpectedInstances)
    }

    EnsureSlots(count) {
        while (this.slots.Length < count)
            this.slots.Push(TrackedSlot(this.slots.Length + 1, this.cfg.LabelFor(this.slots.Length + 1)))
    }

    SlotOf(hwnd) => this.byHwnd.Get(hwnd, "")

    LiveCount() => this.byHwnd.Count

    ; ------------------------------------------------------------ main update
    Refresh() {
        now := this.clock.Now()
        live := Map()
        for hwnd in this.winApi.List()
            live[hwnd] := true
        changed := false

        ; Windows that disappeared -> MISSING.
        for slot in this.slots {
            if (slot.hwnd && !live.Has(slot.hwnd)) {
                this.byHwnd.Delete(slot.hwnd)
                slot.lastHwnd := slot.hwnd
                slot.Reset()
                slot.missingSince := now
                changed := true
            }
        }

        ; New windows -> lowest free slot, oldest process (lowest PID) first.
        fresh := []
        for hwnd in live
            if !this.byHwnd.Has(hwnd)
                fresh.Push(hwnd)
        if fresh.Length {
            api := this.winApi
            for hwnd in WindowTracker.SortBy(fresh, (h) => api.Pid(h)) {
                this.Adopt(this.FreeSlot(), hwnd, now)
                changed := true
            }
        }

        ; Per-window flags.
        graceMs := this.cfg.HungGraceSeconds * 1000
        for slot in this.slots {
            if !slot.hwnd
                continue
            onCur := !this.winApi.HasMethod("IsOnCurrentDesktop") || this.winApi.IsOnCurrentDesktop(slot.hwnd)
            slot.otherDesktop := !onCur
            isMin := this.winApi.IsMinimized(slot.hwnd)
            if (onCur && isMin && this.cfg.KeepRenderable && (now - slot.lastRestoreTick >= 3000 || slot.lastRestoreTick = 0)) {
                slot.lastRestoreTick := now
                if this.winApi.RestoreToBackground(slot.hwnd)
                    isMin := this.winApi.IsMinimized(slot.hwnd)
            }
            slot.minimized := isMin
            if this.winApi.IsHung(slot.hwnd) {
                if !slot.hungSince
                    slot.hungSince := now
            } else {
                slot.hungSince := 0
            }
            slot.hung := slot.hungSince && (now - slot.hungSince) >= graceMs
        }

        if changed
            this.SaveState()
        return changed
    }

    FreeSlot() {
        for slot in this.slots
            if !slot.hwnd
                return slot
        this.EnsureSlots(this.slots.Length + 1)
        return this.slots[this.slots.Length]
    }

    Adopt(slot, hwnd, now) {
        slot.Reset()
        slot.hwnd := hwnd
        slot.lastHwnd := hwnd
        slot.missingSince := 0
        slot.firstSeen := now
        slot.lastInput := now
        this.byHwnd[hwnd] := slot
    }

    ; ------------------------------------------------------------ inputs
    RecordInput(hwnd) {
        slot := this.byHwnd.Get(hwnd, "")
        if !slot
            return false
        slot.lastInput := this.clock.Now()
        slot.hasInput := true
        this.lastInputHwnd := hwnd
        return true
    }

    ; result: "dc" | "ok" | "unknown"
    SetDcResult(hwnd, result) {
        slot := this.byHwnd.Get(hwnd, "")
        if !slot
            return
        if (result = "dc") {
            slot.dcStreak += 1
            slot.dc := slot.dcStreak >= this.cfg.DcConfirmScans
        } else if (result = "ok") {
            slot.dcStreak := 0
            slot.dc := false
            slot.dcReason := ""
            slot.dcDetail := ""
        }
    }

    SetDcReason(hwnd, info) {
        slot := this.byHwnd.Get(hwnd, "")
        if (!slot || !info)
            return
        if (info.code != "")
            slot.dcReason := info.code
        if (info.detail != "")
            slot.dcDetail := info.detail
    }

    ; Tracks how long the 3D viewport hash has been static; sets slot.frozen
    ; once identical for FreezeSeconds (0 = disabled).
    UpdateFrameHash(hwnd, hash, now := -1) {
        slot := this.byHwnd.Get(hwnd, "")
        if (!slot || hash = 0)
            return
        if (now < 0)
            now := this.clock.Now()
        if (slot.lastHash != hash || slot.sameHashSince = 0) {
            slot.lastHash := hash
            slot.sameHashSince := now
            slot.frozen := false
            return
        }
        freezeMs := this.cfg.FreezeSeconds * 1000
        slot.frozen := (freezeMs > 0) && ((now - slot.sameHashSince) >= freezeMs)
    }

    UpdateVisionStats(hwnd, stats, timers := "", now := -1) {
        slot := this.byHwnd.Get(hwnd, "")
        if !slot
            return
        if (now < 0)
            now := this.clock.Now()
        slot.lastOcrTick := now
        if stats {
            if (stats.cash != "") {
                hasSuffix := RegExMatch(stats.cash, "[KMBT]$") != 0
                prevHadSuffix := RegExMatch(slot.cash, "[KMBT]$") != 0
                if (hasSuffix || !prevHadSuffix) {
                    slot.cash := stats.cash
                    slot.unsuffixedStreak := 0
                } else {
                    slot.unsuffixedStreak += 1
                    if (slot.unsuffixedStreak >= 2) {
                        slot.cash := stats.cash
                        slot.unsuffixedStreak := 0
                    }
                }
            }
            if (stats.boost >= 0) {
                if (slot.boost >= 0 && stats.boost < slot.boost) {
                    slot.prevBoost := slot.boost
                    slot.boostDropped := true
                }
                slot.boost := stats.boost
            }
        }
        if (timers && timers.nextEvent != "")
            slot.eventTimer := timers.nextEvent
        else if (timers && timers.activeBuff != "")
            slot.eventTimer := timers.activeBuff
    }

    ; Updates per-slot egg scan streaks and returns an Array of egg keys that
    ; newly transitioned to confirmed-spawned on this scan.
    UpdateEggScan(hwnd, scanResult) {
        slot := this.byHwnd.Get(hwnd, "")
        if (!slot || !scanResult)
            return []
        slot.indexOpen := scanResult.indexOpen
        if !scanResult.indexOpen
            return []

        newlySpawned := []
        confirmNeed := Max(1, this.cfg.EggsConfirmScans)
        for item in scanResult.eggs {
            key := item.key
            if item.spawned {
                streak := slot.eggStreaks.Get(key, 0) + 1
                slot.eggStreaks[key] := streak
                if (streak >= confirmNeed && !slot.eggSpawned.Get(key, false)) {
                    slot.eggSpawned[key] := true
                    newlySpawned.Push(key)
                }
            } else {
                slot.eggStreaks[key] := 0
                slot.eggSpawned[key] := false
            }
        }
        return newlySpawned
    }

    ; Round-robin over live windows so capture cost is spread across ticks.
    NextScanTarget() {
        count := this.slots.Length
        loop count {
            this.scanIndex := Mod(this.scanIndex, count) + 1
            slot := this.slots[this.scanIndex]
            if slot.hwnd
                return slot
        }
        return ""
    }

    ; ------------------------------------------------------------ queries
    VisibleSlots() {
        highest := 0
        for slot in this.slots
            if (slot.hwnd || slot.missingSince)
                highest := slot.index
        count := Max(this.cfg.ExpectedInstances, highest)
        this.EnsureSlots(count)
        result := []
        loop count
            result.Push(this.slots[A_Index])
        return result
    }

    ; Live slots, most urgent first: status priority, then idle time (largest first).
    UrgencyOrder(now) {
        live := []
        for slot in this.slots
            if slot.hwnd
                live.Push(slot)
        cfg := this.cfg
        return WindowTracker.SortBy(live, (s) => -(Status.Priority[Status.Evaluate(s, now, cfg)] * 10000000000000 + (now - s.lastInput)))
    }

    ClearMissing() {
        for slot in this.slots
            if !slot.hwnd
                slot.missingSince := 0
        ; Drop trailing empty slots beyond the expected count.
        while (this.slots.Length > this.cfg.ExpectedInstances && !this.slots[this.slots.Length].hwnd)
            this.slots.Pop()
    }

    RefreshLabels() {
        for slot in this.slots
            slot.label := this.cfg.LabelFor(slot.index)
    }

    ; ------------------------------------------------------------ persistence
    ; state.ini lets a script restart (e.g. Reload settings) keep slot labels and
    ; idle clocks. A_TickCount is 64-bit system uptime, so saved ticks stay valid
    ; until reboot; values from the future (after a reboot) are ignored.
    SaveState() {
        if (this.statePath = "")
            return
        text := "[Slots]`nCount=" this.slots.Length "`n"
        for slot in this.slots {
            text .= Format("Slot{1}Hwnd={2}`nSlot{1}LastInput={3}`nSlot{1}FirstSeen={4}`nSlot{1}HasInput={5}`n",
                slot.index, slot.hwnd, slot.lastInput, slot.firstSeen, slot.hasInput ? 1 : 0)
        }
        tmp := this.statePath ".tmp"
        try {
            if FileExist(tmp)
                FileDelete(tmp)
            FileAppend(text, tmp, "UTF-16")
            FileMove(tmp, this.statePath, 1)
        }
    }

    LoadState() {
        if (this.statePath = "" || !FileExist(this.statePath))
            return 0
        now := this.clock.Now()
        live := Map()
        for hwnd in this.winApi.List()
            live[hwnd] := true
        restored := 0
        try {
            count := IniRead(this.statePath, "Slots", "Count", 0)
            if !IsInteger(count)
                return 0
            loop Min(Integer(count), Config.MaxSlots) {
                i := A_Index
                hwnd := IniRead(this.statePath, "Slots", "Slot" i "Hwnd", 0)
                if !(IsInteger(hwnd) && hwnd && live.Has(hwnd + 0) && !this.byHwnd.Has(hwnd + 0))
                    continue
                hwnd := Integer(hwnd)
                this.EnsureSlots(i)
                slot := this.slots[i]
                if slot.hwnd
                    continue
                this.Adopt(slot, hwnd, now)
                lastInput := IniRead(this.statePath, "Slots", "Slot" i "LastInput", 0)
                firstSeen := IniRead(this.statePath, "Slots", "Slot" i "FirstSeen", 0)
                if (IsInteger(lastInput) && lastInput > 0 && lastInput <= now) {
                    slot.lastInput := Integer(lastInput)
                    slot.hasInput := IniRead(this.statePath, "Slots", "Slot" i "HasInput", 0) = 1
                }
                if (IsInteger(firstSeen) && firstSeen > 0 && firstSeen <= now)
                    slot.firstSeen := Integer(firstSeen)
                restored++
            }
        }
        return restored
    }

    ; Stable insertion sort (arrays here hold at most ~20 items).
    static SortBy(arr, keyFn) {
        items := []
        for value in arr
            items.Push({key: keyFn(value), value: value})
        loop items.Length - 1 {
            j := A_Index + 1
            current := items[j]
            while (j > 1 && items[j - 1].key > current.key) {
                items[j] := items[j - 1]
                j--
            }
            items[j] := current
        }
        result := []
        for item in items
            result.Push(item.value)
        return result
    }
}
