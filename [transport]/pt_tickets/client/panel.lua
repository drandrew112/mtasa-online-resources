-- The ticket sale panel: a small DX window (about 30 % of the screen width) listing the stops
-- the player can buy a ticket to, with the distance and the price. Mouse or arrows + Enter;
-- Backspace / the Cancel button closes it. Walking away (PTT.SALE_RANGE) closes it too.

local sw, sh = guiGetScreenSize()
local S = sh / 1080
local sale = nil          -- the open offer view (server/tickets.lua openSale)
local sel, top = 1, 1
local origin = nil        -- { x, y, z } where the panel opened
local hover = nil         -- "row:<i>" | "buy" | "cancel"
local fonts = {}

local C = {
    bg     = tocolor(14, 20, 32, 240),
    head   = tocolor(22, 74, 150, 255),
    row    = tocolor(255, 255, 255, 10),
    rowHot = tocolor(255, 255, 255, 28),
    rowSel = tocolor(40, 120, 220, 200),
    text   = tocolor(235, 240, 248, 255),
    dim    = tocolor(160, 172, 190, 255),
    accent = tocolor(255, 196, 60, 255),
    btn    = tocolor(40, 150, 90, 255),
    btnHot = tocolor(55, 180, 110, 255),
    btn2   = tocolor(70, 78, 92, 255),
    btn2Hot = tocolor(95, 104, 120, 255),
}

local function font(bold, size)
    local key = (bold and "b" or "r") .. size
    if not fonts[key] then
        fonts[key] = dxCreateFont(bold and "fonts/RobotoB.ttf" or "fonts/Roboto.ttf", math.max(7, math.floor(size * S)), false, "antialiased")
            or (bold and "default-bold" or "default")
    end
    return fonts[key]
end

local function money(n) return L.money(n or 0) end
local function txt(x) if x == nil then return "" end return L.resolve(x) or "" end

local function layout()
    local w = math.floor(math.min(sw * 0.4, math.max(PTT.PANEL.MIN_W * S, sw * PTT.PANEL.W)))
    local rowH = math.floor(34 * S)
    local rows = math.min(#sale.stops, PTT.PANEL.ROWS)
    local headH, infoH, footH = math.floor(64 * S), math.floor(54 * S), math.floor(96 * S)
    local h = headH + infoH + rows * rowH + footH
    local x, y = math.floor((sw - w) / 2), math.floor((sh - h) / 2)
    return { x = x, y = y, w = w, h = h, rowH = rowH, rows = rows, headH = headH, infoH = infoH, footH = footH,
        pad = math.floor(16 * S) }
end

local function inside(cx, cy, x, y, w, h) return cx and cx >= x and cx <= x + w and cy >= y and cy <= y + h end

local function close(tellServer)
    if not sale then return end
    sale = nil
    showCursor(false)
    if tellServer then triggerServerEvent("pt:sale:cancel", resourceRoot) end
end

local function buy()
    if not sale or not sale.stops[sel] or sale.busy then return end
    sale.busy = true
    triggerServerEvent("pt:sale:buy", resourceRoot, sel)
end

local function clampScroll(l)
    if sel < top then top = sel end
    if sel > top + l.rows - 1 then top = sel - l.rows + 1 end
    top = math.max(1, math.min(top, #sale.stops - l.rows + 1))
end

addEventHandler("onClientRender", root, function()
    if not sale then return end
    if origin then
        local x, y, z = getElementPosition(localPlayer)
        if getDistanceBetweenPoints3D(x, y, z, origin[1], origin[2], origin[3]) > PTT.SALE_RANGE or isPedDead(localPlayer) then
            close(true)
            return
        end
    end
    local l = layout()
    clampScroll(l)
    local cx, cy
    if isCursorShowing() then
        local rx, ry = getCursorPosition()
        cx, cy = rx * sw, ry * sh
    end
    hover = nil

    dxDrawRectangle(l.x, l.y, l.w, l.h, C.bg, true)
    -- header: operator + train
    dxDrawRectangle(l.x, l.y, l.w, l.headH, C.head, true)
    dxDrawText(txt(sale.operator) .. "  ·  " .. L("pt_tickets.panel.ticket_sale"), l.x + l.pad, l.y + 6 * S, l.x + l.w - l.pad, l.y + l.headH / 2 + 4 * S,
        C.dim, 1, font(false, 12), "left", "center", true, false, true)
    dxDrawText(txt(sale.line) .. "  " .. txt(sale.title), l.x + l.pad, l.y + l.headH / 2, l.x + l.w - l.pad, l.y + l.headH - 6 * S,
        C.text, 1, font(true, 16), "left", "center", true, false, true)
    -- from + column titles
    local iy = l.y + l.headH
    dxDrawText(L("pt_tickets.panel.from", { from = txt(sale.fromName) }), l.x + l.pad, iy + 4 * S, l.x + l.w - l.pad, iy + l.infoH / 2 + 4 * S,
        C.text, 1, font(true, 13), "left", "center", true, false, true)
    dxDrawText(L("pt_tickets.panel.destination"), l.x + l.pad, iy + l.infoH / 2, l.x + l.w, iy + l.infoH,
        C.dim, 1, font(false, 11), "left", "center", true, false, true)
    dxDrawText(L("pt_tickets.panel.distance"), l.x, iy + l.infoH / 2, l.x + l.w * 0.70, iy + l.infoH,
        C.dim, 1, font(false, 11), "right", "center", true, false, true)
    dxDrawText(L("pt_tickets.panel.price"), l.x, iy + l.infoH / 2, l.x + l.w - l.pad, iy + l.infoH,
        C.dim, 1, font(false, 11), "right", "center", true, false, true)
    -- destinations
    local ry = iy + l.infoH
    for k = 0, l.rows - 1 do
        local i = top + k
        local st = sale.stops[i]
        if st then
            local y = ry + k * l.rowH
            local hot = inside(cx, cy, l.x, y, l.w, l.rowH - 2)
            if hot then hover = "row:" .. i end
            dxDrawRectangle(l.x + 6 * S, y + 1, l.w - 12 * S, l.rowH - 2, i == sel and C.rowSel or (hot and C.rowHot or C.row), true)
            dxDrawText(txt(st.name), l.x + l.pad, y, l.x + l.w * 0.55, y + l.rowH, C.text, 1, font(i == sel, 13), "left", "center", true, false, true)
            dxDrawText(("%.1f km"):format(st.km or 0), l.x, y, l.x + l.w * 0.70, y + l.rowH, C.dim, 1, font(false, 12), "right", "center", true, false, true)
            dxDrawText(money(st.price), l.x, y, l.x + l.w - l.pad, y + l.rowH, i == sel and C.text or C.accent, 1, font(true, 13), "right", "center", true, false, true)
        end
    end
    if #sale.stops > l.rows then
        dxDrawText(("%d-%d / %d"):format(top, top + l.rows - 1, #sale.stops), l.x, ry + l.rows * l.rowH - 2, l.x + l.w - l.pad, ry + l.rows * l.rowH + 12 * S,
            C.dim, 1, font(false, 9), "right", "top", false, false, true)
    end
    -- footer: supplement note, money, buttons
    local fy = ry + l.rows * l.rowH
    local note = sale.supplement and L("pt_tickets.panel.ic_supplement_included") or ""
    local wallet = L("pt_tickets.panel.wallet", { cash = money(sale.cash) }) ..
        (sale.bank and ("   " .. L("pt_tickets.panel.bank", { bank = money(sale.bank) })) or "")
    dxDrawText(note, l.x + l.pad, fy + 6 * S, l.x + l.w - l.pad, fy + 24 * S, C.dim, 1, font(false, 10), "left", "top", true, false, true)
    dxDrawText(wallet, l.x + l.pad, fy + 24 * S, l.x + l.w - l.pad, fy + 42 * S, C.dim, 1, font(false, 10), "left", "top", true, false, true)
    local bh, gap = math.floor(38 * S), math.floor(10 * S)
    local by = l.y + l.h - bh - l.pad * 0.75
    local bw2 = math.floor(l.w * 0.30)
    local bw = l.w - l.pad * 2 - bw2 - gap
    local bx = l.x + l.pad
    local st = sale.stops[sel]
    local hotBuy = inside(cx, cy, bx, by, bw, bh)
    local hotCancel = inside(cx, cy, bx + bw + gap, by, bw2, bh)
    if hotBuy then hover = "buy" elseif hotCancel then hover = "cancel" end
    dxDrawRectangle(bx, by, bw, bh, hotBuy and C.btnHot or C.btn, true)
    dxDrawText(sale.busy and L("pt_tickets.panel.please_wait") or L("pt_tickets.panel.buy", { price = money(st and st.price) }),
        bx, by, bx + bw, by + bh, C.text, 1, font(true, 13), "center", "center", true, false, true)
    dxDrawRectangle(bx + bw + gap, by, bw2, bh, hotCancel and C.btn2Hot or C.btn2, true)
    dxDrawText(L("pt_tickets.panel.cancel"), bx + bw + gap, by, bx + bw + gap + bw2, by + bh, C.text, 1, font(true, 13), "center", "center", true, false, true)
end)

addEventHandler("onClientClick", root, function(button, state)
    if not sale or button ~= "left" or state ~= "down" or not hover then return end
    if hover == "buy" then buy()
    elseif hover == "cancel" then close(true)
    else
        local i = tonumber(hover:match("^row:(%d+)$"))
        if i then
            if i == sel then buy() else sel = i end   -- a second click on the selected row buys
        end
    end
end)

addEventHandler("onClientKey", root, function(key, press)
    if not sale then return end
    if key == "arrow_u" or key == "arrow_d" or key == "enter" or key == "num_enter" or key == "backspace"
        or key == "mouse_wheel_up" or key == "mouse_wheel_down" then
        cancelEvent()
        if not press then return end
        local n = #sale.stops
        if key == "arrow_u" or key == "mouse_wheel_up" then sel = sel > 1 and sel - 1 or n
        elseif key == "arrow_d" or key == "mouse_wheel_down" then sel = sel < n and sel + 1 or 1
        elseif key == "enter" or key == "num_enter" then buy()
        elseif key == "backspace" then close(true) end
    end
end)

addEvent("pt:sale:open", true)
addEventHandler("pt:sale:open", resourceRoot, function(view)
    if type(view) ~= "table" or type(view.stops) ~= "table" or #view.stops == 0 then return end
    sale = view
    sel, top = 1, 1
    origin = { getElementPosition(localPlayer) }
    showCursor(true)
end)

addEvent("pt:sale:close", true)
addEventHandler("pt:sale:close", resourceRoot, function() close(false) end)

addEvent("pt:notify", true)
addEventHandler("pt:notify", resourceRoot, function(title, text)
    title, text = L.resolve(title) or "", L.resolve(text) or ""
    if title == "" then title = L("pt_tickets.panel.tickets") end
    -- a failed purchase leaves the panel open: the button works again
    if sale then sale.busy = false end
    local res = getResourceFromName("ui_core")
    if res and getResourceState(res) == "running" then exports.ui_core:addNotification(title, text)
    else outputChatBox("[" .. title .. "] " .. text, 120, 180, 255) end
end)

addEventHandler("onClientResourceStop", resourceRoot, function() if sale then showCursor(false) end end)
