if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
--[[
    ui_phone / client/apps/messages.lua
    Messages app: the v_socialpanel conversations (private + crew), read only.
    Writing stays in the social panel and the account menu.

      list      conversations (newest first, unread count on the right)
      thread    one conversation as chat bubbles, newest at the bottom;
                arrows scroll, Backspace goes back

    Everything goes through the v_socialpanel client API (c_api.lua):
    spRequestSnapshot -> v_socialpanel:onClientSnapshot (conversations),
    spOpenThread -> v_socialpanel:onClientThread (also marks it read).
]]

local u = PhoneUI.u
local WHITE = PhoneShader.WHITE

local conversations = {}
local thread = nil     -- { kind, target, title, messages = {...} | nil (loading), layout }
local scroll = 0       -- thread: px scrolled up from the newest message

local function spCall(fn, ...)
    local res = getResourceFromName("v_socialpanel")
    if not res or getResourceState(res) ~= "running" then return false end
    local ok = pcall(function(...) exports.v_socialpanel[fn](exports.v_socialpanel, ...) end, ...)
    return ok
end

local function convoTitle(c)
    if c.kind == "crew" then return "[" .. tostring(c.crewTag or "") .. "] " .. tostring(c.with) end
    return tostring(c.with)
end

-- "14:05" today, "10.21. 14:05" before (getRealTime is the client's local time)
local function stamp(ts)
    ts = tonumber(ts) or 0
    if ts <= 0 then return "" end
    local t, now = getRealTime(ts), getRealTime()
    if t.year == now.year and t.yearday == now.yearday then
        return ("%02d:%02d"):format(t.hour, t.minute)
    end
    return ("%02d.%02d. %02d:%02d"):format(t.month + 1, t.monthday, t.hour, t.minute)
end

addEvent("v_socialpanel:onClientSnapshot")
addEventHandler("v_socialpanel:onClientSnapshot", localPlayer, function(snap)
    conversations = type(snap) == "table" and type(snap.conversations) == "table" and snap.conversations or {}
end)

addEvent("v_socialpanel:onClientThread")
addEventHandler("v_socialpanel:onClientThread", localPlayer, function(kind, target, messages)
    if not thread or thread.kind ~= kind or tostring(target):lower() ~= thread.target:lower() then return end
    thread.messages = type(messages) == "table" and messages or {}
    thread.layout = nil
end)

-- a new message: refresh the list (the open thread gets its own onClientThread)
addEvent("v_socialpanel:onClientNotify")
addEventHandler("v_socialpanel:onClientNotify", localPlayer, function()
    if Phone and Phone.isOpen() then spCall("spRequestSnapshot") end
end)

local function unreadTotal()
    local n = 0
    for _, c in ipairs(conversations) do n = n + (tonumber(c.unread) or 0) end
    return n
end

--------------------------------------------------------------------------------
-- Thread view
--------------------------------------------------------------------------------

local NAME_S, TEXT_S, TIME_S = 0.85, 0.95, 0.75

-- bubbles laid out once per message list (top to bottom, y from 0)
local function layoutThread(w)
    local maxW = w * 0.8
    local pad = u(8)
    local nameH = PhoneUI.lineH(u(NAME_S), "default-bold")
    local timeH = PhoneUI.lineH(u(TIME_S), "default")
    local out, y = {}, 0
    for _, m in ipairs(thread.messages or {}) do
        local lines = PhoneUI.wrap(m.text, maxW - pad * 2, u(TEXT_S), "default")
        local tw = 0
        for _, line in ipairs(lines) do tw = math.max(tw, L.width(line, u(TEXT_S), "default", true)) end
        local name = (thread.kind == "crew" and not m.mine) and tostring(m.from) or nil
        local time = stamp(m.time)
        tw = math.max(tw, L.width(time, u(TIME_S), "default"))
        if name then tw = math.max(tw, math.min(maxW - pad * 2, L.width(name, u(NAME_S), "default-bold"))) end
        local h = pad * 2 + (name and nameH or 0) + #lines * PhoneUI.lineH(u(TEXT_S), "default") + timeH
        out[#out + 1] = { m = m, lines = lines, name = name, time = time, y = y, w = tw + pad * 2, h = h }
        y = y + h + u(8)
    end
    return { bubbles = out, total = math.max(0, y - u(8)) }
end

local function drawThread(scr)
    local C = PhoneUI.C
    local viewTop, viewBottom = scr.y + u(10), scr.y + scr.h - u(26)
    local viewH = viewBottom - viewTop
    local x, w = scr.x + u(12), scr.w - u(24)

    if not thread.messages then
        PhoneUI.drawEmpty(L("ui_phone.messages.loading"))
        return
    end
    if #thread.messages == 0 then
        PhoneUI.drawEmpty(L("ui_phone.messages.no_messages"))
        return
    end

    thread.layout = thread.layout or layoutThread(w)
    local lay = thread.layout
    scroll = math.max(0, math.min(scroll, math.max(0, lay.total - viewH)))
    -- newest at the bottom: content y 0 sits at bottom - total (+ scroll)
    local base = (lay.total <= viewH) and viewTop or (viewBottom - lay.total + scroll)
    local pad = u(8)
    local textLH = PhoneUI.lineH(u(TEXT_S), "default")
    local nameH = PhoneUI.lineH(u(NAME_S), "default-bold")

    for i, b in ipairs(lay.bubbles) do
        local by = base + b.y
        if by >= viewTop - 1 and by + b.h <= viewBottom + 1 then
            local bx = b.m.mine and (x + w - b.w) or x
            if b.m.mine then
                PhoneUI.rounded("msg_b_" .. i, bx, by, b.w, b.h, u(10), WHITE, C.accent[1], C.accent[2], C.accent[3], 70)
            else
                PhoneUI.rounded("msg_b_" .. i, bx, by, b.w, b.h, u(10), WHITE, C.tile[1], C.tile[2], C.tile[3], 235)
            end
            local ty = by + pad
            if b.name then
                PhoneUI.text(L.fit(b.name, b.w - pad * 2, u(NAME_S), "default-bold"), bx + pad, ty, b.w - pad * 2, nameH,
                    tocolor(C.accent[1], C.accent[2], C.accent[3], 255), u(NAME_S), "default-bold", "left", "top")
                ty = ty + nameH
            end
            PhoneUI.lines(b.lines, bx + pad, ty, b.w - pad * 2, C.white, u(TEXT_S), "default")
            ty = ty + #b.lines * textLH
            PhoneUI.text(b.time, bx + pad, ty, b.w - pad * 2, PhoneUI.lineH(u(TIME_S), "default"),
                C.faint, u(TIME_S), "default", "right", "top")
        end
    end
    -- the scroll bar measures from the top: scrolled to the bottom = full
    PhoneUI.scrollBar(viewTop, viewH, math.max(0, lay.total - viewH) - scroll, lay.total)
end

--------------------------------------------------------------------------------
-- App
--------------------------------------------------------------------------------

PhoneApp.defer(function()
PhoneApp.register({
    id    = "messages",
    name  = L("ui_phone.messages.title"),
    order = 20,

    badge = function() return unreadTotal() end,

    open  = function() thread = nil; spCall("spRequestSnapshot") end,
    close = function() thread = nil end,

    headerTitle = function()
        if thread then return thread.title end
        return L("ui_phone.messages.title")
    end,

    hint = function() return L("ui_phone.messages.hint_list") end,
    empty = L("ui_phone.messages.empty"),

    items = function()
        if thread then return nil end
        local rows = {}
        for _, c in ipairs(conversations) do
            local unread = tonumber(c.unread) or 0
            rows[#rows + 1] = {
                title = convoTitle(c),
                titleColor = (c.kind == "dm" and c.online) and PhoneUI.C.good or nil,
                subtitle = tostring(c.last or ""), subtitleLines = 2,
                right = unread > 0 and tostring(unread) or stamp(c.time),
                rightColor = unread > 0 and tocolor(PhoneUI.C.badge[1], PhoneUI.C.badge[2], PhoneUI.C.badge[3], 255) or PhoneUI.C.faint,
                _c = c,
            }
        end
        return rows
    end,

    onSelect = function(_, row)
        local c = row._c
        thread = { kind = c.kind, target = tostring(c.with), title = convoTitle(c), messages = nil }
        scroll = 0
        if not spCall("spOpenThread", c.kind, c.with) then thread.messages = {} end
        c.unread = 0
    end,

    render = function(_, scr)
        if not thread then return end
        drawThread(scr)
        PhoneUI.text(L("ui_phone.messages.hint_thread"), scr.x, scr.y + scr.h - u(20), scr.w, u(18),
            PhoneUI.C.faint, u(0.85), "default", "center", "top")
    end,

    key = function(_, key)
        if not thread then return false end
        if key == "backspace" then
            thread = nil
            spCall("spRequestSnapshot")
            PhoneSound.select()
        elseif key == "arrow_u" then
            scroll = scroll + u(48)
        elseif key == "arrow_d" then
            scroll = math.max(0, scroll - u(48))
        end
        return true
    end,
})
end)

-- v_socialpanel pushes a snapshot on login; after a restart of this resource ask for one
addEventHandler("onClientResourceStart", resourceRoot, function()
    if getElementData(localPlayer, "loaded") then spCall("spRequestSnapshot") end
end)
