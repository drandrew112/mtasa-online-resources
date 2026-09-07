-- crewTagBox.lua
--------------------------------------------------------------------------------
-- "Crew tag box": egy TEGLALAP alaku hatter, aminek a szine a crew szine
-- (crewColor element data), es a kozepen a crew tag (crewTag element data,
-- max ~4 karakter). Ha nincs crew tag ("" vagy nil), semmi nem rajzolodik ki.
--
-- A doboz MERETET NEM te adod meg, hanem a SZOVEG-SKALAT. Ugyanazt az erteket
-- add at, amit a dxDrawText-nek adnal a jatekos nevehez -- pl. a yoverlay-ben
-- ui(1.2) -> a tag pont akkora lesz, mint a nev, es olvashato. A doboz szelesseget
-- / magassagat a fuggveny szamolja ki a szoveg kore (a 4 karakter kenyelmesen elfer).
--
-- Minden ertek valodi kepernyo-pixel / dx-skala: a fuggveny NEM hiv ui()-t.
--
-- Exportok (client):
--   drawCrewTagBox(x, y, textScale, crewTag, crewColor, alpha, alignX, alignY)
--   drawCrewTagBoxForPlayer(player, x, y, textScale, alpha, alignX, alignY)
--   getCrewTagBoxSize(crewTag, textScale)   -> boxW, boxH   (0,0 ha nincs tag)
--
--   x, y        a horgonypont; hogy a doboz hova esik hozza kepest, az alignX/alignY donti el
--   textScale   dx szoveg-skala a taghez (add at ugyanazt, amit a nevhez hasznalsz)
--   crewTag     string (vagy number); "" / nil  ->  nem rajzol, 0,0-t ad vissza
--   crewColor   {r,g,b} vagy {r=,g=,b=} tabla (a "crewColor" element data);
--               nil  ->  semleges szurke
--   alpha       0-255, opcionalis, alap 255 (ezzel halvanyithatod a HUD-dal egyutt)
--   alignX      "left" (alap) | "center" | "right"   -- a doboz vizszintesen x-hez kepest
--   alignY      "top"  (alap) | "center" | "bottom"  -- a doboz fuggolegesen y-hoz kepest
--
-- Visszateres: a kirajzolt doboz szelessege es magassaga (boxW, boxH), vagy 0,0
-- ha nem volt tag. A szelesseggel konnyen tovabb tudsz pakolni mellette.
--------------------------------------------------------------------------------

local BOX_FONT = "default-bold"
local NEUTRAL  = { 130, 130, 130 }

-- crewColor lehet {r,g,b} vagy {r=,g=,b=} alaku is
local function normColour(c)
    if type(c) == "table" then
        local r = tonumber(c[1] or c.r)
        local g = tonumber(c[2] or c.g)
        local b = tonumber(c[3] or c.b)
        if r and g and b then
            return math.max(0, math.min(255, r)),
                   math.max(0, math.min(255, g)),
                   math.max(0, math.min(255, b))
        end
    end
    return NEUTRAL[1], NEUTRAL[2], NEUTRAL[3]
end

-- Vilagos dobozra sotet, sotet dobozra vilagos tag-szoveg (kontraszt miatt).
local function readableText(r, g, b, a)
    local luma = 0.299 * r + 0.587 * g + 0.114 * b
    if luma > 150 then
        return tocolor(20, 20, 20, a)
    end
    return tocolor(245, 245, 245, a)
end

-- A doboz merete a szoveg kore, a megadott skalan.
local function boxMetrics(crewTag, textScale)
    local th   = dxGetFontHeight(textScale, BOX_FONT)
    local tw   = dxGetTextWidth(crewTag, textScale, BOX_FONT)
    local padX = math.max(4, th * 0.40)
    local padY = math.max(2, th * 0.16)
    return math.ceil(tw + padX * 2), math.ceil(th + padY * 2)
end

function getCrewTagBoxSize(crewTag, textScale)
    if type(crewTag) == "number" then crewTag = tostring(crewTag) end
    if type(crewTag) ~= "string" or crewTag == "" then return 0, 0 end
    return boxMetrics(crewTag, textScale or 1)
end

function drawCrewTagBox(x, y, textScale, crewTag, crewColor, alpha, alignX, alignY)
    if type(crewTag) == "number" then crewTag = tostring(crewTag) end
    if type(crewTag) ~= "string" or crewTag == "" then return 0, 0 end
    textScale = textScale or 1
    alpha = alpha or 255
    if alpha <= 0 then return 0, 0 end

    local w, h = boxMetrics(crewTag, textScale)

    if alignX == "center" then x = x - w / 2
    elseif alignX == "right" then x = x - w end
    if alignY == "center" then y = y - h / 2
    elseif alignY == "bottom" then y = y - h end

    local r, g, b = normColour(crewColor)

    -- kitoltes
    dxDrawRectangle(x, y, w, h, tocolor(r, g, b, alpha))

    -- vekony, sotetebb keret, hogy a halvany crew szinek is elvaljanak a hattertol
    local edge = math.max(1, h * 0.09)
    local br, bg, bb = r * 0.55, g * 0.55, b * 0.55
    dxDrawRectangle(x, y, w, edge, tocolor(br, bg, bb, alpha))
    dxDrawRectangle(x, y + h - edge, w, edge, tocolor(br, bg, bb, alpha))
    dxDrawRectangle(x, y, edge, h, tocolor(br, bg, bb, alpha))
    dxDrawRectangle(x + w - edge, y, edge, h, tocolor(br, bg, bb, alpha))

    -- 1px arnyek az olvashatosagert, majd maga a tag
    dxDrawText(crewTag, x + 1, y + 1, x + w + 1, y + h + 1,
        tocolor(0, 0, 0, alpha * 0.45), textScale, BOX_FONT, "center", "center")
    dxDrawText(crewTag, x, y, x + w, y + h,
        readableText(r, g, b, alpha), textScale, BOX_FONT, "center", "center")

    return w, h
end

function drawCrewTagBoxForPlayer(player, x, y, textScale, alpha, alignX, alignY)
    if not isElement(player) then return 0, 0 end
    return drawCrewTagBox(
        x, y, textScale,
        getElementData(player, "crewTag"),
        getElementData(player, "crewColor"),
        alpha, alignX, alignY
    )
end
