-- police_system / modules/radio_voice/server/voice.lua
-- The dispatcher voice triggers: game events on the internal bus -> RV.say(phrase, args, ctx) -> "rv:say" to the
-- listeners. The server only picks the phrase, its arguments and who hears it (trigger audience); the order of the
-- sounds is built on every client from the same data/voice.json (client/builder.lua).
--   audience: officer (ctx.player) | unit (ctx.unit) | chase (the units of ctx.chase) | onduty
--   cooldown: per phrase + ctx.key (trigger "cooldown" ms)
-- Hooks: radio.used, query.result, callout.offered / announced, backup.requested, transport.requested,
--        chase.changed / ended, wanted.phase / changed / reasons / cleared.

local RV = POL.module("voice", { cool = {}, seen = {}, chases = {} })
local V = POLICE.VOICE
local DB

------------------------------------------------------------------------ sending

local function chaseMembers(c)
    local out = {}
    if not c then return out end
    for unit in pairs(c.units or {}) do
        if POL.units.list[unit.id] == unit then
            for _, p in ipairs(POL.units.members(unit)) do out[#out + 1] = p end
        end
    end
    return out
end

local function listeners(audience, ctx)
    if audience == "officer" then return { ctx.player } end
    if audience == "unit" then return ctx.unit and POL.units.members(ctx.unit) or {} end
    if audience == "chase" then return chaseMembers(ctx.chase) end
    return POL.units.onDuty()
end

-- -> true when sent
function RV.say(pid, args, ctx)
    if not DB then return false end
    local t = DB.triggers[pid]
    if not t then return false end
    ctx = ctx or {}
    local key = pid .. "|" .. tostring(ctx.key or "")
    local now = getTickCount()
    if t.cooldown and RV.cool[key] and now - RV.cool[key] < t.cooldown then return false end
    local to = listeners(t.audience, ctx)
    if #to == 0 then return false end
    if t.cooldown then RV.cool[key] = now end
    POL.send(to, "rv:say", pid, args or {})
    return true
end

------------------------------------------------------------------------ helpers

local function vehicleOf(el)
    if not isElement(el) then return nil end
    if getElementType(el) == "vehicle" then return el end
    return getPedOccupiedVehicle(el)
end

-- GTA heading of an element: where it moves, or where it faces when it stands
local function headingOf(el)
    local v = vehicleOf(el) or el
    local vx, vy = getElementVelocity(v)
    if vx and (vx * vx + vy * vy) > 0.0025 then return (math.deg(math.atan2(-vx, vy)) + 360) % 360 end
    local _, _, rz = getElementRotation(v)
    return rz or 0
end

local function colorOf(veh)
    local r, g, b = getVehicleColor(veh, true)
    return r and ("%d,%d,%d"):format(r, g, b) or nil
end

local function zoneOf(el)
    if not isElement(el) then return nil end
    return getZoneName(getElementPosition(el))
end

-- the most serious wanted reason of a player (maps.reasonOrder)
local function topReason(player)
    local st = isElement(player) and getElementType(player) == "player" and POL.wanted.get(player)
    if not st then return nil end
    for _, id in ipairs(DB.maps.reasonOrder or {}) do
        if st.reasons[id] then return id end
    end
    return nil
end

-- the description of a suspect for the pursuit phrases
local function suspectArgs(c, crime)
    local s = c.suspect
    local veh = vehicleOf(s)
    local a = { crime = crime, area = zoneOf(s), heading = headingOf(s), direction = true, onFoot = veh == nil }
    if veh then
        a.model = getElementModel(veh)
        a.color = colorOf(veh)
        a.vehicle = DB.maps.vehicles[tostring(a.model)] ~= nil
    end
    return a
end

local function expired(v) return tostring(v or ""):find("expired") ~= nil end

------------------------------------------------------------------------ radio buttons

local ACK_IDS = { STATUS_AVAILABLE = true, STATUS_RESPONDING = true, STATUS_BUSY = true, REQUEST_TOW = true,
                  REQUEST_BACKUP = true }

POL.on("radio.used", function(player, id, ok)
    if not ok then return end
    local unit = POL.units.of(player)
    if not unit then return end
    if id == "CODE_4" then
        RV.say("ACK_CODE_4", { callsign = unit.callsign }, { unit = unit })
    elseif id == "REQUEST_AMBULANCE" then
        RV.say("ACK_AMBULANCE", {}, { unit = unit })
    elseif ACK_IDS[id] then
        RV.say("ACK", {}, { player = player })
    end
end)

POL.on("transport.requested", function(officer, unit)
    if unit then RV.say("ACK_TRANSPORT", {}, { unit = unit }) end
end)

------------------------------------------------------------------------ queries

POL.on("query.result", function(unit, r)
    if r.kind == "vehicle" then
        local warrant = (tonumber(r.ownerWarrants) or 0) > 0
        local stolen = r.stolen and true or false
        RV.say("QUERY_VEHICLE", {
            callsign = unit.callsign, plate = r.plate, color = r.color, model = r.model,
            vehicle = DB.maps.vehicles[tostring(r.model)] ~= nil,
            stolen = stolen, warrant = warrant, caution = stolen or warrant, felony = stolen and warrant,
            violation = expired(r.registration) or r.registration == "invalid" or expired(r.inspection),
        }, { unit = unit })
    elseif r.kind == "person" then
        RV.say("QUERY_PERSON", {
            callsign = unit.callsign, name = r.npc and r.name or nil, gender = r.gender,
            warrant = (tonumber(r.warrants) or 0) > 0,
            licence = r.licence ~= nil and r.licence ~= "valid", wanted = (tonumber(r.wanted) or 0) > 0,
        }, { unit = unit })
    end
end)

------------------------------------------------------------------------ calls + backup

local function crimeOfCall(c)
    if c.kind == "scene" then return type(c.meta) == "table" and c.meta.category or nil end
    if c.kind == "agency" then return DB.maps.callKindCrime and DB.maps.callKindCrime.agency or nil end
    return nil
end

POL.on("callout.offered", function(unit, c)
    RV.say("CALL_OFFER", { callsign = unit.callsign, crime = crimeOfCall(c), area = c.zone, priority = c.priority },
        { unit = unit })
end)

POL.on("callout.announced", function(c, offered)
    local crime = crimeOfCall(c)
    if not offered and tonumber(c.priority) == 1 and crime then
        RV.say("CALL_ALL_UNITS", { crime = crime, area = c.zone, priority = c.priority })
    end
end)

POL.on("backup.requested", function(unit, best, x, y, z)
    local area = getZoneName(x, y, z)
    RV.say("BACKUP_REQUESTED", { area = area })
    RV.say("BACKUP_ASSIGNED", { callsign = best.callsign, area = area }, { unit = best })
end)

------------------------------------------------------------------------ pursuits

-- RV.chases[c] = { dir = 1-4, announced = bool }
local function announce(c)
    local st = RV.chases[c]
    if not st or POL.chase.list[c.suspect] ~= c or not isElement(c.suspect) then return end
    local crime = topReason(c.suspect) or "evading_police"
    local a = suspectArgs(c, crime)
    st.announced, st.dir = true, VOICE.dirIndex(a.heading)
    RV.say("PURSUIT_START", a, { key = c.id })
end

POL.on("chase.changed", function(c)
    if RV.chases[c] or not next(c.units) then return end
    RV.chases[c] = { announced = false }
    -- an NPC driver that pulls over ends the chase at once: no call then
    setTimer(function() announce(c) end, V.START_DELAY, 1)   -- closure: setTimer drops table args
end)

POL.on("chase.ended", function(c, how)
    local st = RV.chases[c]
    RV.chases[c] = nil
    if not st or not st.announced then return end
    if how == "caught" then
        RV.say("SUSPECT_ARRESTED", {}, { chase = c })
    elseif how == "lost" and c.kind == "npc" then
        RV.say("PURSUIT_LOST", { heading = isElement(c.suspect) and headingOf(c.suspect) or 0, direction = true,
            area = c.lastX and getZoneName(c.lastX, c.lastY, c.lastZ or 0) }, { chase = c, key = c.id })
    end
end)

POL.on("wanted.phase", function(player, phase)
    if phase ~= "evading" then return end
    local c = POL.chase.of(player)
    local st = c and RV.chases[c]
    if not st or not st.announced then return end
    RV.say("PURSUIT_LOST", { heading = headingOf(player), direction = true, area = zoneOf(player) },
        { chase = c, key = c.id })
end)

local function tick()
    for c, st in pairs(RV.chases) do
        if POL.chase.list[c.suspect] ~= c or not isElement(c.suspect) then
            RV.chases[c] = nil
        elseif st.announced and c.phase == "active" then
            local h = headingOf(c.suspect)
            local d = VOICE.dirIndex(h)
            if d ~= st.dir and RV.say("PURSUIT_UPDATE", { heading = h, area = zoneOf(c.suspect) }, { chase = c, key = c.id }) then
                st.dir = d
            end
        end
    end
end

------------------------------------------------------------------------ wanted

POL.on("wanted.changed", function(player, level, old)
    if (tonumber(level) or 0) >= V.SWAT_LEVEL and (tonumber(old) or 0) < V.SWAT_LEVEL then
        local c = POL.chase.of(player)
        if c then RV.say("SWAT", { crime = topReason(player) or "evading_police" }, { chase = c, key = c.id }) end
    end
end)

POL.on("wanted.reasons", function(player)
    local st = POL.wanted.get(player)
    if not st then return end
    local seen = RV.seen[player] or {}
    RV.seen[player] = seen
    local new = {}
    for id in pairs(st.reasons) do
        if not seen[id] then seen[id], new[id] = true, true end
    end
    if new.shots_at_police or new.police_down then
        RV.say("PANIC", { shots = new.shots_at_police or false, area = zoneOf(player) }, { key = player })
    end
    if new.evading_arrest or new.escape_custody then
        local c = POL.chase.of(player)
        if c then RV.say("RESIST_ARREST", {}, { chase = c, key = player }) end
    end
end)

POL.on("wanted.cleared", function(player) RV.seen[player] = nil end)
addEventHandler("onPlayerQuit", root, function() RV.seen[source] = nil end)

------------------------------------------------------------------------ start

function RV.start()
    DB = VOICE.load()
    if not DB then return end
    setTimer(tick, V.TICK, 0)
end
