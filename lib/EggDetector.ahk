; =============================================================================
; EggDetector.ahk - Resolution-independent computer vision detector for the
; in-game Index egg grid.
;
; How it works:
;   1. Locates the Index dialog's cream parchment background (#FCEEBD) by
;      finding vertical pure-parchment separator strips between the 3 card
;      columns. If fewer than 3 strips exist, the Index dialog is closed and
;      detection exits immediately in <1 ms.
;   2. Segments the 3 card columns and full horizontal card rows inside the
;      parchment area.
;   3. Classifies each card's background gradient:
;        - The 4 rare target eggs (363B, 1T, 2.5T, 3T) share an identical
;          cyan-teal top (#5D8D8D..#639595) to purple-lavender bottom
;          (#896D91..#9F82AB) vertical gradient.
;        - The optional 210B egg immediately precedes 363B and has a dark
;          obsidian card background (#0B1111..#0F1616).
;   4. Samples a 5x5 grid (25 points) across the center of each target egg card
;      (X: 34%..66%, Y: 28%..60%) plus the top-border "xN In Map" badge:
;        - Unspawned / undiscovered eggs render as a solid black silhouette
;          (>= 65% of center points are near-black R<=22, G<=25, B<=25).
;        - When an egg spawns, its silhouette is replaced by a bright colored
;          egg icon (blackRatio < 0.55 and avgBrightness > 32) and/or a white
;          "x1 In Map" label on the top border.
; =============================================================================

class EggDetector {
    static GradientKeys := ["363B", "1T", "2.5T", "3T"]

    __New(cfg) {
        this.cfg := cfg
    }

    ; Returns {indexOpen: bool, cols: Array, rows: Array, eggs: Array of
    ; {key, row, col, x0, y0, x1, y1, blackRatio, avgRgb, badgeHits, spawned}}
    ScanFrame(frame) {
        result := {indexOpen: false, cols: [], rows: [], eggs: []}
        if !frame || frame.width < 150 || frame.height < 150
            return result

        grid := EggDetector.LocateIndexGrid(frame)
        if !grid.indexOpen
            return result

        result.indexOpen := true
        result.cols := grid.cols
        result.rows := grid.rows

        gradCards := []
        allCards := []

        for rIdx, row in grid.rows {
            for cIdx, col in grid.cols {
                if (cIdx > 3)
                    break
                box := {x0: col.x0, y0: row.y0, x1: col.x1, y1: row.y1, row: rIdx, col: cIdx}
                allCards.Push(box)
                if EggDetector.IsCyanPurpleCard(frame, box)
                    gradCards.Push(box)
            }
        }

        ; Optional 210B dark-background egg sits immediately before the first
        ; cyan-purple gradient card (Row r, Col 1 when 363B is at Row r, Col 2).
        if (this.cfg.EggsTrack210B && gradCards.Length >= 1) {
            firstGrad := gradCards[1]
            if (firstGrad.col = 2) {
                col1 := grid.cols[1]
                row1 := grid.rows[firstGrad.row]
                box210 := {x0: col1.x0, y0: row1.y0, x1: col1.x1, y1: row1.y1, row: firstGrad.row, col: 1}
                if !EggDetector.IsParchmentCard(frame, box210) {
                    metrics210 := EggDetector.MeasureCardCenter(frame, box210, true)
                    result.eggs.Push({
                        key: "210B",
                        row: box210.row,
                        col: box210.col,
                        x0: box210.x0,
                        y0: box210.y0,
                        x1: box210.x1,
                        y1: box210.y1,
                        blackRatio: metrics210.blackRatio,
                        avgRgb: metrics210.avgRgb,
                        badgeHits: metrics210.badgeHits,
                        spawned: metrics210.spawned
                    })
                }
            }
        }

        for idx, card in gradCards {
            if (idx > EggDetector.GradientKeys.Length)
                break
            key := EggDetector.GradientKeys[idx]
            metrics := EggDetector.MeasureCardCenter(frame, card, false)
            result.eggs.Push({
                key: key,
                row: card.row,
                col: card.col,
                x0: card.x0,
                y0: card.y0,
                x1: card.x1,
                y1: card.y1,
                blackRatio: metrics.blackRatio,
                avgRgb: metrics.avgRgb,
                badgeHits: metrics.badgeHits,
                spawned: metrics.spawned
            })
        }

        return result
    }

    ; Returns true if 0xRRGGBB matches the Index parchment (#FCEEBD).
    static IsParchmentPixel(rgb) {
        r := (rgb >> 16) & 0xFF
        g := (rgb >> 8) & 0xFF
        b := rgb & 0xFF
        return (r >= 240 && g >= 225 && g <= 246 && b >= 175 && b <= 205)
    }

    ; Locates vertical parchment strips and extracts the 3 card columns and full card rows.
    static LocateIndexGrid(frame) {
        w := frame.width, h := frame.height
        minRunH := Max(40, Round(h * 0.40))
        minStripW := Max(6, Round(w * 0.008))

        pStrips := []
        inStrip := false, s0 := 0, yMin := h, yMax := 0
        x := 0
        while (x < w) {
            run := 0, bestRun := 0, rStart := 0, bStart := 0, bEnd := 0
            y := 0
            while (y < h) {
                if EggDetector.IsParchmentPixel(frame.GetPixelXY(x, y)) {
                    if (run = 0)
                        rStart := y
                    run += 2
                    if (run > bestRun) {
                        bestRun := run
                        bStart := rStart
                        bEnd := y
                    }
                } else {
                    run := 0
                }
                y += 2
            }
            if (bestRun >= minRunH) {
                if !inStrip {
                    inStrip := true, s0 := x, yMin := bStart, yMax := bEnd
                } else {
                    if (bStart < yMin)
                        yMin := bStart
                    if (bEnd > yMax)
                        yMax := bEnd
                }
            } else if inStrip {
                if (x - s0 >= minStripW)
                    pStrips.Push({x0: s0, x1: x - 1, y0: yMin, y1: yMax})
                inStrip := false
            }
            x++
        }
        if (inStrip && (w - s0 >= minStripW))
            pStrips.Push({x0: s0, x1: w - 1, y0: yMin, y1: yMax})

        if (pStrips.Length < 3)
            return {indexOpen: false, cols: [], rows: []}

        cols := []
        minColW := Max(30, Round(w * 0.04))
        maxColW := Round(w * 0.35)
        loop pStrips.Length - 1 {
            i := A_Index
            cx0 := pStrips[i].x1 + 1
            cx1 := pStrips[i + 1].x0 - 1
            cw := cx1 - cx0 + 1
            if (cw >= minColW && cw <= maxColW) {
                cols.Push({
                    x0: cx0,
                    x1: cx1,
                    y0: Max(pStrips[i].y0, pStrips[i + 1].y0),
                    y1: Min(pStrips[i].y1, pStrips[i + 1].y1)
                })
            }
        }

        ; When Row 2 Col 3 is empty parchment, Strip 3 starts immediately after Col 2
        ; and swallows Col 3's lower half. Reconstruct Col 3 from Col 1 & Col 2 geometry.
        if (cols.Length = 2) {
            cw := cols[1].x1 - cols[1].x0
            gap := cols[2].x0 - cols[1].x1
            c3x0 := cols[2].x1 + gap
            c3x1 := c3x0 + cw
            if (c3x1 < w)
                cols.Push({x0: c3x0, x1: c3x1, y0: cols[2].y0, y1: cols[2].y1})
        }

        if (cols.Length < 3)
            return {indexOpen: false, cols: [], rows: []}

        ; Segment horizontal card rows along the vertical centerline of Column 1.
        midX := (cols[1].x0 + cols[1].x1) // 2
        minCardH := Max(40, Round((cols[1].x1 - cols[1].x0) * 0.70))
        rows := []
        inCard := false, r0 := 0
        y := cols[1].y0
        while (y <= cols[1].y1) {
            isP := EggDetector.IsParchmentPixel(frame.GetPixelXY(midX, y))
            if (!isP && !inCard) {
                inCard := true, r0 := y
            } else if (isP && inCard) {
                if (y - r0 >= minCardH)
                    rows.Push({y0: r0, y1: y - 1})
                inCard := false
            }
            y++
        }
        if (inCard && (cols[1].y1 - r0 + 1 >= minCardH))
            rows.Push({y0: r0, y1: cols[1].y1})

        if (rows.Length < 1)
            return {indexOpen: false, cols: [], rows: []}

        return {indexOpen: true, cols: cols, rows: rows}
    }

    ; Checks if a card slot is empty parchment (e.g. bottom-right empty cell).
    static IsParchmentCard(frame, box) {
        cw := box.x1 - box.x0, ch := box.y1 - box.y0
        c1 := frame.GetPixelXY(box.x0 + Round(cw * 0.5), box.y0 + Round(ch * 0.5))
        c2 := frame.GetPixelXY(box.x0 + Round(cw * 0.2), box.y0 + Round(ch * 0.2))
        return EggDetector.IsParchmentPixel(c1) && EggDetector.IsParchmentPixel(c2)
    }

    ; Checks if `box` has the cyan-teal top to purple-lavender bottom gradient
    ; shared by the 4 rare eggs (363B, 1T, 2.5T, 3T).
    static IsCyanPurpleCard(frame, box) {
        cw := box.x1 - box.x0, ch := box.y1 - box.y0
        if (cw < 30 || ch < 35)
            return false

        ; Sample top-left & top-mid inside the card border for cyan-teal (#5D8D8D..#639595)
        tl1 := frame.GetPixelXY(box.x0 + Round(cw * 0.08), box.y0 + Round(ch * 0.08))
        tl2 := frame.GetPixelXY(box.x0 + Round(cw * 0.14), box.y0 + Round(ch * 0.08))
        tm  := frame.GetPixelXY(box.x0 + Round(cw * 0.50), box.y0 + Round(ch * 0.06))
        cyanOk := EggDetector.IsCyanTopPixel(tl1) || EggDetector.IsCyanTopPixel(tl2) || EggDetector.IsCyanTopPixel(tm)
        if !cyanOk
            return false

        ; Sample bottom-left & bottom-right above the luck text for purple-lavender (#896D91..#9F82AB)
        bl := frame.GetPixelXY(box.x0 + Round(cw * 0.08), box.y0 + Round(ch * 0.76))
        br := frame.GetPixelXY(box.x0 + Round(cw * 0.92), box.y0 + Round(ch * 0.76))
        purpleOk := EggDetector.IsPurpleBottomPixel(bl) || EggDetector.IsPurpleBottomPixel(br)
        return purpleOk
    }

    static IsCyanTopPixel(rgb) {
        r := (rgb >> 16) & 0xFF
        g := (rgb >> 8) & 0xFF
        b := rgb & 0xFF
        return (g >= 115 && b >= 115 && (g - r) >= 20 && Abs(g - b) <= 22)
    }

    static IsPurpleBottomPixel(rgb) {
        r := (rgb >> 16) & 0xFF
        g := (rgb >> 8) & 0xFF
        b := rgb & 0xFF
        return (r >= 115 && b >= 125 && b > g && r > g && (b - g) >= 12)
    }

    ; Samples a 5x5 grid across the center of `box` (X: 34%..66%, Y: 28%..60%)
    ; and checks the top border for the white "x1 In Map" badge.
    static MeasureCardCenter(frame, box, isDarkBg := false) {
        cw := box.x1 - box.x0, ch := box.y1 - box.y0
        blackCnt := 0, totalCnt := 0
        sumR := 0, sumG := 0, sumB := 0

        loop 5 {
            gy := A_Index - 1
            sy := box.y0 + Round(ch * (0.28 + gy * 0.08))
            loop 5 {
                gx := A_Index - 1
                sx := box.x0 + Round(cw * (0.34 + gx * 0.08))
                rgb := frame.GetPixelXY(sx, sy)
                r := (rgb >> 16) & 0xFF
                g := (rgb >> 8) & 0xFF
                b := rgb & 0xFF
                totalCnt++
                sumR += r, sumG += g, sumB += b
                if (r <= 22 && g <= 25 && b <= 25)
                    blackCnt++
            }
        }

        avgR := sumR // totalCnt
        avgG := sumG // totalCnt
        avgB := sumB // totalCnt
        avgLuma := (avgR + avgG + avgB) // 3
        blackRatio := blackCnt / Float(totalCnt)

        ; Count bright white glyph pixels along the top border ("x1 In Map" / "x2 In Map")
        badgeHits := 0
        yStart := Max(0, box.y0 - 3)
        yEnd := Min(frame.height - 1, box.y0 + Max(4, Round(ch * 0.06)))
        xStart := box.x0 + Round(cw * 0.15)
        xEnd := box.x1 - Round(cw * 0.15)
        y := yStart
        while (y <= yEnd) {
            x := xStart
            while (x <= xEnd) {
                rgb := frame.GetPixelXY(x, y)
                if (((rgb >> 16) & 0xFF) >= 220 && ((rgb >> 8) & 0xFF) >= 220 && (rgb & 0xFF) >= 220)
                    badgeHits++
                x += 2
            }
            y += 1
        }

        ; A target egg is spawned when its center is no longer a black silhouette
        ; (blackRatio < 0.55 and average center luma > 32) OR when the top border
        ; displays the white "x1 In Map" badge.
        spawned := (blackRatio < 0.55 && avgLuma > 32) || (badgeHits >= 12 && !isDarkBg)
        return {
            blackRatio: blackRatio,
            avgRgb: Format("({},{},{})", avgR, avgG, avgB),
            badgeHits: badgeHits,
            spawned: spawned
        }
    }
}
