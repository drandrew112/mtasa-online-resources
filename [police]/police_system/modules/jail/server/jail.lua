-- police_system / modules/jail/server/jail.lua
-- Jail (the decision): an arrested player is put in the cell of the nearest station. Minutes: the wanted level
-- (1 minute a level) + the warrants (the minutes of their reasons, together at most WARRANT_MAX_MINUTES). Like the
-- admin jail: no vehicle, no weapon, nothing; leaving the cell (teleport, glitch) puts the player back. The time
-- runs in real time, offline too (accData police.jail = { untilTs, minutes, station }); the player is told so.

local J = POL.module("jail", { list = {} })   -- [player] = { untilTs, station, minutes }
local C = POLICE.JAIL
local CONTROLS = { "fire", "aim_weapon", "next_weapon", "previous_weapon", "enter_exit", "enter_passenger", "action" }

local function accData(player, value)
    if not POL.running("v_mysql") then return nil end
    if value == nil then
        local ok, v = pcall(function() return exports.v_mysql:getAccData(player, C.ACC_KEY) end)
        return ok and v or nil
    end
    pcall(function() exports.v_mysql:setAccData(player, C.ACC_KEY, value) end)
end

local function cellOf(j) return POL.stationById(j.station).jail end

local function putIn(player, j)
    local cell = cellOf(j)
    local veh = getPedOccupiedVehicle(player)
    if veh then removePedFromVehicle(player) end
    setElementInterior(player, cell.interior or 0)
    setElementDimension(player, cell.dimension or 0)
    setElementPosition(player, cell[1], cell[2], cell[3])
    setElementRotation(player, 0, 0, cell.rot or 0)
    setPedWeaponSlot(player, 0)
end

local function setControls(player, on)
    for _, c in ipairs(CONTROLS) do toggleControl(player, c, on) end
end

function J.isJailed(player) return J.list[player] ~= nil end

function J.jail(player, minutes, stationId, why)
    minutes = math.max(1, math.floor(tonumber(minutes) or 1))
    local j = { untilTs = POL.now() + minutes * 60, minutes = minutes, station = stationId or "lspd", why = why }
    J.list[player] = j
    accData(player, toJSON({ untilTs = j.untilTs, minutes = minutes, station = j.station }, true))
    if POL.arrest.isCuffed(player) then POL.arrest.uncuff(nil, player, true) end
    setPedAnimation(player)
    putIn(player, j)
    setControls(player, false)
    setElementData(player, "pol.jail", j.untilTs, "subscribe")
    addElementDataSubscriber(player, "pol.jail", player)
    POL.notify(player, "police_system.jail.jailed", { minutes = minutes })
    POL.db.stat("jailed", 1)
    J.ensureTimer()
end

function J.release(player)
    local j = J.list[player]
    J.list[player] = nil
    accData(player, "")
    if not isElement(player) then return end
    removeElementData(player, "pol.jail")
    setControls(player, true)
    local r = POL.stationById(j and j.station).release
    setElementInterior(player, 0)
    setElementDimension(player, 0)
    setElementPosition(player, r[1], r[2], r[3])
    setElementRotation(player, 0, 0, r.rot or 0)
    POL.notify(player, "police_system.jail.released")
end

local timer
local function check()
    if not next(J.list) then killTimer(timer); timer = nil return end
    local now = POL.now()
    for player, j in pairs(J.list) do
        if not isElement(player) then
            J.list[player] = nil
        elseif now >= j.untilTs then
            J.release(player)
        elseif not isPedDead(player) then
            local cell = cellOf(j)
            local x, y, z = getElementPosition(player)
            if getElementInterior(player) ~= (cell.interior or 0) or getElementDimension(player) ~= (cell.dimension or 0)
                or (x - cell[1]) ^ 2 + (y - cell[2]) ^ 2 + (z - cell[3]) ^ 2 > C.ESCAPE_DIST ^ 2 or getPedOccupiedVehicle(player) then
                putIn(player, j)
            end
        end
    end
end

function J.ensureTimer()
    if not timer then timer = setTimer(check, C.CHECK, 0) end
end

-- after login / spawn: the stored time (it ran on while the player was offline)
local function restore(player)
    local raw = accData(player)
    if type(raw) ~= "string" or raw == "" then return end
    local ok, d = pcall(fromJSON, raw)
    if not ok or type(d) ~= "table" or not tonumber(d.untilTs) then return end
    local left = tonumber(d.untilTs) - POL.now()
    if left <= 0 then
        accData(player, "")
        POL.notify(player, "police_system.jail.served_offline")
        return
    end
    local j = { untilTs = tonumber(d.untilTs), minutes = tonumber(d.minutes) or 1, station = d.station or "lspd" }
    J.list[player] = j
    putIn(player, j)
    setControls(player, false)
    setElementData(player, "pol.jail", j.untilTs, "subscribe")
    addElementDataSubscriber(player, "pol.jail", player)
    POL.notify(player, "police_system.jail.still_jailed", { minutes = math.ceil(left / 60) })
    J.ensureTimer()
end

addEvent("onPlayerLoaded")
addEventHandler("onPlayerLoaded", root, function()
    local p = source
    setTimer(function() if isElement(p) then restore(p) end end, 1500, 1)
end)

addEventHandler("onPlayerSpawn", root, function()
    local j = J.list[source]
    if j then
        local p = source
        setTimer(function() if isElement(p) and J.list[p] then putIn(p, j) end end, 300, 1)
    end
end)

addEventHandler("onVehicleStartEnter", root, function(player)
    if J.list[player] then cancelEvent() end
end)

addEventHandler("onPlayerQuit", root, function() J.list[source] = nil end)

function J.start()
    for _, p in ipairs(getElementsByType("player")) do
        if getElementData(p, "loaded") then restore(p) end
    end
end

function J.stop()
    for p in pairs(J.list) do if isElement(p) then setControls(p, true) end end
end
