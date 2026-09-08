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
            modelName   = exports.v_ownveh:getModelName(v.model) or ("Vehicle " .. tostring(v.model)),
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
    not_found          = "That vehicle no longer exists.",
    not_owner          = "That is not your vehicle.",
    destroyed          = "That vehicle is destroyed.",
    already_spawned    = "You already have a personal vehicle out.",
    no_free_spawnpoint = "No free spawn point nearby.",
    create_failed      = "Could not spawn the vehicle.",
    invalid_player     = "Could not request vehicle.",
}

addEvent("ui_inac:requestPersonalVehicle", true)
addEventHandler("ui_inac:requestPersonalVehicle", root, function(id)
    local player = client
    if not isElement(player) then return end
    if not ownvehReady() then
        notify(player, "Error", "Personal vehicles are unavailable right now.")
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
        notify(player, "Error", "That is not your vehicle.")
        return
    end
    if anySpawned then
        notify(player, "Vehicle", "You already have a personal vehicle out. Store it first.")
        sendList(player)
        return
    end

    local veh, err = exports.v_ownveh:spawnOwnedVehicle(player, id)
    if veh then
        notify(player, "Vehicle", "Personal vehicle requested.")
    else
        notify(player, "Vehicle", REQUEST_ERRORS[err] or ("Could not request vehicle (" .. tostring(err) .. ")."))
    end
    sendList(player)
end)

addEvent("ui_inac:storePersonalVehicle", true)
addEventHandler("ui_inac:storePersonalVehicle", root, function()
    local player = client
    if not isElement(player) then return end
    if not ownvehReady() then
        notify(player, "Error", "Personal vehicles are unavailable right now.")
        return
    end

    local ok, err = exports.v_ownveh:storePersonalVehicle(player)
    if ok then
        notify(player, "Vehicle", "Personal vehicle stored.")
    elseif err == "not_spawned" then
        notify(player, "Vehicle", "You have no personal vehicle out.")
    elseif err == "occupied" then
        notify(player, "Vehicle", "Someone is still inside it.")
    else
        notify(player, "Vehicle", "Could not store vehicle.")
    end
end)
