-- police_system / modules/wanted/server/evasion.lua
-- 1 Hz, only for wanted players (nothing runs without a wanted player):
--   * seen = a police vehicle (AI or a player unit's) within EVADE_VEHICLE_DIST, or an officer on foot (AI ped or
--     player) within EVADE_FOOT_DIST. "Seeing" is distance (the server has no line of sight), like GTA's search circle.
--     For DISPATCH_GRACE s after a level rise the suspect counts as seen (the AI units are on their way).
--   * not seen: evasion phase - the stars blink (ui_core setWantedBlinking on the client), v_radar shows a circle at
--     the last known position (to the suspect and the units chasing it). Seen again: the timer starts over.
--     Held for EVADE[level].hold s: evaded, cleared, v_levelsys XP (only when the chase lasted EVADE_MIN_CHASE s and
--     not within EVADE_XP_COOLDOWN of the last one).
--   * interior / other dimension: paused (no progress), continued when the player comes out.
--   * 1 -> 2: a unit with lights on following within FOLLOW_DIST while the suspect keeps moving MOVING_TIME s.
--   * surrender offer: a unit within SURRENDER_DIST and the suspect stands on foot.

local W = POL.wanted
local C = POLICE.WANTED
local lastXp = {}   -- [account] = epoch of the last evasion XP

local function lightsOn(veh) return getElementData(veh, "mkjState") == true end

-- distance of the nearest police vehicle (lights: only ones with lights on) and officer on foot
local function nearestPolice(player, x, y, z)
    local vehD, footD, lightD = math.huge, math.huge, math.huge
    for veh in pairs(POL.ai.vehicles) do
        if isElement(veh) and getElementDimension(veh) == 0 then
            local vx, vy, vz = POL.pos(veh)
            local d = math.sqrt((vx - x) ^ 2 + (vy - y) ^ 2)
            if d < vehD then vehD = d end
            if d < lightD and lightsOn(veh) then lightD = d end
        end
    end
    for ped in pairs(POL.ai.peds) do
        if isElement(ped) and not isPedDead(ped) and not getPedOccupiedVehicle(ped) then
            local px, py = getElementPosition(ped)
            local d = math.sqrt((px - x) ^ 2 + (py - y) ^ 2)
            if d < footD then footD = d end
        end
    end
    for _, p in ipairs(POL.units.onDuty()) do
        if p ~= player and getElementDimension(p) == getElementDimension(player) and not isPedDead(p) then
            local px, py = getElementPosition(p)
            local d = math.sqrt((px - x) ^ 2 + (py - y) ^ 2)
            local veh = getPedOccupiedVehicle(p)
            if veh then
                if d < vehD then vehD = d end
                if d < lightD and lightsOn(veh) then lightD = d end
            elseif d < footD then
                footD = d
            end
        end
    end
    return vehD, footD, lightD
end

local function setBlink(player, st, on)
    if st.blinking == on then return end
    st.blinking = on
    POL.send(player, "wanted:state", st.level, st.phase)
end

local function circleViewers(player, st)
    local list = { player }
    for unit in pairs(st.units) do
        for _, p in ipairs(POL.units.members(unit)) do list[#list + 1] = p end
    end
    return list
end

local function showCircle(player, st)
    if not POL.running("v_radar") then return end
    local r = (C.EVADE[st.level] or C.EVADE[1]).radius
    local ok, id = pcall(function()
        return exports.v_radar:addCircleArea(circleViewers(player, st), st.lx, st.ly, r, 40, 120, 255, 70, true)
    end)
    st.circle = ok and id or nil
end

local function hideCircle(st)
    if st.circle and POL.running("v_radar") then pcall(function() exports.v_radar:removeCircleArea(st.circle) end) end
    st.circle = nil
end

local function evaded(player, st)
    local level = st.level
    local chase = (getTickCount() - st.startedAt) / 1000
    local acc = POL.accountOf(player)
    local now = POL.now()
    local xp = (C.EVADE[level] or C.EVADE[1]).xp
    local give = chase >= C.EVADE_MIN_CHASE and acc and (not lastXp[acc] or now - lastXp[acc] >= C.EVADE_XP_COOLDOWN)
    W.clear(player, "evaded")
    POL.db.stat("evaded", 1)
    triggerEvent("onPlayerWantedEvaded", resourceRoot, player, level)
    if give then
        lastXp[acc] = now
        if POL.running("v_levelsys") then pcall(function() exports.v_levelsys:giveXp(player, xp) end) end
        POL.notify(player, "police_system.wanted.evaded_xp", { xp = xp })
    else
        POL.notify(player, "police_system.wanted.evaded")
    end
end

local function tick()
    local now = getTickCount()
    for player, st in pairs(W.list) do
        if not isElement(player) then
            W.list[player] = nil
        elseif getElementDimension(player) ~= 0 or getElementInterior(player) ~= 0 then
            if st.phase ~= "paused" then
                st.phase = "paused"
                hideCircle(st)
                setBlink(player, st, false)
                POL.send(player, "wanted:state", st.level, st.phase)
            end
        else
            local x, y, z = getElementPosition(player)
            local vehD, footD, lightD = nearestPolice(player, x, y, z)
            local seen = vehD <= C.EVADE_VEHICLE_DIST or footD <= C.EVADE_FOOT_DIST or now < (st.knownUntil or 0)
            if seen or st.surrendered then
                st.lastSeen, st.lx, st.ly, st.lz = now, x, y, z
                if st.phase ~= "active" then
                    st.phase = "active"
                    hideCircle(st)
                    setBlink(player, st, false)
                    POL.send(player, "wanted:state", st.level, st.phase)
                    POL.emit("wanted.phase", player, "active")
                end
            elseif st.phase ~= "evading" then
                st.phase = "evading"
                st.evadeAt = now
                showCircle(player, st)
                setBlink(player, st, true)
                POL.send(player, "wanted:state", st.level, st.phase)
                POL.emit("wanted.phase", player, "evading")
            elseif now - st.evadeAt >= (C.EVADE[st.level] or C.EVADE[1]).hold * 1000 then
                evaded(player, st)
            end

            if W.list[player] and not st.surrendered then
                -- 1 -> 2: followed with lights on and still moving
                local veh = getPedOccupiedVehicle(player)
                local speed = POL.speed(veh or player)
                local moving = veh and speed > C.MOVING_SPEED or (not veh and speed > 4)
                if st.level == 1 and lightD <= C.FOLLOW_DIST and moving then
                    st.movingFor = st.movingFor + 1
                    if st.movingFor >= C.MOVING_TIME then W.add(player, "evading_police", 2) end
                else
                    st.movingFor = 0
                end
                -- surrender offer
                local near = math.min(vehD, footD) <= C.SURRENDER_DIST
                local offer = near and not veh and speed < 0.6 and not isPedDead(player)
                if offer ~= (st.offer or false) then
                    st.offer = offer
                    POL.send(player, "wanted:surrender", offer)
                end
            end
        end
    end
end

-- the units chasing a suspect see its search circle too
POL.on("chase.unitJoined", function(player, unit)
    local st = W.list[player]
    if not st then return end
    st.units[unit] = true
    if st.circle and POL.running("v_radar") then
        pcall(function() exports.v_radar:setCircleAreaVisibleTo(st.circle, circleViewers(player, st)) end)
    end
end)

local timer
POL.on("wanted.changed", function()
    if not timer then timer = setTimer(function()
        if not next(W.list) then killTimer(timer); timer = nil return end
        tick()
    end, 1000, 0) end
end)
