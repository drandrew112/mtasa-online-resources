-- police_system / modules/wanted/server/wanted.lua
-- The wanted level: GTA's own (setPlayerWantedLevel, 0-6) is the source. Next to it the module keeps the reasons,
-- the heat points and the phase. Nothing is saved: the level only rises and only drops to 0 (evaded, arrested,
-- death, quit, admin). External scripts: addWanted(player, reasonId [, level]) - level is a minimum, the reason is
-- always added. Only in dimension 0 (job matches, editors, tutorials: false, "dimension"); an officer on duty gets
-- none. In an interior the level stays but nothing moves on (no AI, no evasion) until the player comes out.
--
-- state = { level, reasons = { [id] = true }, reasonList = { id, ... }, heat, phase ("active" | "evading" | "paused"),
--           startedAt, lastSeen (tick), lx, ly, lz (last known position), evadeAt, movingFor, surrendered, offer,
--           knownUntil (tick: DISPATCH_GRACE after a level rise the suspect counts as seen),
--           circle (v_radar area id), units = { [unit] = true } (player units that chased) }

local W = POL.module("wanted", { list = {} })
local C = POLICE.WANTED

addEvent("onPlayerWantedChange")    -- (player, new, old, reasons), source = resourceRoot
addEvent("onPlayerWantedEvaded")    -- (player, level)

function W.get(player) return W.list[player] end

local function publicReasons(st)
    local out = {}
    for i, id in ipairs(st.reasonList) do out[i] = id end
    return out
end

local function changed(player, st, old)
    st.knownUntil = getTickCount() + C.DISPATCH_GRACE * 1000
    setPlayerWantedLevel(player, st.level)
    triggerEvent("onPlayerWantedChange", resourceRoot, player, st.level, old, publicReasons(st))
    POL.emit("wanted.changed", player, st.level, old)
    POL.send(player, "wanted:state", st.level, st.phase)
end

local function newState(player)
    local x, y, z = getElementPosition(player)
    return { level = 0, reasons = {}, reasonList = {}, heat = 0, phase = "active", startedAt = getTickCount(),
             lastSeen = getTickCount(), lx = x, ly = y, lz = z, movingFor = 0, units = {} }
end

-- -> true | false, reason ("dimension" | "unknown_reason" | "police" | "bad_player")
function W.add(player, reasonId, level)
    if not isElement(player) or getElementType(player) ~= "player" or isPedDead(player) then return false, "bad_player" end
    local def = WANTED_REASONS[reasonId]
    if not def then return false, "unknown_reason" end
    if getElementDimension(player) ~= 0 then return false, "dimension" end
    if POL.units.isOnDuty(player) then return false, "police" end
    if POL.jail and POL.jail.isJailed(player) then return false, "jailed" end
    local st = W.list[player]
    if not st then st = newState(player); W.list[player] = st end
    if not st.reasons[reasonId] then
        st.reasons[reasonId] = true
        st.reasonList[#st.reasonList + 1] = reasonId
    end
    local want = math.max(1, math.min(C.MAX, math.floor(tonumber(level) or def.level)))
    local old = st.level
    if want > old then
        st.level = want
        if old == 0 then
            st.startedAt = getTickCount()
            POL.db.stat("wanted", 1)
        end
        changed(player, st, old)
    else
        POL.emit("wanted.reasons", player)
    end
    return true
end

-- heat points: police hurt / killed / their vehicles destroyed / shots near them. 3 is the floor once police got hurt,
-- 4-6 by the thresholds.
function W.heat(player, kind, reasonId)
    if not isElement(player) or getElementType(player) ~= "player" or POL.units.isOnDuty(player) then return end
    if getElementDimension(player) ~= 0 then return end
    local st = W.list[player]
    local pts = C.HEAT[kind] or 0
    if kind == "nearShot" then
        W.add(player, reasonId or "shots_near_police", st and st.level >= 2 and st.level or 2)
    else
        W.add(player, reasonId or "shots_at_police", 3)
    end
    st = W.list[player]
    if not st then return end
    st.heat = st.heat + pts
    local lv = st.level
    for l = C.MAX, 4, -1 do
        if st.heat >= (C.HEAT_LEVELS[l] or math.huge) then lv = math.max(lv, l) break end
    end
    if lv > st.level and not st.surrendered then
        local old = st.level
        st.level = lv
        changed(player, st, old)
    end
end

function W.clear(player, why)
    local st = W.list[player]
    if not st then return false end
    W.list[player] = nil
    local old = st.level
    if st.circle and POL.running("v_radar") then pcall(function() exports.v_radar:removeCircleArea(st.circle) end) end
    if isElement(player) then
        setPlayerWantedLevel(player, 0)
        if st.surrendered then setPedAnimation(player) end
        POL.send(player, "wanted:state", 0, "active")
        POL.send(player, "wanted:surrender", false)
        triggerEvent("onPlayerWantedChange", resourceRoot, player, 0, old, publicReasons(st))
    end
    POL.emit("wanted.cleared", player, old, why, st)
    return true
end

-- the level a player arrested now would serve (minutes), then cleared
function W.arrested(player)
    local st = W.list[player]
    local level = st and st.level or 0
    W.clear(player, "arrest")
    return level
end

------------------------------------------------------------------------ surrender

POL.net("wanted:surrender", function(player)
    local st = W.list[player]
    if not st or st.surrendered or not st.offer then return end
    st.surrendered = true
    st.offer = false
    POL.send(player, "wanted:surrender", false)
    setPedAnimation(player, "ped", "handsup", -1, false, false, false, true)
    POL.notify(player, "police_system.wanted.surrendered_self")
    for unit in pairs(st.units) do
        if POL.units.list[unit.id] then
            POL.notify(POL.units.members(unit), "police_system.wanted.suspect_surrendered", { name = POL.nameOf(player) })
            local inc = POL.events.incidentOf(unit, player)
            if inc then POL.events.log(unit, nil, "surrendered", { name = POL.nameOf(player) }, inc) end
        end
    end
    POL.emit("wanted.surrendered", player)
end)

------------------------------------------------------------------------ escalation reports from the suspect's client

-- rammed a police car (the driver's own client reports it)
POL.net("wanted:ram", function(player, veh)
    if not isElement(veh) or not POL.isPoliceVehicleOrAI(veh) then return end
    local pv = getPedOccupiedVehicle(player)
    if not pv or POL.dist(pv, veh) > 15 then return end
    local st = W.list[player]
    W.add(player, "ramming_police", math.max(2, st and st.level or 0))
end)

-- the player shot (1 / s at most): police near the shooter or the impact -> heat
POL.net("wanted:shot", function(player, hx, hy, hz)
    local x, y, z = getElementPosition(player)
    hx, hy, hz = tonumber(hx) or x, tonumber(hy) or y, tonumber(hz) or z
    if POL.policeNear(x, y, z, C.NEAR_SHOT_RADIUS, player) or POL.policeNear(hx, hy, hz, C.NEAR_SHOT_RADIUS, player) then
        W.heat(player, "nearShot")
    end
end)

------------------------------------------------------------------------ quit, death

addEventHandler("onPlayerWasted", root, function()
    if W.list[source] then W.clear(source, "death") end
end)

addEventHandler("onPlayerQuit", root, function()
    local st = W.list[source]
    local cuffed = POL.arrest and POL.arrest.isCuffed(source)
    if (st and st.level >= C.QUIT_WARRANT_LEVEL) or cuffed then
        local units = {}
        if st then for u in pairs(st.units) do units[#units + 1] = u end end
        local cu = cuffed and POL.arrest.cuffedBy(source)
        if cu then units[#units + 1] = cu end
        POL.warrants.automatic(source, cuffed and "escape_custody" or "evading_arrest", units)
    end
    if st then W.clear(source, "quit") end
end)

------------------------------------------------------------------------ resource restart

-- GTA's wanted level outlives a police_system restart, the list does not: without this the stars stayed on the HUD
-- while the MDC (Wanted, Pursuits) and the chase knew nothing of them. The level is taken over (reasons unknown);
-- where the player could not get one now (other dimension, on duty, jailed) it is cleared. A tick later, so every
-- module started already (chase, evasion react to wanted.changed).
function W.start()
    setTimer(function()
        for _, p in ipairs(getElementsByType("player")) do
            local lv = math.min(C.MAX, getPlayerWantedLevel(p))
            if lv > 0 and not W.list[p] then
                if isPedDead(p) or getElementDimension(p) ~= 0 or POL.units.isOnDuty(p)
                    or (POL.jail and POL.jail.isJailed(p)) then
                    setPlayerWantedLevel(p, 0)
                else
                    local st = newState(p)
                    st.level = lv
                    W.list[p] = st
                    changed(p, st, 0)
                end
            end
        end
    end, 50, 1)
end

------------------------------------------------------------------------ exports

function addWanted(player, reasonId, level) return W.add(player, reasonId, level) end

function getWanted(player)
    local st = W.list[player]
    if not st then return { level = 0, reasons = {}, phase = "active" } end
    return { level = st.level, reasons = publicReasons(st), phase = st.phase }
end

function clearWanted(player, why) return W.clear(player, why or "script") end

-- admin test: /polwanted <level> [reason]
addCommandHandler("polwanted", function(p, _, lv, reason)
    if (tonumber(getElementData(p, "admin_level")) or 0) < POLICE.ADMIN_LEVEL then return end
    lv = tonumber(lv) or 0
    if lv <= 0 then W.clear(p, "admin") return end
    W.add(p, reason or "public_shooting", lv)
end)
