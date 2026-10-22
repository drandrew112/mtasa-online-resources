if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ============================================================
--  v_admin / client/panel/players.lua
--  Online players page: online player list | data | actions.
--  "Open account" jumps to the Accounts page of the player's account.
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
-- Account actions only show for a logged-in player (a guest has no account).
local function hasAccount(p) return p.logged and type(p.account) == "string" and p.account ~= "" end

local ACTIONS = {}
local function build_ACTIONS()
ACTIONS = {
    { group = L("v_admin.players.general") },
    { id = "account", label = L("v_admin.page.open_account"), perm = "accounts", show = hasAccount,
      fn = function(p) if hasAccount(p) then AP.setPage("accounts", p.account) end end },
    { id = "goto",    label = L("v_admin.players.go_to"),       perm = "teleport" },
    { id = "spectate", label = L("v_admin.players.spectate"),   perm = "spectate",
      show = function(p) return p.id ~= tonumber(getElementData(localPlayer, "ID")) end,
      fn = function(p) AP.sendAction("spectate", p.id) AP.close() end },
    { id = "gethere", label = L("v_admin.players.bring_here"),  perm = "teleport" },
    { id = "heal",    label = L("v_admin.players.heal"),        perm = "heal" },
    { id = "skin",    label = L("v_admin.players.change_skin"), perm = "skin", form = "skin" },
    { group = L("v_admin.players.vehicle") },
    { id = "fixveh",  label = L("v_admin.players.fix_vehicle"),  perm = "vehicle" },
    { id = "flipveh", label = L("v_admin.players.flip_vehicle"), perm = "vehicle" },
    { id = "getout",  label = L("v_admin.players.pull_out"),     perm = "vehicle" },
    { group = L("v_admin.players.sanctions") },
    { id = "mute",    label = L("v_admin.players.mute"),   perm = "mute", form = "mute", show = function(p) return not p.muted end },
    { id = "unmute",  label = L("v_admin.players.unmute"), perm = "mute", show = function(p) return p.muted end },
    { id = "jail",    label = L("v_admin.players.admin_jail"), perm = "jail", form = "jail", show = function(p) return not p.jailed end },
    { id = "unjail",  label = L("v_admin.players.release_jail"), perm = "jail", show = function(p) return p.jailed end },
    { id = "kick",    label = L("v_admin.players.kick"),   perm = "kick", form = "kick", danger = true },
    { group = L("v_admin.players.account"), show = function(p) return hasAccount(p) or p.banned end },
    { id = "ban",     label = L("v_admin.players.ban_account"),   perm = "ban", form = "ban", danger = true,
      show = function(p) return hasAccount(p) and not p.banned end },
    { id = "unban",   label = L("v_admin.players.unban_account"), perm = "ban", show = function(p) return p.banned end },
    { id = "setlevel", label = L("v_admin.players.admin_level"), perm = "setLevel", dropdown = true, show = hasAccount },
}
end

-- Inline forms.
local FORMS = {}
local function build_FORMS()
FORMS = {
    mute = { title = L("v_admin.players.mute"),       minutes = true, chips = { 5, 15, 30, 60, 120 } },
    jail = { title = L("v_admin.players.admin_jail"), minutes = true, chips = { 10, 30, 60, 120, 240 } },
    kick = { title = L("v_admin.players.kick"),       danger = true },
    ban  = { title = L("v_admin.players.ban_account"), danger = true, note = L("v_admin.players.permanent_account_ban_v_accounts_serial") },
    skin = { title = L("v_admin.players.change_skin"), skin = true, note = L("v_admin.players.skin_form_note") },
}
end

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

    AP.field("pl_filter", x + pad, y + pad, iw, S(44), { placeholder = L("v_admin.players.filter_id_name_account"), max = 32 })

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
        if not p.logged then tags[#tags + 1] = { L("v_admin.players.guest"), C.dim } end
        if p.muted then tags[#tags + 1] = { "M", C.warn } end
        if p.jailed then tags[#tags + 1] = { "J", C.warn } end
        if p.banned then tags[#tags + 1] = { "B", C.bad } end
        local tx = x + pad + iw - S(10)
        for t = #tags, 1, -1 do
            local tw = L.width(tags[t][1], F(0.85), "default-bold") + S(10)
            tx = tx - tw
            AP.text(tags[t][1], tx, ry, tw, rh, sel and C.text or tags[t][2], 0.85, "default-bold", "center")
        end

        AP.area(x + pad, ry, iw, rh, function() selectPlayer(p.id) end)
    end

    local shown = AP.fieldText("pl_filter") ~= "" and (L("v_admin.players.shown", { list = #list })) or ""
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
        local wide = L.width(value, sc, "default-bold") > w - labelW - S(8)
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
            AP.notify(L("v_admin.players.copied_to_clipboard", { label = label }))
        end)
        y = y + h
    end
    return y + S(14)
end

local function drawDetails(p, x, y, w)
    local gap = S(28)
    local colW = (w - gap) / 2
    local lx, rx = x, x + colW + gap

    local ly = drawSection(L("v_admin.players.account_2"), {
        { L("common.name"), p.name },
        { L("v_admin.players.id"), p.id },
        { L("v_admin.players.account"), p.account or L("v_admin.players.not_logged_in"), not p.account and C.dim },
        { L("v_admin.players.account_3"), p.accountId or "-" },
        { L("v_admin.players.e_mail"), p.email or "-" },
        { L("v_admin.players.registered"), fmtDate(p.created) },
        { L("v_admin.players.admin_level"), p.adminLevel .. "  " .. AP.rankName(p.adminLevel), p.adminLevel > 0 and C.head },
    }, lx, y, colW)

    drawSection(L("v_admin.players.character"), {
        { L("v_admin.players.health_armour"), (p.dead and L("v_admin.players.dead") or p.health) .. " / " .. p.armor, p.dead and C.bad },
        { L("v_admin.players.cash"), "€" .. AP.fmtInt(p.cash), C.good },
        { L("v_admin.players.bank"), p.bank and ("€" .. AP.fmtInt(p.bank)) or "-", p.bank and C.good },
        { L("v_admin.players.level_xp"), (p.level or "-") .. " / " .. (p.xp and AP.fmtInt(p.xp) or "-") },
        { L("common.played_time"), p.playtime or "-" },
        { L("v_admin.players.work"), p.work and tostring(p.work) or "-" },
        { L("v_admin.players.skin"), p.skin },
    }, lx, ly, colW)

    local ry = drawSection(L("v_admin.players.connection"), {
        { L("v_admin.players.serial"), p.serial },
        { L("v_admin.players.ip"), p.ip },
        { L("v_admin.players.ping"), p.ping, p.ping > 200 and C.warn },
        { L("v_admin.players.client_version"), p.version },
    }, rx, y, colW)

    ry = drawSection(L("v_admin.players.location"), {
        { L("v_admin.players.zone"), p.zone },
        { L("v_admin.players.position"), ("%.1f, %.1f, %.1f"):format(p.pos[1], p.pos[2], p.pos[3]) },
        { L("v_admin.players.interior_dim"), p.interior .. " / " .. p.dimension },
        { L("v_admin.players.vehicle"), p.vehicle and (L("v_admin.players.hp", { vehicle = p.vehicle, vehicle_hp = p.vehicleHp })) or "-" },
    }, rx, ry, colW)

    local rows = {
        { L("v_admin.players.muted"), p.muted and (L("v_admin.players.yes_left", { mute_left = fmtDuration(p.muteLeft) })) or "no", p.muted and C.warn },
    }
    if p.muted then
        rows[#rows + 1] = { L("v_admin.players.mute_reason"), (p.muteReason or "?") .. "  (" .. (p.muteAdmin or "?") .. ")" }
    end
    rows[#rows + 1] = { L("v_admin.players.admin_jail"), p.jailed and (L("v_admin.players.yes_min_left", { jail_left = p.jailLeft })) or "no", p.jailed and C.warn }
    if p.jailed then
        rows[#rows + 1] = { L("v_admin.players.jail_reason"), (p.jailReason or "?") .. "  (" .. (p.jailAdmin or "?") .. ")" }
    end
    rows[#rows + 1] = { L("v_admin.players.banned"), p.banned and "yes" or "no", p.banned and C.bad }
    if p.banned then
        rows[#rows + 1] = { L("v_admin.players.ban"), (p.banReason or "?") .. "  (" .. (p.banAdmin or "?") .. ", " .. (p.banDate or "?") .. ")" }
    end
    drawSection(L("v_admin.players.sanctions_2"), rows, rx, ry, colW)
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
            label = lvl .. "  " .. AP.rankName(lvl) .. (allowed and "" or L("v_admin.players.locked")),
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
    AP.setField("pl_skin", FORMS[kind].skin and tostring(p.skin) or "")
    AP.setFocus(FORMS[kind].skin and "pl_skin" or FORMS[kind].minutes and "pl_minutes" or "pl_reason")
end

local function submitForm()
    local f = st.form
    if not f then return end
    local def = FORMS[f.kind]
    if def.skin then
        local skin = tonumber(AP.fieldText("pl_skin"))
        if not skin then
            AP.setFocus("pl_skin")
            return AP.notify(L("v_admin.players.enter_skin_id"))
        end
        AP.sendAction(f.kind, f.targetId, skin)
        st.form = nil
        AP.setFocus(nil)
        return
    end
    local reason = AP.fieldText("pl_reason"):gsub("^%s+", ""):gsub("%s+$", "")
    local minutes = tonumber(AP.fieldText("pl_minutes"))

    if def.minutes and (not minutes or minutes < 1) then
        AP.setFocus("pl_minutes")
        return AP.notify(L("v_admin.players.enter_duration_in_minutes"))
    end
    if reason == "" then
        AP.setFocus("pl_reason")
        return AP.notify(L("v_admin.players.enter_reason"))
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
    AP.text(L("v_admin.players.id_2", { name = p.name, id = p.id }), ix, cy, iw, S(30), C.text, 1.0, "default-bold")
    cy = cy + S(44)

    if def.minutes then
        AP.text(L("v_admin.players.minutes"), ix, cy, iw, S(28), C.dim, 0.9)
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
        AP.field("pl_minutes", ix, cy, iw, S(44), { placeholder = L("v_admin.players.or_type_minutes"), max = 5, numeric = true,
            onEnter = function() AP.setFocus("pl_reason") end })
        cy = cy + S(60)
    end

    if def.skin then
        AP.text(L("v_admin.players.skin_id"), ix, cy, iw, S(28), C.dim, 0.9)
        cy = cy + S(30)
        AP.field("pl_skin", ix, cy, iw, S(44), { placeholder = L("v_admin.players.skin_id"), max = 5, numeric = true, onEnter = submitForm })
        cy = cy + S(56)
    else
        AP.text(L("v_admin.players.reason"), ix, cy, iw, S(28), C.dim, 0.9)
        cy = cy + S(30)
        AP.field("pl_reason", ix, cy, iw, S(44), { placeholder = L("v_admin.players.reason_shown_to_player"), max = 120, onEnter = submitForm })
        cy = cy + S(56)
    end

    if def.note then
        local lines = AP.wrap(def.note, iw, 0.85)
        for _, line in ipairs(lines) do
            AP.text(line, ix, cy, iw, S(24), C.warn, 0.85)
            cy = cy + S(24)
        end
        cy = cy + S(8)
    end

    local bw = (iw - S(10)) / 2
    AP.button(ix, cy, bw, S(50), L("common.confirm"), submitForm, def.danger and "danger" or "active")
    AP.button(ix + bw + S(10), cy, bw, S(50), L("common.cancel"), function() st.form = nil; AP.setFocus(nil) end)
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
    local spec = getElementData(localPlayer, "adminSpectating")
    if spec then
        AP.button(ix, cy, iw, S(48), L("v_admin.players.stop_spectating", { name = spec }), function() AP.sendAction("specoff") end, "active")
        cy = cy + S(56)
    end

    for _, a in ipairs(ACTIONS) do
        if a.group then
            if not a.show or a.show(p) then
                if col > 0 then cy = cy + bh + gap end
                col = 0
                AP.text(a.group:upper(), ix, cy, iw, S(34), C.dim, 0.9, "default-bold")
                cy = cy + S(36)
            end
        elseif not a.show or a.show(p) then
            if col >= 2 then col = 0; cy = cy + bh + gap end
            local need = AP.permLevel(a.perm)
            local allowed = AP.myLevel >= need
            local style = not allowed and "off" or (a.danger and "danger" or nil)
            local bx, by = ix + col * (bw + S(8)), cy
            local label = a.dropdown and (a.label .. ": " .. p.adminLevel .. "  ...") or a.label
            AP.button(bx, by, bw, bh, label, function()
                if a.fn then
                    a.fn(p)
                elseif a.dropdown then
                    openLevelDropdown(p, bx, by + bh + S(4), math.max(bw, S(300)))
                elseif a.form then
                    openForm(a.form, p)
                else
                    AP.sendAction(a.id, p.id)
                end
            end, style, allowed and (L("v_admin.players.level", { need = need })) or (L("v_admin.players.needs_level", { need = need })))
            col = col + 1
        end
    end
end

--------------------------------------------------------------------------------
-- tab
--------------------------------------------------------------------------------

AP.addPage({
    id = "players", category = "players", label = function() return L("v_admin.page.online_players") end,
    perm = "panel", order = 20, badge = function() return #AP.players end,
    draw = function(x, y, w, h)
        local listW, actW, gap = S(400), S(460), S(18)
        drawList(x, y, listW, h)

        local p = selectedPlayer()
        local dx = x + listW + gap
        local dw = w - listW - actW - gap * 2
        if not p then
            AP.text(st.selected and L("v_admin.players.that_player_has_left_server") or L("v_admin.players.select_player_on_left"),
                dx, y, dw + actW, S(48), C.dim, 1.1)
            return
        end
        drawDetails(p, dx, y, dw)
        drawActions(p, x + w - actW, y, actW, h)
        AP.text(L("v_admin.players.click_data_row_to_copy_it"), dx, y + h - S(30), dw, S(30), C.off, 0.8)
    end,
    onClose = function() st.form = nil end,
})

-- Texts load only once the player is loaded (acc_loading gate).
local textsLoaded = false
local function loadTexts()
    if textsLoaded then return end
    textsLoaded = true
    build_ACTIONS()
    build_FORMS()
    exports.acc_loading:resourceReady()
end
addEvent("onClientLoadingStarted", true)
addEventHandler("onClientLoadingStarted", root, loadTexts)
addEventHandler("onClientResourceStart", resourceRoot, function()
    if getElementData(localPlayer, "loaded") then loadTexts() end
end)
