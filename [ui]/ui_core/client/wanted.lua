-- Wanted (korozes) csillagok a jobb felso sarokban, a GTA SA alap wanted szintjevel.
-- Onallo onClientRender: csak a wanted-del foglalkozik.
-- Jobbrol balra toltodik: az n. szint az n db legjobboldalibb csillagot aktivalja.

local MAX_STARS = 6
local STAR_SIZE = 26 -- ui() px
local STAR_GAP  = 4  -- ui() px

local getPlayerWantedLevel = getPlayerWantedLevel
local getTickCount = getTickCount
local getElementData = getElementData
local dxDrawImage = dxDrawImage
local tocolor = tocolor

local texGrey, texWhite
local colWhite = tocolor(255, 255, 255, 255)
local colRed   = tocolor(255, 90, 90, 255)
local colBlue  = tocolor(90, 140, 255, 255)

local blinkOn, blinkPeriod = false, 500
local starSize, starGap, startX, startY, rowH

local function layout()
    local tr = UI.slots.topRight
    starSize = ui(STAR_SIZE)
    starGap  = ui(STAR_GAP)
    rowH     = starSize + ui(8) -- ennyivel kerulnek lentebb a tobbi jobb felso elemek
    startY   = tr.y
    startX   = tr.x - ui(10) - (MAX_STARS * starSize + (MAX_STARS - 1) * starGap)
end

-- Mennyivel kell lejjebb tolni a jobb felso oszlopot (0, ha nincs korozes).
-- A yoverlay.lua hivja.
function UI.getWantedOffset()
    if not starSize or getPlayerWantedLevel() <= 0 then return 0 end
    return rowH
end

local function renderWanted()
    local level = getPlayerWantedLevel()
    if level <= 0 or not texGrey then return end
    if getElementData(localPlayer, "hideHUD") then return end

    -- villogas: csak az aktiv csillagok
    local active = true
    if blinkOn then
        active = (getTickCount() % blinkPeriod) < blinkPeriod / 2
    end

    local firstActive = MAX_STARS - level + 1
    local step = starSize + starGap
    local x, y = startX, startY
    for i = 1, MAX_STARS do
        if i < firstActive then
            dxDrawImage(x, y, starSize, starSize, texGrey, 0, 0, 0, colWhite)
        elseif active then
            dxDrawImage(x, y, starSize, starSize, texWhite, 0, 0, 0, colWhite)
        else
            dxDrawImage(x, y, starSize, starSize, texGrey, 0, 0, 0, colWhite)
        end
        x = x + step
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    texGrey  = dxCreateTexture("client/images/star_grey.png", "argb", true, "clamp")
    texWhite = dxCreateTexture("client/images/star_white.png", "argb", true, "clamp")
    layout()
    addEventHandler("onClientRender", root, renderWanted, false)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if isElement(texGrey) then destroyElement(texGrey) end
    if isElement(texWhite) then destroyElement(texWhite) end
end)

-- Export: setWantedBlinking(state [, periodMs])  - az aktiv csillagok villogasa (alap: ki, 500 ms)
function setWantedBlinking(state, periodMs)
    blinkOn = state and true or false
    periodMs = tonumber(periodMs)
    if periodMs and periodMs >= 100 then blinkPeriod = periodMs end
    return true
end

function isWantedBlinking()
    return blinkOn
end
