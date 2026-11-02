-- Safe scene. A scene is safe by default (scene.safe = true); only one with EMS 2 + PD 2 can start "not safe".
-- Then the police must make it safe, and it is detected automatically as well:
--   threat     a fighter / hostile ped, or an armed suspect
--   handled    cuffed, down (medsys dazed / unconscious / clinical death / dead), gone, surrendered with an officer
--              within SAFETY.SURRENDER_CONTROL, or fled: farther than FLED_RADIUS from the centre for FLED_TIME
--   automatic  every threat handled + an officer within CONFIRM_RADIUS of the centre -> safe (by that officer's unit)
--   manual     the MDC "Report scene safe" button (police_system event onPoliceSceneSafeReported): the officer is
--              within CONFIRM_RADIUS and no unhandled threat is within ACTIVE_RADIUS
--   relapse    a handled threat fights again near the scene -> not safe again
-- The ERM task carries meta.safety (state, since, by, auto, staging point); med_erm shows the field, warns the crews
-- on approach and routes them to the staging point. The police call carries the same state + the threat list; the
-- officers of the call get a HUD tracker near the scene and cannot close the call before it is safe. Every change
-- is a system line in both inter-agency channels.

Safety = {}

local S = VSM.SAFETY

local function police() return Agencies.get("pd") end
local function ems() return Agencies.get("ems") end

---------------------------------------------------------------- staging point

-- a road point STAGING_MIN..STAGING_MAX from the centre (navmesh), else a plain point on the ring -> { x, y, z } | nil
local function stagingPoint(c, interior)
    if (tonumber(interior) or 0) ~= 0 then return nil end
    local best
    if vsmResourceRunning("navmesh") then
        local mid = (S.STAGING_MIN + S.STAGING_MAX) / 2
        for i = 0, 7 do
            local a = i * math.pi / 4
            local px, py = c[1] + math.cos(a) * mid, c[2] + math.sin(a) * mid
            local ok, lanes = pcall(function() return exports.navmesh:getNearestLanes(px, py, c[3], { count = 1 }) end)
            local lane = ok and type(lanes) == "table" and lanes[1]
            if lane and lane.x then
                local d = getDistanceBetweenPoints2D(lane.x, lane.y, c[1], c[2])
                if d >= S.STAGING_MIN and d <= S.STAGING_MAX then
                    local score = math.abs(d - mid) + (lane.distance or 0)
                    if not best or score < best.score then best = { x = lane.x, y = lane.y, z = lane.z, score = score } end
                end
            end
        end
    end
    if not best then return nil end
    return { vsmRound(best.x, 1), vsmRound(best.y, 1), vsmRound(best.z, 1) }
end

---------------------------------------------------------------- state views

-- meta.safety of the ERM task
function Safety.ermField(scene)
    local s = scene.safety
    if not s then return nil end
    return { state = s.state, since = s.since, by = s.by or false, auto = s.auto or false, staging = s.staging or false }
end

-- the safety info of the police call (MDC block, tracker, close lock)
function Safety.policeInfo(scene)
    local s = scene.safety
    if not s then return nil end
    return {
        state = s.state, since = s.since, by = s.by or false, auto = s.auto or false,
        threats = s.threats or {}, activeNear = s.activeNear or false,
        emsWaitingSince = scene.emsAssignedAt or false, ermTask = scene.tasks.ems and scene.tasks.ems.id or false,
        radius = S.CONFIRM_RADIUS,
    }
end

local function pushErm(scene)
    local t = scene.tasks.ems
    if t and not t.closed then ems().setMeta(t.id, "safety", Safety.ermField(scene)) end
end

local function pushPolice(scene, force)
    local t = scene.tasks.pd
    if not t or t.closed then return end
    local info = Safety.policeInfo(scene)
    local key = toJSON(info)
    if force or key ~= scene.safety.lastPush then
        scene.safety.lastPush = key
        police().setSafety(t.id, info)
    end
end

local function systemLine(scene, key, params)
    for _, id in ipairs(VSM.AGENCY_ORDER) do
        local t = scene.tasks[id]
        if t and not t.closed then Agencies.get(id).system(t.id, key, params) end
    end
end

---------------------------------------------------------------- start / stop

function Safety.start(scene, safe)
    if safe ~= false then return end
    scene.safety = { state = "unsafe", since = vsmNow(), threats = {}, fled = {}, staging = stagingPoint(scene.center, scene.interior) }
end

-- after the tasks exist (their ids are in scene.tasks)
function Safety.announce(scene)
    if not scene.safety then return end
    pushErm(scene)
    pushPolice(scene, true)
    systemLine(scene, "v_scenemanager.safety.msg_unsafe", {})
end

function Safety.stop(scene)
    if not scene.safety then return end
    Safety.trackers(scene, {})
    scene.safety = nil
end

local function setState(scene, state, by, auto)
    local s = scene.safety
    if s.state == state then return end
    s.state, s.since, s.by, s.auto = state, vsmNow(), by or false, auto or false
    pushErm(scene)
    pushPolice(scene, true)
    if state == "safe" then
        systemLine(scene, auto and "v_scenemanager.safety.msg_safe_auto" or "v_scenemanager.safety.msg_safe", { callsign = by or "-" })
        vsmLog("scene '%s' #%d is safe (%s, %s)", scene.name, scene.id, tostring(by), auto and "automatic" or "reported")
    else
        systemLine(scene, "v_scenemanager.safety.msg_unsafe_again", {})
        vsmLog("scene '%s' #%d is not safe again", scene.name, scene.id)
    end
    Safety.trackers(scene, state == "safe" and {} or nil)
end

function Safety.isUnsafe(scene) return scene.safety ~= nil and scene.safety.state == "unsafe" end

---------------------------------------------------------------- threats

local function isThreat(entry)
    local role = vsmRoleById(entry.role)
    if role and role.threat then return true end
    return entry.role == "suspect" and entry.ai and (entry.ai.weapon or 0) ~= 0
end

-- the units of the scene's police call: { { player, callsign }, ... }
local function officers(scene)
    local t = scene.tasks.pd
    if not t or t.closed then return {} end
    return police().officers(t.id) or {}
end

local function nearestOfficer(list, x, y, z, r)
    local best, bd
    for _, o in ipairs(list) do
        if isElement(o.player) then
            local px, py, pz = getElementPosition(o.player)
            local d = getDistanceBetweenPoints3D(x, y, z, px, py, pz)
            if d <= r and (not bd or d < bd) then best, bd = o, d end
        end
    end
    return best
end

-- -> status of one threat: "down" | "cuffed" | "surrendered" | "fled" | "gone" | "active"; engaging (fights now)
local function threatStatus(scene, ped, cops, now)
    if not isElement(ped) then return "gone", false end
    if Npc.isCuffed(ped) then return "cuffed", false end
    if Npc.isDown(ped) then return "down", false end
    local x, y, z = getElementPosition(ped)
    local c = scene.center
    if Npc.isSurrendered(ped) then
        if nearestOfficer(cops, x, y, z, S.SURRENDER_CONTROL) or Npc.nearestOfficer(x, y, z, S.SURRENDER_CONTROL, scene.dimension, scene.interior) then
            return "surrendered", false
        end
        return "active", false
    end
    local fled = scene.safety.fled
    if getDistanceBetweenPoints2D(x, y, c[1], c[2]) > S.FLED_RADIUS then
        fled[ped] = fled[ped] or now
        if now - fled[ped] >= S.FLED_TIME then return "fled", false end
    else
        fled[ped] = nil
    end
    local engaging = false
    if vsmResourceRunning(VSM.AIPEDS) then
        local ok, beh, mode = pcall(function() return exports[VSM.AIPEDS]:getAIPedBehaviour(ped) end)
        engaging = ok and beh == "enemy" and mode == "engage"
    end
    return "active", engaging
end

local function tickScene(scene)
    local s = scene.safety
    local now = vsmNow()
    local cops = officers(scene)
    local c = scene.center
    local threats, activeNear, clear, relapse = {}, false, true, false
    for ped, entry in pairs(scene.pedEntries) do
        if isThreat(entry) then
            local status, engaging = threatStatus(scene, ped, cops, now)
            threats[#threats + 1] = { id = entry.id, role = entry.role, weapon = entry.ai and entry.ai.weapon or 0, status = status }
            if status == "active" then
                clear = false
                local x, y = getElementPosition(ped)
                local d = getDistanceBetweenPoints2D(x, y, c[1], c[2])
                if d <= S.ACTIVE_RADIUS then activeNear = true end
                if engaging and d <= S.FLED_RADIUS then relapse = true end
            end
        end
    end
    table.sort(threats, function(a, b) return a.id < b.id end)
    s.threats, s.activeNear = threats, activeNear

    if s.state == "unsafe" then
        local o = clear and nearestOfficer(cops, c[1], c[2], c[3], S.CONFIRM_RADIUS)
        if o then setState(scene, "safe", o.callsign, true) end
    elseif relapse then
        setState(scene, "unsafe")
    end
    pushPolice(scene)
    if s.state == "unsafe" then Safety.trackers(scene, cops) end
end

---------------------------------------------------------------- HUD tracker of the officers

-- cops = the call's officers (nil: computed), {} = everyone's tracker off
function Safety.trackers(scene, cops)
    local s = scene.safety
    if not s then return end
    s.tracked = s.tracked or {}
    local want = {}
    cops = cops or officers(scene)
    local c = scene.center
    for _, o in ipairs(cops) do
        if isElement(o.player) then
            local x, y, z = getElementPosition(o.player)
            if getDistanceBetweenPoints3D(x, y, z, c[1], c[2], c[3]) <= S.TRACKER_RADIUS then want[o.player] = true end
        end
    end
    local active = 0
    for _, t in ipairs(s.threats or {}) do if t.status == "active" then active = active + 1 end end
    local data = { call = scene.tasks.pd and scene.tasks.pd.id or 0, emsSince = scene.emsAssignedAt or false, active = active }
    for player in pairs(want) do
        triggerClientEvent(player, "vsm:tracker", resourceRoot, scene.id, data)
        s.tracked[player] = true
    end
    for player in pairs(s.tracked) do
        if not want[player] then
            if isElement(player) then triggerClientEvent(player, "vsm:tracker", resourceRoot, scene.id, false) end
            s.tracked[player] = nil
        end
    end
end

setTimer(function()
    for _, scene in pairs(Live.scenes) do
        if scene.safety and not scene.closedAt then tickScene(scene) end
    end
end, S.TICK, 0)

---------------------------------------------------------------- manual report (police_system MDC)

addEvent("onPoliceSceneSafeReported")
addEventHandler("onPoliceSceneSafeReported", root, function(callId, callsign, player)
    local scene = Live.byAgencyTask("pd", callId)
    if not scene or not Safety.isUnsafe(scene) or not isElement(player) then return end
    local c = scene.center
    local x, y, z = getElementPosition(player)
    if getDistanceBetweenPoints3D(x, y, z, c[1], c[2], c[3]) > S.CONFIRM_RADIUS then return end
    tickScene(scene)
    if not Safety.isUnsafe(scene) then return end
    if scene.safety.activeNear then
        pushPolice(scene, true)
        return
    end
    setState(scene, "safe", callsign, false)
end)

addEventHandler("onPlayerQuit", root, function()
    for _, scene in pairs(Live.scenes) do
        if scene.safety and scene.safety.tracked then scene.safety.tracked[source] = nil end
        if scene.safety and scene.safety.fled then scene.safety.fled[source] = nil end
    end
end)
