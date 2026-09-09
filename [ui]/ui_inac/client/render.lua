uicore = exports.ui_core
ui = function(v) return uicore:ui(v) end

-- "$1,234"
local function money(n)
    local s = tostring(math.floor(n))
    return "$" .. (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

-- small vector tick, centred on (cx, cy)
local function drawTick(cx, cy, s, colour)
    dxDrawLine(cx - s,        cy + s * 0.15, cx - s * 0.25, cy + s * 0.8, colour, ui(2))
    dxDrawLine(cx - s * 0.25, cy + s * 0.8,  cx + s,        cy - s * 0.7, colour, ui(2))
end

-- hollow ring, centred on (cx, cy)
local function drawRing(cx, cy, r, colour)
    local segs, px, py = 18
    for i = 0, segs do
        local a = (i / segs) * math.pi * 2
        local x, y = cx + math.cos(a) * r, cy + math.sin(a) * r
        if px then dxDrawLine(px, py, x, y, colour, ui(1.5)) end
        px, py = x, y
    end
end

sw, sh = uicore:getScreenWH()
sx, sy = uicore:getSafeZone()

addEventHandler("onClientRender", root, function()
    if not MenuState.open then return end

    local menu = MenuState:getMenu()
    if not menu then return end

    local sw, sh = uicore:getScreenWH()

    -- Méretek
    local hasHeader = menu.header ~= false   -- ideiglenes menuk fejlec nelkul
    local w        = ui(420)
    local headerH  = hasHeader and ui(60) or 0
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

    -- Header (az ideiglenes menuknel nincs "FREE V" fejlec)
    if hasHeader then
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
    end

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

    -- Windowing: sok elemnél (pl. a customs lista) csak egy ablaknyi látszik,
    -- a kijelölt elem köré igazítva, hogy ne lógjon le a képernyőről.
    local rowsTop  = titleY + titleH
    local availH   = sh - rowsTop - sy - ui(72)
    local maxRows  = math.max(4, math.floor(availH / itemH))
    local total    = #menu.items
    local firstRow = 1
    if total > maxRows then
        firstRow = math.min(math.max(1, MenuState.selected - math.floor(maxRows / 2)), total - maxRows + 1)
    end
    local lastRow    = math.min(total, firstRow + maxRows - 1)
    local shownCount = lastRow - firstRow + 1

    -- Menü pontok
    for i = firstRow, lastRow do
        local item = menu.items[i]
        local iy = rowsTop + (i - firstRow) * itemH
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
        local rightIcon = nil            -- "check" | "ring"
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
        elseif item.type == "action" then
            -- temp-menu right-hand indicators
            if item.checked then
                rightIcon = "check"
            elseif item.owned then
                rightIcon = "ring"
            elseif type(item.price) == "number" then
                valueText = item.price > 0 and money(item.price) or "Free"
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
        elseif rightIcon == "check" then
            drawTick(x + w - ui(20), iy + itemH / 2, ui(7),
                selected and tocolor(0,0,0,255) or tocolor(120,220,140,255))
        elseif rightIcon == "ring" then
            drawRing(x + w - ui(19), iy + itemH / 2, ui(6),
                selected and tocolor(0,0,0,255) or tocolor(190,190,190,255))
        end
    end

    -- Scrollbar (csak ha van elrejtett elem)
    if total > maxRows then
        local trackH = shownCount * itemH
        local thumbH = math.max(ui(16), trackH * (shownCount / total))
        local thumbY = rowsTop + (trackH - thumbH) * ((firstRow - 1) / (total - shownCount))
        dxDrawRectangle(x + w - ui(3), rowsTop, ui(3), trackH, tocolor(0,0,0,120))
        dxDrawRectangle(x + w - ui(3), thumbY, ui(3), thumbH, tocolor(0,170,220,255))
    end

    -- 4️⃣ Vertical arrows (2px-el a menü alatt)
    local arrowsY = rowsTop + (shownCount * itemH) + ui(2)
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
