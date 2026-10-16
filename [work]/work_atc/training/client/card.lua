if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- The training card (DX): a panel on the left side of the screen with the current instruction,
-- optional rows (the pay receipt, the module list), buttons and a "Quit training" link, plus a pulsing highlight
-- around a screen rectangle (e.g. a label or a menu item of the ATC scope).
-- Same card as the work_bloodtransport tutorial. The radar scope (avi_controller) covers the whole
-- screen: the card tells it where it is (setScopeBlockedRect), so a click on the card does not
-- also act on the scope.
--
-- Card.show(spec)   spec = { title, step, text, note, noteColor, rows, buttons, modal, side }
--   rows    = { { title, desc, status, statusColor, button = { label, fn, disabled } } }
--   buttons = { { label, fn, primary, disabled } }
--   modal   = true: the card shows the cursor itself
--   side    = "bottom": wide, at the bottom centre (the inventory window covers the middle)
-- Card.hide(), Card.setHidden(bool), Card.highlight(rect | nil)
-- Buttons work whenever the cursor is visible; TRAINING.CURSOR_KEY toggles it.

Card = { spec = nil, hidden = false, rect = nil }

local sw, sh = guiGetScreenSize()
local scale = math.max(0.7, sh / 1080)
local function s(v) return v * scale end

local CARD_W = s(430)
local BOTTOM_W = s(780)
local X = s(28)
local PAD = s(20)

local C = {
    bg = tocolor(16, 18, 24, 235),
    edge = tocolor(48, 52, 64, 255),
    accent = tocolor(200, 40, 60, 255),
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
        small = make("training/client/fonts/RobotoB.ttf", 9, "default-bold"),
        body = make("training/client/fonts/Roboto.ttf", 11, "default"),
        bold = make("training/client/fonts/RobotoB.ttf", 11, "default-bold"),
        title = make("training/client/fonts/RobotoB.ttf", 16, "default-bold"),
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
            if L.width(try, 1, font) > width and line ~= "" then
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
        if by > y + h then
            -- the card is below the rectangle (bottom placement)
            dxDrawLine(bx + bw / 2, by, x + w / 2, y + h, color, s(2), true)
        elseif bx > x then
            dxDrawLine(bx, by + s(30), x + w, y + h / 2, color, s(2), true)
        else
            dxDrawLine(bx + bw, by + s(30), x, y + h / 2, color, s(2), true)
        end
    end
end

local function render()
    local spec = Card.spec
    if not spec or Card.hidden then return end
    ensureFonts()
    hits = {}
    local cx, cy = cursor()
    local cursorOn = isCursorShowing()
    local bottom = spec.side == "bottom"
    local W = bottom and BOTTOM_W or CARD_W
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
    if bottom then
        x, y = (sw - W) / 2, sh - h - s(12)
    end
    Card.bounds = { x, y, W, h }
    Card.syncBlocked()

    dxDrawRectangle(x - 1, y - 1, W + 2, h + 2, C.edge, true)
    dxDrawRectangle(x, y, W, h, C.bg, true)
    dxDrawRectangle(x, y, W, s(4), C.accent, true)

    local cy0 = y + PAD
    if spec.step then
        dxDrawText(L.upper(spec.step), x + PAD, cy0, x + W - PAD, cy0 + s(16), C.accent, 1, fonts.small,
            "left", "top", false, false, true)
        cy0 = cy0 + s(18)
    end
    dxDrawText(spec.title or L("work_atc.trn.card.title"), x + PAD, cy0, x + W - PAD, cy0 + s(28), C.text, 1, fonts.title,
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
        -- the status sits at the right edge (left of the row button, if any); the title stops before it
        local right = x + PAD + iw - (row.button and s(120) or s(12))
        local titleRight = right
        if row.status then
            titleRight = right - L.width(row.status, 1, fonts.small) - s(10)
            dxDrawText(row.status, x + PAD + s(12), cy0 + s(8), right, cy0 + s(30),
                row.statusColor or C.muted, 1, fonts.small, "right", "top", true, false, true)
        end
        dxDrawText(row.title, x + PAD + s(12), cy0 + s(8), titleRight, cy0 + s(30), C.text, 1, fonts.bold,
            "left", "top", true, false, true)
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
        local label = armed and L("work_atc.trn.card.click_again_to_skip") or L("work_atc.trn.card.skip")
        local lw = L.width(label, 1, fonts.small)
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
        dxDrawText(L("work_atc.trn.card.press_for_cursor", { cursor_key = TRAINING.CURSOR_KEY:upper(), command = TRAINING.COMMAND }),
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

-- the scope of avi_controller leaves the card area alone (only sent when it changed)
local sentBlocked
function Card.syncBlocked()
    local b = (Card.spec and not Card.hidden) and Card.bounds or nil
    local key = b and table.concat({ math.floor(b[1]), math.floor(b[2]), math.floor(b[3]), math.floor(b[4]) }, ",") or ""
    if key == sentBlocked then return end
    sentBlocked = key
    local res = getResourceFromName("avi_controller")
    if res and getResourceState(res) == "running" then
        pcall(function() exports.avi_controller:setScopeBlockedRect(b) end)
    end
end

function Card.hide()
    Card.spec, Card.rect = nil, nil
    Card.syncBlocked()
    attach(false)
    setOwnCursor(false)
end

function Card.setHidden(hidden)
    hidden = hidden and true or false
    if Card.hidden == hidden then return end
    Card.hidden = hidden
    setOwnCursor(not hidden and Card.spec ~= nil and Card.spec.modal == true)
    Card.syncBlocked()
end

function Card.highlight(rect)
    Card.rect = rect
end

-- No punching / aiming while the cursor is out over the card: a click on a button would also hit.
-- Only the controls this file switched off are switched back on (v_inventory keeps "fire" and
-- "aim_weapon" off while the player holds an item).
local BLOCKED_CONTROLS = { "fire", "action", "aim_weapon" }
local blocked = {}

local function carryingEquipment()
    local slots = getElementData(localPlayer, "inv.slots")
    return type(slots) == "table" and (slots.left ~= nil or slots.right ~= nil)
end

local function setBlocked(state)
    for _, control in ipairs(BLOCKED_CONTROLS) do
        if state and not blocked[control] and isControlEnabled(control) then
            toggleControl(control, false)
            blocked[control] = true
        elseif not state and blocked[control] then
            blocked[control] = nil
            -- the carry lock of v_inventory owns these while something is in the hands
            if control == "action" or not carryingEquipment() then toggleControl(control, true) end
        end
    end
end

addEventHandler("onClientRender", root, function()
    setBlocked(Card.spec ~= nil and not Card.hidden and isCursorShowing())
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    setOwnCursor(false)
    setBlocked(false)
    Card.spec = nil
    Card.syncBlocked()
end)
