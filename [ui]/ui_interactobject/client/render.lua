-- World-space drawing: a dot above every nearby element with a menu, a key prompt on the focused
-- one, and the numbered option panel next to it while the menu is open.

local screenW, screenH = guiGetScreenSize()
local scale = math.max(0.65, screenH / 1080)
local function s(v) return v * scale end

local fonts
local function loadFonts()
    fonts = {
        title = dxCreateFont("assets/fonts/RobotoB.ttf", math.floor(12 * scale), false, "cleartype") or "default-bold",
        row = dxCreateFont("assets/fonts/Roboto.ttf", math.floor(11 * scale), false, "cleartype") or "default",
        bold = dxCreateFont("assets/fonts/RobotoB.ttf", math.floor(10 * scale), false, "cleartype") or "default-bold",
        small = dxCreateFont("assets/fonts/Roboto.ttf", math.floor(9 * scale), false, "cleartype") or "default",
    }
end

local C = {
    bg = tocolor(16, 18, 24, 230),
    header = tocolor(22, 26, 34, 245),
    accent = tocolor(0, 140, 200, 255),
    accentDim = tocolor(0, 140, 200, 120),
    text = tocolor(235, 238, 245, 255),
    textDim = tocolor(150, 156, 170, 255),
    textOff = tocolor(95, 100, 112, 255),
    badgeOff = tocolor(50, 54, 64, 255),
    divider = tocolor(255, 255, 255, 18),
    markerRing = tocolor(16, 18, 24, 200),
    marker = tocolor(235, 238, 245, 230),
}

local MARGIN = 16

local function textWidth(text, font)
    return dxGetTextWidth(text, 1, font)
end

local function drawText(text, x1, y1, x2, y2, color, font, alignX, clip)
    dxDrawText(text, x1, y1, x2, y2, color, 1, font, alignX or "left", "center", clip or false)
end

local function drawKeyBadge(key, x, y, size, color)
    dxDrawRectangle(x, y, size, size, color)
    drawText(key, x, y, x + size, y + size, C.text, fonts.bold, "center")
end

local function drawMarker(x, y, focused)
    if focused then
        dxDrawCircle(x, y, s(9), 0, 360, C.accent, C.accent, 24)
        dxDrawCircle(x, y, s(4), 0, 360, C.text, C.text, 16)
    else
        dxDrawCircle(x, y, s(6), 0, 360, C.markerRing, C.markerRing, 20)
        dxDrawCircle(x, y, s(3.5), 0, 360, C.marker, C.marker, 16)
    end
end

-- "Q  2/3  E" under the prompt / in the panel header when several menus are in range
local function focusCounter()
    local count = #State.candidates
    if count < 2 then return nil end
    local index = 1
    for i, candidate in ipairs(State.candidates) do
        if candidate.element == State.focus then index = i break end
    end
    return ("%s  %d/%d  %s"):format(IO.KEY_PREV:upper(), index, count, IO.KEY_NEXT:upper())
end

local function drawPrompt(candidate, ax, ay)
    local title = candidate.menus[1].def.title
    local h = s(30)
    local badge = s(20)
    local w = s(10) + badge + s(8) + textWidth(title, fonts.title) + s(12)
    local x, y = ax + s(16), ay - h / 2

    dxDrawRectangle(x, y, w, h, C.bg)
    dxDrawRectangle(x, y, s(3), h, C.accent)
    drawKeyBadge(IO.KEY_OPEN:upper(), x + s(10), y + (h - badge) / 2, badge, C.accent)
    drawText(title, x + s(10) + badge + s(8), y, x + w, y + h, C.text, fonts.title)

    local counter = focusCounter()
    if counter then
        local cw = textWidth(counter, fonts.small) + s(14)
        dxDrawRectangle(x, y + h, cw, s(20), C.header)
        drawText(counter, x, y + h, x + cw, y + h + s(20), C.textDim, fonts.small, "center")
    end
end

local function drawPanel(candidate, ax, ay)
    local view = buildView()
    if not view then return end

    local padX = s(12)
    local badge = s(20)
    local headerH, rowH, descRowH, groupH, footerH = s(34), s(30), s(44), s(22), s(24)
    local counter = view.depth == 0 and focusCounter() or nil
    local pageText = view.pages > 1 and ("%d/%d"):format(view.page, view.pages) or nil

    -- size
    local w = padX * 2 + textWidth(view.title, fonts.title)
        + (counter and textWidth(counter, fonts.small) + s(16) or 0) + (pageText and s(40) or 0)
    local h = headerH + footerH
    local lastGroup
    for _, entry in ipairs(view.entries) do
        local item = entry.item
        local lineW = padX * 2 + badge + s(10) + textWidth(item.label, fonts.row) + (item.items and s(18) or 0)
        if item.desc then lineW = math.max(lineW, padX * 2 + badge + s(10) + textWidth(item.desc, fonts.small)) end
        w = math.max(w, lineW)
        if view.grouped and entry.group ~= lastGroup then
            h = h + groupH
            lastGroup = entry.group
        end
        h = h + (item.desc and descRowH or rowH)
    end
    if #view.entries == 0 then h = h + rowH end
    w = math.min(math.max(w, s(230)), s(400))

    -- position: to the right of the anchor, flipped / clamped to stay on screen
    local x, y
    if ax then
        x, y = ax + s(24), ay - headerH / 2
        if x + w > screenW - s(MARGIN) then x = ax - s(24) - w end
    else
        x, y = screenW * 0.6, screenH * 0.35
    end
    x = math.max(s(MARGIN), math.min(x, screenW - s(MARGIN) - w))
    y = math.max(s(MARGIN), math.min(y, screenH - s(MARGIN) - h))

    if ax then
        local lx = x > ax and x or x + w
        dxDrawLine(ax, ay, lx, y + headerH / 2, C.accentDim, s(1.5))
    end

    -- header
    dxDrawRectangle(x, y, w, headerH, C.header)
    dxDrawRectangle(x, y, s(3), headerH, C.accent)
    local titleRight = x + w - padX
    if counter then
        drawText(counter, x, y, titleRight, y + headerH, C.textDim, fonts.small, "right")
        titleRight = titleRight - textWidth(counter, fonts.small) - s(12)
    end
    if pageText then
        drawText(pageText, x, y, titleRight, y + headerH, C.accent, fonts.bold, "right")
        titleRight = titleRight - textWidth(pageText, fonts.bold) - s(12)
    end
    local titleText = view.depth > 0 and ("< " .. view.title) or view.title
    drawText(titleText, x + padX, y, titleRight, y + headerH, C.text, fonts.title, "left", true)

    -- rows
    local cy = y + headerH
    dxDrawRectangle(x, cy, w, h - headerH - footerH, C.bg)
    lastGroup = nil
    for i, entry in ipairs(view.entries) do
        local item = entry.item
        if view.grouped and entry.group ~= lastGroup then
            lastGroup = entry.group
            drawText(entry.group:upper(), x + padX, cy, x + w - padX, cy + groupH, C.textDim, fonts.small, "left", true)
            dxDrawRectangle(x + padX, cy + groupH - 1, w - padX * 2, 1, C.divider)
            cy = cy + groupH
        end

        local rh = item.desc and descRowH or rowH
        local disabled = item.disabled
        drawKeyBadge(tostring(i), x + padX, cy + (rowH - badge) / 2, badge, disabled and C.badgeOff or C.accent)

        local textX = x + padX + badge + s(10)
        drawText(item.label, textX, cy, x + w - padX - (item.items and s(18) or 0), cy + rowH,
            disabled and C.textOff or C.text, fonts.row, "left", true)
        if item.items then
            drawText(">", x, cy, x + w - padX, cy + rowH, disabled and C.textOff or C.textDim, fonts.bold, "right")
        end
        if item.desc then
            drawText(item.desc, textX, cy + rowH - s(8), x + w - padX, cy + rh - s(4), C.textDim, fonts.small, "left", true)
        end
        cy = cy + rh
    end
    if #view.entries == 0 then
        drawText("No options", x + padX, cy, x + w, cy + rowH, C.textDim, fonts.row)
        cy = cy + rowH
    end

    -- footer
    dxDrawRectangle(x, cy, w, footerH, C.header)
    local hints = {}
    if #view.entries > 0 then hints[#hints + 1] = ("1-%d select"):format(#view.entries) end
    if view.pages > 1 then hints[#hints + 1] = IO.KEY_PAGE .. " next page" end
    hints[#hints + 1] = view.depth > 0 and "BKSP back" or (IO.KEY_OPEN:upper() .. " close")
    drawText(table.concat(hints, "  ·  "), x + padX, cy, x + w - padX, cy + footerH, C.textDim, fonts.small, "left", true)
end

addEventHandler("onClientRender", root, function()
    local candidates = State.candidates
    if #candidates == 0 then return end
    if not fonts then loadFonts() end

    local focused = getFocusCandidate()
    local fx, fy
    for _, candidate in ipairs(candidates) do
        if isElement(candidate.element) then
            local sx, sy = getScreenFromWorldPosition(getAnchor(candidate.element, candidate.menus[1]))
            if candidate == focused then
                fx, fy = sx, sy
            elseif sx and not State.open then
                drawMarker(sx, sy, false)
            end
        end
    end

    if not focused or not isElement(focused.element) then return end
    if fx then drawMarker(fx, fy, true) end
    if State.open then
        drawPanel(focused, fx, fy)
    elseif fx then
        drawPrompt(focused, fx, fy)
    end
end)
