if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
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
            modelName   = exports.veh_manager:getModelName(v.model) or (L.msg("ui_phone.contacts.vehicle", { model = tostring(v.model) })),
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
    not_found          = L.msg("ui_phone.myveh.that_vehicle_no_longer_exists"),
    not_owner          = L.msg("ui_phone.myveh.that_is_not_your_vehicle"),
    destroyed          = L.msg("ui_phone.myveh.that_vehicle_is_destroyed"),
    already_spawned    = L.msg("ui_phone.myveh.you_already_have_personal_vehicle_out"),
    no_free_spawnpoint = L.msg("ui_phone.myveh.no_free_spawn_point_nearby"),
    create_failed      = L.msg("ui_phone.myveh.could_not_spawn_vehicle"),
    invalid_player     = L.msg("ui_phone.myveh.could_not_request_vehicle"),
}

PhoneServer.on("myveh:request", function(player, id)
    if not ownvehReady() then
        PhoneServer.toast(player, L.msg("ui_phone.myveh.personal_vehicles_are_unavailable_right_now"))
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
        PhoneServer.toast(player, L.msg("ui_phone.myveh.that_is_not_your_vehicle"))
        push(player)
        return
    end

    if anySpawned then
        PhoneServer.toast(player, L.msg("ui_phone.myveh.you_already_have_personal_vehicle_out_2"))
        push(player)
        return
    end

    local veh, err = exports.v_ownveh:spawnOwnedVehicle(player, id)
    if veh then
        PhoneServer.toast(player, L.msg("ui_phone.myveh.personal_vehicle_requested"))
        PhoneServer.close(player)
    else
        PhoneServer.toast(player, REQUEST_ERRORS[err] or (L.msg("ui_phone.myveh.could_not_request_vehicle_2", { err = tostring(err) })))
    end
    push(player)
end)
