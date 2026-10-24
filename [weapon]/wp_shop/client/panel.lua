if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- wp_shop / client/panel.lua
-- Top-left panel of the weapon browser, in the ui_inac menu look (same place, width, colours):
-- title bar, the weapon row, an info row, the switch hint and the key help.

local uicore = exports.ui_core
local function ui(v) return uicore:ui(v) end

local CYAN = tocolor(0, 170, 220, 255)

local function drawTick(cx, cy, s, colour)
    dxDrawLine(cx - s,        cy + s * 0.15, cx - s * 0.25, cy + s * 0.8, colour, ui(2))
    dxDrawLine(cx - s * 0.25, cy + s * 0.8,  cx + s,        cy - s * 0.7, colour, ui(2))
end

local function infoText(id, def, own)
    if def.thrown then
        return own and L("wp_shop.panel.thrown_have", { count = own }) or L("wp_shop.panel.thrown")
    elseif def.mag then
        local key = def.box and "wp_shop.panel.box" or "wp_shop.panel.magazine"
        return L(key, { rounds = def.mag, price = VAT.gross("weapons", def.magPrice) })
    end
    return L("wp_shop.panel.melee")
end

addEventHandler("onClientRender", root, function()
    if not Browse or Browse.state ~= "browse" then return end
    local id = currentWeapon()
    local def = id and WS.weapons[id]
    if not def then return end
    local own = ownedWeapons()[id]

    local x, y = uicore:getSafeZone()
    local w, titleH, rowH = ui(420), ui(30), ui(32)
    local titleSize, itemSize = ui(1.7), ui(1.4)
    local padX = ui(12)

    -- title: shop name + position in the list
    dxDrawRectangle(x, y, w, titleH, tocolor(0, 0, 0, 200))
    dxDrawText(L.upper(Browse.int.name), x + padX, y, nil, y + titleH, CYAN, titleSize, "default-bold", "left", "center")
    dxDrawText(Browse.index .. "/" .. #Browse.list, x + w - padX, y, x + w - padX, y + titleH, CYAN, titleSize, "default-bold", "right", "center")

    -- weapon row (selected look): name + price, or a tick when owned
    local ry = y + titleH
    dxDrawRectangle(x, ry, w, rowH, tocolor(255, 255, 255, 255))
    dxDrawText("<  " .. weaponName(id) .. "  >", x + padX, ry, nil, ry + rowH, tocolor(0, 0, 0, 255), itemSize, "default-bold", "left", "center")
    if own and not def.thrown then
        drawTick(x + w - ui(20), ry + rowH / 2, ui(7), tocolor(0, 0, 0, 255))
    else
        local gross = VAT.gross("weapons", def.price)
        local price = def.thrown and L("wp_shop.panel.each", { price = gross }) or L.money(gross)
        dxDrawText(price, x + padX, ry, x + w - padX, ry + rowH, tocolor(0, 0, 0, 255), itemSize, "default", "right", "center")
    end

    -- info row: ammo per magazine / pieces owned
    ry = ry + rowH
    dxDrawRectangle(x, ry, w, rowH, tocolor(0, 0, 0, 170))
    dxDrawText(infoText(id, def, own), x + padX, ry, nil, ry + rowH, tocolor(255, 255, 255, 255), itemSize, "default", "left", "center")
    if own and def.mag then
        dxDrawText(L("wp_shop.panel.ammo", { ammo = own }), x + padX, ry, x + w - padX, ry + rowH,
            tocolor(180, 180, 180, 255), itemSize, "default", "right", "center")
    end

    -- switch hint (the ui_inac arrow row, horizontal here)
    ry = ry + rowH + ui(2)
    dxDrawRectangle(x, ry, w, ui(30), tocolor(0, 0, 0, 200))
    dxDrawText("<     >", x, ry, x + w, ry + ui(30), tocolor(255, 255, 255, 255), titleSize, "default-bold", "center", "center")

    -- key help
    ry = ry + ui(30) + ui(2)
    dxDrawRectangle(x, ry, w, ui(30), tocolor(20, 20, 20, 170))
    dxDrawText(L("wp_shop.panel.help"), x + padX, ry, x + w - padX, ry + ui(30), tocolor(255, 255, 255, 255), itemSize, "default", "left", "center")
end)
