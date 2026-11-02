-- police_system / modules/plates/server/alpr.lua
-- ALPR: the plate labels of the client (plates/client/plates.lua) ask the flags of the vehicles they show. Only an
-- officer with the right sitting in a police vehicle gets an answer. Flags: stolen, registration / inspection
-- expired, the owner's active warrant, the owner's licence not valid; a vehicle without a plate (plate "0",
-- ai_land_traffic) is "no_plate" and is not looked up. NPC vehicles get their record here (history/npc.lua), as at
-- a query. Results are kept for POLICE.PLATES.CACHE ms per vehicle element.

local A = POL.module("alpr", { cache = {} })   -- [veh] = { at = tick, flags = { ... } }

local function noPlate(veh)
    return ((getVehiclePlateText(veh) or ""):gsub("%s", "")) == "0"
end

-- cb(flags): a list of flag ids
local function lookup(veh, cb)
    if noPlate(veh) then return cb({ "no_plate" }) end
    POL.records.vehicleOf(veh, function(row)
        if not row then return cb({}) end
        POL.records.vehicleProfile(row.id, function(prof)
            if not prof then return cb({}) end
            local f = {}
            if prof.stolen then f[#f + 1] = "stolen" end
            if tostring(prof.registration):find("expired") or prof.registration == "invalid" then f[#f + 1] = "registration" end
            if tostring(prof.inspection):find("expired") then f[#f + 1] = "inspection" end
            local o = prof.owner
            if not o then return cb(f) end
            if (tonumber(o.warrants) or 0) > 0 then f[#f + 1] = "warrant" end
            if o.kind ~= "npc" then return cb(f) end
            POL.records.citizen(o.id, function(c)
                local lic = c and POL.db.unjson(c.flags).licence or "valid"
                if lic ~= "valid" then f[#f + 1] = "licence_" .. tostring(lic) end
                cb(f)
            end)
        end)
    end)
end

POL.net("alpr:scan", function(player, list)
    if type(list) ~= "table" or not POL.rights.has(player) or not isPoliceVehicle(getPedOccupiedVehicle(player)) then return end
    local now = getTickCount()
    local out, left = {}, 1   -- 1: the loop itself (a lookup may answer at once)
    local function reply()
        if #out > 0 and isElement(player) then POL.send(player, "alpr:result", out) end
    end
    for i = 1, math.min(#list, POLICE.PLATES.MAX) do
        local veh = list[i]
        if isElement(veh) and getElementType(veh) == "vehicle" and POL.dist(player, veh) <= POLICE.PLATES.RANGE + 15 then
            local c = A.cache[veh]
            if c and now - c.at < POLICE.PLATES.CACHE then
                out[#out + 1] = { v = veh, f = c.flags }
            else
                left = left + 1
                lookup(veh, function(flags)
                    A.cache[veh] = { at = getTickCount(), flags = flags }
                    out[#out + 1] = { v = veh, f = flags }
                    left = left - 1
                    if left == 0 then reply() end
                end)
            end
        end
    end
    left = left - 1
    if left == 0 then reply() end
end)

addEventHandler("onElementDestroy", root, function()
    if A.cache[source] then A.cache[source] = nil end
end)

-- a fine / warrant / record change shows at the next scan
function A.forget(veh) if veh then A.cache[veh] = nil else A.cache = {} end end
