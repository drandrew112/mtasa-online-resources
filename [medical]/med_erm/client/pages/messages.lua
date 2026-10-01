-- Messages: two channels, like the dispatcher console (without broadcast sending).
--   Dispatch -> the unit's thread with the dispatchers (broadcasts show here too)
--   Case     -> case chat: every unit on the active task + the dispatchers

local s = Gfx.s

Pages.messages = { channel = "dispatch" }

local TAGS = {
    broadcast = { "BROADCAST", { 163, 113, 247 } },
    task      = { "CASE",      { 247, 107, 21 } },
    unit      = { "DIRECT",    { 62, 155, 255 } },
}

local inputToken

local function openInput()
    local res = getResourceFromName("ui_core")
    if not res or getResourceState(res) ~= "running" then return end
    local t = State.task
    local prompt = Pages.messages.channel == "case" and t and string.format("Message to case #%d chat", t.id) or "Message to dispatch"
    inputToken = exports.ui_core:openTextInput(prompt, 200, "")
end

addEvent("ui_core:textInputResult")
addEventHandler("ui_core:textInputResult", root, function(token, text)
    if token ~= inputToken then return end
    inputToken = nil
    if text and text:gsub("%s", "") ~= "" then
        triggerServerEvent("erm:sendMessage", resourceRoot, text, Pages.messages.channel)
        Gfx.scroll.messages = 0
    end
end)

local function inChannel(m, channel)
    if channel == "case" then
        return m.channel == "task" and State.task and m.target == State.task.id
    end
    return m.channel ~= "task"
end

-- Flattens the channel's messages into drawable rows (header / text lines / gap).
local function buildRows(width, channel)
    local rows = {}
    local font = Gfx.font(10)
    local myUnit = State.unit.id
    for _, m in ipairs(State.messages) do
        if inChannel(m, channel) then
            local tag = TAGS[m.channel] or TAGS.unit
            local tagText, color = m.channel == "task" and "DISPATCH" or tag[1], tag[2]
            if not m.fromDispatch then
                if m.fromUnit == myUnit then
                    tagText, color = "SENT", { 46, 160, 67 }
                else
                    tagText, color = "UNIT", { 62, 155, 255 }
                end
            end
            rows[#rows + 1] = { kind = "head", msg = m, tag = tagText, color = color }
            for _, line in ipairs(Gfx.wrap(m.text, width, font)) do
                rows[#rows + 1] = { kind = "line", text = line }
            end
            rows[#rows + 1] = { kind = "gap" }
        end
    end
    return rows
end

local function drawTabs(x, y, h)
    local t = State.task
    local tabs = {
        { "dispatch", "Dispatch", true },
        { "case", t and string.format("Case #%d", t.id) or "Case chat", t and true or false },
    }
    local tx = x
    for _, tab in ipairs(tabs) do
        local key, label, enabled = tab[1], tab[2], tab[3]
        local active = Pages.messages.channel == key
        local badge = not active and State.unreadBy[key] or 0
        local font = Gfx.font(9, true)
        local tw = dxGetTextWidth(label, 1, font) + s(28) + (badge > 0 and s(26) or 0)
        local hov = enabled and not active and Gfx.hover(tx, y, tw, h)
        Gfx.round(tx, y, tw, h, s(6), active and Theme.accent or (hov and Theme.line or Theme.panel))
        Gfx.text(label, tx + s(14), y, tw, h, enabled and (active and tocolor(255, 255, 255) or Theme.dim) or Theme.faint, font)
        if badge > 0 then
            Gfx.round(tx + tw - s(34), y + (h - s(16)) / 2, s(22), s(16), s(8), Theme.accent)
            Gfx.text(tostring(badge), tx + tw - s(34), y + (h - s(16)) / 2, s(22), s(16), tocolor(255, 255, 255), Gfx.font(8, true), "center")
        end
        if enabled and not active then
            Gfx.hit(tx, y, tw, h, function()
                Pages.messages.channel = key
                Gfx.scroll.messages = 0
            end)
        end
        tx = tx + tw + s(8)
    end
end

function Pages.messages.draw(x, y, w, h)
    -- the case chat disappears with the case
    if Pages.messages.channel == "case" and not State.task then Pages.messages.channel = "dispatch" end
    local channel = Pages.messages.channel
    State.markRead(channel)

    local pad = s(18)
    local ix, iw = x + pad, w - pad * 2
    Gfx.text("Messages", ix, y + s(14), s(120), s(30), Theme.text, Gfx.font(15, true))
    drawTabs(ix + s(120), y + s(14), s(30))
    Gfx.text(channel == "case" and "Case chat  ·  every unit on the case + dispatch"
        or "Dispatch channel  ·  " .. State.unit.callsign, ix, y + s(42), iw, s(18), Theme.dim, Gfx.font(9))

    local ly = y + s(66)
    local inputH = s(42)
    local lh = s(20)
    local listH = y + h - ly - inputH - s(26)
    Gfx.round(ix, ly, iw, listH, s(8), Theme.panel)

    local rows = buildRows(iw - s(28), channel)
    local visible = math.floor((listH - s(12)) / lh)
    -- offset counts rows from the bottom (0 = newest visible)
    local offset = Gfx.getScroll("messages", #rows - visible)
    Gfx.scrollArea("messages", ix, ly, iw, listH)

    if #rows == 0 then
        Gfx.text("No messages yet.", ix, ly, iw, listH, Theme.faint, Gfx.font(10), "center")
    end

    local last = #rows - offset
    local first = math.max(1, last - visible + 1)
    for i = first, last do
        local r = rows[i]
        local ry = ly + s(6) + (i - first) * lh
        if r.kind == "head" then
            local tw = dxGetTextWidth(r.tag, 1, Gfx.font(7, true)) + s(12)
            Gfx.round(ix + s(12), ry + s(3), tw, s(15), s(3), Gfx.rgb(r.color))
            Gfx.text(r.tag, ix + s(12), ry + s(3), tw, s(15), tocolor(255, 255, 255), Gfx.font(7, true), "center")
            local from = r.msg.from:gsub("#%x%x%x%x%x%x", "")
            Gfx.text(Gfx.fit(from, iw - tw - s(90), Gfx.font(9, true)), ix + s(20) + tw, ry, iw - tw - s(90), lh, Theme.text, Gfx.font(9, true))
            Gfx.text(r.msg.time, ix, ry, iw - s(14), lh, Theme.faint, Gfx.font(8, true), "right")
        elseif r.kind == "line" then
            Gfx.text(r.text, ix + s(14), ry, iw - s(28), lh, Theme.dim, Gfx.font(10))
        end
    end

    -- input bar
    local by = y + h - inputH - s(14)
    local hov = Gfx.hover(ix, by, iw - s(96), inputH)
    Gfx.round(ix, by, iw - s(96), inputH, s(8), hov and Theme.panel2 or Theme.panel)
    Gfx.text(channel == "case" and "Write to the case chat…" or "Write a message to dispatch…", ix + s(14), by, iw - s(120), inputH, Theme.faint, Gfx.font(10))
    Gfx.hit(ix, by, iw - s(96), inputH, openInput)
    Gfx.button(ix + iw - s(88), by, s(88), inputH, "Send", { color = { 224, 60, 49 } }, openInput)
end
