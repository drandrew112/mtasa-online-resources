-- police_system / modules/arrest/server/arrest.lua
-- Arrest manager. Cuffs: from the stop menu or the interact menu of a wanted / surrendered suspect. A player suspect
-- must be on foot, within CUFF_DIST, standing or surrendered; it takes CUFF_TIME and fails when the suspect gets
-- farther than CUFF_BREAK. pol.cuffed = true (broadcast: icon, hands pose, walk only). Uncuff / release from the
-- menu; death removes the cuffs. Escort ("grab"): the officer holds the suspect from behind (attached in front of
-- the officer, walk anim while the officer moves; NPC and player alike). Place in / take out of a police vehicle (a player may get
-- in with G as a passenger, getting out is blocked). Handover at the station marker: the NPC goes, the player goes
-- to jail; the warrants are served. AI arrest ("Busted"): no escorting, straight to the station.
-- Every step is logged.

local AR = POL.module("arrest", { cuffed = {}, escorts = {}, pending = {}, markers = {}, custody = {} })
local C = POLICE.ARREST
local PLAYER_CONTROLS = { "sprint", "jump", "fire", "aim_weapon", "next_weapon", "previous_weapon", "enter_exit", "crouch" }

function AR.isCuffed(el) return AR.cuffed[el] ~= nil end
function AR.cuffedBy(el) local c = AR.cuffed[el]; return c and c.unit end

local function aipeds() return POL.running("ai_peds") and exports.ai_peds or nil end

local function subjectName(el, cb)
    POL.records.citizenOf(el, function(row) cb(row and POL.records.nameOf(row) or "?", row) end)
end

-- the open incident of the officer's unit about the target, else a new "arrest" incident
local function incidentFor(officer, target, name, row)
    local unit = POL.units.of(officer)
    if not unit then return nil end
    local inc = POL.events.incidentOf(unit, target)
    if not inc then
        -- a pursuit incident of this suspect counts too
        for i in pairs(unit.incidents) do if i.el == target then inc = i end end
    end
    if not inc then
        inc = POL.events.open(unit, "arrest", { citizenId = row and row.id, name = name, el = target })
        inc.el = target
        inc.zone = getZoneName(getElementPosition(target))
    end
    return inc
end

local function setPlayerCuffControls(p, on)
    for _, c in ipairs(PLAYER_CONTROLS) do toggleControl(p, c, not on) end
    if on then setPedWeaponSlot(p, 0) end
end

local function applyCuffs(officer, target)
    local unit = POL.units.of(officer)
    AR.cuffed[target] = { officer = officer, unit = unit, at = POL.now() }
    setElementData(target, "pol.cuffed", true)
    if getElementType(target) == "player" then
        setPedAnimation(target)
        setPlayerCuffControls(target, true)
        local st = POL.wanted.get(target)
        if st then st.surrendered = true; POL.emit("wanted.surrendered", target) end
        POL.notify(target, "police_system.arrest.you_are_cuffed")
    else
        local p = aipeds()
        if p and p:isAIPed(target) then
            p:setAIPedBehaviour(target, "cuffed", {})
            p:setAIPedKeep(target, true)
        end
    end
    subjectName(target, function(name, row)
        local inc = incidentFor(officer, target, name, row)
        if inc then
            POL.events.addSubject(inc, { citizenId = row and row.id, name = name, el = target })
            POL.events.log(unit, officer, "cuffed", { name = name }, inc)
        end
    end)
    POL.emit("arrest.cuffed", target, officer)
    AR.refreshMenus(target)
end

-- cb(true | false, err)
function AR.cuff(officer, target, cb)
    cb = cb or function() end
    if not isElement(target) or AR.cuffed[target] or AR.pending[target] then return cb(false, "busy") end
    if not POL.units.of(officer) then return cb(false, "not_in_unit") end
    if getPedOccupiedVehicle(target) or getPedOccupiedVehicle(officer) then return cb(false, "in_vehicle") end
    if POL.dist(officer, target) > C.CUFF_DIST + 0.6 then return cb(false, "too_far") end
    if getElementType(target) == "player" then
        local st = POL.wanted.get(target)
        local stopped = POL.stop.of(target)
        if POL.speed(target) > 1.2 and not (st and st.surrendered) then return cb(false, "moving") end
        -- no wanted level, no stop: an active warrant is a reason too (looked up, then the checks again)
        if not st and not stopped then
            AR.pending[target] = true
            POL.history.player(target, function(row)
                if not (row and row.id) then AR.pending[target] = nil return cb(false, "no_reason") end
                POL.warrants.activeFor(row.id, function(list)
                    AR.pending[target] = nil
                    if #list == 0 then return cb(false, "no_reason") end
                    if not isElement(target) or not isElement(officer) then return cb(false, "gone") end
                    if POL.dist(officer, target) > C.CUFF_DIST + 0.6 then return cb(false, "too_far") end
                    AR.startCuff(officer, target, cb)
                end)
            end)
            return
        end
    end
    AR.startCuff(officer, target, cb)
end

function AR.startCuff(officer, target, cb)
    AR.pending[target] = true
    POL.send(officer, "arrest:progress", target, C.CUFF_TIME)
    setTimer(function()
        AR.pending[target] = nil
        if not isElement(target) or not isElement(officer) or isPedDead(target) then return cb(false, "gone") end
        if POL.dist(officer, target) > C.CUFF_BREAK + 0.5 then
            POL.notify(officer, "police_system.arrest.cuff_failed")
            return cb(false, "moved")
        end
        applyCuffs(officer, target)
        cb(true)
    end, C.CUFF_TIME, 1)
end

-- officer nil = automatic (death, jail); silent = no log
function AR.uncuff(officer, target, silent)
    local c = AR.cuffed[target]
    if not c then return false end
    AR.cuffed[target] = nil
    AR.custody[target] = nil
    AR.stopEscort(target)
    if isElement(target) then
        removeElementData(target, "pol.cuffed")
        if getElementType(target) == "player" then
            setPlayerCuffControls(target, false)
        else
            -- an AI ped still in the "cuffed" behaviour (released by the officer) walks off as a civilian
            local p = aipeds()
            if p and p:isAIPed(target) and not isPedDead(target) and p:getAIPedBehaviour(target) == "cuffed" then
                p:setAIPedBehaviour(target, "civilian", {})
                p:setAIPedKeep(target, false)
            end
        end
    end
    if not silent and officer then POL.events.logFor(officer, "uncuffed", { name = POL.stop.nameOf(target) }) end
    AR.refreshMenus(target)
    return true
end

-- the officer grabs the cuffed suspect (NPC and player): attached in front of the officer (the ai_peds motor leaves
-- an attached ped alone). pol.escort = the officer (broadcast): every client plays the walk anim itself from the
-- officer's smooth local speed (cuffs.lua) - server-side anim toggles by the jumpy synced velocity made it jump.
-- An escorted player cannot walk on its own: its movement would fight the attach.
local GRAB_OFFSET = 0.6
local MOVE_CONTROLS = { "forwards", "backwards", "left", "right", "walk" }
local grabTimer

local function setPlayerMoveControls(p, on)
    for _, c in ipairs(MOVE_CONTROLS) do toggleControl(p, c, on) end
end

local function grabTick()
    local any = false
    for target, officer in pairs(AR.escorts) do
        if not isElement(target) or not isElement(officer) or isPedDead(officer) or getPedOccupiedVehicle(officer)
            or getPedOccupiedVehicle(target) then
            AR.stopEscort(target)
        else
            any = true
        end
    end
    if not any and isTimer(grabTimer) then killTimer(grabTimer); grabTimer = nil end
end

function AR.escort(officer, target)
    if not AR.cuffed[target] or getPedOccupiedVehicle(target) then return false end
    if AR.escorts[target] == officer then return AR.stopEscort(target) end
    if getPedOccupiedVehicle(officer) or POL.dist(officer, target) > C.CUFF_DIST + 1.5 then return false end
    AR.escorts[target] = officer
    if not isTimer(grabTimer) then grabTimer = setTimer(grabTick, 200, 0) end
    setPedAnimation(target)
    if getElementType(target) == "player" then setPlayerMoveControls(target, false) end
    setElementCollisionsEnabled(target, false)
    attachElements(target, officer, 0, GRAB_OFFSET, 0, 0, 0, 0)
    setElementData(target, "pol.escort", officer)
    POL.events.logFor(officer, "escort", { name = POL.stop.nameOf(target) })
    AR.refreshMenus(target)
    return true
end

function AR.stopEscort(target)
    if not AR.escorts[target] then return false end
    AR.escorts[target] = nil
    if isElement(target) then
        if isElementAttached(target) then detachElements(target) end
        setElementCollisionsEnabled(target, true)
        removeElementData(target, "pol.escort")
        if getElementType(target) == "player" then setPlayerMoveControls(target, true) end
    end
    AR.refreshMenus(target)
    return true
end

-- pol.custody (broadcast) on whoever can be taken out of a police vehicle: the custody interact menu shows on it
-- (defined before AR.place, which uses it)
local function setCustody(el, on)
    if not isElement(el) then return end
    if on then setElementData(el, "pol.custody", true)
    elseif getElementData(el, "pol.custody") then removeElementData(el, "pol.custody") end
end

local function freeSeat(veh)
    for _, s in ipairs({ 2, 3, 1 }) do
        if s <= getVehicleMaxPassengers(veh) and not getVehicleOccupant(veh, s) then return s end
    end
    return nil
end

function AR.place(officer, target, veh)
    if not AR.cuffed[target] or not isPoliceVehicle(veh) or getPedOccupiedVehicle(target) then return false, "bad" end
    if POL.dist(officer, veh) > C.PLACE_DIST + 2 or POL.dist(target, veh) > C.PLACE_DIST + 4 then return false, "too_far" end
    local seat = freeSeat(veh)
    if not seat then return false, "full" end
    AR.stopEscort(target)
    -- the detach needs a moment before the warp takes; the seat is re-checked then
    setTimer(function()
        if not isElement(target) or not isElement(veh) or getPedOccupiedVehicle(target) then return end
        if getVehicleOccupant(veh, seat) then seat = freeSeat(veh) end
        if not seat then return POL.notify(officer, "police_system.arrest.err_full") end
        warpPedIntoVehicle(target, veh, seat)
        AR.custody[target] = veh
        setCustody(target, true)
        AR.refreshMenus(target)
    end, 100, 1)
    POL.events.logFor(officer, "placed", { name = POL.stop.nameOf(target) })
    return true
end

-- AR.custody[suspect] = the police vehicle it was placed in, until taken out / handed over / uncuffed. The server's
-- seat is not always the suspect's own: a client that did not take the warp (or that GTA put out) syncs on foot and
-- the other clients drop it out of the car (left behind on the way to the station). Put back into the same car: on
-- an exit the server sees, and when the suspect's own client reports it is not seated (arrest:unseated).
local RESEAT_COOLDOWN = 2000
local reseating, reseatAt = {}, {}

local function reseat(target, why)
    local veh = AR.custody[target]
    if not veh then return end
    if not isElement(target) or not isElement(veh) or not AR.cuffed[target] or isPedDead(target) or isVehicleBlown(veh) then
        AR.custody[target] = nil
        return
    end
    local now = getTickCount()
    if now - (reseatAt[target] or 0) < RESEAT_COOLDOWN then return end
    reseatAt[target] = now
    local cur = getPedOccupiedVehicle(target)
    local seat = cur == veh and getPedOccupiedVehicleSeat(target) or freeSeat(veh)
    if not seat then AR.custody[target] = nil return end   -- the car got full: stays where it is
    outputDebugString(("[police] custody: %s (%s) back into %s seat %d (%s)"):format(tostring(target),
        getElementType(target), tostring(veh), seat, why))
    reseating[target] = true
    if cur then removePedFromVehicle(target) end
    setElementInterior(target, getElementInterior(veh))
    setElementDimension(target, getElementDimension(veh))
    warpPedIntoVehicle(target, veh, seat)
    reseating[target] = nil
    setCustody(target, true)
    AR.refreshMenus(target)
end

POL.net("arrest:unseated", function(player)
    if AR.custody[player] then reseat(player, "client not seated") end
end)

-- who may be taken out of a police vehicle: a cuffed suspect, or anyone else in it but an officer (on duty / AI)
function AR.canTakeOut(target)
    local veh = isElement(target) and getElementType(target) ~= "vehicle" and getPedOccupiedVehicle(target)
    if not veh or not isPoliceVehicle(veh) then return false end
    if AR.cuffed[target] then return true end
    if POL.ai.peds[target] then return false end
    return not (getElementType(target) == "player" and POL.units.isOnDuty(target))
end

addEventHandler("onVehicleEnter", root, function(ped)
    if isPoliceVehicle(source) then setCustody(ped, AR.canTakeOut(ped)) end
end)
addEventHandler("onVehicleExit", root, function(ped)
    if reseating[ped] then return end
    setCustody(ped, false)
    -- out without a take out (the officer never does it this way): back in a moment later
    if AR.custody[ped] then
        setTimer(function() if isElement(ped) and not getPedOccupiedVehicle(ped) then reseat(ped, "exit") end end, 500, 1)
    end
end)

-- only out of a police vehicle (a stopped driver is ordered out instead); the person stands at its own door:
-- seats 0 / 2 on the left, 1 / 3 on the right, the rear seats farther back
function AR.takeOut(officer, target)
    local veh = getPedOccupiedVehicle(target)
    if not veh then return false, "bad" end
    if not isPoliceVehicle(veh) then return false, "not_police_vehicle" end
    if not AR.canTakeOut(target) then return false, "bad" end
    local seat = getPedOccupiedVehicleSeat(target) or 0
    -- getElementBoundingBox is client-only: a fixed half width (police cars are ~1 m) + a step away from the door
    local side = (seat == 1 or seat == 3) and 1.6 or -1.6
    local back = seat >= 2 and -0.9 or 0.2
    local m = getElementMatrix(veh)
    local x = m[4][1] + m[1][1] * side + m[2][1] * back
    local y = m[4][2] + m[1][2] * side + m[2][2] * back
    local z = m[4][3] + m[1][3] * side + m[2][3] * back
    AR.custody[target] = nil
    removePedFromVehicle(target)
    setCustody(target, false)
    setElementPosition(target, x, y, z + 0.2)
    -- the exit may still be running on the client when the first position arrives: placed again a moment later
    setTimer(function()
        if isElement(target) and not getPedOccupiedVehicle(target) then setElementPosition(target, x, y, z + 0.2) end
    end, 150, 1)
    POL.events.logFor(officer, "taken_out", { name = POL.stop.nameOf(target) })
    AR.refreshMenus(target)
    return true
end

-- a cuffed player cannot get out on its own
addEventHandler("onVehicleStartExit", root, function(player)
    if AR.cuffed[player] then cancelEvent() end
end)

-- a cuffed player may only get in as a passenger (G) of a police vehicle
addEventHandler("onVehicleStartEnter", root, function(player, seat)
    if AR.cuffed[player] and (seat == 0 or not isPoliceVehicle(source)) then cancelEvent() end
end)

-- cuff / escort / custody state of an element, also what is left on it without an AR.cuffed entry (element data
-- outlives a resource restart): data off, controls back
local function clearState(el)
    if not isElement(el) then return end
    if isElementAttached(el) and getElementData(el, "pol.escort") then
        detachElements(el)
        setElementCollisionsEnabled(el, true)
    end
    for _, k in ipairs({ "pol.cuffed", "pol.escort", "pol.custody" }) do
        if getElementData(el, k) ~= false and getElementData(el, k) ~= nil then removeElementData(el, k) end
    end
    if getElementType(el) == "player" then
        setPlayerCuffControls(el, false)
        setPlayerMoveControls(el, true)
    end
end

addEventHandler("onPlayerWasted", root, function()
    if AR.cuffed[source] then AR.uncuff(nil, source, true) end
    clearState(source)
end)
-- an AI ped going down (lethal hit = "downed", not wasted) or taken over by another behaviour is out of the cuffs
addEvent("onAIPedBehaviourChanged")
addEventHandler("onAIPedBehaviourChanged", root, function(new)
    if AR.cuffed[source] and new ~= "cuffed" then
        AR.uncuff(nil, source, true)
        clearState(source)
    end
end)
addEventHandler("onPlayerSpawn", root, function()
    if not AR.cuffed[source] then clearState(source) end
end)
addEventHandler("onPedWasted", root, function() if AR.cuffed[source] then AR.uncuff(nil, source, true) end end)
addEventHandler("onElementDestroy", root, function()
    if AR.cuffed[source] then AR.cuffed[source] = nil; AR.escorts[source] = nil end
    AR.custody[source] = nil
end)
addEventHandler("onPlayerQuit", root, function()
    -- the automatic warrant of a cuffed player is made by wanted.lua (it runs before: same event, earlier script)
    AR.cuffed[source] = nil
    AR.escorts[source] = nil
    AR.custody[source] = nil
    for t, o in pairs(AR.escorts) do if o == source then AR.stopEscort(t) end end
end)

------------------------------------------------------------------------ handover at the station

local function handover(officer, target, station)
    local unit = POL.units.of(officer)
    local isPlayer = getElementType(target) == "player"
    subjectName(target, function(name, row)
        local inc = unit and POL.events.incidentOf(unit, target)
        if not inc and unit then inc = incidentFor(officer, target, name, row) end
        local function finish(warrantMinutes)
            if inc then
                POL.events.log(unit, officer, "handover", { name = name, station = station.name }, inc)
                inc.arrested = isPlayer and "player" or "npc"
            end
            if isPlayer then
                local level = POL.wanted.arrested(target)
                if inc then inc.level = math.max(inc.level or 0, level) end
                AR.uncuff(nil, target, true)
                local minutes = level + (warrantMinutes or 0)
                POL.jail.jail(target, math.max(1, minutes), station.id, "arrest")
                triggerEvent("onPoliceArrest", resourceRoot, target, officer, "player")
            else
                AR.uncuff(nil, target, true)
                triggerEvent("onPoliceArrest", resourceRoot, target, officer, "player")
                local p = aipeds()
                if p and p:isAIPed(target) then p:destroyAIPed(target) end
                if isElement(target) then destroyElement(target) end
            end
            POL.db.stat("arrests", 1)
            if inc then POL.events.close(inc, "handover", officer) end
        end
        if row and row.id then POL.warrants.serve(row.id, officer, finish) else finish(0) end
    end)
end

local function onHandoverHit(st, el)
    if getElementType(el) ~= "player" or not POL.units.of(el) then return end
    local officer = el
    local veh = getPedOccupiedVehicle(officer)
    local done = 0
    for target, c in pairs(AR.cuffed) do
        if isElement(target) and not isPedDead(target) then
            local tv = getPedOccupiedVehicle(target)
            local mine = (veh and tv == veh) or AR.escorts[target] == officer
                or (not veh and not tv and POL.dist(officer, target) < 6)
            if mine then
                AR.custody[target] = nil
                if tv then removePedFromVehicle(target) end
                handover(officer, target, st)
                done = done + 1
            end
        end
    end
    if done > 0 then POL.notify(officer, "police_system.arrest.handed_over", { count = done }) end
end

-- on stop the cuffs come off (a restart would leave them on with nobody to take them off)
function AR.stop()
    for el in pairs(AR.cuffed) do clearState(el) end
    for el in pairs(AR.escorts) do clearState(el) end
end

function AR.start()
    -- leftovers of a crash / an older version
    for _, t in ipairs({ "player", "ped" }) do
        for _, el in ipairs(getElementsByType(t)) do
            if getElementData(el, "pol.cuffed") or getElementData(el, "pol.escort") or getElementData(el, "pol.custody") then clearState(el) end
        end
    end
    for _, st in ipairs(POLICE.STATIONS) do
        local h = st.handover
        local m = createMarker(h[1], h[2], h[3] - 1, "cylinder", POLICE.HANDOVER_RADIUS, 40, 110, 255, 90)
        AR.markers[m] = st
        addEventHandler("onMarkerHit", m, function(el, dim) if dim then onHandoverHit(st, el) end end)
    end
end

------------------------------------------------------------------------ AI arrest ("Busted")

function AR.aiArrest(suspect, unit)
    -- a suspect cuffed by a player unit is theirs: the AI never takes it over
    if not isElement(suspect) or getElementType(suspect) ~= "player" or AR.busted[suspect] or AR.cuffed[suspect] then return end
    AR.busted[suspect] = true
    POL.send(suspect, "arrest:busted")
    setTimer(function()
        AR.busted[suspect] = nil
        if not isElement(suspect) then return end
        local x, y = getElementPosition(suspect)
        local st = POL.nearestStation(x, y)
        local level = POL.wanted.arrested(suspect)
        POL.history.player(suspect, function(row)
            local function go(wm)
                if not isElement(suspect) then return end
                if AR.cuffed[suspect] then AR.uncuff(nil, suspect, true) end
                POL.jail.jail(suspect, math.max(1, level + (wm or 0)), st.id, "ai_arrest")
                triggerEvent("onPoliceArrest", resourceRoot, suspect, false, "ai")
                POL.db.stat("arrests", 1)
            end
            if row and row.id then POL.warrants.serve(row.id, nil, go) else go(0) end
        end)
    end, 2600, 1)
end
AR.busted = {}

------------------------------------------------------------------------ interact menus of suspects

-- the arrest menu on a wanted / cuffed suspect for the officers on duty
function AR.refreshMenus(target)
    POL.stop.refreshMenu(target)
end
