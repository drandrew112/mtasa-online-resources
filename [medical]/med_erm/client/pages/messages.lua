-- Messages: dispatcher thread of the unit (direct, case and broadcast messages).

local s = Gfx.s

Pages.messages = {}

local TAGS = {
    broadcast = { "BROADCAST", { 163, 113, 247 } },
    task      = { "CASE",      { 247, 107, 21 } },
    unit      = { "DIRECT",    { 62, 155, 255 } },
}

local inputToken

local function openInput()
    local res = getResourceFromName("ui_core")
    if not res or getResourceState(res) ~= "running" then return end
    inputToken = exports.ui_core:openTextInput("Message to dispatch", 200, "")
end

addEvent("ui_core:textInputResult")
addEventHandler("ui_core:textInputResult", root, function(token, text)
    if token ~= inputToken then return end
    inputToken = nil
    if text and text:gsub("%s", "") ~= "" then
        triggerServerEvent("erm:sendMessage", resourceRoot, text)
        Gfx.scroll.messages = 0
    end
end)

-- Flattens the messages into drawable rows (header / text lines / gap).
local function buildRows(width)
    local rows = {}
    local font = Gfx.font(10)
    for _, m in ipairs(State.messages) do
        local tag = TAGS[m.channel] or TAGS.unit
        local tagText = m.channel == "task" and (m.label or "CASE"):upper() or tag[1]
        if not m.fromDispatch then tagText = "SENT" end
        rows[#rows + 1] = { kind = "head", msg = m, tag = tagText, color = m.fromDispatch and tag[2] or { 46, 160, 67 } }
        for _, line in ipairs(Gfx.wrap(m.text, width, font)) do
            rows[#rows + 1] = { kind = "line", text = line }
        end
        rows[#rows + 1] = { kind = "gap" }
    end
    return rows
end

function Pages.messages.draw(x, y, w, h)
    State.unread = 0

    local pad = s(18)
    local ix, iw = x + pad, w - pad - s(6)
    Gfx.text("Messages", ix, y + s(14), iw, s(26), Theme.text, Gfx.font(15, true))
    Gfx.text("Dispatch channel  ·  " .. State.unit.callsign, ix, y + s(38), iw, s(18), Theme.dim, Gfx.font(9))

    local ly = y + s(66)
    local inputH = s(42)
    local lh = s(20)
    local listH = y + h - ly - inputH - s(26)
    Gfx.round(ix, ly, iw, listH, s(8), Theme.panel)

    local rows = buildRows(iw - s(28))
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
    Gfx.text("Write a message to dispatch…", ix + s(14), by, iw - s(120), inputH, Theme.faint, Gfx.font(10))
    Gfx.hit(ix, by, iw - s(96), inputH, openInput)
    Gfx.button(ix + iw - s(88), by, s(88), inputH, "Send", { color = { 224, 60, 49 } }, openInput)
end
