-- The tutorial card (DX): a panel on the left side of the screen with the current instruction,
-- optional rows (minigame list), buttons and a "Skip tutorial" link, plus a pulsing highlight
-- around a screen rectangle (e.g. a section of the examination panel).
--
-- Card.show(spec)   spec = { title, step, text, note, noteColor, rows, buttons, modal }
--   rows    = { { title, desc, status, statusColor, button = { label, fn, disabled } } }
--   buttons = { { label, fn, primary, disabled } }
--   modal   = true: the card shows the cursor itself
-- Card.hide(), Card.setHidden(bool) (e.g. while a minigame runs), Card.highlight(rect | nil)
-- Buttons work whenever the cursor is visible; TUTORIAL.CURSOR_KEY toggles it.

Card = { spec = nil, hidden = false, rect = nil }

local sw, sh = guiGetScreenSize()
local scale = math.max(0.7, sh / 1080)
local function s(v) return v * scale end

local W = s(430)
local X = s(28)
local PAD = s(20)

local C = {
    bg = tocolor(16, 18, 24, 235),
    edge = tocolor(48, 52, 64, 255),
    accent = tocolor(215, 55, 65, 255),
    text = tocolor(235, 238, 245, 255),
    muted = tocolor(150, 156, 170, 255),
    faint = tocolor(105, 110, 124, 255),
    row = tocolor(28, 31, 40, 255),
    button = tocolor(40, 44, 56, 255),
    buttonHover = tocolor(58, 64, 80, 255),
    primary = tocolor(46, 160, 67, 255),
    primaryHover = tocolor(60, 185, 85, 255),
    off = tocolor(30, 32, 40, 255),
    good = tocolor(80, 210, 120, 255),
    bad = tocolor(235, 70, 70, 255),
}
Card.colors = C

local fonts
local function ensureFonts()
    if fonts then return end
    local function make(file, size, fallback)
        return dxCreateFont(file, s(size), false, "antialiased") or fallback
    end
    fonts = {
        small = make("tutorial/client/fonts/RobotoB.ttf", 9, "default-bold"),
        body = make("tutorial/client/fonts/Roboto.ttf", 11, "default"),
        bold = make("tutorial/client/fonts/RobotoB.ttf", 11, "default-bold"),
        title = make("tutorial/client/fonts/RobotoB.ttf", 16, "default-bold"),
    }
end

local hits = {}
local ownCursor = false
local skipArmed = 0

local function setOwnCursor(state)
    if ownCursor == state then return end
    ownCursor = state
    showCursor(state, false)
end

function Card.toggleCursor()
    if not Card.spec or Card.hidden then return end
    if Card.spec.modal then return end
    setOwnCursor(not ownCursor)
end

local function cursor()
    if not isCursorShowing() then return -1, -1 end
    local rx, ry = getCursorPosition()
    return rx * sw, ry * sh
end

local function inside(x, y, w, h, cx, cy)
    return cx >= x and cx <= x + w and cy >= y and cy <= y + h
end

-- Wrapped text height
local function textHeight(text, width, font)
    local lines, line = 0, ""
    for paragraph in (text .. "\n"):gmatch("(.-)\n") do
        line = ""
        if paragraph == "" then lines = lines + 1 end
        for word in paragraph:gmatch("%S+") do
            local try = line == "" and word or (line .. " " .. word)
            if dxGetTextWidth(try, 1, font) > width and line ~= "" then
                lines = lines + 1
                line = word
            else
                line = try
            end
        end
        if line ~= "" then lines = lines + 1 end
    end
    return lines * dxGetFontHeight(1, font)
end

local function button(x, y, w, h, b, cx, cy)
    local hov = not b.disabled and inside(x, y, w, h, cx, cy)
    local bg = b.disabled and C.off or (b.primary and (hov and C.primaryHover or C.primary) or (hov and C.buttonHover or C.button))
    dxDrawRectangle(x, y, w, h, bg, true)
    dxDrawText(b.label, x, y, x + w, y + h, b.disabled and C.faint or C.text, 1, fonts.bold, "center", "center",
        false, false, true)
    if not b.disabled and b.fn then hits[#hits + 1] = { x, y, w, h, b.fn } end
end

local function drawHighlight()
    local r = Card.rect
    if not r then return end
    local pulse = 0.5 + 0.5 * math.sin(getTickCount() / 180)
    local color = tocolor(255, 200, 60, 140 + 115 * pulse)
    local t = s(3)
    local x, y, w, h = r[1] - s(6), r[2] - s(6), r[3] + s(12), r[4] + s(12)
    dxDrawRectangle(x, y, w, t, color, true)
    dxDrawRectangle(x, y + h - t, w, t, color, true)
    dxDrawRectangle(x, y, t, h, color, true)
    dxDrawRectangle(x + w - t, y, t, h, color, true)
    -- connector from the card to the rectangle
    if Card.bounds then
        local bx, by, bw = Card.bounds[1], Card.bounds[2], Card.bounds[3]
        dxDrawLine(bx + bw, by + s(30), x, y + h / 2, color, s(2), true)
    end
end

local function render()
    local spec = Card.spec
    if not spec or Card.hidden then return end
    ensureFonts()
    hits = {}
    local cx, cy = cursor()
    local cursorOn = isCursorShowing()
    local iw = W - PAD * 2

    -- measure
    local h = PAD
    if spec.step then h = h + s(18) end
    h = h + s(30)
    local textH = spec.text and textHeight(spec.text, iw, fonts.body) or 0
    h = h + textH + s(10)
    local noteH = spec.note and (textHeight(spec.note, iw, fonts.bold) + s(10)) or 0
    h = h + noteH
    local rowHeights = {}
    for i, row in ipairs(spec.rows or {}) do
        local rh = s(34) + (row.desc and textHeight(row.desc, iw - s(130), fonts.body) or 0) + s(12)
        rowHeights[i] = rh
        h = h + rh + s(8)
    end
    local buttons = spec.buttons or {}
    if #buttons > 0 then h = h + s(48) end
    h = h + s(34) + PAD

    local y = math.max(s(20), (sh - h) / 2 - s(60))
    local x = X
    Card.bounds = { x, y, W, h }

    dxDrawRectangle(x - 1, y - 1, W + 2, h + 2, C.edge, true)
    dxDrawRectangle(x, y, W, h, C.bg, true)
    dxDrawRectangle(x, y, W, s(4), C.accent, true)

    local cy0 = y + PAD
    if spec.step then
        dxDrawText(spec.step:upper(), x + PAD, cy0, x + W - PAD, cy0 + s(16), C.accent, 1, fonts.small,
            "left", "top", false, false, true)
        cy0 = cy0 + s(18)
    end
    dxDrawText(spec.title or "EMS tutorial", x + PAD, cy0, x + W - PAD, cy0 + s(28), C.text, 1, fonts.title,
        "left", "top", true, false, true)
    cy0 = cy0 + s(30)
    if spec.text then
        dxDrawText(spec.text, x + PAD, cy0, x + PAD + iw, cy0 + textH, C.text, 1, fonts.body,
            "left", "top", false, true, true)
        cy0 = cy0 + textH + s(10)
    end
    if spec.note then
        dxDrawText(spec.note, x + PAD, cy0, x + PAD + iw, cy0 + noteH, spec.noteColor or C.muted, 1, fonts.bold,
            "left", "top", false, true, true)
        cy0 = cy0 + noteH
    end

    for i, row in ipairs(spec.rows or {}) do
        local rh = rowHeights[i]
        dxDrawRectangle(x + PAD, cy0, iw, rh, C.row, true)
        dxDrawText(row.title, x + PAD + s(12), cy0 + s(8), x + PAD + iw - s(120), cy0 + s(30), C.text, 1, fonts.bold,
            "left", "top", true, false, true)
        if row.status then
            dxDrawText(row.status, x + PAD + s(12), cy0 + s(8), x + PAD + iw - s(120), cy0 + s(30),
                row.statusColor or C.muted, 1, fonts.small, "right", "top", true, false, true)
        end
        if row.desc then
            dxDrawText(row.desc, x + PAD + s(12), cy0 + s(32), x + PAD + iw - s(118), cy0 + rh - s(6), C.muted, 1,
                fonts.body, "left", "top", false, true, true)
        end
        if row.button then
            local bw, bh = s(96), s(34)
            button(x + PAD + iw - bw - s(10), cy0 + (rh - bh) / 2, bw, bh, row.button, cx, cy)
        end
        cy0 = cy0 + rh + s(8)
    end

    if #buttons > 0 then
        cy0 = cy0 + s(6)
        local gap = s(10)
        local bw = (iw - gap * (#buttons - 1)) / #buttons
        for i, b in ipairs(buttons) do
            button(x + PAD + (i - 1) * (bw + gap), cy0, bw, s(40), b, cx, cy)
        end
        cy0 = cy0 + s(48)
    end

    -- footer: skip link / cursor hint
    local fy = y + h - PAD - s(24)
    dxDrawRectangle(x + PAD, fy - s(6), iw, 1, C.edge, true)
    if spec.noSkip then
        -- nothing
    elseif cursorOn then
        local armed = getTickCount() - skipArmed < 3000
        local label = armed and "Click again to skip the tutorial" or "Skip tutorial"
        local lw = dxGetTextWidth(label, 1, fonts.small)
        local hov = inside(x + PAD, fy, lw, s(24), cx, cy)
        dxDrawText(label, x + PAD, fy, x + W, fy + s(24), (hov or armed) and C.bad or C.faint, 1, fonts.small,
            "left", "center", false, false, true)
        hits[#hits + 1] = { x + PAD, fy, lw, s(24), function()
            if getTickCount() - skipArmed < 3000 then
                skipArmed = 0
                if Card.onSkip then Card.onSkip() end
            else
                skipArmed = getTickCount()
            end
        end }
    else
        dxDrawText(("Press %s for the cursor  ·  /%s skip"):format(TUTORIAL.CURSOR_KEY:upper(), TUTORIAL.COMMAND),
            x + PAD, fy, x + W - PAD, fy + s(24), C.faint, 1, fonts.small, "left", "center", false, false, true)
    end

    drawHighlight()
end

local function onClick(btn, state)
    if btn ~= "left" or state ~= "down" or not Card.spec or Card.hidden then return end
    local cx, cy = cursor()
    for i = #hits, 1, -1 do
        local hit = hits[i]
        if inside(hit[1], hit[2], hit[3], hit[4], cx, cy) then
            playSoundFrontEnd(41)
            hit[5]()
            return
        end
    end
end

local attached = false
local function attach(state)
    if attached == state then return end
    attached = state
    local fn = state and addEventHandler or removeEventHandler
    fn("onClientRender", root, render)
    fn("onClientClick", root, onClick)
end

-- Called again and again with fresh specs: the cursor is only touched when the card appears or
-- its modal flag changes (a cursor toggled with the cursor key stays)
function Card.show(spec)
    local old = Card.spec
    Card.spec = spec
    attach(true)
    if not old or (old.modal == true) ~= (spec.modal == true) then
        setOwnCursor(spec.modal == true and not Card.hidden)
    end
end

function Card.hide()
    Card.spec, Card.rect = nil, nil
    attach(false)
    setOwnCursor(false)
end

function Card.setHidden(hidden)
    hidden = hidden and true or false
    if Card.hidden == hidden then return end
    Card.hidden = hidden
    setOwnCursor(not hidden and Card.spec ~= nil and Card.spec.modal == true)
end

function Card.highlight(rect)
    Card.rect = rect
end

addEventHandler("onClientResourceStop", resourceRoot, function() setOwnCursor(false) end)
