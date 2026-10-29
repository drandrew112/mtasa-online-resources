if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- world_clothes-shop / client/label.lua
-- Marker UI of the changer markers. The cards are ui_core marker UIs (server/main.lua); this
-- file sets their client-side state as local meta while they are in range: the price, the
-- purchase result (green / red) and, while the outfit list is open, the card pinned to the
-- bottom of the screen (the camera looks at the player then).

local GREEN, RED = { 70, 190, 90 }, { 218, 54, 51 }

local near = {}   -- ui id -> marker, cards within range

-- same id as server/main.lua
local function uiId(m)
    return "c" .. tostring(getElementData(m, "clothes:shop")) .. ":" .. tostring(getElementData(m, "clothes:changer"))
end

local function metaFor(marker)
    local price = CLOTHES.gross()
    local meta = {
        hint = L("world_clothes_shop.label.outfits_each", { price = price }),
        hintActive = L("world_clothes_shop.label.press_browse_outfits_each", { key = CLOTHES.key:upper(), price = price }),
    }
    if marker ~= ChangerMarker then return meta end
    if Status and getTickCount() < Status.untilTick then
        meta.color = Status.ok and GREEN or RED
        meta.hint, meta.hintActive = Status.text, Status.text
    elseif isClothesMenuOpen() then
        local text = L("world_clothes_shop.label.every_outfit_enter_buy_backspace_back", { price = price })
        meta.hint, meta.hintActive = text, text
    end
    meta.pinned = isClothesMenuOpen() or nil
    return meta
end

-- called by client/main.lua whenever the state changes
function refreshClothesLabels()
    for id, m in pairs(near) do
        if isElement(m) then exports.ui_core:setMarkerUIMeta(id, metaFor(m)) else near[id] = nil end
    end
end

addEvent("onClientMarkerUIStreamIn")
addEventHandler("onClientMarkerUIStreamIn", resourceRoot, function(id)
    for _, m in ipairs(getElementsByType("marker", resourceRoot)) do
        if getElementData(m, "clothes:shop") and uiId(m) == id then
            near[id] = m
            exports.ui_core:setMarkerUIMeta(id, metaFor(m))
            return
        end
    end
end)

addEvent("onClientMarkerUIStreamOut")
addEventHandler("onClientMarkerUIStreamOut", resourceRoot, function(id) near[id] = nil end)

L.onChange(refreshClothesLabels)
