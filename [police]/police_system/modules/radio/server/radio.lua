-- police_system / modules/radio/server/radio.lua
-- Radio.handle(player, id, args) is the only entry point of the radio messages (shared/radio.lua). The radio panel
-- (C), the F keys and the MDC call it through pol:radio; the later voice client through the radioCommand export.
-- args (optional): { target = element } (STATUS_PURSUIT), { confirm = true } (REQUEST_TOW of a police car).

local RD = POL.module("radio", {})

function RD.handle(player, id, args)
    if not isElement(player) or not POL.rights.has(player) or not RADIO_IDS[id] then return false, "bad" end
    args = type(args) == "table" and args or {}
    local unit = POL.units.of(player)
    if not unit then
        POL.notify(player, "police_system.radio.not_in_unit")
        return false, "not_in_unit"
    end
    local def = RADIO_IDS[id]
    POL.events.log(unit, player, "radio", { id = id })
    if id == "STATUS_PURSUIT" then
        local ok, err = POL.chase.start(player, args.target)
        if not ok then POL.notify(player, "police_system.chase.err_" .. tostring(err)) end
        return ok
    elseif def.status then
        return POL.units.setStatus(unit, def.status, player)
    elseif id == "CODE_4" then
        -- the current incident ends (a stop is released), status Available
        local inc = POL.events.incidentOf(unit)
        if inc then
            local s = inc.el and POL.stop.of(inc.el)
            if s then POL.stop.release(player, s) else POL.events.close(inc, "code4", player) end
        end
        POL.dispatch.clearObjective(unit)
        POL.units.setStatus(unit, "available", player)
        return true
    elseif id == "REQUEST_BACKUP" then
        local ok, err = POL.dispatch.requestBackup(player)
        POL.notify(player, ok and "police_system.dispatch.backup_requested" or ("police_system.dispatch.err_" .. tostring(err)))
        return ok
    elseif id == "REQUEST_AMBULANCE" then
        return POL.medical.request(player)
    elseif id == "REQUEST_TOW" then
        return POL.tow.request(player, args.confirm == true)
    elseif id == "QUERY_PERSON" then
        return POL.query.nearestPerson(player)
    elseif id == "QUERY_VEHICLE" then
        return POL.query.nearestVehicle(player)
    end
    return false
end

POL.net("radio", function(player, id, args)
    RD.handle(player, id, args)
end)

-- export (the later voice radio)
function radioCommand(player, messageId, args) return RD.handle(player, messageId, args) end
