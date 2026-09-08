UI.yOverlay = {
    active = false,
    startTick = 0,
    duration = 10000,
    fadeTime = 1000,

    -- Csak a szint sav rovid megjelenitesehez (pl. XP szerzeskor).
    levelOnly = {
        active = false,
        startTick = 0,
        duration = 3000,
        fadeTime = 400,
    },
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

-- Idozites -> alpha (0..255) egy {startTick, duration, fadeTime} allapotbol.
local function fadeAlpha(state)
    local elapsed = getTickCount() - state.startTick

    local a
    if elapsed < state.fadeTime then
        a = elapsed / state.fadeTime * 255
    elseif elapsed > state.duration - state.fadeTime then
        a = (state.duration - elapsed) / state.fadeTime * 255
    else
        a = 255
    end

    return math.max(0, math.min(255, a))
end

local function getAlpha()
    return fadeAlpha(UI.yOverlay)
end

-- =========================
-- TOP CENTER – LEVEL / XP sav
-- =========================
local function drawLevelBar(alpha)
    local tc = UI.slots.topCenter
    local level    = tonumber(getElementData(localPlayer, "level")) or 0
    local next_lvl = level + 1
    local xp       = tonumber(getElementData(localPlayer, "xp")) or 0
    local next_xp  = tonumber(getElementData(localPlayer, "next_xp")) or 1
    local prev_xp  = tonumber(getNextXp(level-1)) or 0

    local barW = ui(300)
    local barX = tc.x - barW/2
    local barY = tc.y + ui(25)

    local span = next_xp - prev_xp
    local fill = (span > 0) and math.min(1, math.max(0, (xp-prev_xp)/span)) or 0

    dxDrawRectangle(barX, barY, barW, ui(10), tocolor(0,0,0,alpha))
    dxDrawRectangle(barX, barY, barW * fill, ui(10), tocolor(80,180,255,alpha))

    dxDrawText(level, barX - ui(10), barY+ui(5), _,_, tocolor(255,255,255,alpha), ui(1.4), "pricedown", "right", "center")
    dxDrawText(next_lvl, barX + barW + ui(10), barY+ui(5), _,_, tocolor(255,255,255,alpha), ui(1.4), "pricedown", "left", "center")
    dxDrawText(xp.."/"..next_xp, tc.x, barY + ui(15), _,_, tocolor(220,220,220,alpha), ui(1.2), "arial", "center", "top")
end

bindKey("y", "down", function()
    if UI.yOverlay.active then return end
    UI.yOverlay.active = true
    UI.yOverlay.startTick = getTickCount()
end)

-- ui_core export: rovid ideig (3 mp) megmutatja csak a szint savot.
function UI.yOverlay:showLevelOnly()
    self.levelOnly.active = true
    self.levelOnly.startTick = getTickCount()
end

function UI.yOverlay:drawLevelOnly()
    local lo = self.levelOnly
    if not lo.active then return end

    -- ha a teljes Y overlay is fut, az rajzolja a savot, ne duplazzuk
    if self.active then return end

    if getTickCount() > lo.startTick + lo.duration then
        lo.active = false
        return
    end

    if getElementData(localPlayer, "hideHUD") then return end

    drawLevelBar(fadeAlpha(lo))
end

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
    -- TOP RIGHT – MONEY (cash + bank)
    -- =========================
    local tr = UI.slots.topRight

    local scale  = 1.3
    local rx     = tr.x - ui(10)
    local lx     = rx - ui(400)
    local lh     = ui(28)
    local soff   = ui(2)
    local shadow = tocolor(0, 0, 0, alpha / 255 * 160)

    local cash = getPlayerMoney(localPlayer)
    local bank = tonumber(getElementData(localPlayer, "bank_money")) or 0

    -- cash (getPlayerMoney)
    do
        local ty = tr.y
        local color = tocolor(50, 200, 50, alpha)
        dxDrawText("$ "..formatMoney(cash), lx + soff, ty + soff, rx + soff, ty + lh + soff,
            shadow, scale, "pricedown", "right", "top")
        dxDrawText("$ "..formatMoney(cash), lx, ty, rx, ty + lh,
            color, scale, "pricedown", "right", "top")
    end

    -- bank (elementdata bank_money)
    do
        local ty = tr.y + lh
        local color = tocolor(120, 180, 255, alpha)
        dxDrawText("$ "..formatMoney(bank), lx + soff, ty + soff, rx + soff, ty + lh + soff,
            shadow, scale, "pricedown", "right", "top")
        dxDrawText("$ "..formatMoney(bank), lx, ty, rx, ty + lh,
            color, scale, "pricedown", "right", "top")
    end

    -- =========================
    -- TOP CENTER – LEVEL / XP
    -- =========================
    drawLevelBar(alpha)

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
