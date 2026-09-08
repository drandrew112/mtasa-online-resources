--[[
    ui_phone / server/apps/myveh.lua
    Feeds the MyVeh app from v_ownveh and turns a row tap into a summon request.

      push       -> "myveh:list"  { { id, model, modelName, plate, isDestroyed, spawned }, ... }
      "myveh:request" (RPC)       summon vehicle <id> via v_ownveh, refuse when
                                  the player already has a personal vehicle out.
]]

local function ownvehReady()
    local res = getResourceFromName("v_ownveh")
    return res and getResourceState(res) == "running"
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

local function push(player)
    if isElement(player) then
        PhoneServer.push(player, "myveh:list", buildList(player))
    end
end

PhoneServer.onPull(function(player) push(player) end)

local REQUEST_ERRORS = {
    not_found          = "That vehicle no longer exists.",
    not_owner          = "That is not your vehicle.",
    destroyed          = "That vehicle is destroyed.",
    already_spawned    = "You already have a personal vehicle out.",
    no_free_spawnpoint = "No free spawn point nearby.",
    create_failed      = "Could not spawn the vehicle.",
    invalid_player     = "Could not request vehicle.",
}

PhoneServer.on("myveh:request", function(player, id)
    if not ownvehReady() then
        PhoneServer.toast(player, "Personal vehicles are unavailable right now.")
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
        PhoneServer.toast(player, "That is not your vehicle.")
        push(player)
        return
    end

    if anySpawned then
        PhoneServer.toast(player, "You already have a personal vehicle out. Store it first.")
        push(player)
        return
    end

    local veh, err = exports.v_ownveh:spawnOwnedVehicle(player, id)
    if veh then
        PhoneServer.toast(player, "Personal vehicle requested.")
        PhoneServer.close(player)
    else
        PhoneServer.toast(player, REQUEST_ERRORS[err] or ("Could not request vehicle (" .. tostring(err) .. ")."))
    end
    push(player)
end)
