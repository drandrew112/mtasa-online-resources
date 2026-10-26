if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- world_clothes-shop / client/main.lua
-- Changer markers: press CLOTHES.key inside one to open the outfit list (ui_inac temp menu).
-- While the list is open the camera looks at the player from the front and the controls are
-- off. Hovering an outfit previews it on the local player only; it is always reverted when the
-- menu closes, a bought outfit then arrives from the server.
-- Feedback goes to the marker label (client/label.lua), not to notifications.

ChangerMarker = nil  -- changer marker the local player stands in
Status        = nil  -- { text, ok, untilTick } shown on the marker label

local menu = nil     -- { id, previewFrom, wornPath, selPath }

addEvent("ui_inac:tempMenuHover")
addEvent("ui_inac:tempMenuSelect")
addEvent("ui_inac:tempMenuClose")
addEvent("clothes:status", true)
addEvent("clothes:bought", true)

local function setStatus(text, ok)
    Status = { text = text, ok = ok, untilTick = getTickCount() + CLOTHES.statusMs }
end

---------------------------------------------------------------- camera

local function startCamera()
    local c = CLOTHES.camera
    local shop = CLOTHES.shopById[getElementData(ChangerMarker, "clothes:shop")]
    local int = shop and CLOTHES.interiors[shop.interior]
    local changer = int and int.changers[getElementData(ChangerMarker, "clothes:changer")]
    local px, py, pz = getElementPosition(localPlayer)
    local _, _, base = getElementRotation(localPlayer)
    base = changer and changer.rot or base

    -- The camera goes where there is room (the shop side, not the mirror / booth walls):
    -- try the configured facing, then the opposite and the sides, keep the most open one.
    -- The player faces the camera.
    local best
    for _, off in ipairs({ 0, 180, 90, 270 }) do
        local heading = (base + off) % 360
        local a = math.rad(heading + 90 + c.side)   -- heading + 90 = the ped's forward direction
        local cx, cy, cz = px + math.cos(a) * c.distance, py + math.sin(a) * c.distance, pz + c.height
        local hit, hx, hy, hz = processLineOfSight(px, py, cz, cx, cy, cz,
            true, false, false, true, false, false, false, false, localPlayer)
        local free = hit and getDistanceBetweenPoints3D(px, py, cz, hx, hy, hz) or c.distance
        if not best or free > best.free + 0.01 then
            best = { heading = heading, a = a, free = free }
        end
        if not hit then break end
    end

    local dist = math.min(c.distance, math.max(1, best.free - 0.3))
    setElementRotation(localPlayer, 0, 0, best.heading)
    setCameraMatrix(px + math.cos(best.a) * dist, py + math.sin(best.a) * dist, pz + c.height,
        px, py, pz + c.lookHeight, 0, c.fov)
    toggleAllControls(false, true, false)
end

local function stopCamera()
    setCameraTarget(localPlayer)
    toggleAllControls(true, true, false)
end

---------------------------------------------------------------- preview

local function preview(model)
    if not menu then return end
    model = model or menu.previewFrom
    if getElementModel(localPlayer) ~= model then setElementModel(localPlayer, model) end
end

local function closeMenu()
    if not menu then return end
    preview(nil)
    if exports.ui_inac:isTempMenuOpen() then exports.ui_inac:closeTempMenu() end
    menu = nil
    stopCamera()
end

function isClothesMenuOpen() return menu ~= nil end

---------------------------------------------------------------- menu

local GROUPS = {}

-- Texts load only once the player is loaded (v_loading gate).
local textsLoaded = false
local function loadTexts()
    if textsLoaded then return end
    textsLoaded = true
    GROUPS = {
        { key = "male",   label = L("world_clothes_shop.main.men"),   title = L("world_clothes_shop.main.men_2") },
        { key = "female", label = L("world_clothes_shop.main.women"), title = L("world_clothes_shop.main.women_2") },
    }
    exports.v_loading:resourceReady()
end
addEvent("onClientLoadingStarted", true)
addEventHandler("onClientLoadingStarted", root, loadTexts)
-- also when this resource started after the loading screen appeared (v_loading asks again)
addEvent("onClientReadyCheck")
addEventHandler("onClientReadyCheck", root, loadTexts)
addEventHandler("onClientResourceStart", resourceRoot, function()
    if getElementData(localPlayer, "loaded") then loadTexts() end
end)

local function openMenu()
    local current, wornPath = getElementModel(localPlayer), nil
    local groups = {}
    for g, group in ipairs(GROUPS) do
        local items = {}
        for i, skin in ipairs(CLOTHES.skins[group.key]) do
            local own = skin == current
            if own then wornPath = g .. "/" .. i end
            items[i] = {
                label = L("world_clothes_shop.main.outfit", { skin = skin }), desc = L("world_clothes_shop.main.buy_and_wear_this_outfit"), value = skin,
                price = CLOTHES.gross(), checked = own or nil, closeOnSelect = false,
            }
        end
        groups[g] = { label = group.label, desc = L("world_clothes_shop.main.s_outfits", { label = group.label }), title = group.title, items = items }
    end
    local id = exports.ui_inac:createTempMenu({ title = L("world_clothes_shop.main.clothes"), items = groups })
    if not id then return end
    menu = { id = id, previewFrom = current, wornPath = wornPath }
    Status = nil
    startCamera()
end

local function onKey()
    if menu then closeMenu() return end
    if not isElement(ChangerMarker) or isCursorShowing() or isChatBoxInputActive() then return end
    if isPedInVehicle(localPlayer) or isPedDead(localPlayer) then return end
    openMenu()
end

---------------------------------------------------------------- markers

addEventHandler("onClientMarkerHit", resourceRoot, function(hit, matchingDim)
    if hit ~= localPlayer or not matchingDim or not getElementData(source, "clothes:shop") then return end
    ChangerMarker = source
    Status = nil
    bindKey(CLOTHES.key, "down", onKey)
end)

addEventHandler("onClientMarkerLeave", resourceRoot, function(left)
    if left ~= localPlayer or source ~= ChangerMarker then return end
    ChangerMarker = nil
    unbindKey(CLOTHES.key, "down", onKey)
    closeMenu()
end)

---------------------------------------------------------------- ui_inac events

addEventHandler("ui_inac:tempMenuHover", root, function(id, value)
    if not menu or id ~= menu.id then return end
    preview(tonumber(value))
end)

addEventHandler("ui_inac:tempMenuSelect", root, function(id, value, path)
    if not menu or id ~= menu.id or not tonumber(value) then return end
    menu.selPath = path
    triggerServerEvent("clothes:buy", resourceRoot, tonumber(value))
end)

addEventHandler("ui_inac:tempMenuClose", root, function(id)
    if not menu or id ~= menu.id then return end
    preview(nil)
    menu = nil
    stopCamera()
end)

---------------------------------------------------------------- server replies

addEventHandler("clothes:status", resourceRoot, function(text)
    setStatus(tostring(text or ""), false)
end)

-- The outfit is bought: it becomes the menu's base model and the list marks it as worn
addEventHandler("clothes:bought", resourceRoot, function(skin)
    setStatus(L("world_clothes_shop.main.outfit_bought", { price = CLOTHES.gross() }), true)
    if not menu then return end
    menu.previewFrom = skin
    if menu.wornPath then exports.ui_inac:updateTempMenuItem(menu.wornPath, { checked = false }) end
    if menu.selPath then exports.ui_inac:updateTempMenuItem(menu.selPath, { checked = true }) end
    menu.wornPath = menu.selPath
end)

addEventHandler("onClientPlayerWasted", localPlayer, closeMenu)
addEventHandler("onClientResourceStop", resourceRoot, closeMenu)
