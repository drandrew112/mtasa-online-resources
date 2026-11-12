-- police_system / modules/stop/server/menu.lua
-- The temp menu (ui_inac) of a stopped person / vehicle or a wanted / cuffed suspect, built for the officer in its
-- language (stays open after a pick, except arrest / escort), and the actions it sends back (stop:action target, value):
--   details, vehicle (queries), bac, drug (tests), search, search_vehicle (search/server/search.lua), warn:<id>,
--   fine:<id> (penal code), arrest, uncuff, escort, place,
--   takeout, out (order out of the vehicle), return (back into the vehicle), release (Release / Code 4),
--   transport (prisoner transport for a cuffed suspect: charges menu, then the AI van - modules/transport)
-- Tests: an NPC's result comes from its History; a player is always negative for now (pol.bac / pol.drug element
-- data is read when a future drink / drug system sets it).

local ST = POL.stop
local C = POLICE.STOP

local function aipeds() return POL.running("ai_peds") and exports.ai_peds or nil end
local function T(p, key, params) return L.forPlayer(p, key, params) end

local function personOf(el)
    if isElement(el) and getElementType(el) == "vehicle" then return getVehicleController(el) end
    return el
end

local function btkItems(officer, warning, cat)
    local out = {}
    for _, c in ipairs(POL.btk.list()) do
        if (warning and c.warning) or (not warning and not c.warning) then
            local sub = {}
            for _, it in ipairs(c.items) do
                if warning then
                    sub[#sub + 1] = { label = T(officer, btkKey(it.id)), value = "warn:" .. it.id }
                else
                    sub[#sub + 1] = { label = T(officer, btkKey(it.id)), value = "fine:" .. it.id,
                                      desc = L.money(it.amount, officer) }
                end
            end
            if warning then return sub end
            out[#out + 1] = { label = T(officer, btkCategoryKey(c.id)), items = sub }
        end
    end
    return out
end

local function nearestPoliceVehicle(officer)
    local x, y, z = getElementPosition(officer)
    local best, bd
    for _, v in ipairs(getElementsWithinRange(x, y, z, POLICE.ARREST.PLACE_DIST + 2, "vehicle")) do
        if isPoliceVehicle(v) then
            local d = POL.dist(officer, v)
            if not bd or d < bd then best, bd = v, d end
        end
    end
    return best
end

-- the cuffed suspect the officer is escorting, else the nearest cuffed one within reach
local function suspectToPlace(officer)
    local best, bd
    for t in pairs(POL.arrest.cuffed) do
        if isElement(t) and not getPedOccupiedVehicle(t) then
            if POL.arrest.escorts[t] == officer then return t end
            local d = POL.dist(officer, t)
            if d <= POLICE.ARREST.PLACE_DIST + 2 and (not bd or d < bd) then best, bd = t, d end
        end
    end
    return best
end

-- who comes out of a police vehicle: a cuffed suspect first, else anyone else who is not an officer
local function occupantToTakeOut(veh)
    -- seat by seat (getVehicleOccupants did not return the placed suspect in a live test)
    local other
    for seat = 0, getVehicleMaxPassengers(veh) or 3 do
        local o = getVehicleOccupant(veh, seat)
        if o then
            if POL.arrest.isCuffed(o) then return o end
            if not other and POL.arrest.canTakeOut(o) then other = o end
        end
    end
    return other
end

-- a medic on duty (med_erm unit) within HOSTAGE_EMS_DIST of the ped
local function medicNear(ped)
    if not POL.running("med_erm") then return false end
    local x, y, z = getElementPosition(ped)
    for _, p in ipairs(getElementsWithinRange(x, y, z, POLICE.ARREST.HOSTAGE_EMS_DIST, "player")) do
        local ok, u = pcall(function() return exports.med_erm:getUnitData(p) end)
        if ok and u then return p end
    end
    return false
end

function ST.openMenu(officer, target)
    if not POL.units.of(officer) or not isElement(target) then return end
    local s = ST.list[target]
    local person = personOf(target)
    local items = {}
    local function add(key, value, extra)
        local it = { label = T(officer, key), value = value }
        if extra then for k, v in pairs(extra) do it[k] = v end end
        items[#items + 1] = it
    end
    local title
    if s and s.kind == "vehicle" then
        title = T(officer, "police_system.stop.title_vehicle", { model = exports.veh_manager:getModelName(getElementModel(target)), plate = getVehiclePlateText(target) })
        add("police_system.stop.details", "details", { desc = T(officer, "police_system.stop.driver") })
        add("police_system.stop.vehicle_details", "vehicle", { desc = getVehiclePlateText(target) })
        add("police_system.stop.bac", "bac")
        add("police_system.stop.drug", "drug")
        add("police_system.stop.search_vehicle", "search_vehicle")
        items[#items + 1] = { label = T(officer, "police_system.stop.warning"), items = btkItems(officer, true) }
        items[#items + 1] = { label = T(officer, "police_system.stop.fine"), items = btkItems(officer, false) }
        add("police_system.stop.order_out", "out")
        add("police_system.stop.release", "release", { desc = "Code 4" })
    elseif getElementType(target) == "vehicle" then
        -- a vehicle that is not stopped: data, and the place / take out of cuffed suspects
        title = T(officer, "police_system.stop.title_vehicle", { model = exports.veh_manager:getModelName(getElementModel(target)), plate = getVehiclePlateText(target) })
        if getVehicleController(target) then add("police_system.stop.details", "details", { desc = T(officer, "police_system.stop.driver") }) end
        add("police_system.stop.vehicle_details", "vehicle", { desc = getVehiclePlateText(target) })
        if isPoliceVehicle(target) then
            if suspectToPlace(officer) then add("police_system.stop.place", "place") end
            local o = occupantToTakeOut(target)
            if o then add("police_system.stop.take_out", "takeout") end
            if o and POL.arrest.isCuffed(o) and not POL.transport.jobOf(o) then add("police_system.stop.transport", "transport") end
        end
    elseif getElementData(target, "vsm.hostage") then
        -- a hostage (v_scenemanager): grab / let go, hand over to EMS (a medic close by), release (no EMS at all)
        local state = getElementData(target, "vsm.hostage")
        title = T(officer, "police_system.hostage.title")
        if (state == "held" or state == "safe") and not getPedOccupiedVehicle(target) then
            add(POL.arrest.escorts[target] == officer and "police_system.hostage.let_go" or "police_system.hostage.grab", "escort")
            if medicNear(target) then add("police_system.hostage.to_ems", "hostage_ems") end
            if getElementData(target, "vsm.hostage.release") == true then add("police_system.hostage.release", "hostage_release") end
        end
        add("police_system.stop.details", "details")
    else
        local cuffed = POL.arrest.isCuffed(target)
        title = T(officer, "police_system.stop.title_ped", { name = ST.nameOf(target) })
        add("police_system.stop.details", "details")
        if s then
            add("police_system.stop.bac", "bac")
            add("police_system.stop.drug", "drug")
            items[#items + 1] = { label = T(officer, "police_system.stop.warning"), items = btkItems(officer, true) }
            items[#items + 1] = { label = T(officer, "police_system.stop.fine"), items = btkItems(officer, false) }
        end
        local veh = getPedOccupiedVehicle(target)
        if (s or cuffed) and not veh then add("police_system.stop.search_person", "search") end
        if s and s.fromVehicle and isElement(s.fromVehicle) then add("police_system.stop.search_vehicle", "search_vehicle") end
        if veh and POL.arrest.canTakeOut(target) then add("police_system.stop.take_out", "takeout") end
        if not cuffed then
            if not veh then add("police_system.stop.arrest", "arrest") end
        else
            if not veh then
                add(POL.arrest.escorts[target] == officer and "police_system.stop.stop_escort" or "police_system.stop.escort", "escort")
                if nearestPoliceVehicle(officer) then add("police_system.stop.place", "place") end
            end
            if not POL.transport.jobOf(target) then add("police_system.stop.transport", "transport") end
            add("police_system.stop.uncuff", "uncuff")
        end
        if s and s.fromVehicle and isElement(s.fromVehicle) and not getPedOccupiedVehicle(target) and not cuffed then
            add("police_system.stop.return", "return")
        end
        if s then add("police_system.stop.release", "release", { desc = "Code 4" }) end
    end
    -- evidence: the questionable / illegal items found by a search and not seized yet (modules/evidence)
    local function seizeMenu(el, code)
        local ids = isElement(el) and POL.evidence.seizable(el) or {}
        if #ids == 0 then return end
        local sub = { { label = T(officer, "police_system.evidence.seize_all", { count = #ids }), value = "seizeall:" .. code } }
        for _, id in ipairs(ids) do
            sub[#sub + 1] = { label = T(officer, "police_system.item." .. id), value = "seize:" .. code .. ":" .. id,
                              desc = T(officer, "police_system.search.class_" .. POL.search.classOf(id)) }
        end
        items[#items + 1] = { label = T(officer, "police_system.evidence.seize", { count = #ids }), items = sub }
    end
    if s and s.kind == "vehicle" then
        seizeMenu(person, "p")
        seizeMenu(target, "v")
    elseif getElementType(target) ~= "vehicle" then
        seizeMenu(target, "p")
        if s and s.fromVehicle then seizeMenu(s.fromVehicle, "v") end
    end
    if getElementType(target) == "vehicle" and isPoliceVehicle(target) and POL.units.of(officer)
        and POL.units.of(officer).vehicle == target and POL.evidence.hasBags(officer) then
        add("police_system.evidence.store", "store_evidence")
    end
    -- the menu stays open after an action, only these close it
    local closing = { arrest = true, escort = true, transport = true, release = true, out = true, takeout = true }
    local function keepOpen(list)
        for _, it in ipairs(list) do
            if it.items then keepOpen(it.items)
            elseif not closing[it.value] then it.closeOnSelect = false end
        end
    end
    keepOpen(items)
    POL.send(officer, "stop:menu", target, title, items)
end

------------------------------------------------------------------------ actions

local function tests(officer, s, which)
    local person = s and s.person
    if not isElement(person) then return end
    local f = s.flags or {}
    local name = ST.nameOf(person)
    if which == "bac" then
        local v = 0
        if getElementType(person) == "player" then v = tonumber(getElementData(person, "pol.bac")) or 0 else v = tonumber(f.bac) or 0 end
        local txt = ("%.2f"):format(v)
        POL.events.log(s.unit, officer, "test_bac", { name = name, value = txt }, s.inc)
        POL.notify(POL.units.members(s.unit), "police_system.stop.bac_result", { name = name, value = txt })
    else
        local pos
        if getElementType(person) == "player" then pos = getElementData(person, "pol.drug") == true else pos = f.drug == true end
        POL.events.log(s.unit, officer, "test_drug", { name = name, result = pos }, s.inc)
        POL.notify(POL.units.members(s.unit), pos and "police_system.stop.drug_pos" or "police_system.stop.drug_neg", { name = name })
    end
end

local function issue(officer, s, kind, id)
    if not s or not isElement(s.person) then return end
    local subject = { el = s.person, citizenId = s.citizenId, vehicleId = s.vehicleId }
    POL.records.issue(officer, subject, kind, id, function(ok, amount)
        if not ok then return POL.notify(officer, "police_system.stop.err_" .. tostring(amount)) end
        local name = ST.nameOf(s.person)
        s.inc.fines[#s.inc.fines + 1] = { btk = id, amount = amount, kind = kind }
        POL.events.log(s.unit, officer, kind, { name = name, item = id, amount = amount }, s.inc)
        POL.notify(officer, kind == "fine" and "police_system.stop.fine_done" or "police_system.stop.warning_done",
            { name = name, item = L.msg(btkKey(id)), amount = amount })
    end)
end

local function orderOut(officer, s)
    local veh = s.target
    local driver = getVehicleController(veh)
    if not driver then return end
    if getElementType(driver) == "player" then
        POL.notify(driver, "police_system.stop.get_out")
        POL.events.log(s.unit, officer, "order_out", {}, s.inc)
        return
    end
    local t, p = POL.running("ai_land_traffic") and exports.ai_land_traffic, aipeds()
    if not p then return end
    -- an NPC still looking for a place off the road: not in the middle of the road
    if s.held and not s.parked and t and t:isTrafficVehicleHeld(veh) then
        return POL.notify(officer, "police_system.stop.err_not_stopped")
    end
    if t and t:isTrafficVehicle(veh) == true then t:releaseTrafficVehicle(veh) end
    p:adoptTrafficDriver(driver, veh, { behaviour = "detained", args = { officer = officer }, keep = true })
    POL.events.log(s.unit, officer, "order_out", {}, s.inc)
    -- from now on the stop is about the pedestrian; the vehicle waits (physics, empty)
    ST.list[veh] = nil
    if isElement(s.blip) then destroyElement(s.blip) end
    removeElementData(veh, "pol.stop")
    ST.refreshMenu(veh)
    s.target = driver
    s.kind = "ped"
    s.fromVehicle = veh
    s.outside = true
    ST.list[driver] = s
    setElementData(driver, "pol.stop", s.unit.callsign, "subscribe")
    for _, m in ipairs(POL.units.members(s.unit)) do addElementDataSubscriber(driver, "pol.stop", m) end
    local b = createBlipAttachedTo(driver, 0, 2, 245, 140, 50, 255, 5, 99999, root)
    setElementVisibleTo(b, root, false)
    for _, m in ipairs(POL.units.members(s.unit)) do setElementVisibleTo(b, m, true) end
    s.blip = b
    ST.refreshMenu(driver)
end

local function returnToVehicle(officer, s)
    local p = aipeds()
    local ped, veh = s.target, s.fromVehicle
    if not p or not isElement(veh) then return end
    p:aiPedEnterVehicle(ped, veh, 0)
    POL.events.log(s.unit, officer, "returned", { name = ST.nameOf(ped) }, s.inc)
end

-- inMenu = picked in the interact menu (its range is already checked there)
function ST.action(officer, target, value, inMenu)
    if value == "takeout" then
        outputDebugString(("[police] takeout: officer=%s rights=%s unit=%s target=%s (%s) inVeh=%s"):format(
            getPlayerName(officer), tostring(POL.rights.has(officer)), tostring(POL.units.of(officer) ~= nil),
            tostring(target), isElement(target) and getElementType(target) or "-",
            tostring(isElement(target) and getElementType(target) ~= "vehicle" and getPedOccupiedVehicle(target) or nil)))
    end
    if not POL.rights.has(officer) or not POL.units.of(officer) or not isElement(target) or type(value) ~= "string" then return end
    local s = ST.list[target]
    -- distance: the officer at the target (a stopped vehicle may be checked from the police car next to it)
    if not inMenu and POL.dist(officer, target) > 30 then return POL.notify(officer, "police_system.stop.err_too_far") end
    if s and s.unit ~= POL.units.of(officer) then return POL.notify(officer, "police_system.stop.err_other_unit") end
    local person = personOf(target)
    local kind, arg = value:match("^(%a+):(.+)$")
    if value == "details" then
        if person then POL.query.person(officer, person) end
    elseif value == "vehicle" then
        if getElementType(target) == "vehicle" then POL.query.vehicle(officer, target) end
    elseif value == "bac" or value == "drug" then
        tests(officer, s, value)
    elseif value == "search" then
        if getElementType(target) ~= "vehicle" and (s or POL.arrest.isCuffed(target)) then POL.search.search(officer, target, "person", s) end
    elseif value == "search_vehicle" then
        local veh = getElementType(target) == "vehicle" and target or (s and s.fromVehicle)
        if s and isElement(veh) then POL.search.search(officer, veh, "vehicle", s) end
    elseif kind == "warn" then
        issue(officer, s, "warning", arg)
    elseif kind == "fine" then
        issue(officer, s, "fine", arg)
    elseif value == "out" then
        if s and s.kind == "vehicle" then orderOut(officer, s) end
    elseif value == "return" then
        if s and s.fromVehicle then returnToVehicle(officer, s) end
    elseif value == "release" then
        if s then ST.release(officer, s) end
    elseif value == "arrest" then
        POL.arrest.cuff(officer, target, function(ok, err)
            if not ok then POL.notify(officer, "police_system.arrest.err_" .. tostring(err)) end
        end)
    elseif value == "uncuff" then
        POL.arrest.uncuff(officer, target)
    elseif value == "escort" then
        POL.arrest.escort(officer, target)
    elseif value == "place" then
        local ok, err
        if getElementType(target) == "vehicle" then
            local suspect = suspectToPlace(officer)
            if suspect then ok, err = POL.arrest.place(officer, suspect, target) else ok, err = false, "bad" end
        else
            local pv = nearestPoliceVehicle(officer)
            if pv then ok, err = POL.arrest.place(officer, target, pv) else ok, err = false, "bad" end
        end
        if not ok then POL.notify(officer, "police_system.arrest.err_" .. tostring(err)) end
    elseif value == "takeout" then
        -- a police vehicle: its cuffed suspect / other occupant, else the driver of a stopped vehicle is ordered out
        local suspect = target
        if getElementType(target) == "vehicle" then
            suspect = isPoliceVehicle(target) and occupantToTakeOut(target) or nil
            if not suspect and s and s.kind == "vehicle" then return orderOut(officer, s) end
        end
        if not suspect then
            local seats = {}
            if getElementType(target) == "vehicle" then
                for seat = 0, getVehicleMaxPassengers(target) or 3 do
                    local o = getVehicleOccupant(target, seat)
                    seats[#seats + 1] = seat .. "=" .. (o and ("%s cuffed=%s can=%s"):format(getElementType(o),
                        tostring(POL.arrest.isCuffed(o)), tostring(POL.arrest.canTakeOut(o))) or "-")
                end
            end
            outputDebugString(("[police] takeout: nobody to take out of %s police=%s seats: %s"):format(tostring(target),
                tostring(getElementType(target) == "vehicle" and isPoliceVehicle(target)), table.concat(seats, ", ")))
            return POL.notify(officer, "police_system.arrest.err_bad")
        end
        local ok, err = POL.arrest.takeOut(officer, suspect)
        outputDebugString(("[police] takeout: suspect=%s (%s) -> %s %s, still in vehicle: %s"):format(tostring(suspect),
            getElementType(suspect), tostring(ok), tostring(err), tostring(getPedOccupiedVehicle(suspect))))
        if not ok then POL.notify(officer, "police_system.arrest.err_" .. tostring(err)) end
    elseif kind == "seizeall" or kind == "seize" then
        -- "seizeall:p|v" / "seize:p|v:<item id>": p = the person, v = the vehicle of this stop / target
        local code, id = arg:match("^(%a):?(.*)$")
        local el
        if code == "v" then el = getElementType(target) == "vehicle" and target or (s and s.fromVehicle)
        else el = person end
        if isElement(el) then
            POL.evidence.seize(officer, el, (kind == "seize" and id ~= "") and { id } or nil, s)
            ST.openMenu(officer, target)
        end
    elseif value == "hostage_ems" or value == "hostage_release" then
        if not POL.arrest.isHostage(target) then return end
        if POL.arrest.escorts[target] then POL.arrest.stopEscort(target) end
        if value == "hostage_ems" then
            if not medicNear(target) then return POL.notify(officer, "police_system.hostage.no_medic") end
            triggerEvent("onPoliceHostageAction", target, "ems", officer)
            POL.events.logFor(officer, "hostage_ems", { name = ST.nameOf(target) })
            POL.notify(officer, "police_system.hostage.handed_ems")
        else
            if getElementData(target, "vsm.hostage.release") ~= true then return POL.notify(officer, "police_system.hostage.cannot_release") end
            triggerEvent("onPoliceHostageAction", target, "release", officer)
            POL.events.logFor(officer, "hostage_released", { name = ST.nameOf(target) })
            POL.notify(officer, "police_system.hostage.released")
        end
        ST.openMenu(officer, target)
    elseif value == "store_evidence" then
        if getElementType(target) == "vehicle" then POL.evidence.store(officer, target) end
    elseif value == "tow" then
        if getElementType(target) == "vehicle" then POL.tow.request(officer, false, target) end
    elseif value == "transport" then
        local suspect = target
        if getElementType(target) == "vehicle" then suspect = isPoliceVehicle(target) and occupantToTakeOut(target) or nil end
        if suspect and POL.arrest.isCuffed(suspect) then POL.transport.ask(officer, suspect) end
    end
end

POL.net("stop:action", function(officer, target, value) ST.action(officer, target, value) end)
