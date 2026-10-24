if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
--[[
    ui_phone / client/apps/mail.lua
    Email app: the in-game mails of server/apps/mail.lua (`phone_mails`).

      list      newest first; unread ones show "NEW"
      reader    subject, sender, date and the word-wrapped text; arrows scroll,
                Enter twice deletes, Backspace goes back
]]

local u = PhoneUI.u

local mails = {}        -- { { id, time, sender, subject, body, read }, ... } (server/apps/mail.lua)
local reading = nil     -- the open mail
local layout = nil      -- reader lines, built once per mail
local scroll = 0
local confirmDelete = false

phoneOnServer("mail:list", function(list)
    mails = type(list) == "table" and list or {}
    if reading then
        local still = false
        for _, m in ipairs(mails) do
            if m.id == reading.id then still = true end
        end
        if not still then reading, layout = nil, nil end
    end
end)

local function stamp(ts)
    ts = tonumber(ts) or 0
    if ts <= 0 then return "" end
    local t, now = getRealTime(ts), getRealTime()
    if t.year == now.year and t.yearday == now.yearday then
        return ("%02d:%02d"):format(t.hour, t.minute)
    end
    return ("%04d.%02d.%02d. %02d:%02d"):format(t.year + 1900, t.month + 1, t.monthday, t.hour, t.minute)
end

local function unreadCount()
    local n = 0
    for _, m in ipairs(mails) do
        if not m.read then n = n + 1 end
    end
    return n
end

--------------------------------------------------------------------------------
-- Reader
--------------------------------------------------------------------------------

-- flat list of lines { text, scale, font, color, h } + the total height
local function buildLayout(m, w)
    local C = PhoneUI.C
    local out, total = {}, 0
    local function add(text, scale, font, color, gapAfter)
        for _, line in ipairs(PhoneUI.wrap(text, w, scale, font)) do
            local h = PhoneUI.lineH(scale, font)
            out[#out + 1] = { text = line, scale = scale, font = font, color = color, y = total, h = h }
            total = total + h
        end
        total = total + (gapAfter or 0)
    end
    add(m.subject, u(1.15), "default-bold", C.white, u(6))
    add(L("ui_phone.mail.from", { sender = m.sender }), u(0.9), "default", C.dim, 0)
    add(stamp(m.time), u(0.85), "default", C.faint, u(10))
    out[#out + 1] = { rule = true, y = total, h = 1 }
    total = total + u(10)
    add(m.body, u(1.0), "default", C.white, 0)
    return { lines = out, total = total }
end

local function drawReader(scr)
    local x, w = scr.x + u(16), scr.w - u(32)
    local viewTop, viewBottom = scr.y + u(12), scr.y + scr.h - u(26)
    local viewH = viewBottom - viewTop
    layout = layout or buildLayout(reading, w)
    scroll = math.max(0, math.min(scroll, math.max(0, layout.total - viewH)))

    for _, line in ipairs(layout.lines) do
        local y = viewTop + line.y - scroll
        if y >= viewTop - 1 and y + line.h <= viewBottom + 1 then
            if line.rule then
                dxDrawRectangle(x, y, w, 1, PhoneUI.C.line)
            else
                PhoneUI.text(line.text, x, y, w, line.h, line.color, line.scale, line.font, "left", "top")
            end
        end
    end
    PhoneUI.scrollBar(viewTop, viewH, scroll, layout.total)

    local hint = confirmDelete and L("ui_phone.mail.confirm_delete") or L("ui_phone.mail.hint_reader")
    PhoneUI.text(hint, scr.x, scr.y + scr.h - u(20), scr.w, u(18),
        confirmDelete and PhoneUI.C.bad or PhoneUI.C.faint, u(0.85), "default", "center", "top")
end

--------------------------------------------------------------------------------
-- App
--------------------------------------------------------------------------------

local function closeReader()
    reading, layout, scroll, confirmDelete = nil, nil, 0, false
end

PhoneApp.defer(function()
PhoneApp.register({
    id    = "mail",
    name  = L("ui_phone.mail.title"),
    order = 10,

    badge = function() return unreadCount() end,

    open  = function() closeReader(); phonePull() end,
    close = closeReader,

    headerTitle = function() return L("ui_phone.mail.title") end,

    hint = function() return L("ui_phone.mail.hint_list") end,
    empty = L("ui_phone.mail.empty"),

    items = function()
        if reading then return nil end
        local rows = {}
        for _, m in ipairs(mails) do
            rows[#rows + 1] = {
                title = m.subject, titleLines = 2,
                subtitle = m.sender .. "  ·  " .. stamp(m.time), subtitleLines = 1,
                titleColor = m.read and PhoneUI.C.dim or nil,
                right = (not m.read) and L("ui_phone.mail.new") or nil,
                rightColor = tocolor(PhoneUI.C.accent[1], PhoneUI.C.accent[2], PhoneUI.C.accent[3], 255),
                _m = m,
            }
        end
        return rows
    end,

    onSelect = function(_, row)
        closeReader()
        reading = row._m
        if not reading.read then
            reading.read = true
            phoneRPC("mail:read", reading.id)
        end
    end,

    render = function(_, scr)
        if reading then drawReader(scr) end
    end,

    key = function(_, key)
        if not reading then return false end
        if key == "backspace" then
            closeReader()
            PhoneSound.select()
        elseif key == "arrow_u" then
            scroll = math.max(0, scroll - u(48))
            confirmDelete = false
        elseif key == "arrow_d" then
            scroll = scroll + u(48)
            confirmDelete = false
        elseif key == "enter" then
            if not confirmDelete then
                confirmDelete = true
                PhoneSound.click()
            else
                local id = reading.id
                for i, m in ipairs(mails) do
                    if m.id == id then table.remove(mails, i) break end
                end
                phoneRPC("mail:delete", id)
                closeReader()
                Phone.setSelected(1)
                PhoneSound.select()
            end
        end
        return true
    end,
})
end)
