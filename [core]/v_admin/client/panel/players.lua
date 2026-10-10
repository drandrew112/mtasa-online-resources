-- ============================================================
--  v_admin / client/panel/players.lua
--  Players tab: online player list | data | actions.
--  Actions that need input (mute, jail, kick, ban) open an inline
--  form in the action column; the admin level is a dropdown.
-- ============================================================

local S, F, C = AP.S, AP.F, AP.C

local st = {
    selected   = nil,   -- player ID
    listScroll = 0,
    form       = nil,   -- { action, targetId, ... } while an inline form is open
}

-- Action buttons. perm = key in ADMIN.perms.
local ACTIONS = {
    { group = "General" },
    { id = "goto",    label = "Go to",       perm = "teleport" },
    { id = "gethere", label = "Bring here",  perm = "teleport" },
    { id = "heal",    label = "Heal",        perm = "heal" },
    { group = "Vehicle" },
    { id = "fixveh",  label = "Fix vehicle",  perm = "vehicle" },
    { id = "flipveh", label = "Flip vehicle", perm = "vehicle" },
    { id = "getout",  label = "Pull out",     perm = "vehicle" },
    { group = "Sanctions" },
    { id = "mute",    label = "Mute",   perm = "mute", form = "mute", show = function(p) return not p.muted end },
    { id = "unmute",  label = "Unmute", perm = "mute", show = function(p) return p.muted end },
    { id = "jail",    label = "Admin jail", perm = "jail", form = "jail", show = function(p) return not p.jailed end },
    { id = "unjail",  label = "Release jail", perm = "jail", show = function(p) return p.jailed end },
    { id = "kick",    label = "Kick",   perm = "kick", form = "kick", danger = true },
    { group = "Account" },
    { id = "ban",     label = "Ban account",   perm = "ban", form = "ban", danger = true, show = function(p) return not p.banned end },
    { id = "unban",   label = "Unban account", perm = "ban", show = function(p) return p.banned end },
    { id = "setlevel", label = "Admin level", perm = "setLevel", dropdown = true },
}

-- Inline forms.
local FORMS = {
    mute = { title = "Mute",       minutes = true, chips = { 5, 15, 30, 60, 120 } },
    jail = { title = "Admin jail", minutes = true, chips = { 10, 30, 60, 120, 240 } },
    kick = { title = "Kick",       danger = true },
    ban  = { title = "Ban account", danger = true, note = "Permanent account ban (v_accounts). The serial is stored too." },
}

local function fmtDuration(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    local m, s = math.floor(seconds / 60), seconds % 60
    if m >= 60 then return ("%dh %02dm"):format(math.floor(m / 60), m % 60) end
    return ("%dm %02ds"):format(m, s)
end

local function fmtDate(ts)
    if not ts then return "-" end
    local t = getRealTime(ts)
    return ("%04d.%02d.%02d %02d:%02d"):format(t.year + 1900, t.month + 1, t.monthday, t.hour, t.minute)
end

local function selectedPlayer()
    if not st.selected then return nil end
    for _, p in ipairs(AP.players) do
        if p.id == st.selected then return p end
    end
end

local function selectPlayer(id)
    if st.selected ~= id then st.form = nil end
    st.selected = id
end

--------------------------------------------------------------------------------
-- player list
--------------------------------------------------------------------------------

local function filteredPlayers()
    local f = AP.fieldText("pl_filter"):lower()
    if f == "" then return AP.players end
    local out = {}
    for _, p in ipairs(AP.players) do
        if tostring(p.id) == f
        or p.name:lower():find(f, 1, true)
        or (p.account and p.account:lower():find(f, 1, true)) then
            out[#out + 1] = p
        end
    end
    return out
end

local function drawList(x, y, w, h)
    dxDrawRectangle(x, y, w, h, C.side)
    local pad = S(10)
    local iw = w - pad * 2

    AP.field("pl_filter", x + pad, y + pad, iw, S(44), { placeholder = "Filter: ID / name / account", max = 32 })

    local list = filteredPlayers()
    local ly = y + pad + S(54)
    local rowH = S(48)
    local visible = math.max(1, math.floor((y + h - S(36) - ly) / rowH))
    st.listScroll = math.max(0, math.min(st.listScroll, #list - visible))
    AP.scrollArea(x, ly, w, visible * rowH, function(dir) st.listScroll = st.listScroll + dir end)

    for i = 1, visible do
        local p = list[st.listScroll + i]
        if not p then break end
        local ry = ly + (i - 1) * rowH
        local rh = rowH - S(4)
        local sel = p.id == st.selected
        dxDrawRectangle(x + pad, ry, iw, rh, sel and C.accent or (AP.hovered(x + pad, ry, iw, rh) and C.rowHot or C.row))
        AP.text(tostring(p.id), x + pad + S(10), ry, S(50), rh, sel and C.text or C.dim, 1.0, "default-bold")
        AP.text(p.name, x + pad + S(62), ry, iw - S(150), rh, C.text, 1.0, "default-bold")

        local tags = {}
        if p.adminLevel > 0 then tags[#tags + 1] = { "A" .. p.adminLevel, C.head } end
        if not p.logged then tags[#tags + 1] = { "GUEST", C.dim } end
        if p.muted then tags[#tags + 1] = { "M", C.warn } end
        if p.jailed then tags[#tags + 1] = { "J", C.warn } end
        if p.banned then tags[#tags + 1] = { "B", C.bad } end
        local tx = x + pad + iw - S(10)
        for t = #tags, 1, -1 do
            local tw = dxGetTextWidth(tags[t][1], F(0.85), "default-bold") + S(10)
            tx = tx - tw
            AP.text(tags[t][1], tx, ry, tw, rh, sel and C.text or tags[t][2], 0.85, "default-bold", "center")
        end

        AP.area(x + pad, ry, iw, rh, function() selectPlayer(p.id) end)
    end

    local shown = AP.fieldText("pl_filter") ~= "" and (" / " .. #list .. " shown") or ""
    AP.text(#AP.players .. " online" .. shown, x + pad, y + h - S(34), iw, S(28), C.dim, 0.85, "default", "right")
end

--------------------------------------------------------------------------------
-- details
--------------------------------------------------------------------------------

-- Label/value rows; a value too long for its cell goes on its own line.
-- Clicking a row copies the value.
local function drawSection(title, rows, x, y, w)
    AP.text(title, x, y, w, S(32), C.head, 1.0, "default-bold")
    y = y + S(34)
    local rowH = S(28)
    local labelW = w * 0.36
    local sc = F(0.9)
    for _, r in ipairs(rows) do
        local label, value, color = r[1], tostring(r[2]), r[3] or C.text
        local wide = dxGetTextWidth(value, sc, "default-bold") > w - labelW - S(8)
        local h = wide and rowH * 2 or rowH
        if AP.hovered(x, y, w, h) then dxDrawRectangle(x, y, w, h, C.rowHot) end
        AP.text(label, x + S(6), y, labelW, rowH, C.dim, 0.9)
        if wide then
            AP.text(value, x + S(18), y + rowH, w - S(24), rowH, color, 0.9, "default-bold")
        else
            AP.text(value, x + labelW, y, w - labelW - S(6), rowH, color, 0.9, "default-bold")
        end
        AP.area(x, y, w, h, function()
            setClipboard(value)
            AP.notify(label .. " copied to the clipboard.")
        end)
        y = y + h
    end
    return y + S(14)
end

local function drawDetails(p, x, y, w)
    local gap = S(28)
    local colW = (w - gap) / 2
    local lx, rx = x, x + colW + gap

    local ly = drawSection("ACCOUNT", {
        { "Name", p.name },
        { "ID", p.id },
        { "Account", p.account or "not logged in", not p.account and C.dim },
        { "Account #", p.accountId or "-" },
        { "E-mail", p.email or "-" },
        { "Registered", fmtDate(p.created) },
        { "Admin level", p.adminLevel .. "  " .. AP.rankName(p.adminLevel), p.adminLevel > 0 and C.head },
    }, lx, y, colW)

    drawSection("CHARACTER", {
        { "Health / armour", (p.dead and "DEAD" or p.health) .. " / " .. p.armor, p.dead and C.bad },
        { "Cash", "€" .. AP.fmtInt(p.cash), C.good },
        { "Bank", p.bank and ("€" .. AP.fmtInt(p.bank)) or "-", p.bank and C.good },
        { "Level / XP", (p.level or "-") .. " / " .. (p.xp and AP.fmtInt(p.xp) or "-") },
        { "Played time", p.playtime or "-" },
        { "Work", p.work and tostring(p.work) or "-" },
        { "Skin", p.skin },
    }, lx, ly, colW)

    local ry = drawSection("CONNECTION", {
        { "Serial", p.serial },
        { "IP", p.ip },
        { "Ping", p.ping, p.ping > 200 and C.warn },
        { "Client version", p.version },
    }, rx, y, colW)

    ry = drawSection("LOCATION", {
        { "Zone", p.zone },
        { "Position", ("%.1f, %.1f, %.1f"):format(p.pos[1], p.pos[2], p.pos[3]) },
        { "Interior / dim.", p.interior .. " / " .. p.dimension },
        { "Vehicle", p.vehicle and (p.vehicle .. "  (" .. p.vehicleHp .. " HP)") or "-" },
    }, rx, ry, colW)

    local rows = {
        { "Muted", p.muted and ("yes, " .. fmtDuration(p.muteLeft) .. " left") or "no", p.muted and C.warn },
    }
    if p.muted then
        rows[#rows + 1] = { "Mute reason", (p.muteReason or "?") .. "  (" .. (p.muteAdmin or "?") .. ")" }
    end
    rows[#rows + 1] = { "Admin jail", p.jailed and ("yes, " .. p.jailLeft .. " min left") or "no", p.jailed and C.warn }
    if p.jailed then
        rows[#rows + 1] = { "Jail reason", (p.jailReason or "?") .. "  (" .. (p.jailAdmin or "?") .. ")" }
    end
    rows[#rows + 1] = { "Banned", p.banned and "yes" or "no", p.banned and C.bad }
    if p.banned then
        rows[#rows + 1] = { "Ban", (p.banReason or "?") .. "  (" .. (p.banAdmin or "?") .. ", " .. (p.banDate or "?") .. ")" }
    end
    drawSection("SANCTIONS", rows, rx, ry, colW)
end

--------------------------------------------------------------------------------
-- actions
--------------------------------------------------------------------------------

local function openLevelDropdown(p, x, y, w)
    local myLevel = AP.myLevel
    local maxGrant = myLevel >= ADMIN.maxLevel and ADMIN.maxLevel or myLevel - 1
    local items = {}
    for lvl = 0, ADMIN.maxLevel do
        local allowed = lvl <= maxGrant
        items[#items + 1] = {
            label = lvl .. "  " .. AP.rankName(lvl) .. (allowed and "" or "  - locked"),
            disabled = not allowed,
            active = lvl == p.adminLevel,
            fn = function()
                if lvl ~= p.adminLevel then AP.sendAction("setlevel", p.id, lvl) end
            end,
        }
    end
    AP.openDropdown(x, y, w, items)
end

local function openForm(kind, p)
    st.form = { kind = kind, targetId = p.id }
    AP.setField("pl_minutes", "")
    AP.setField("pl_reason", "")
    AP.setFocus(FORMS[kind].minutes and "pl_minutes" or "pl_reason")
end

local function submitForm()
    local f = st.form
    if not f then return end
    local def = FORMS[f.kind]
    local reason = AP.fieldText("pl_reason"):gsub("^%s+", ""):gsub("%s+$", "")
    local minutes = tonumber(AP.fieldText("pl_minutes"))

    if def.minutes and (not minutes or minutes < 1) then
        AP.setFocus("pl_minutes")
        return AP.notify("Enter the duration in minutes.")
    end
    if reason == "" then
        AP.setFocus("pl_reason")
        return AP.notify("Enter a reason.")
    end

    if def.minutes then
        AP.sendAction(f.kind, f.targetId, minutes, reason)
    else
        AP.sendAction(f.kind, f.targetId, reason)
    end
    st.form = nil
    AP.setFocus(nil)
end

local function drawForm(p, x, y, w, h)
    local f = st.form
    local def = FORMS[f.kind]
    dxDrawRectangle(x, y, w, h, C.side)
    local pad = S(14)
    local ix, iw = x + pad, w - pad * 2
    local cy = y + pad

    AP.text(def.title:upper(), ix, cy, iw, S(36), def.danger and C.bad or C.head, 1.2, "default-bold")
    cy = cy + S(38)
    AP.text(p.name .. "  (ID " .. p.id .. ")", ix, cy, iw, S(30), C.text, 1.0, "default-bold")
    cy = cy + S(44)

    if def.minutes then
        AP.text("Minutes", ix, cy, iw, S(28), C.dim, 0.9)
        cy = cy + S(30)
        local n = #def.chips
        local cw = (iw - (n - 1) * S(6)) / n
        for i, m in ipairs(def.chips) do
            local active = AP.fieldText("pl_minutes") == tostring(m)
            AP.button(ix + (i - 1) * (cw + S(6)), cy, cw, S(40), tostring(m), function()
                AP.setField("pl_minutes", m)
                AP.setFocus("pl_reason")
            end, active and "active")
        end
        cy = cy + S(48)
        AP.field("pl_minutes", ix, cy, iw, S(44), { placeholder = "or type minutes", max = 5, numeric = true,
            onEnter = function() AP.setFocus("pl_reason") end })
        cy = cy + S(60)
    end

    AP.text("Reason", ix, cy, iw, S(28), C.dim, 0.9)
    cy = cy + S(30)
    AP.field("pl_reason", ix, cy, iw, S(44), { placeholder = "Reason (shown to the player)", max = 120, onEnter = submitForm })
    cy = cy + S(56)

    if def.note then
        local lines = AP.wrap(def.note, iw, 0.85)
        for _, line in ipairs(lines) do
            AP.text(line, ix, cy, iw, S(24), C.warn, 0.85)
            cy = cy + S(24)
        end
        cy = cy + S(8)
    end

    local bw = (iw - S(10)) / 2
    AP.button(ix, cy, bw, S(50), "Confirm", submitForm, def.danger and "danger" or "active")
    AP.button(ix + bw + S(10), cy, bw, S(50), "Cancel", function() st.form = nil; AP.setFocus(nil) end)
end

local function drawActions(p, x, y, w, h)
    if st.form then
        if st.form.targetId ~= p.id then st.form = nil else return drawForm(p, x, y, w, h) end
    end

    dxDrawRectangle(x, y, w, h, C.side)
    local pad = S(14)
    local ix, iw = x + pad, w - pad * 2
    local bw, bh, gap = (iw - S(8)) / 2, S(56), S(8)
    local col, cy = 0, y + pad - S(4)

    for _, a in ipairs(ACTIONS) do
        if a.group then
            if col > 0 then cy = cy + bh + gap end
            col = 0
            AP.text(a.group:upper(), ix, cy, iw, S(34), C.dim, 0.9, "default-bold")
            cy = cy + S(36)
        elseif not a.show or a.show(p) then
            if col >= 2 then col = 0; cy = cy + bh + gap end
            local need = AP.permLevel(a.perm)
            local allowed = AP.myLevel >= need
            local style = not allowed and "off" or (a.danger and "danger" or nil)
            local bx, by = ix + col * (bw + S(8)), cy
            local label = a.dropdown and (a.label .. ": " .. p.adminLevel .. "  ...") or a.label
            AP.button(bx, by, bw, bh, label, function()
                if a.dropdown then
                    openLevelDropdown(p, bx, by + bh + S(4), math.max(bw, S(300)))
                elseif a.form then
                    openForm(a.form, p)
                else
                    AP.sendAction(a.id, p.id)
                end
            end, style, allowed and ("level " .. need .. "+") or ("needs level " .. need))
            col = col + 1
        end
    end
end

--------------------------------------------------------------------------------
-- tab
--------------------------------------------------------------------------------

AP.addTab({
    id = "players", label = "Players", perm = "panel", order = 1,
    draw = function(x, y, w, h)
        local listW, actW, gap = S(380), S(420), S(18)
        drawList(x, y, listW, h)

        local p = selectedPlayer()
        local dx = x + listW + gap
        local dw = w - listW - actW - gap * 2
        if not p then
            AP.text(st.selected and "That player has left the server." or "Select a player on the left.",
                dx, y, dw + actW, S(48), C.dim, 1.1)
            return
        end
        drawDetails(p, dx, y, dw)
        drawActions(p, x + w - actW, y, actW, h)
        AP.text("Click a data row to copy it.", dx, y + h - S(30), dw, S(30), C.off, 0.8)
    end,
    onClose = function() st.form = nil end,
})
