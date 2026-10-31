-- police_system / modules/stop/server/stop.lua
-- Stop the ped / traffic stop.
--   Pedestrian or player: hold E (0.8 s) on someone in front within 4 m. NPC: ai_peds "detained" (stands, faces the
--   officer), History runs. Player: "You were stopped by the police"; farther than LEAVE_DIST = the stop ends (logged).
--   Vehicle: left Shift in a police vehicle at the vehicle in front (25 m, +-12 deg; the client picks, the server
--   checks); again = cancel. v_els: lights on + a 0.5 s siren blip when the siren was off (a running siren is left).
--   AI vehicle: pullOverTrafficVehicle (aside, held). Player driver: "Pull over"; still driving after 20 s =
--   "failure to stop" (0 -> 1, 1 -> 2). Busy sub label "Traffic stop".
-- An interact menu (ui_interactobject type menus: ped, player, vehicle) for every officer on duty opens the ui_inac
-- temp menu (actions below): data, vehicle data, arrest, escort, place / take out; the stop tools only on stopped ones.
-- pol.stop (callsign) on the target: subscribe, only the unit's members.

local ST = POL.module("stop", { list = {} })   -- list[target] = stop
local C = POLICE.STOP

local function aipeds() return POL.running("ai_peds") and exports.ai_peds or nil end
local function traffic() return POL.running("ai_land_traffic") and exports.ai_land_traffic or nil end
local function io() return POL.running("ui_interactobject") and exports.ui_interactobject or nil end

function ST.of(el) return ST.list[el] end

-- the person of a stop target (the driver of a vehicle)
local function personOf(el)
    if isElement(el) and getElementType(el) == "vehicle" then return getVehicleController(el) end
    return el
end

local names = setmetatable({}, { __mode = "k" })
function ST.nameOf(el)
    if not isElement(el) then return "?" end
    if getElementType(el) == "player" then return POL.nameOf(el) end
    return names[el] or "?"
end

------------------------------------------------------------------------ interact menus (one per element type)

-- Two separate menus for the officers on duty: persons on foot (ped + player: data, arrest, escort, uncuff, place)
-- and vehicles (vehicle data, driver data, tow truck, place, take out). Someone sitting in a vehicle has no menu of
-- its own (targetInVehicle = false on the menu): one interact object per vehicle, the vehicle's menu covers the
-- driver / the suspect in the back. Items are static (a type menu); ST.action checks the target. The stop tools
-- (fine, warning, tests...) stay in the stop menu (ST.openMenu: "Actions").
local function item(key, value) return { label = L.msg(key), value = value } end
local PERSON_ITEMS = {
    item("police_system.stop.menu_actions", "open"),
    item("police_system.stop.details", "details"), item("police_system.stop.escort", "escort"),
    item("police_system.stop.place", "place"),
}
local VEHICLE_ITEMS = {
    item("police_system.stop.menu_actions", "open"),
    item("police_system.stop.vehicle_details", "vehicle"),
    { label = L.msg("police_system.stop.details"), value = "details", desc = L.msg("police_system.stop.driver") },
    item("police_system.stop.tow", "tow"),
    item("police_system.stop.place", "place"), item("police_system.stop.take_out", "takeout"),
}
local TYPES = { ped = PERSON_ITEMS, player = PERSON_ITEMS, vehicle = VEHICLE_ITEMS }
local typeMenus, typeViewers = {}, ""

function ST.refreshMenu()
    local m = io()
    if not m then return end
    local viewers = POL.units.onDuty()
    local sig = {}
    for i, p in ipairs(viewers) do sig[i] = tostring(p) end
    table.sort(sig)
    sig = table.concat(sig, ",")
    if #viewers == 0 then
        for t, id in pairs(typeMenus) do m:removeInteractMenu(id); typeMenus[t] = nil end
        typeViewers = ""
        return
    end
    if sig == typeViewers and next(typeMenus) then return end
    typeViewers = sig
    for t, items in pairs(TYPES) do
        local id = typeMenus[t]
        if id and m:isInteractMenu(id) then
            m:setInteractMenuVisibleTo(id, viewers)
        else
            local def = {
                title = L.msg(t == "vehicle" and "police_system.stop.menu_vehicle" or "police_system.stop.menu_title"), range = C.MENU_RANGE, priority = 50, lineOfSight = false, checkRange = false,
                items = items,
            }
            if t ~= "vehicle" then def.targetInVehicle = false end   -- persons on foot only
            typeMenus[t] = m:addInteractTypeMenu(t, def, viewers)
        end
    end
end

POL.on("units.changed", function() ST.refreshMenu() end)

addEvent("onInteractMenuSelect")
addEventHandler("onInteractMenuSelect", root, function(menuId, value, target)
    if typeMenus[getElementType(target)] ~= menuId then return end
    -- the menus are checkRange = false: the server position of a traffic vehicle (and its driver) is seconds old,
    -- so the distance is checked here by the simulated pose (POL.dist)
    if POL.dist(source, target) > C.MENU_RANGE + 3 then return POL.notify(source, "police_system.stop.err_too_far") end
    if value == "open" then ST.openMenu(source, target) else ST.action(source, target, value, true) end
end)

addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) == "ui_interactobject" then typeMenus, typeViewers = {}, ""; ST.refreshMenu() end
end)

------------------------------------------------------------------------ stop lifecycle

local function subscribe(target, unit)
    setElementData(target, "pol.stop", unit.callsign, "subscribe")
    for _, p in ipairs(POL.units.members(unit)) do addElementDataSubscriber(target, "pol.stop", p) end
end

local function stopBlip(s)
    local b = createBlipAttachedTo(s.target, 0, 2, 245, 140, 50, 255, 5, 99999, root)
    setElementVisibleTo(b, root, false)
    for _, p in ipairs(POL.units.members(s.unit)) do setElementVisibleTo(b, p, true) end
    s.blip = b
end

local function begin(officer, target, kind)
    local unit = POL.units.of(officer)
    local s = { target = target, kind = kind, unit = unit, officer = officer, startedAt = POL.now() }
    ST.list[target] = s
    subscribe(target, unit)
    stopBlip(s)
    return s
end

function ST.finish(s, why, by)
    if ST.list[s.target] ~= s then return end
    ST.list[s.target] = nil
    if isElement(s.blip) then destroyElement(s.blip) end
    if isElement(s.target) then removeElementData(s.target, "pol.stop") end
    if s.inc and POL.units.list[s.unit.id] then POL.events.close(s.inc, why, by) end
    ST.refreshMenu(s.target)
end

-- the person stopped: cb(row) when the History / registration answered
local function attachPerson(s, person, cb)
    POL.records.citizenOf(person, function(row)
        local name = row and POL.records.nameOf(row) or "?"
        names[person] = name
        s.citizenId = row and row.id
        s.person = person
        s.flags = row and POL.db.unjson(row.flags) or {}
        if s.inc then POL.events.addSubject(s.inc, { citizenId = s.citizenId, name = name, el = person }) end
        if cb then cb(row) end
    end)
end

function ST.ped(officer, target)
    local unit = POL.units.of(officer)
    if not unit then return false, "not_in_unit" end
    if not isElement(target) or isPedDead(target) or target == officer then return false, "bad_target" end
    local t = getElementType(target)
    if t ~= "ped" and t ~= "player" then return false, "bad_target" end
    if getPedOccupiedVehicle(officer) or getPedOccupiedVehicle(target) then return false, "in_vehicle" end
    if POL.dist(officer, target) > C.PED_RANGE + 1.5 then return false, "too_far" end
    if t == "player" and POL.units.isOnDuty(target) then return false, "bad_target" end
    local old = ST.list[target]
    if old then
        if old.unit == unit then return false, "already" end
        return false, "other_unit"
    end
    local s = begin(officer, target, "ped")
    s.inc = POL.events.open(unit, "ped_stop", nil)
    s.inc.el = target
    s.inc.zone = getZoneName(getElementPosition(target))
    if t == "ped" then
        local p = aipeds()
        if p and p:isAIPed(target) then
            p:setAIPedBehaviour(target, "detained", { officer = officer })
            p:setAIPedKeep(target, true)
        end
    else
        POL.notify(target, "police_system.stop.you_were_stopped", { callsign = unit.callsign })
    end
    attachPerson(s, target, function()
        POL.events.log(unit, officer, "stop_ped", { name = names[target] }, s.inc)
    end)
    POL.units.setSub(unit, "ped_stop")
    ST.refreshMenu(target)
    return true
end

-- lights on + 0.5 s siren when the siren was off; a running siren is not touched
local function signal(pv)
    if not isElement(pv) or not POL.running("v_els") then return end
    local e = exports.v_els
    if getElementData(pv, "sirenState") == true then return end
    e:setElsLights(pv, true)
    e:setElsSiren(pv, true)
    setTimer(function()
        if isElement(pv) and POL.running("v_els") then
            exports.v_els:setElsSiren(pv, false)
            exports.v_els:setElsLights(pv, true)
        end
    end, C.SIREN_BLIP, 1)
end

function ST.vehicle(officer, veh)
    local unit = POL.units.of(officer)
    if not unit then return false, "not_in_unit" end
    local pv = getPedOccupiedVehicle(officer)
    if not isElement(veh) or getElementType(veh) ~= "vehicle" or veh == pv then return false, "bad_target" end
    local old = ST.list[veh]
    if old then
        -- the same unit again: the stop is cancelled
        if old.unit == unit then
            ST.release(officer, old)
            return true, "cancelled"
        end
        return false, "other_unit"
    end
    if not pv or not isPoliceVehicle(pv) then return false, "not_police_vehicle" end
    -- the server checks the client's pick loosely: in front, not far. A traffic vehicle by its simulated pose (its
    -- element position is seconds old), the cone is the client's (it sees the real positions)
    local px, py = getElementPosition(pv)
    local vx, vy = POL.pos(veh)
    local d = math.sqrt((vx - px) ^ 2 + (vy - py) ^ 2)
    local m = getElementMatrix(pv)
    local dot = ((vx - px) * m[2][1] + (vy - py) * m[2][2]) / math.max(d, 0.01)
    if d > C.VEH_RANGE + 15 or dot < 0.2 then return false, "not_in_front" end
    local driver = getVehicleController(veh)
    if not driver then return false, "no_driver" end
    if getElementType(driver) == "player" and POL.units.isOnDuty(driver) then return false, "bad_target" end
    local s = begin(officer, veh, "vehicle")
    s.inc = POL.events.open(unit, "traffic_stop", nil)
    s.inc.el = veh
    s.inc.zone = getZoneName(vx, vy, 0)
    local r, g, b = getVehicleColor(veh, true)
    POL.events.addSubject(s.inc, { plate = getVehiclePlateText(veh), model = getElementModel(veh) })
    signal(pv)
    local t = traffic()
    if getElementType(driver) == "ped" and t and t:isTrafficVehicle(veh) then
        -- a released traffic vehicle (physics after a bump) goes back into the simulation first
        if t:isTrafficVehicle(veh) == "released" then t:adoptTrafficVehicle(veh) end
        s.held = t:pullOverTrafficVehicle(veh, pv) == true
        if not s.held then outputDebugString("[police_system] stop: pullOverTrafficVehicle refused " .. getVehiclePlateText(veh), 2) end
    elseif getElementType(driver) == "player" then
        POL.notify(driver, "police_system.stop.pull_over", { callsign = unit.callsign })
        s.pullover = { since = getTickCount(), driver = driver }
    end
    POL.records.vehicleOf(veh, function(row)
        if not row then return end
        s.vehicleId = row.id
        POL.events.addSubject(s.inc, { vehicleId = row.id, plate = row.plate or getVehiclePlateText(veh),
            model = getElementModel(veh), color = nil })
    end)
    attachPerson(s, driver, function()
        POL.events.log(unit, officer, "stop_vehicle", { plate = getVehiclePlateText(veh), model = getElementModel(veh), name = names[driver] }, s.inc)
    end)
    POL.units.setSub(unit, "traffic_stop")
    ST.refreshMenu(veh)
    return true
end

-- Release / Code 4: the NPC walks / drives on, the stop ends
function ST.release(officer, s)
    local t, p = traffic(), aipeds()
    local person = s.person
    if s.kind == "vehicle" and isElement(s.target) then
        if s.outside and person and isElement(person) and not getPedOccupiedVehicle(person) and p and p:isAIPed(person) then
            -- the driver gets back in first, then the vehicle goes on (see onAIPedEnteredVehicle)
            s.releasing = true
            p:aiPedEnterVehicle(person, s.target, 0)
            POL.events.log(s.unit, officer, "released", { name = names[person] }, s.inc)
            ST.finish(s, "released", officer)
            ST.pendingRelease = ST.pendingRelease or {}
            ST.pendingRelease[person] = s.target
            return
        end
        if t then
            if t:isTrafficVehicleHeld(s.target) then t:releaseTrafficHold(s.target)
            elseif person and isElement(person) and getElementType(person) == "ped" then t:adoptTrafficVehicle(s.target) end
        end
    elseif person and isElement(person) and getElementType(person) == "ped" and p and p:isAIPed(person) then
        if not POL.arrest.isCuffed(person) then
            p:setAIPedBehaviour(person, "civilian", { task = "wander" })
            p:setAIPedKeep(person, false)
        end
    elseif person and isElement(person) and getElementType(person) == "player" then
        POL.notify(person, "police_system.stop.released_you")
    end
    if s.inc then POL.events.log(s.unit, officer, "released", { name = names[person] or "?" }, s.inc) end
    ST.finish(s, "released", officer)
end

addEvent("onAIPedEnteredVehicle")
addEventHandler("onAIPedEnteredVehicle", root, function(veh)
    local pr = ST.pendingRelease and ST.pendingRelease[source]
    if pr and pr == veh then
        ST.pendingRelease[source] = nil
        local t, p = traffic(), aipeds()
        if p then p:setAIPedKeep(source, false) end
        if t then t:adoptTrafficVehicle(veh) end
    end
end)

------------------------------------------------------------------------ checks (1 Hz while there are stops)

local function tick()
    local now = getTickCount()
    for target, s in pairs(ST.list) do
        if not isElement(target) or not POL.units.list[s.unit.id] then
            ST.finish(s, "gone")
        else
            local person = personOf(target)
            -- a player walked / drove away
            if s.kind == "ped" and getElementType(target) == "player" then
                local near = false
                for _, p in ipairs(POL.units.members(s.unit)) do if POL.dist(p, target) <= C.LEAVE_DIST then near = true end end
                if not near then
                    POL.events.log(s.unit, nil, "stop_left", { name = POL.nameOf(target) }, s.inc)
                    ST.finish(s, "left")
                end
            elseif s.pullover and isElement(s.pullover.driver) then
                if POL.speed(target) < 1.5 then
                    s.pullover = nil
                elseif now - s.pullover.since > C.PULLOVER_TIME * 1000 then
                    local d = s.pullover.driver
                    s.pullover = nil
                    local st = POL.wanted.get(d)
                    POL.wanted.add(d, "failure_to_stop", (st and st.level or 0) + 1)
                    POL.events.log(s.unit, nil, "failure_to_stop", { name = POL.nameOf(d) }, s.inc)
                end
            end
            if s.kind == "ped" and person and isPedDead(person) then ST.finish(s, "dead") end
        end
    end
end

function ST.start()
    ST.refreshMenu()
    setTimer(function() if next(ST.list) then tick() end end, 1000, 0)
end

POL.on("unit.signedOff", function(unit)
    for _, s in pairs(ST.list) do if s.unit == unit then ST.finish(s, "unit_end") end end
end)

addEventHandler("onElementDestroy", root, function()
    local s = ST.list[source]
    if s then ST.finish(s, "gone") end
end)

------------------------------------------------------------------------ client requests

POL.net("stop:ped", function(player, target)
    if not POL.rights.has(player) then return end
    local ok, err = ST.ped(player, target)
    if not ok then POL.notify(player, "police_system.stop.err_" .. tostring(err)) end
end)

POL.net("stop:vehicle", function(player, veh)
    if not POL.rights.has(player) then return end
    local ok, err = ST.vehicle(player, veh)
    if not ok then POL.notify(player, "police_system.stop.err_" .. tostring(err))
    elseif err == "cancelled" then POL.notify(player, "police_system.stop.cancelled") end
end)
