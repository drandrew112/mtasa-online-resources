if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Mission HUD (server: mode_mission/server/runner.lua, jobmanager:missionHud once a second and on
-- every stage change):
--   * objective line at the top, the stage title as a subtitle when a stage starts
--   * Team lives and the objective progress as ui_core stat trackers, the time limit as drawTimer
--   * targets: v_radar objectives + a marker in the world (zones get a ring wall)
--   * red radar blips on the enemies
--   * hold-E interaction points
--   * squad guard: players of one mission cannot hurt each other (the MTA team has no friendly
--     fire; this covers explosions, vehicles and melee as well)

local uicore = exports.ui_core
local screenW, screenH = guiGetScreenSize()
local SCALE = (uicore:ui(1000) or 1000) / 1000
local function S(v) return v * SCALE end

JobMission = { active = false, data = nil }

local INTERACT_KEY = "e"
local INTERACT_RANGE = 2.2

local deadline = nil
local radarIds = {}             -- target index -> v_radar objective id
local radarPos = {}
local enemyBlips = {}           -- element -> blip
local trackers = {}             -- tracker id -> true
local hold = nil                -- { id, start, ms }
local rendering = false
local render

local function radarReady()
    local res = getResourceFromName("v_radar")
    return res and getResourceState(res) == "running"
end

local function objectiveLabel(o)
    if o.label then return o.label end
    return L("v_jobmanager.mission.obj." .. o.type)
end

function JobMission.objectiveText()
    local d = JobMission.data
    if not d then return "" end
    return d.title or ""
end

--------------------------------------------------------------------------------
-- radar + blips
--------------------------------------------------------------------------------

local function clearRadar()
    if radarReady() then
        for _, id in pairs(radarIds) do exports.v_radar:removeObjective(id) end
    end
    radarIds, radarPos = {}, {}
end

local function syncRadar(targets, title)
    if not radarReady() then return end
    for i = #targets + 1, #radarIds do
        exports.v_radar:removeObjective(radarIds[i])
        radarIds[i], radarPos[i] = nil, nil
    end
    for i, t in ipairs(targets) do
        local x, y, z = t[1], t[2], t[3]
        if isElement(t[4]) then x, y, z = getElementPosition(t[4]) end
        local old = radarPos[i]
        if not radarIds[i] then
            radarIds[i] = exports.v_radar:addObjective(x, y, z, title)
            radarPos[i] = { x, y, z }
        elseif not old or (old[1] - x) ^ 2 + (old[2] - y) ^ 2 > 25 then
            exports.v_radar:updateObjective(radarIds[i], x, y, z, title)
            radarPos[i] = { x, y, z }
        end
    end
end

local function syncEnemies(list)
    local keep = {}
    for _, el in ipairs(list or {}) do
        if isElement(el) then
            keep[el] = true
            if not isElement(enemyBlips[el]) then
                local blip = createBlipAttachedTo(el, 0, 1, 230, 40, 40, 255, 1, 250)
                if blip then setElementDimension(blip, getElementDimension(localPlayer)) end
                enemyBlips[el] = blip
            end
        end
    end
    for el, blip in pairs(enemyBlips) do
        if not keep[el] then
            if isElement(blip) then destroyElement(blip) end
            enemyBlips[el] = nil
        end
    end
end

local function clearTrackers()
    for id in pairs(trackers) do uicore:removeStatTracker(id) end
    trackers = {}
end

local function syncTrackers(d)
    local want = {}
    want["jm_lives"] = true
    uicore:addStatTracker("jm_lives", L("v_jobmanager.mission.team_lives"), tostring(d.lives), { order = 1, color = d.lives == 0 and { 230, 80, 70 } or nil })
    for i, o in ipairs(d.objectives) do
        if o.progress and not o.done then
            local id = "jm_obj" .. i
            want[id] = true
            uicore:addStatTracker(id, objectiveLabel(o), o.progress, { order = 1 + i })
        end
    end
    for id in pairs(trackers) do if not want[id] then uicore:removeStatTracker(id) end end
    trackers = want
end

--------------------------------------------------------------------------------
-- state
--------------------------------------------------------------------------------

local function setRendering(on)
    if on == rendering then return end
    rendering = on
    if on then addEventHandler("onClientRender", root, render) else removeEventHandler("onClientRender", root, render) end
end

local function stop()
    JobMission.active, JobMission.data, deadline, hold = false, nil, nil, nil
    clearRadar()
    syncEnemies({})
    clearTrackers()
    setRendering(false)
end

addEvent("jobmanager:missionHud", true)
addEventHandler("jobmanager:missionHud", resourceRoot, function(d)
    if type(d) ~= "table" then return stop() end
    JobMission.active, JobMission.data = true, d
    deadline = d.timeLeft and (getTickCount() + d.timeLeft) or nil
    if d.stageChanged then
        clearRadar()
        uicore:drawSubtitle(d.title, 7000)
        playSoundFrontEnd(d.stage == 1 and 41 or 43)
    end
    syncRadar(d.targets or {}, d.title)
    syncEnemies(d.enemies)
    syncTrackers(d)
    setRendering(true)
end)

for _, name in ipairs({ "jobmanager:matchEnded", "jobmanager:matchLeft", "jobmanager:matchQuietEnd" }) do
    addEvent(name, true)
    addEventHandler(name, resourceRoot, stop)
end

addEventHandler("onClientResourceStop", resourceRoot, function()
    clearRadar()
    clearTrackers()
end)

--------------------------------------------------------------------------------
-- world markers + interaction
--------------------------------------------------------------------------------

local YELLOW = { 255, 200, 0 }

local function ring(x, y, z, radius, height, rgb, alpha)
    local verts = {}
    local seg = 36
    local top = tocolor(rgb[1], rgb[2], rgb[3], 0)
    local bottom = tocolor(rgb[1], rgb[2], rgb[3], alpha)
    for i = 0, seg do
        local a = i / seg * math.pi * 2
        local px, py = x + math.cos(a) * radius, y + math.sin(a) * radius
        verts[#verts + 1] = { px, py, z, bottom }
        verts[#verts + 1] = { px, py, z + height, top }
    end
    dxDrawPrimitive3D("trianglestrip", false, unpack(verts))
end

-- downward pointing pyramid over a target
local function pointer(x, y, z, rgb)
    local bob = math.sin(getTickCount() / 300) * 0.2
    z = z + bob
    local c1, c2 = tocolor(rgb[1], rgb[2], rgb[3], 220), tocolor(rgb[1] * 0.7, rgb[2] * 0.7, rgb[3] * 0.7, 220)
    local s = 0.45
    local tip = { x, y, z }
    local a, b, c, d = { x - s, y - s, z + 0.9 }, { x + s, y - s, z + 0.9 }, { x + s, y + s, z + 0.9 }, { x - s, y + s, z + 0.9 }
    local function v(p, col) return { p[1], p[2], p[3], col } end
    dxDrawPrimitive3D("trianglelist", false,
        v(tip, c1), v(a, c1), v(b, c1),  v(tip, c2), v(b, c2), v(c, c2),
        v(tip, c1), v(c, c1), v(d, c1),  v(tip, c2), v(d, c2), v(a, c2))
end

local function nearestPoint(d)
    local px, py, pz = getElementPosition(localPlayer)
    for _, p in ipairs(d.points or {}) do
        if getDistanceBetweenPoints3D(px, py, pz, p.x, p.y, p.z) <= INTERACT_RANGE then return p end
    end
end

render = function()
    local d = JobMission.data
    if not d then return end
    if getElementData(localPlayer, "scoreboardOpen") then return end
    local now = getTickCount()

    -- objective line
    local line = d.title or ""
    if d.total and d.total > 1 then line = line .. "   " .. L("v_jobmanager.mission.stage_of", { stage = d.stage, total = d.total }) end
    dxDrawText(line, S(2), S(42) + S(2), screenW + S(2), S(80) + S(2), tocolor(0, 0, 0, 200), S(1.35), "default-bold", "center", "top")
    dxDrawText(line, 0, S(42), screenW, S(80), tocolor(255, 220, 90, 255), S(1.35), "default-bold", "center", "top")

    if deadline then uicore:drawTimer(string.format("%d:%02d", math.floor(math.max(0, deadline - now) / 60000), math.floor(math.max(0, deadline - now) / 1000) % 60)) end

    for _, t in ipairs(d.targets or {}) do
        local x, y, z = t[1], t[2], t[3]
        if isElement(t[4]) then
            x, y, z = getElementPosition(t[4])
            pointer(x, y, z + 2.2, YELLOW)
        elseif t.radius then
            ring(x, y, z - 1, t.radius, math.min(t.height or 8, 6), YELLOW, 120)
        else
            pointer(x, y, z + 1.4, YELLOW)
        end
    end

    -- interaction points
    for _, p in ipairs(d.points or {}) do ring(p.x, p.y, p.z - 1, 0.8, 1.2, { 90, 200, 255 }, 170) end
    local p = nearestPoint(d)
    if p then
        local holding = getKeyState(INTERACT_KEY) and not JobUi.inputBlocked() and not isPedInVehicle(localPlayer)
        if holding then
            if not hold or hold.id ~= p.id then hold = { id = p.id, start = now, ms = p.holdMs } end
        else
            hold = nil
        end
        local progress = hold and math.min(1, (now - hold.start) / hold.ms) or 0
        local text = L("v_jobmanager.mission.hold_to", { key = INTERACT_KEY:upper(), label = p.label or L("v_jobmanager.mission.obj.interact") })
        local w, h = S(320), S(46)
        local x, y = (screenW - w) / 2, screenH * 0.7
        dxDrawRectangle(x, y, w, h, tocolor(0, 0, 0, 170))
        dxDrawText(text, x, y, x + w, y + h - S(8), tocolor(255, 255, 255), S(1.05), "default-bold", "center", "center")
        dxDrawRectangle(x, y + h - S(6), w * progress, S(6), tocolor(90, 200, 255, 230))
        if hold and progress >= 1 and not hold.sent then
            hold.sent = true
            triggerServerEvent("jobmanager:missionInteract", resourceRoot, p.id)
            playSoundFrontEnd(41)
        end
    else
        hold = nil
    end
end

--------------------------------------------------------------------------------
-- squad guard
--------------------------------------------------------------------------------

local function squadOf(el)
    return isElement(el) and getElementData(el, "jobs.squad") or nil
end

local function samePlayerSquad(attacker)
    if isElement(attacker) and getElementType(attacker) == "vehicle" then attacker = getVehicleController(attacker) end
    if not isElement(attacker) or getElementType(attacker) ~= "player" or attacker == localPlayer then return false end
    local mine = squadOf(localPlayer)
    return mine ~= nil and squadOf(attacker) == mine
end

addEventHandler("onClientPlayerDamage", localPlayer, function(attacker)
    if samePlayerSquad(attacker) then cancelEvent() end
end)

addEventHandler("onClientVehicleDamage", root, function(attacker)
    local occupant = getVehicleController(source)
    if occupant == localPlayer and samePlayerSquad(attacker) then cancelEvent() end
end)

--------------------------------------------------------------------------------
-- chasing enemy vehicles: the vehicle's syncer drives its GTA driver ped
--------------------------------------------------------------------------------

local chase = {}        -- vehicle -> { stuckSince, reverseUntil }

local function steer(vehicle, ped, target)
    local st = chase[vehicle] or {}
    chase[vehicle] = st
    local now = getTickCount()
    local vx, vy, vz = getElementPosition(vehicle)
    local carrier = getPedOccupiedVehicle(target) or target
    local tx, ty = getElementPosition(carrier)
    local tvx, tvy = getElementVelocity(carrier)
    tx, ty = tx + tvx * 50, ty + tvy * 50        -- about a second ahead
    local m = getElementMatrix(vehicle)
    local fx, fy = m[2][1], m[2][2]
    local dx, dy = tx - vx, ty - vy
    local dist = math.sqrt(dx * dx + dy * dy)
    local cross = fx * dy - fy * dx
    local dot = fx * dx + fy * dy
    local angle = math.atan2(cross, dot)       -- > 0: target on the left
    local svx, svy, svz = getElementVelocity(vehicle)
    local speed = math.sqrt(svx * svx + svy * svy + svz * svz) * 180

    if st.reverseUntil and now < st.reverseUntil then
        setPedControlState(ped, "accelerate", false)
        setPedControlState(ped, "brake_reverse", true)
        setPedAnalogControlState(ped, "vehicle_left", angle < 0 and 1 or 0)
        setPedAnalogControlState(ped, "vehicle_right", angle > 0 and 1 or 0)
        return
    end
    st.reverseUntil = nil
    if speed < 3 and dist > 8 then
        st.stuckSince = st.stuckSince or now
        if now - st.stuckSince > 2000 then st.reverseUntil, st.stuckSince = now + 1500, nil end
    else
        st.stuckSince = nil
    end
    local amount = math.min(1, math.abs(angle) / 0.6)
    setPedAnalogControlState(ped, "vehicle_left", angle > 0 and amount or 0)
    setPedAnalogControlState(ped, "vehicle_right", angle < 0 and amount or 0)
    local sharp = math.abs(angle) > 1.4 and speed > 50
    setPedControlState(ped, "accelerate", not sharp)
    setPedControlState(ped, "brake_reverse", sharp)
    setPedControlState(ped, "handbrake", math.abs(angle) > 1.0 and speed > 40)
end

local function release(vehicle, ped)
    chase[vehicle] = nil
    if isElement(ped) then
        for _, c in ipairs({ "accelerate", "brake_reverse", "handbrake" }) do setPedControlState(ped, c, false) end
        setPedAnalogControlState(ped, "vehicle_left", 0)
        setPedAnalogControlState(ped, "vehicle_right", 0)
    end
end

setTimer(function()
    for _, vehicle in ipairs(getElementsByType("vehicle", root, true)) do
        local target = getElementData(vehicle, "jobs.chase")
        local ped = getVehicleController(vehicle)
        if isElement(target) and isElement(ped) and getElementType(ped) == "ped" and isElementSyncer(vehicle) then
            steer(vehicle, ped, target)
        elseif chase[vehicle] then
            release(vehicle, ped)
        end
    end
    for vehicle in pairs(chase) do
        if not isElement(vehicle) then chase[vehicle] = nil end
    end
end, 100, 0)
