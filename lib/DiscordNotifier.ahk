; =============================================================================
; DiscordNotifier.ahk - Sends rich Discord Webhook embeds when a rare egg
; spawns in the Index (matching the SenZ V2 egg notifier format).
;
; Disabled while [Discord] WebhookUrl is empty. Uses asynchronous WinHttpTransport
; so webhook HTTP POSTs never block the HUD or timers.
; =============================================================================

class DiscordNotifier {
    __New(cfg, logger, clock, transport := "", unixTimeFn := "") {
        this.cfg := cfg
        this.logger := logger
        this.clock := clock
        this.transport := transport ? transport : WinHttpTransport(logger)
        this.unixTimeFn := unixTimeFn ? unixTimeFn : () => DiscordNotifier.CurrentUnixTime()
        this.lastSent := Map()
    }

    Enabled => Trim(this.cfg.DiscordWebhookUrl) != ""

    ; Sends a Discord rich embed for `eggKey` ("363B", "1T", "2.5T", "3T", "210B").
    ; `force` skips cooldown (used by "Send test Discord egg alert").
    NotifyEggSpawn(eggKey, slotLabel := "", force := false) {
        if !this.Enabled
            return false

        if !force {
            now := this.clock.Now()
            cooldownMs := this.cfg.DiscordCooldownSeconds * 1000
            if (this.lastSent.Has(eggKey) && (now - this.lastSent[eggKey] < cooldownMs))
                return false
            this.lastSent[eggKey] := now
        }

        meta := this.cfg.EggMeta(eggKey)
        unixTs := this.unixTimeFn.Call()
        payload := this.BuildPayload(meta, unixTs, slotLabel)
        headers := Map("Content-Type", "application/json; charset=utf-8")

        try {
            this.transport.Post(Trim(this.cfg.DiscordWebhookUrl), payload, headers)
            this.logger.Info("Discord webhook sent for " meta.name (slotLabel != "" ? " (" slotLabel ")" : ""))
            return true
        } catch as e {
            this.logger.Warn("Discord webhook failed: " e.Message)
            return false
        }
    }

    BuildPayload(meta, unixTs, slotLabel := "") {
        roleId := Trim(meta.roleId)
        if RegExMatch(roleId, "^\d+$")
            mention := "<@&" roleId ">"
        else if (roleId != "")
            mention := roleId
        else
            mention := "@" meta.name

        content := mention " spawned!"
        title := meta.emoji " " meta.name " Spawned!! - <t:" unixTs ":t>"

        descLines := [
            meta.emoji " **Egg:** " meta.name,
            "💎 **Rarity:** " meta.rarity,
            "🍀 **Luck:** " meta.luck,
            "🕒 **Spawned:** <t:" unixTs ":R>"
        ]
        joinUrl := Trim(this.cfg.DiscordJoinGameUrl)
        if (joinUrl != "")
            descLines.Push("🟦 **Join Game:** [Click Here](" joinUrl ")")

        desc := ""
        for i, line in descLines
            desc .= (i > 1 ? "\n" : "") DiscordNotifier.EscapeJson(line)

        embedFields := []
        embedFields.Push('"title":"' DiscordNotifier.EscapeJson(title) '"')
        embedFields.Push('"description":"' desc '"')
        embedFields.Push('"color":' Integer(this.cfg.DiscordEmbedColor))

        thumb := Trim(meta.thumbnailUrl)
        if (thumb != "")
            embedFields.Push('"thumbnail":{"url":"' DiscordNotifier.EscapeJson(thumb) '"}')

        footer := Trim(this.cfg.DiscordFooterText)
        if (footer != "") {
            footerObj := '"text":"' DiscordNotifier.EscapeJson(footer) '"'
            avatar := Trim(this.cfg.DiscordBotAvatarUrl)
            if (avatar != "")
                footerObj .= ',"icon_url":"' DiscordNotifier.EscapeJson(avatar) '"'
            embedFields.Push('"footer":{' footerObj '}')
        }

        embedJson := "{" DiscordNotifier.Join(embedFields, ",") "}"

        rootFields := []
        botName := Trim(this.cfg.DiscordBotName)
        if (botName != "")
            rootFields.Push('"username":"' DiscordNotifier.EscapeJson(botName) '"')
        botAvatar := Trim(this.cfg.DiscordBotAvatarUrl)
        if (botAvatar != "")
            rootFields.Push('"avatar_url":"' DiscordNotifier.EscapeJson(botAvatar) '"')
        rootFields.Push('"content":"' DiscordNotifier.EscapeJson(content) '"')
        rootFields.Push('"allowed_mentions":{"parse":["roles"]}')
        rootFields.Push('"embeds":[' embedJson ']')

        return "{" DiscordNotifier.Join(rootFields, ",") "}"
    }

    Poll() => this.transport.Poll()

    static CurrentUnixTime() {
        return DateDiff(A_NowUTC, "19700101000000", "Seconds")
    }

    static EscapeJson(s) {
        s := StrReplace(s, "\", "\\")
        s := StrReplace(s, '"', '\"')
        s := StrReplace(s, "`r", "")
        s := StrReplace(s, "`n", "\n")
        s := StrReplace(s, "`t", "\t")
        return s
    }

    static Join(arr, sep) {
        out := ""
        for i, v in arr
            out .= (i > 1 ? sep : "") v
        return out
    }
}
