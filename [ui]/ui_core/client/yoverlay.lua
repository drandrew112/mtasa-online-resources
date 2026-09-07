UI.yOverlay = {
    active = false,
    startTick = 0,
    duration = 10000,
    fadeTime = 1000,
}

local xp_color = tocolor ( 80, 140, 230, 255 )

local xpLvlDos = 1000
local nextLvlXp = 600
function getNextXp(level)
    if level==0 then return 0 end
    local next_xp = xpLvlDos
    for i=1, level do
        next_xp = next_xp + ( i * nextLvlXp )
    end
    return next_xp
end

local function formatMoney(amount)
    local formatted = tostring(math.floor(amount))
    local sign = ""
    if formatted:sub(1,1) == "-" then
        sign = "-"
        formatted = formatted:sub(2)
    end
    local k
    repeat
        formatted, k = formatted:gsub("^(%d+)(%d%d%d)", "%1.%2")
    until k == 0
    return sign..formatted
end

local function getAlpha()
    local now = getTickCount()
    local elapsed = now - UI.yOverlay.startTick

    if elapsed < UI.yOverlay.fadeTime then
        return elapsed / UI.yOverlay.fadeTime * 255
    end

    if elapsed > UI.yOverlay.duration - UI.yOverlay.fadeTime then
        return (UI.yOverlay.duration - elapsed) / UI.yOverlay.fadeTime * 255
    end

    return 255
end

bindKey("y", "down", function()
    if UI.yOverlay.active then return end
    UI.yOverlay.active = true
    UI.yOverlay.startTick = getTickCount()
end)

function UI.yOverlay:draw()
    if not self.active then return end
    if getElementData(localPlayer, "hideHUD") then return end

    local now = getTickCount()
    if now > self.startTick + self.duration then
        self.active = false
        return
    end

    local alpha = math.max(0, math.min(255, getAlpha()))
    local sw, sh = UI.sw, UI.sh

    -- =========================
    -- TOP RIGHT – MONEY + TIME
    -- =========================
    local tr = UI.slots.topRight
    local money = getPlayerMoney(localPlayer)

    dxDrawText(
        "$ "..formatMoney(money),
        tr.x - ui(10), tr.y,
        tr.x - ui(10), tr.y,
        tocolor(50,200,50,alpha),
        1.3, "pricedown", "right", "top"
    )

    local h, m = getTime()
    if h < 10 then h = "0"..h end
    if m < 10 then m = "0"..m end

    dxDrawText(
        h..":"..m,
        tr.x - ui(10), tr.y + ui(30),
        tr.x - ui(10), tr.y + ui(30),
        tocolor(240,240,240,alpha),
        1.2, "pricedown", "right", "top"
    )

    -- =========================
    -- TOP CENTER – LEVEL / XP
    -- =========================
    local tc = UI.slots.topCenter
    local level    = tonumber(getElementData(localPlayer, "level")) or 0
    local next_lvl = level + 1
    local xp       = tonumber(getElementData(localPlayer, "xp")) or 0
    local next_xp  = tonumber(getElementData(localPlayer, "next_xp")) or 1
    local prev_xp  = tonumber(getNextXp(level-1)) or 0

    local barW = ui(300)
    local barX = tc.x - barW/2
    local barY = tc.y + ui(25)

    dxDrawRectangle(barX, barY, barW, ui(10), tocolor(0,0,0,alpha))
    dxDrawRectangle(
        barX,
        barY,
        barW * math.min(1, (xp-prev_xp)/(next_xp-prev_xp)),
        ui(10),
        tocolor(80,180,255,alpha)
    )

    dxDrawText(level, barX - ui(10), barY+ui(5), _,_, tocolor(255,255,255,alpha), ui(1.4), "pricedown", "right", "center")
    dxDrawText(next_lvl, barX + barW + ui(10), barY+ui(5), _,_, tocolor(255,255,255,alpha), ui(1.4), "pricedown", "left", "center")
    dxDrawText(xp.."/"..next_xp, tc.x, barY + ui(15), _,_, tocolor(220,220,220,alpha), ui(1.2), "arial", "center", "top")

    -- =========================
    -- LEFT – PLAYER LIST
    -- =========================
    local listX = UI.safe.x
    local listY = UI.safe.y
    local listW = ui(300)
    local rowH  = ui(30)

    local players = getElementsByType("player")

    dxDrawRectangle(listX, listY, listW, rowH, tocolor(0,0,0,alpha))
    dxDrawText(
        "FreeV ("..#players..")",
        listX + ui(8), listY+(rowH/2),
        _,_, tocolor(255,255,255,alpha),
        ui(1.3), "default-bold", "left", "center"
    )
    dxDrawText(
        "lvl",
        listX + listW - ui(8), listY+(rowH/2),
        _,_, tocolor(255,255,255,alpha),
        ui(1.3), "default", "right", "center"
    )

    for i, player in ipairs(players) do
        local y = listY + rowH*i
        local r = (i % 2 == 0) and 80 or 100
        local g = (i % 2 == 0) and 140 or 160
        local b = (i % 2 == 0) and 230 or 250

        local a = alpha
        local target_a = 140
        if alpha > target_a then a = target_a end

        dxDrawRectangle(listX, y, listW, rowH, tocolor(r,g,b,a))

        local pName = getPlayerName(player)
        dxDrawText(
            pName,
            listX + ui(8), y+(rowH/2),
            _,_, tocolor(255,255,255,alpha),
            ui(1.2), "default", "left", "center"
        )

        -- crew tag box a név mellett jobbra, a névvel azonos betűméretben
        local nameW = dxGetTextWidth(pName, ui(1.2), "default")
        drawCrewTagBoxForPlayer(
            player,
            listX + ui(8) + nameW + ui(6),
            y + rowH / 2,
            ui(1.2),
            alpha,
            "left", "center"
        )

        local lvl = getElementData(player, "level") or 0
        dxDrawText(
            lvl,
            listX + listW - ui(8), y+(rowH/2),
            _,_, tocolor(255,255,255,alpha),
            ui(1.2), "default", "right", "center"
        )
    end
end
