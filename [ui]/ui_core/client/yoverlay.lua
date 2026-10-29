if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
UI.yOverlay = {
    active = false,
    startTick = 0,
    duration = 10000,
    fadeTime = 1000,

    -- Csak a szint sav rovid megjelenitesehez (pl. XP szerzeskor).
    levelOnly = {
        active = false,
        startTick = 0,
        duration = 6000,
        fadeTime = 400,
    },

    -- Penzmozgasok rovid megjelenitese, tipusonkent kulon blokk: "cash" (zold)
    -- felul, "bank" (kek) alatta - egyszerre mindketto latszhat. Egy blokk =
    -- egyenleg sor + alatta a valtozas sorok (legujabb felul, a regiek lefele
    -- tolodnak). Azonos iranyu mozgas a legujabb sorba adodik amig az meg teljesen
    -- latszik; ellenkezo iranyu (levonasra hozzaadas / forditva) uj sort nyit.
    moneyOnly = {
        duration = 4000, -- egy valtozas sor elettartama (ms), osszeadaskor ujraindul
        fadeTime = 400,
        maxRows  = 4,    -- valtozas sorok blokkonkent; a legregebbi esik ki
        lastTick = 0,
        cash = { entries = {} },
        bank = { entries = {} },
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

-- =========================
-- TOP RIGHT – MONEY sorok
-- =========================
local MONEY_SCALE = 1.3

local function moneyMetrics()
    local tr = UI.slots.topRight
    local rx = tr.x - ui(10)
    local lx = rx - ui(400)
    return tr, lx, rx, ui(28)
end

-- A pricedown fontban nincs € jel, ezert az elotag ("€", "+ €", "- €")
-- default-bold fonttal megy, a szam pricedown-nal; a ketto egy dobozba
-- kozepre igazitva, egymas mellett.
local MONEY_PREFIX_FONT = "default-bold"

local function drawShadowed(text, x1, y1, x2, y2, color, shadow, soff, scale, font, alignX)
    dxDrawText(text, x1 + soff, y1 + soff, x2 + soff, y2 + soff, shadow, scale, font, alignX, "center")
    dxDrawText(text, x1, y1, x2, y2, color, scale, font, alignX, "center")
end

-- Egy jobbra igazitott, arnyekolt penz-sor ("€ 1,234" / "+ € 100").
-- Visszaadja a sormagassagot.
local function drawMoneyRow(text, ty, color, alpha, scale)
    local _, lx, rx, lh = moneyMetrics()
    scale = scale or MONEY_SCALE
    local soff = ui(2)
    local shadow = tocolor(0, 0, 0, alpha / 255 * 160)

    local prefix, amount = text:match("^(.-)%s*([%d,%.]+)$")
    if not prefix then prefix, amount = "", text end

    local boxH = dxGetFontHeight(scale, "pricedown")
    local y2 = ty + boxH
    drawShadowed(amount, lx, ty, rx, y2, color, shadow, soff, scale, "pricedown", "right")

    if prefix ~= "" then
        -- a default-bold kisebb, felskalazzuk hogy nagyjabol a szamjegyek magassagat hozza
        local pScale = scale * 0.62 * boxH / dxGetFontHeight(scale, MONEY_PREFIX_FONT)
        local pRx = rx - L.width(amount, scale, "pricedown") - ui(6)
        drawShadowed(prefix, lx, ty, pRx, y2, color, shadow, soff, pScale, MONEY_PREFIX_FONT, "right")
    end
    return lh
end

-- =========================
-- PLAYER LIST – admin kartya (mint a v_nametags-ben)
-- =========================
-- a rang feliratok es szinek a v_nametags locale kulcsaibol, pl. "#000000[#BAFFBAADMIN#000000] #FF0000":
-- a szin a "[" utani kod, a felirat a sima szoveg. Elso rajzolaskor epul (a szovegek akkor mar betoltve).
local adminTitles
local function getAdminTitle(level)
    if not adminTitles then
        adminTitles = {}
        local keys = { "trial_mod", "mod", "admin", "superadmin", "dev", "owner" }
        for lvl, key in ipairs(keys) do
            local raw = L("v_nametags.sourcec." .. key)
            local hex = raw:match("%[#(%x%x%x%x%x%x)") or "FFFFFF"
            local text = raw:gsub("#%x%x%x%x%x%x", ""):gsub("[%[%]]", ""):gsub("^%s+", ""):gsub("%s+$", "")
            adminTitles[lvl] = {
                text = text,
                r = tonumber(hex:sub(1, 2), 16), g = tonumber(hex:sub(3, 4), 16), b = tonumber(hex:sub(5, 6), 16),
            }
        end
    end
    return adminTitles[level]
end

local CARD_S, CARD_FONT = 1.0, "default-bold"

local function drawOutline(x, y, w, h, color)
    dxDrawRectangle(x, y, w, 1, color)
    dxDrawRectangle(x, y + h - 1, w, 1, color)
    dxDrawRectangle(x, y, 1, h, color)
    dxDrawRectangle(x + w - 1, y, 1, h, color)
end

-- szolgalatban teli (rang szinu) kartya, egyebkent sotet kartya rang szinu kerettel
local function drawAdminCard(title, duty, x, cy, w, alpha)
    local s = ui(CARD_S)
    local h = dxGetFontHeight(s, CARD_FONT) + ui(2)
    local y = cy - h / 2
    if duty then
        dxDrawRectangle(x, y, w, h, tocolor(title.r, title.g, title.b, alpha))
        dxDrawText(title.text, x, y, x + w, y + h,
            tocolor(title.r * 0.15, title.g * 0.15, title.b * 0.15, alpha), s, CARD_FONT, "center", "center")
    else
        dxDrawRectangle(x, y, w, h, tocolor(0, 0, 0, alpha / 255 * 120))
        drawOutline(x, y, w, h, tocolor(title.r, title.g, title.b, alpha))
        dxDrawText(title.text, x, y, x + w, y + h,
            tocolor(title.r, title.g, title.b, alpha), s, CARD_FONT, "center", "center")
    end
end

function setBindForYOverlay()
    bindKey("y", "down", function()
        if UI.yOverlay.active then return end
        UI.yOverlay.active = true
        UI.yOverlay.startTick = getTickCount()
    end)
end
addEvent("onClientPlayerLoaded", true)
addEventHandler("onClientPlayerLoaded", localPlayer, setBindForYOverlay)
addEventHandler("onClientResourceStart", resourceRoot, function()
    if getElementData(localPlayer, "loaded") then
        setBindForYOverlay()
    end
end)

-- ui_core export: rovid ideig megmutatja az egyenleget es alatta a valtozast
-- (+ € 100 zolddel, - € 100 pirossal).
--   kind      = "add" vagy "take"
--   moneyType = "cash" (keszpenz, getPlayerMoney) vagy "bank" (bank_money)
-- Az ellenorzes az exports.lua-ban van, ide mar ervenyes ertek jon.
local MONEY_TYPES = { "cash", "bank" }
local MONEY_COLORS = {
    cash = { 50, 200, 50 },
    bank = { 120, 180, 255 },
}

function UI.yOverlay:showMoney(kind, change, moneyType)
    local mo = self.moneyOnly
    local block = mo[moneyType]
    if not block then return false end

    local amount = math.floor(math.abs(tonumber(change) or 0))
    if amount == 0 then return false end
    local sign = (kind == "take") and -1 or 1
    local now = getTickCount()

    local last = block.entries[1]
    if last and last.sign == sign and now < last.startTick + last.duration - last.fadeTime then
        -- azonos irany, meg teljesen latszik: osszeadjuk, ujrainditjuk fade-in nelkul
        last.amount = last.amount + amount
        last.startTick = now - last.fadeTime
    else
        table.insert(block.entries, 1, {
            sign = sign, amount = amount,
            startTick = now, duration = mo.duration, fadeTime = mo.fadeTime,
        })
        while #block.entries > mo.maxRows do
            table.remove(block.entries)
        end
    end
    return true
end

local function moneyBalance(moneyType)
    if moneyType == "bank" then
        return tonumber(getElementData(localPlayer, "bank_money")) or 0
    end
    return getPlayerMoney(localPlayer)
end

-- Sima mozgas a cel y fele; nil (uj sor) -> rogton a celra ugrik.
local function approach(cur, target, k)
    if not cur then return target end
    return cur + (target - cur) * k
end

-- A jobb felso penz-oszlop: blokkonkent egyenleg + valtozas sorok, egymas alatt.
-- balanceAlpha: ha meg van adva (teljes Y overlay), mindket egyenleg sor ezzel
-- latszik akkor is, ha nincs hozza valtozas; kulonben egy blokk csak akkor
-- latszik, ha van elo valtozas sora, es annak alpha-jat koveti.
local function drawMoneyStack(mo, balanceAlpha)
    local now = getTickCount()
    local dt = (mo.lastTick > 0) and math.min(now - mo.lastTick, 100) or 0
    mo.lastTick = now
    local k = 1 - math.exp(-dt / 70)

    local tr = moneyMetrics()
    local y = tr.y
    for _, moneyType in ipairs(MONEY_TYPES) do
        local block = mo[moneyType]
        local entries = block.entries
        for i = #entries, 1, -1 do
            if now > entries[i].startTick + entries[i].duration then
                table.remove(entries, i)
            end
        end

        if balanceAlpha or #entries > 0 then
            local alpha = balanceAlpha or 0
            if not balanceAlpha then
                for _, e in ipairs(entries) do alpha = math.max(alpha, fadeAlpha(e)) end
            end

            block.y = approach(block.y, y, k)
            local c = MONEY_COLORS[moneyType]
            y = y + drawMoneyRow("€ "..formatMoney(moneyBalance(moneyType)), block.y, tocolor(c[1], c[2], c[3], alpha), alpha)

            for _, e in ipairs(entries) do
                local a = fadeAlpha(e)
                local prefix, col
                if e.sign < 0 then
                    prefix, col = "- € ", tocolor(230, 60, 60, a)
                else
                    prefix, col = "+ € ", tocolor(60, 210, 60, a)
                end
                e.y = approach(e.y, y, k)
                y = y + drawMoneyRow(prefix..formatMoney(e.amount), e.y, col, a, MONEY_SCALE * 0.85)
            end
        else
            block.y = nil
        end
    end
end

function UI.yOverlay:drawMoneyOnly()
    -- ha a teljes Y overlay is fut, az rajzolja a penzt, ne duplazzuk
    if self.active then return end

    local mo = self.moneyOnly
    if #mo.cash.entries == 0 and #mo.bank.entries == 0 then
        mo.lastTick = 0
        return
    end
    if getElementData(localPlayer, "hideHUD") then return end

    drawMoneyStack(mo)
end

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
    -- TOP RIGHT – MONEY (cash + bank, alattuk az elo valtozasok)
    -- =========================
    drawMoneyStack(self.moneyOnly, alpha)

    -- =========================
    -- TOP CENTER – LEVEL / XP
    -- =========================
    drawLevelBar(alpha)

    -- =========================
    -- LEFT – PLAYER LIST
    -- =========================
    local listX = UI.safe.x
    local listY = UI.safe.y
    local listW = ui(380)
    local rowH  = ui(30)

    local players = getElementsByType("player")

    -- oszlopok: [admin kartya] [zaszlo] nev - a kartya oszlop a leghosszabb latszo rang szelessege,
    -- igy a zaszlok es nevek egy vonalban vannak; ha nincs admin a listan, nincs kartya oszlop
    local cardW = 0
    for _, player in ipairs(players) do
        local title = getAdminTitle(tonumber(getElementData(player, "admin_level")) or 0)
        if title then
            cardW = math.max(cardW, L.width(title.text, ui(CARD_S), CARD_FONT) + ui(8))
        end
    end
    local flagW, flagH = ui(20), ui(14)
    local nameX = listX + ui(8) + ((cardW > 0) and (cardW + ui(6)) or 0) + flagW + ui(6)

    dxDrawRectangle(listX, listY, listW, rowH, tocolor(0,0,0,alpha))
    dxDrawText(
        L("ui_core.yoverlay.freev", { players = #players }),
        listX + ui(8), listY+(rowH/2),
        _,_, tocolor(255,255,255,alpha),
        ui(1.3), "default-bold", "left", "center"
    )
    dxDrawText(
        L("ui_core.yoverlay.lvl"),
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

        local title = getAdminTitle(tonumber(getElementData(player, "admin_level")) or 0)
        if title then
            drawAdminCard(title, getElementData(player, "adminDuty") == true, listX + ui(8), y + rowH / 2, cardW, alpha)
        end

        -- zaszlo a kartya es a nev kozott (amig nincs letoltve / ismeretlen orszag, ures hely)
        drawPlayerFlag(player, nameX - ui(6) - flagW, y + (rowH - flagH) / 2, flagW, flagH, alpha)

        local pName = getPlayerName(player)
        dxDrawText(
            pName,
            nameX, y+(rowH/2),
            _,_, tocolor(255,255,255,alpha),
            ui(1.2), "default", "left", "center"
        )

        -- crew tag box a név mellett jobbra, a névvel azonos betűméretben
        local nameW = L.width(pName, ui(1.2), "default")
        drawCrewTagBoxForPlayer(
            player,
            nameX + nameW + ui(6),
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
