if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Depot menu (ui_inac temp menu). The server sends the options when the player presses the
-- depot key inside a depot marker, and re-checks every pick. The 3D card above the marker is a
-- ui_core marker UI (server/depot.lua), hidden while the menu is open.

local inMarker = nil
local menuId = nil

addEventHandler("onClientMarkerHit", root, function(el, dim)
    if el ~= localPlayer or not dim or not getElementData(source, "rw.depot") then return end
    if isPedInVehicle(localPlayer) then return end
    inMarker = source
end)

addEventHandler("onClientMarkerLeave", root, function(el)
    if el ~= localPlayer or source ~= inMarker then return end
    inMarker = nil
    if menuId then
        exports.ui_inac:closeTempMenu()
        menuId = nil
        exports.ui_core:setMarkerUIsHidden(false)
    end
end)

bindKey(RW.DEPOT_KEY, "down", function()
    if not inMarker or menuId or isChatBoxInputActive() or isCursorShowing() then return end
    if exports.ui_inac:isTempMenuOpen() then return end
    triggerServerEvent("rw:depot:open", resourceRoot)
end)

addEvent("rw:depot:menu", true)
addEventHandler("rw:depot:menu", resourceRoot, function(data)
    if not inMarker then return end
    local serviceItems = {}
    for _, v in ipairs(data.services) do
        local label = ("%s %02d:%02d - %s"):format(v.number, math.floor(v.dep / 3600) % 24, math.floor(v.dep / 60) % 60, v.toName)
        if v.ok then
            serviceItems[#serviceItems + 1] = { label = label, value = { "apply", v.tripId }, desc = L("rw_core.depot.from_train_is_created_now", { name = v.name, from_name = v.fromName }) }
        else
            serviceItems[#serviceItems + 1] = { label = label, value = { "none" }, desc = L("rw_core.depot.not_available", { reason = tostring(v.reason) }) }
        end
    end
    if #serviceItems == 0 then
        serviceItems[1] = { label = L("rw_core.depot.no_service_available_now"), value = { "none" } }
    end

    local spawnItems = {}
    for _, s in ipairs(data.spawns) do
        local presets = {}
        for _, p in ipairs(data.presets) do
            presets[#presets + 1] = { label = p.name, value = { "spawn", s.id, p.id } }
        end
        spawnItems[#spawnItems + 1] = { label = s.name, title = s.name, items = presets }
    end

    local trainItems = {}
    for _, c in ipairs(data.consists) do
        local sub = {}
        for _, t in ipairs(data.carriageTypes) do
            sub[#sub + 1] = { label = L("rw_core.depot.add", { name = t.name:lower() }), value = { "add", c.id, t.id }, desc = L("rw_core.depot.coupled_to_end_of_train") }
        end
        if c.carriages > 0 then
            sub[#sub + 1] = { label = L("rw_core.depot.uncouple_last_carriage"), value = { "remove", c.id } }
        end
        sub[#sub + 1] = { label = L("rw_core.depot.send_to_shed_remove"), value = { "despawn", c.id } }
        trainItems[#trainItems + 1] = { label = c.label, title = c.number, items = sub }
    end
    if #trainItems == 0 then
        trainItems[1] = { label = L("rw_core.depot.no_train_at_this_depot"), value = { "none" } }
    end

    local items = {
        { label = L("rw_core.depot.services"), title = L("rw_core.depot.services"), desc = L("rw_core.depot.apply_for_service_your_train_is"), items = serviceItems },
        { label = L("rw_core.depot.trains_at_depot"), title = L("rw_core.depot.assembly"), desc = L("rw_core.depot.couple_uncouple_carriages"), items = trainItems },
    }
    if data.admin then
        items[#items + 1] = { label = L("rw_core.depot.new_train_admin"), title = L("rw_core.depot.spawn_point"), desc = L("rw_core.depot.assemble_free_train_on_free_track"), items = spawnItems }
    end
    menuId = exports.ui_inac:createTempMenu({ title = data.depot, items = items })
    if menuId then exports.ui_core:setMarkerUIsHidden(true) end
end)

addEvent("ui_inac:tempMenuSelect", false)
addEventHandler("ui_inac:tempMenuSelect", root, function(id, value)
    if id ~= menuId or type(value) ~= "table" then return end
    if value[1] ~= "none" then
        triggerServerEvent("rw:depot:action", resourceRoot, value[1], value[2], value[3])
    end
end)

addEvent("ui_inac:tempMenuClose", false)
addEventHandler("ui_inac:tempMenuClose", root, function(id)
    if id == menuId then
        menuId = nil
        exports.ui_core:setMarkerUIsHidden(false)
    end
end)
