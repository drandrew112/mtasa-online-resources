if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Bridges the interaction menu's personal-vehicle actions to v_ownveh.
--
--   ui_inac:requestPersonalVehicleList  -> send the player's owned vehicles
--   ui_inac:requestPersonalVehicle <id> -> summon it (refused if one is out)
--   ui_inac:storePersonalVehicle        -> store the vehicle currently out

local function ownvehReady()
    local res = getResourceFromName("v_ownveh")
    return res and getResourceState(res) == "running"
end

local function notify(player, title, text)
    triggerClientEvent(player, "ui_inac:notify", player, title, text)
end

local function ownedList(player)
    if not ownvehReady() then return {} end
    return exports.v_ownveh:getOwnedVehicles(player) or {}
end

local function buildList(player)
    local out = {}
    for _, v in ipairs(ownedList(player)) do
        out[#out + 1] = {
            id          = v.id,
            model       = v.model,
            modelName   = exports.veh_manager:getModelName(v.model) or (L.msg("ui_inac.vehicles.vehicle", { model = tostring(v.model) })),
            plate       = v.plate,
            isDestroyed = v.isDestroyed,
            spawned     = v.spawned,
        }
    end
    return out
end

local function sendList(player)
    if isElement(player) then
        triggerClientEvent(player, "ui_inac:personalVehicleList", player, buildList(player))
    end
end

addEvent("ui_inac:requestPersonalVehicleList", true)
addEventHandler("ui_inac:requestPersonalVehicleList", root, function()
    if isElement(client) then sendList(client) end
end)

local REQUEST_ERRORS = {
    not_found          = L.msg("ui_inac.ownveh.that_vehicle_no_longer_exists"),
    not_owner          = L.msg("ui_inac.ownveh.that_is_not_your_vehicle"),
    destroyed          = L.msg("ui_inac.ownveh.that_vehicle_is_destroyed"),
    already_spawned    = L.msg("ui_inac.ownveh.you_already_have_personal_vehicle_out"),
    no_free_spawnpoint = L.msg("ui_inac.ownveh.no_free_spawn_point_nearby"),
    create_failed      = L.msg("ui_inac.ownveh.could_not_spawn_vehicle"),
    invalid_player     = L.msg("ui_inac.ownveh.could_not_request_vehicle"),
}

addEvent("ui_inac:requestPersonalVehicle", true)
addEventHandler("ui_inac:requestPersonalVehicle", root, function(id)
    local player = client
    if not isElement(player) then return end
    if not ownvehReady() then
        notify(player, L.msg("ui_inac.main.error"), L.msg("ui_inac.ownveh.personal_vehicles_are_unavailable_right_now"))
        return
    end

    id = tonumber(id)
    if not id then return end

    local mine, anySpawned = false, false
    for _, v in ipairs(ownedList(player)) do
        if v.id == id then mine = true end
        if v.spawned then anySpawned = true end
    end

    if not mine then
        notify(player, L.msg("ui_inac.main.error"), L.msg("ui_inac.ownveh.that_is_not_your_vehicle"))
        return
    end
    if anySpawned then
        notify(player, L.msg("ui_inac.main.vehicle"), L.msg("ui_inac.ownveh.you_already_have_personal_vehicle_out_2"))
        sendList(player)
        return
    end

    local veh, err = exports.v_ownveh:spawnOwnedVehicle(player, id)
    if veh then
        notify(player, L.msg("ui_inac.main.vehicle"), L.msg("ui_inac.ownveh.personal_vehicle_requested"))
    else
        notify(player, L.msg("ui_inac.main.vehicle"), REQUEST_ERRORS[err] or (L.msg("ui_inac.ownveh.could_not_request_vehicle_2", { err = tostring(err) })))
    end
    sendList(player)
end)

addEvent("ui_inac:storePersonalVehicle", true)
addEventHandler("ui_inac:storePersonalVehicle", root, function()
    local player = client
    if not isElement(player) then return end
    if not ownvehReady() then
        notify(player, L.msg("ui_inac.main.error"), L.msg("ui_inac.ownveh.personal_vehicles_are_unavailable_right_now"))
        return
    end

    local ok, err = exports.v_ownveh:storePersonalVehicle(player)
    if ok then
        notify(player, L.msg("ui_inac.main.vehicle"), L.msg("ui_inac.ownveh.personal_vehicle_stored"))
    elseif err == "not_spawned" then
        notify(player, L.msg("ui_inac.main.vehicle"), L.msg("ui_inac.ownveh.you_have_no_personal_vehicle_out"))
    elseif err == "occupied" then
        notify(player, L.msg("ui_inac.main.vehicle"), L.msg("ui_inac.ownveh.someone_is_still_inside_it"))
    else
        notify(player, L.msg("ui_inac.main.vehicle"), L.msg("ui_inac.ownveh.could_not_store_vehicle"))
    end
end)
