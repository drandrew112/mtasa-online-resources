uicore = exports.ui_core
ui = function(v) return uicore:ui(v) end

sw, sh = uicore:getScreenWH()
sx, sy = uicore:getSafeZone()

addEventHandler("onClientRender", root, function()
    if not MenuState.open then return end

    local menu = MenuState:getMenu()
    if not menu then return end

    local sw, sh = uicore:getScreenWH()

    -- Méretek
    local w        = ui(420)
    local headerH  = ui(60)
    local titleH   = ui(30)
    local itemH    = ui(32)
    local padding  = 0

    local titleSize   = ui(1.7)
    local itemSize    = ui(1.4)
    local freeVSize   = ui(1.6)

    local h = headerH + titleH + (#menu.items * itemH)

    -- Pos
    local x = sx+padding
    local y = sy+padding

    -- Header
    dxDrawRectangle(x, y, w, headerH, tocolor(0, 100, 150, 255))
    dxDrawText(
        "FREE V",
        x + w/2,
        y + headerH / 2,
        nil, nil,
        tocolor(255, 255, 255, 255),
        freeVSize,
        "pricedown",
        "center",
        "center"
    )

    -- Title
    local titleY = y + headerH
    dxDrawRectangle(x, titleY, w, titleH, tocolor(0,0,0,200))

    -- Bal oldali menü neve
    dxDrawText(
        menu.title,
        x + ui(12),
        titleY + titleH / 2,
        nil, nil,
        tocolor(0, 170, 220, 255),
        titleSize,
        "default-bold",
        "left",
        "center"
    )

    -- Jobb oldali kijelölt/összes
    dxDrawText(
        MenuState.selected .. "/" .. #menu.items,
        x + w - ui(12),
        titleY + titleH / 2,
        nil, nil,
        tocolor(0, 170, 220, 255),
        titleSize,
        "default-bold",
        "right",
        "center"
    )

    -- Menü pontok
    for i, item in ipairs(menu.items) do
        local iy = titleY + titleH + (i - 1) * itemH
        local selected = (MenuState.selected == i)

        if selected then
            dxDrawRectangle(x, iy, w, itemH, tocolor(255, 255, 255, 255))
        else
            dxDrawRectangle(x, iy, w, itemH, tocolor(0, 0, 0, 170))
        end

        -- Bal oldali label
        dxDrawText(
            item.label or "",
            x + ui(12),
            iy + itemH / 2,
            nil, nil,
            selected and tocolor(0,0,0,255) or tocolor(255,255,255,255),
            itemSize,
            "default",
            "left",
            "center"
        )

        -- Jobb oldali érték
        local valueText = ""
        if item.type == "select" and item.options then
            local opt = item.options[item.value]
            if opt then
                valueText = "< " .. opt.label .. " >"
            end
        elseif item.type == "spawnvehicle" then
            valueText = "ID " .. tostring(item.model)
        elseif item.type == "data" then
            local raw = getElementData(item.source, item.key)
            if item.format then
                valueText = item.format(raw)
            else
                valueText = tostring(raw or "—")
            end
        end

        if valueText ~= "" then
            dxDrawText(
                valueText,
                x + w - ui(12),
                iy + itemH / 2,
                nil, nil,
                selected and tocolor(0,0,0,255) or tocolor(180,180,180,255),
                itemSize,
                "default",
                "right",
                "center"
            )
        end
    end

    -- 4️⃣ Vertical arrows (2px-el a menü alatt)
    local arrowsY = titleY + titleH + (#menu.items * itemH) + ui(2)
    dxDrawRectangle(x, arrowsY, w, ui(30), tocolor(0,0,0,200))
    dxDrawImage(x + (w/2) - ui(7), arrowsY + ui(4), ui(14), ui(22), "vertical_arrows.png")

    -- 5️⃣ Leírás sor (5px-el az arrow sor alatt)
    local descY = arrowsY + ui(30) + ui(2)
    dxDrawRectangle(x, descY, w, ui(30), tocolor(20,20,20,170))
    local desc = menu.items[MenuState.selected].desc or ""
    dxDrawText(
        desc,
        x + ui(12),
        descY + ui(15),
        x + w - ui(12),
        nil,
        tocolor(255,255,255,255),
        itemSize,
        "default",
        "left",
        "center"
    )
end)
