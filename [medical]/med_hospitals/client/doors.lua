-- Staff-only hospital door: [E] hint (same box as the hospital PC hint) + E key while inside its area
-- (server side: doors/server/doors.lua)
local areaId, areaText

local function onKey() if areaId then triggerServerEvent("hosp:doorOpen", resourceRoot, areaId) end end

local function drawHint()
    if not areaText then return end
    local s = HGfx.s
    local f = HGfx.font(10, true)
    local w = L.width(areaText, 1, f) + s(30)
    local x, y = (HGfx.screenW - w) / 2, HGfx.screenH * 0.78
    HGfx.round(x, y, w, s(32), s(6), tocolor(14, 18, 22, 210))
    HGfx.text(areaText, x, y, w, s(32), HTheme.text, f, "center")
end

addEvent("hosp:doorArea", true)
addEventHandler("hosp:doorArea", resourceRoot, function(id, inside, text)
    removeEventHandler("onClientRender", root, drawHint)
    unbindKey("e", "down", onKey)
    if inside then
        areaId, areaText = id, text
        bindKey("e", "down", onKey)
        addEventHandler("onClientRender", root, drawHint)
    elseif areaId == id then
        areaId, areaText = nil, nil
    end
end)
