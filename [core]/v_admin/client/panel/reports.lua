if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ============================================================
--  v_admin / client/panel/reports.lua
--  Reports tab – the admin report manager (/reports opens the panel
--  here). Same server events as before (server/report.lua):
--    Active cases – live list, claim, chat, teleport, close
--    Logs         – closed reports from report_logs/, read-only
-- ============================================================

local S, F, C = AP.S, AP.F, AP.C
local E = ADMIN.events

local st = {
    mode         = "active",  -- "active" | "logs"
    active       = {},        -- packed reports (server push)
    logs         = nil,       -- log index entries (newest first), nil = not loaded
    selActive    = nil,       -- report id
    selLog       = nil,       -- file name
    logData      = nil,       -- { file, data }
    listScroll   = 0,
    chatScroll   = 0,         -- lines scrolled up from the bottom
    confirmClose = nil,       -- { id, tick }
    wrapCache    = {},
}

local COLORS = {
    player = tocolor(102, 200, 255, 255),
    admin  = tocolor(255, 192, 80, 255),
    system = tocolor(176, 176, 176, 255),
}

local function strip(s) return (tostring(s or ""):gsub("#%x%x%x%x%x%x", "")) end

local function selectedReport()
    for _, r in ipairs(st.active) do
        if r.id == st.selActive then return r end
    end
end

local function waitingCount()
    local n = 0
    for _, r in ipairs(st.active) do
        if r.status ~= "claimed" then n = n + 1 end
    end
    return n
end

--------------------------------------------------------------------------------
-- server events
--------------------------------------------------------------------------------

addEvent(E.reportAdminList, true)
addEventHandler(E.reportAdminList, resourceRoot, function(list)
    st.active = type(list) == "table" and list or {}
    table.sort(st.active, function(a, b) return a.id < b.id end)
end)

addEvent(E.reportLogList, true)
addEventHandler(E.reportLogList, resourceRoot, function(list)
    st.logs = type(list) == "table" and list or {}
end)

addEvent(E.reportLogData, true)
addEventHandler(E.reportLogData, resourceRoot, function(fileName, data)
    if fileName ~= st.selLog or type(data) ~= "table" then return end
    st.logData = { file = fileName, data = data }
    st.chatScroll = 0
end)

local function setMode(mode)
    st.mode = mode
    st.listScroll, st.chatScroll = 0, 0
    st.confirmClose = nil
    if mode == "logs" then
        st.logs = nil
        triggerServerEvent(E.reportLogList, resourceRoot)
    else
        triggerServerEvent(E.reportWantActive, resourceRoot)
    end
end

--------------------------------------------------------------------------------
-- chat rendering
--------------------------------------------------------------------------------

-- messages: { { kind = "player"|"admin"|"system", name, text, time } }
-- -> flat list of lines { text, color, font, indent }
local function buildLines(key, messages, w)
    local cacheKey = key .. "|" .. #messages .. "|" .. math.floor(w)
    if st.wrapCache.key == cacheKey then return st.wrapCache.lines end

    local lines = {}
    for _, m in ipairs(messages) do
        local color = COLORS[m.kind] or COLORS.admin
        if m.kind == "system" then
            for _, l in ipairs(AP.wrap("[" .. (m.time or "--:--") .. "]  " .. m.text, w, 0.9)) do
                lines[#lines + 1] = { text = l, color = color, font = "default" }
            end
        else
            lines[#lines + 1] = { text = m.name .. "   " .. (m.time or ""), color = color, font = "default-bold" }
            for _, l in ipairs(AP.wrap(m.text, w - S(16), 0.95)) do
                lines[#lines + 1] = { text = l, color = C.text, font = "default", indent = S(16) }
            end
        end
        lines[#lines + 1] = { text = "", color = C.text, font = "default", gap = true }
    end
    st.wrapCache = { key = cacheKey, lines = lines }
    return lines
end

local function drawChat(key, messages, x, y, w, h)
    dxDrawRectangle(x, y, w, h, C.field)
    local pad = S(12)
    local lines = buildLines(key, messages, w - pad * 2)
    local lineH = S(30)
    local visible = math.max(1, math.floor((h - pad * 2) / lineH))
    local maxScroll = math.max(0, #lines - visible)
    st.chatScroll = math.max(0, math.min(st.chatScroll, maxScroll))
    AP.scrollArea(x, y, w, h, function(dir) st.chatScroll = st.chatScroll - dir end)

    local first = math.max(1, #lines - visible + 1 - st.chatScroll)
    local count = math.min(visible, #lines)
    -- bottom-aligned
    local by = y + h - pad - count * lineH
    for i = 0, count - 1 do
        local l = lines[first + i]
        if not l then break end
        if not l.gap then
            AP.text(l.text, x + pad + (l.indent or 0), by + i * lineH, w - pad * 2 - (l.indent or 0), lineH,
                l.color, l.font == "default-bold" and 0.9 or 0.95, l.font)
        end
    end
    if #lines == 0 then
        AP.text(L("v_admin.reports.no_messages"), x, y, w, h, C.dim, 1.0, "default", "center")
    end
    if st.chatScroll > 0 then
        AP.text(L("v_admin.reports.scrolled_up_lines_mouse_wheel", { chat_scroll = st.chatScroll }), x, y + S(4), w - pad, S(26), C.off, 0.8, "default", "right")
    end
end

local function liveMessages(r)
    local out = {}
    for _, m in ipairs(r.messages or {}) do
        out[#out + 1] = { kind = m.who == "system" and "system" or m.who, name = strip(m.name), text = m.text, time = m.time }
    end
    return out
end

local function logMessages(data)
    local info = data.info or {}
    local out = {}
    for _, m in ipairs(data.messages or {}) do
        local kind = (m.sender == "SYSTEM") and "system" or (m.sender == info.player and "player" or "admin")
        out[#out + 1] = { kind = kind, name = strip(m.sender), text = m.text, time = m.time }
    end
    return out
end

--------------------------------------------------------------------------------
-- left list
--------------------------------------------------------------------------------

local function drawList(x, y, w, h)
    dxDrawRectangle(x, y, w, h, C.side)
    local pad = S(10)
    local iw = w - pad * 2

    local tw = (iw - S(8)) / 2
    AP.button(x + pad, y + pad, tw, S(44), L("v_admin.reports.active_cases", { active = #st.active }),
        function() setMode("active") end, st.mode == "active" and "active")
    AP.button(x + pad + tw + S(8), y + pad, tw, S(44), L("v_admin.reports.logs"),
        function() setMode("logs") end, st.mode == "logs" and "active")

    local ly = y + pad + S(56)
    local rowH = S(66)
    local items = st.mode == "active" and st.active or (st.logs or {})
    local visible = math.max(1, math.floor((y + h - pad - ly) / rowH))
    st.listScroll = math.max(0, math.min(st.listScroll, #items - visible))
    AP.scrollArea(x, ly, w, visible * rowH, function(dir) st.listScroll = st.listScroll + dir end)

    if st.mode == "logs" and not st.logs then
        AP.text(L("common.loading"), x + pad, ly, iw, S(40), C.dim, 1.0)
        return
    end
    if #items == 0 then
        AP.text(st.mode == "active" and L("v_admin.reports.no_active_reports") or L("v_admin.reports.no_saved_logs"), x + pad, ly, iw, S(40), C.dim, 1.0)
        return
    end

    for i = 1, visible do
        local it = items[st.listScroll + i]
        if not it then break end
        local ry = ly + (i - 1) * rowH
        local rh = rowH - S(6)
        local sel
        if st.mode == "active" then sel = it.id == st.selActive else sel = it.file == st.selLog end
        dxDrawRectangle(x + pad, ry, iw, rh, sel and C.accent or (AP.hovered(x + pad, ry, iw, rh) and C.rowHot or C.row))

        if st.mode == "active" then
            AP.text(L("v_admin.reports.id", { id = it.id, player_name = strip(it.playerName), player_id = it.playerId or 0 }),
                x + pad + S(12), ry + S(4), iw - S(24), rh / 2, C.text, 0.95, "default-bold")
            local status, col
            if not it.online then status, col = L("v_admin.reports.player_offline"), C.bad
            elseif it.status == "claimed" then status, col = L("v_admin.reports.claimed_by", { claimed_by_name = strip(it.claimedByName) }), C.good
            else status, col = L("v_admin.reports.waiting_for_admin"), C.warn end
            AP.text(status, x + pad + S(12), ry + rh / 2, iw - S(24), rh / 2 - S(4), sel and C.text or col, 0.85)
            AP.area(x + pad, ry, iw, rh, function()
                if st.selActive ~= it.id then st.chatScroll = 0; st.confirmClose = nil end
                st.selActive = it.id
            end)
        else
            AP.text(tostring(it.date or "?") .. "   " .. strip(it.player),
                x + pad + S(12), ry + S(4), iw - S(24), rh / 2, C.text, 0.95, "default-bold")
            AP.text(L("v_admin.reports.admin", { admin = ((it.admin and it.admin ~= "") and strip(it.admin) or L("v_admin.reports.never_claimed")) }),
                x + pad + S(12), ry + rh / 2, iw - S(24), rh / 2 - S(4), sel and C.text or C.dim, 0.85)
            AP.area(x + pad, ry, iw, rh, function()
                if st.selLog == it.file then return end
                st.selLog, st.logData, st.chatScroll = it.file, nil, 0
                triggerServerEvent(E.reportLogOpen, resourceRoot, it.file)
            end)
        end
    end
end

--------------------------------------------------------------------------------
-- right side
--------------------------------------------------------------------------------

local function sendMessage(r)
    local text = AP.fieldText("rp_msg"):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return end
    triggerServerEvent(E.reportMsg, resourceRoot, r.id, text)
    AP.setField("rp_msg", "")
    st.chatScroll = 0
end

local function drawActive(x, y, w, h)
    local r = selectedReport()
    if not r then
        AP.text(st.selActive and L("v_admin.reports.this_report_was_closed") or L("v_admin.reports.select_report_on_left"), x, y, w, S(48), C.dim, 1.1)
        return
    end

    -- header
    AP.text(L("v_admin.reports.report_id", { id = r.id, player_name = strip(r.playerName), player_id = r.playerId or 0 }),
        x, y, w, S(40), C.head, 1.2, "default-bold")
    local status, col
    if not r.online then status, col = L("v_admin.reports.player_offline"), C.bad
    elseif r.status == "claimed" then status, col = L("v_admin.reports.claimed_by_2", { claimed_by_name = strip(r.claimedByName) }), C.good
    else status, col = L("v_admin.reports.waiting_for_admin_to_respond"), C.warn end
    AP.text(status, x, y + S(40), w, S(32), col, 0.95)

    -- buttons
    local bw, bh = S(170), S(46)
    local bx = x + w - bw
    local now = getTickCount()
    local armed = st.confirmClose and st.confirmClose.id == r.id and now - st.confirmClose.tick < 4000
    AP.button(bx, y, bw, bh, armed and L("v_admin.reports.confirm_close") or L("v_admin.reports.close_report"), function()
        if armed then
            triggerServerEvent(E.reportClose, resourceRoot, r.id)
            st.confirmClose = nil
        else
            st.confirmClose = { id = r.id, tick = getTickCount() }
        end
    end, "danger")
    bx = bx - bw - S(8)
    AP.button(bx, y, bw, bh, L("v_admin.reports.teleport"), function()
        triggerServerEvent(E.reportTP, resourceRoot, r.id)
    end, r.online and nil or "off")
    bx = bx - bw - S(8)
    local mine = r.status == "claimed" and strip(r.claimedByName) == strip(getPlayerName(localPlayer))
    AP.button(bx, y, bw, bh, mine and L("v_admin.reports.claimed") or L("v_admin.reports.claim"), function()
        triggerServerEvent(E.reportClaim, resourceRoot, r.id)
    end, mine and "off" or "active")

    -- chat + input
    local inputH = S(48)
    local chatY = y + S(84)
    local chatH = h - (chatY - y) - inputH - S(12)
    drawChat("a" .. r.id, liveMessages(r), x, chatY, w, chatH)

    local sendW = S(140)
    AP.field("rp_msg", x, y + h - inputH, w - sendW - S(8), inputH, {
        placeholder = L("v_admin.reports.write_to_player_enter_to_send"),
        max = ADMIN.report.maxLength, onEnter = function() sendMessage(r) end })
    AP.button(x + w - sendW, y + h - inputH, sendW, inputH, L("common.send"), function() sendMessage(r) end, "active")
end

local function drawLog(x, y, w, h)
    if not st.selLog then
        AP.text(L("v_admin.reports.select_log_on_left"), x, y, w, S(48), C.dim, 1.1)
        return
    end
    if not st.logData then
        AP.text(L("common.loading"), x, y, w, S(48), C.dim, 1.1)
        return
    end
    local info = st.logData.data.info or {}
    AP.text(L("v_admin.reports.log", { player = strip(info.player or "?") }), x, y, w, S(40), C.head, 1.2, "default-bold")
    local claimed = info.adminClaimed and info.adminClaimed ~= ""
    AP.text((claimed and (L("v_admin.reports.claimed_by_3", { admin_claimed = strip(info.adminClaimed) })) or L("v_admin.reports.never_claimed_2")) .. "     " .. st.logData.file,
        x, y + S(40), w, S(32), claimed and C.good or C.warn, 0.95)
    drawChat("l" .. st.logData.file, logMessages(st.logData.data), x, y + S(84), w, h - S(84))
end

--------------------------------------------------------------------------------
-- tab
--------------------------------------------------------------------------------

AP.addTab({
    id = "reports", perm = "reports", order = 2,
    label = function()
        local n = waitingCount()
        return n > 0 and (L("v_admin.reports.reports", { n = n })) or (L("v_admin.reports.reports_2", { active = #st.active }))
    end,
    onShow = function() setMode(st.mode) end,
    draw = function(x, y, w, h)
        local listW, gap = S(460), S(18)
        drawList(x, y, listW, h)
        local rx, rw = x + listW + gap, w - listW - gap
        if st.mode == "active" then drawActive(rx, y, rw, h) else drawLog(rx, y, rw, h) end
    end,
    onClose = function() st.confirmClose = nil end,
})
