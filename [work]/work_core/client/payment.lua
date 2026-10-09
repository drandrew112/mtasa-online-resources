-- Itemised payment receipts (server/payment.lua triggers "work:payment" after a successful
-- payWork()). One is shown at a time; further payments queue up. It fades out on its own after
-- WORK.PAYMENT_DURATION, and ENTER skips straight to the next one in the queue.

local sw, sh = guiGetScreenSize()
local function s(v) return v * sh / 1080 end

local fonts = {}
local function font(size, bold)
    local key = size .. (bold and "b" or "")
    if fonts[key] == nil then
        fonts[key] = dxCreateFont(bold and "client/fonts/RobotoB.ttf" or "client/fonts/Roboto.ttf", s(size), false, "antialiased")
            or (bold and "default-bold" or "default")
    end
    return fonts[key]
end

local GREEN, RED, GREY = { 46, 204, 113 }, { 218, 54, 51 }, { 200, 205, 212 }

local function rgb(c, a) return tocolor(c[1], c[2], c[3], a or 255) end

local function round(x, y, w, h, r, color)
    r = math.min(r, w / 2, h / 2)
    if r < 1 then return dxDrawRectangle(x, y, w, h, color) end
    dxDrawRectangle(x + r, y, w - 2 * r, h, color)
    dxDrawRectangle(x, y + r, r, h - 2 * r, color)
    dxDrawRectangle(x + w - r, y + r, r, h - 2 * r, color)
    dxDrawCircle(x + r, y + r, r, 180, 270, color, color, 12)
    dxDrawCircle(x + w - r, y + r, r, 270, 360, color, color, 12)
    dxDrawCircle(x + r, y + h - r, r, 90, 180, color, color, 12)
    dxDrawCircle(x + w - r, y + h - r, r, 0, 90, color, color, 12)
end

local function money(n)
    local digits = tostring(math.abs(math.floor(n)))
    digits = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return (n < 0 and "-€" or "€") .. digits
end

---------------------------------------------------------------- queue

local queue = {}                   -- pending receipts
local current = nil                -- the one on screen, plus .start (tick)
local bound = false

local skip

local function showNext()
    current = table.remove(queue, 1)
    if current then
        current.start = getTickCount()
        if not bound then bindKey("enter", "down", skip); bound = true end
    elseif bound then
        unbindKey("enter", "down", skip)
        bound = false
    end
end

skip = function()
    if not current or isChatBoxInputActive() or isCursorShowing() then return end
    showNext()
end

addEvent("work:payment", true)
addEventHandler("work:payment", resourceRoot, function(workName, color, items, total, reason)
    queue[#queue + 1] = {
        workName = tostring(workName or "Work"),
        color = type(color) == "table" and color or WORK.DEFAULT_COLOR,
        items = type(items) == "table" and items or {},
        total = tonumber(total) or 0,
        reason = reason and tostring(reason) or nil,
    }
    if not current then showNext() end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if bound then unbindKey("enter", "down", skip) end
end)

---------------------------------------------------------------- drawing

local function draw(d, alpha)
    local fTitle, fName, fLabel, fAmount = font(14, true), font(9, true), font(11), font(11, true)
    local fTotalLabel, fTotalAmount, fReason, fHint = font(12, true), font(16, true), font(10), font(9)
    local pad, gap = s(18), s(14)
    local rowH, totalH, hintH = s(22), s(30), s(22)
    local iconSize = s(28)

    local amountColW = math.max(dxGetTextWidth("TOTAL", 1, fTotalAmount), s(1))
    local labelColW = 0
    for _, it in ipairs(d.items) do
        labelColW = math.max(labelColW, dxGetTextWidth(it.label, 1, fLabel))
        amountColW = math.max(amountColW, dxGetTextWidth(money(it.amount), 1, fAmount))
    end
    amountColW = math.max(amountColW, dxGetTextWidth(money(d.total), 1, fTotalAmount))
    local rowsW = labelColW + gap + amountColW

    local titleStr = "PAYMENT RECEIPT"
    local nameStr = d.workName:upper()
    local titleW = math.max(dxGetTextWidth(titleStr, 1, fTitle), dxGetTextWidth(nameStr, 1, fName))

    local hintStr = "ENTER · SKIP"
    local reasonW = d.reason and dxGetTextWidth(d.reason, 1, fReason) or 0

    local contentW = math.max(rowsW, titleW + iconSize + gap, reasonW, dxGetTextWidth(hintStr, 1, fHint))
    local w = contentW + pad * 2
    local headH = s(44)
    local h = headH + #d.items * rowH + s(10) + totalH + (d.reason and s(18) or 0) + hintH

    local x, y = sw / 2 - w / 2, sh * 0.20
    local a = alpha / 255

    round(x, y, w, h, s(8), tocolor(14, 17, 21, 225 * a))

    -- header: colour icon + work name / "PAYMENT RECEIPT"
    local ix, iy = x + pad, y + (headH - iconSize) / 2
    round(ix, iy, iconSize, iconSize, s(6), rgb(d.color, 240 * a))
    dxDrawText(d.workName:sub(1, 1):upper(), ix, iy, ix + iconSize, iy + iconSize,
        tocolor(255, 255, 255, 255 * a), 1, font(13, true), "center", "center")

    local tx = ix + iconSize + gap
    dxDrawText(nameStr, tx, y + s(7), tx + titleW, y + headH * 0.48, rgb(d.color, 255 * a), 1, fName, "left", "center")
    dxDrawText(titleStr, tx, y + headH * 0.46, tx + titleW, y + headH, tocolor(255, 255, 255, 255 * a), 1, fTitle, "left", "center")

    -- items
    local ry = y + headH
    for _, it in ipairs(d.items) do
        local col = it.amount < 0 and RED or GREY
        dxDrawText(it.label, x + pad, ry, x + pad + labelColW, ry + rowH,
            tocolor(GREY[1], GREY[2], GREY[3], 220 * a), 1, fLabel, "left", "center")
        dxDrawText(money(it.amount), x + w - pad - amountColW, ry, x + w - pad, ry + rowH,
            rgb(col, 255 * a), 1, fAmount, "right", "center")
        ry = ry + rowH
    end

    -- divider
    dxDrawRectangle(x + pad, ry + s(4), w - pad * 2, s(1), rgb(d.color, 120 * a))
    ry = ry + s(10)

    -- total
    local totalCol = d.total > 0 and GREEN or (d.total < 0 and RED or GREY)
    dxDrawText("TOTAL", x + pad, ry, x + pad + labelColW, ry + totalH,
        tocolor(255, 255, 255, 255 * a), 1, fTotalLabel, "left", "center")
    dxDrawText(money(d.total), x + w - pad - amountColW, ry, x + w - pad, ry + totalH,
        rgb(totalCol, 255 * a), 1, fTotalAmount, "right", "center")
    ry = ry + totalH

    if d.reason then
        dxDrawText(d.reason, x + pad, ry, x + w - pad, ry + s(18),
            tocolor(GREY[1], GREY[2], GREY[3], 200 * a), 1, fReason, "center", "center")
        ry = ry + s(18)
    end

    -- footer hint + remaining-time bar
    dxDrawText(hintStr, x + pad, ry, x + w - pad, ry + hintH,
        tocolor(140, 145, 152, 200 * a), 1, fHint, "right", "center")

    local elapsed = getTickCount() - d.start
    local frac = math.max(0, 1 - elapsed / WORK.PAYMENT_DURATION)
    dxDrawRectangle(x, y + h, w * frac, s(2), rgb(d.color, 200 * a))
end

addEventHandler("onClientRender", root, function()
    if not current then return end
    local elapsed = getTickCount() - current.start
    local duration, fade = WORK.PAYMENT_DURATION, WORK.PAYMENT_FADE

    if elapsed >= duration then
        showNext()
        return
    end

    local alpha = 255
    if elapsed < fade then alpha = 255 * elapsed / fade
    elseif elapsed > duration - fade then alpha = 255 * (duration - elapsed) / fade end

    draw(current, alpha)
end)
