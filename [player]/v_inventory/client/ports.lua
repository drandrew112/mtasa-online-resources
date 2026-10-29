-- Port markers: the 3D cards over the ports this player sees (ui_core marker UIs, registered here
-- from the list the server sends, inv:ports) and the E key while standing in one.

local ports = {}       -- the visible ports (server data)
local byUi = {}        -- ui id -> port
local current          -- the port the player stands in

local function holdsContainer()
    for _, slot in ipairs(INV.SLOTS) do
        if Hud[slot] and Hud[slot].cap then return true end
    end
    return false
end

local function cardMeta(holds)
    if holds then return { hint = L.msg("v_inventory.ui.port_hint_open", { key = INV.KEY_PORT:upper() }) } end
    return { hint = L.msg("v_inventory.ui.port_hint_container"), color = { 255, 140, 130 } }
end

local cardsHolding = false
local function registerCards()
    for id in pairs(byUi) do exports.ui_core:removeMarkerUI(id) end
    byUi, current = {}, nil
    for _, port in ipairs(ports) do
        local id = "port:" .. tostring(port.id)
        local ok = exports.ui_core:createMarkerUI(id, {
            type = "inv_port", color = port.color or INV.PORT_COLOR, icon = port.icon or "P",
            x = port.x, y = port.y, z = port.z, interior = port.int, dimension = port.dim,
            size = port.radius * 2 + 0.2,   -- inside = within radius + 0.6
            name = L.msg("v_inventory.ui.port_sub", { name = port.name or "" }),
            title = port.title or L.msg("v_inventory.ui.storage"),
            radius = INV.PORT_LABEL_DISTANCE, fullRadius = INV.PORT_LABEL_FULL_DISTANCE,
            minScale = INV.PORT_LABEL_MIN_SCALE, height = INV.PORT_LABEL_HEIGHT,
        })
        if ok then
            byUi[id] = port
            exports.ui_core:setMarkerUIMeta(id, cardMeta(cardsHolding))
        end
    end
end

addEvent("inv:ports", true)
addEventHandler("inv:ports", resourceRoot, function(list)
    ports = type(list) == "table" and list or {}
    registerCards()
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("inv:requestPorts", resourceRoot)
end)

addEvent("onClientMarkerUISystemStart")
addEventHandler("onClientMarkerUISystemStart", root, registerCards)

addEvent("onClientMarkerUIHit")
addEventHandler("onClientMarkerUIHit", resourceRoot, function(id)
    if byUi[id] then current = byUi[id] end
end)

addEvent("onClientMarkerUILeave")
addEventHandler("onClientMarkerUILeave", resourceRoot, function(id)
    if current and byUi[id] == current then current = nil end
end)

-- hidden cards while the inventory window / HUD is off; the hint follows the held container
local cardsHidden = false
setTimer(function()
    local hide = (not TextsLoaded or WindowOpen or getElementData(localPlayer, "hideHUD")) and true or false
    if hide ~= cardsHidden then
        cardsHidden = hide
        exports.ui_core:setMarkerUIsHidden(hide)
    end
    local holds = holdsContainer()
    if holds ~= cardsHolding then
        cardsHolding = holds
        for id in pairs(byUi) do exports.ui_core:setMarkerUIMeta(id, cardMeta(holds)) end
    end
end, 250, 0)

-- ---------------------------------------------------------------------------------------------
-- E in the marker
-- ---------------------------------------------------------------------------------------------

local lastOpen = 0
bindKey(INV.KEY_PORT, "down", function()
    if not current or WindowOpen or not TextsLoaded then return end
    if isCursorShowing() or OtherPanelOpen() or isPedInVehicle(localPlayer) or isPedDead(localPlayer) then return end
    if getTickCount() - lastOpen < 600 then return end
    lastOpen = getTickCount()
    triggerServerEvent("inv:openPort", resourceRoot, current.id)
end)
