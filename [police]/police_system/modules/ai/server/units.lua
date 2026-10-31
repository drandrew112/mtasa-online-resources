-- police_system / modules/ai/server/units.lua
-- AI police units: spawn and removal. Only the chase module asks for them (AI.request); the AI decides where a unit
-- appears and what it does (tactics.lua). Spawn only on a road 180-400 m from the suspect at a point no player camera
-- sees (ai_land_traffic findHiddenRoadSpawn, with priority over the civilian traffic); removal only unseen and farther
-- than DESPAWN_DIST from every player (setScriptedDespawnUnseen). Until then a unit retreats: siren off, it drives
-- on as normal traffic. Model by zone: city 596 / 598 (hu_pd, ELS extra 1), countryside 599, tank 432 (levels 5-6).
-- Only dimension 0 / interior 0 (the scripted traffic vehicles only sync there).
--
-- Every unit has a radar blip (BLIP) that only its suspect (a player) sees, until it retreats.
--
-- unit = { veh, driver, partner, chase, tank, blip, role ("tail" | "intercept" | "roadblock"), state ("chase" | "foot" |
--          "search" | "retreat" | "roadblock" | "boarding"), spawnedAt, sirenAt, opts (chase motor options) }

local AI = POL.module("ai", { vehicles = {}, peds = {}, units = {}, demands = {}, lastSpawn = {} })
local A = POLICE.AI
local TRAFFIC_RES = "ai_land_traffic"

local function traffic() return POL.running(TRAFFIC_RES) and exports.ai_land_traffic or nil end
local function peds() return POL.running("ai_peds") and exports.ai_peds or nil end

local function inCity(x, y)
    for _, b in ipairs(A.CITY_BOX) do
        if x >= b[1] and y >= b[2] and x <= b[3] and y <= b[4] then return true end
    end
    return false
end

local function pickModel(x, y)
    local zone = inCity(x, y) and "city" or "rural"
    local total, list = 0, {}
    for model, def in pairs(POLICE.VEHICLES) do
        if def.ai and def.ai.zones and def.ai.zones[zone] then
            total = total + (def.ai.weight or 1)
            list[#list + 1] = { model, def.ai.weight or 1 }
        end
    end
    local r = math.random() * total
    for _, e in ipairs(list) do
        r = r - e[2]
        if r <= 0 then return e[1], zone end
    end
    return 596, zone
end

function AI.countFor(c)
    local n = 0
    for _, u in pairs(AI.units) do if u.chase == c and u.state ~= "retreat" then n = n + 1 end end
    return n
end

function AI.total(tank)
    local n = 0
    for _, u in pairs(AI.units) do if (u.tank or false) == (tank or false) then n = n + 1 end end
    return n
end

-- radar blip on the unit, only its suspect sees it (a player)
local function addBlip(unit, c)
    if not isElement(c.suspect) or getElementType(c.suspect) ~= "player" then return end
    local b = A.BLIP
    local blip = createBlipAttachedTo(unit.veh, b.icon, b.size, b.color[1], b.color[2], b.color[3], 255, 1, 99999, root)
    if not blip then return end
    setElementVisibleTo(blip, root, false)
    setElementVisibleTo(blip, c.suspect, true)
    unit.blip = blip
end

local function removeBlip(unit)
    if unit.blip and isElement(unit.blip) then destroyElement(unit.blip) end
    unit.blip = nil
end

local function addPed(ped, unit)
    AI.peds[ped] = unit
    setElementData(ped, "pol.ai", true)
end

-- a new unit for chase c. -> unit | nil
function AI.spawn(c, tank)
    local t = traffic()
    if not t or not POL.inWorld(c.suspect) then return nil end
    local tx, ty, tz = getElementPosition(c.suspect)
    local sx, sy, sz, rot = t:findHiddenRoadSpawn(tx, ty, tz, { minDist = A.SPAWN_MIN, maxDist = A.SPAWN_MAX,
        toward = c.suspect, priority = true })
    if not sx then return nil end
    local model, zone = pickModel(sx, sy)
    if tank then model = POLICE.TANK_MODEL end
    local skins = zone == "rural" and A.RURAL_SKINS or A.SKINS
    local skin = tank and A.TANK_SKIN or skins[math.random(#skins)]
    local veh, driver = t:createScriptedVehicle(model, sx, sy, sz, { heading = rot, skin = skin, profile = "pursuit",
        speedFactor = tank and 1.0 or 1.4, keepDriver = true })
    if not veh then return nil end
    local def = POLICE.VEHICLES[model] or {}
    if def.paintjob and POL.running("v_paintjobs") then pcall(function() exports.v_paintjobs:setVehicleCustomPaintjob(veh, def.paintjob) end) end
    if def.elsExtra and POL.running("v_els") then pcall(function() exports.v_els:setElsExtra(veh, def.elsExtra) end) end
    setVehiclePlateText(veh, "SAPD" .. math.random(100, 999))
    setElementData(veh, "pol.ai", true)
    local unit = { veh = veh, driver = driver, chase = c, tank = tank or false, role = "tail", state = "chase",
                   spawnedAt = getTickCount(), sirenAt = 0 }
    if not tank then
        local partner = createPed(skins[math.random(#skins)], sx, sy, sz + 2)
        if partner then
            setElementSyncer(partner, false)
            warpPedIntoVehicle(partner, veh, 1)
            unit.partner = partner
            addPed(partner, unit)
        end
    end
    addPed(driver, unit)
    AI.vehicles[veh] = unit
    AI.units[veh] = unit
    addBlip(unit, c)
    POL.ai.sirens.on(unit)
    POL.ai.tactics.engage(unit)
    return unit
end

-- the unit goes away: no siren, its crew back in, driving on as traffic, removed when nobody sees it
function AI.retreat(unit)
    if unit.state == "retreat" then return end
    unit.state = "retreat"
    unit.chase = nil
    removeBlip(unit)
    POL.ai.sirens.off(unit, true)
    local t = traffic()
    if not t or not isElement(unit.veh) then return AI.remove(unit) end
    if unit.parked then setElementFrozen(unit.veh, false) end
    -- crew out on foot: back in first (tactics.lua finishes the retreat when they sat down)
    if POL.ai.tactics.crewOut(unit) then
        POL.ai.tactics.board(unit)
        return
    end
    AI.leave(unit)
end

-- driving away (called when the crew sits)
function AI.leave(unit)
    local t = traffic()
    if not t or not isElement(unit.veh) then return AI.remove(unit) end
    t:setScriptedChase(unit.veh, false)
    if not t:isScriptedVehicle(unit.veh) then
        -- physics vehicle that could not go back on a lane: removed by the budget check when unseen
        unit.manualDespawn = true
        return
    end
    t:clearScriptedTargets(unit.veh)
    t:setScriptedDespawnUnseen(unit.veh, { minDist = A.DESPAWN_DIST })
end

function AI.remove(unit)
    removeBlip(unit)
    AI.units[unit.veh] = nil
    AI.vehicles[unit.veh] = nil
    for _, ped in ipairs({ unit.driver, unit.partner }) do
        if ped then
            AI.peds[ped] = nil
            if isElement(ped) then
                if POL.running("ai_peds") then pcall(function() exports.ai_peds:destroyAIPed(ped) end) end
                if isElement(ped) then destroyElement(ped) end
            end
        end
    end
    if isElement(unit.veh) then
        local t = traffic()
        if not (t and t:destroyScriptedVehicle(unit.veh)) and isElement(unit.veh) then destroyElement(unit.veh) end
    end
end

------------------------------------------------------------------------ requests (chase module)

function AI.request(c, demand)
    AI.demands[c] = demand
end

function AI.release(c)
    AI.demands[c] = nil
    AI.lastSpawn[c] = nil
    for _, u in pairs(AI.units) do if u.chase == c then AI.retreat(u) end end
end

-- after the chase tick (1 Hz): spawn what is missing, retreat the surplus
function AI.tickRequests()
    local now = getTickCount()
    local seen = {}
    for c, d in pairs(AI.demands) do
        seen[c] = true
        if not POL.chase.list[c.suspect] then
            AI.release(c)
        else
            POL.ai.budget.fulfil(c, d, now)
        end
    end
    -- units of chases that are gone
    for _, u in pairs(AI.units) do
        if u.chase and not seen[u.chase] then AI.retreat(u) end
    end
    POL.ai.budget.cleanup(now)
end

------------------------------------------------------------------------ ai_land_traffic / ai_peds events

addEvent("onTrafficVehicleRemoved")
addEventHandler("onTrafficVehicleRemoved", root, function(veh, reason)
    local unit = AI.units[veh]
    if not unit then return end
    if reason == "crash" or reason == "damage" then
        -- keepDriver: still ours, a physics vehicle now; the chase motor takes it if the chase goes on
        if unit.state ~= "retreat" and unit.chase and isElement(veh) then
            POL.ai.tactics.engage(unit, true)
        else
            unit.manualDespawn = true
        end
        return
    end
    -- despawned / destroyed / timeout: gone
    AI.remove(unit)
end)

addEventHandler("onElementDestroy", root, function()
    local unit = AI.units[source]
    if unit and getElementType(source) == "vehicle" then
        AI.units[source] = nil
        AI.vehicles[source] = nil
        unit.veh = nil
        removeBlip(unit)
        for _, ped in ipairs({ unit.driver, unit.partner }) do
            if ped and isElement(ped) and not getPedOccupiedVehicle(ped) then
                -- the crew outside stays until unseen (budget cleanup)
                AI.orphans = AI.orphans or {}
                AI.orphans[ped] = getTickCount()
            elseif ped then
                AI.peds[ped] = nil
            end
        end
    elseif AI.peds[source] then
        AI.peds[source] = nil
    end
end)

addEventHandler("onVehicleExplode", root, function()
    local unit = AI.units[source]
    if unit then unit.dead = true end
end)

function AI.stop()
    for _, u in pairs(AI.units) do AI.remove(u) end
end
