-- biz_missions / server/enemies.lua
-- Enemies on the road during a sell mission (MIS.ATTACK_CHANCE of the
-- deliveries). Waves of armed cars: an ai_land_traffic scripted vehicle with
-- the pursuit behaviour, spawned on a lane out of every player's view, chases
-- one van. When it is close (onTrafficVehiclePursuitEngage) it becomes a
-- physics vehicle and everybody inside gets out as an ai_peds enemy of the
-- van's driver.

ENEMY = {}

local function weapon() return MIS.PURSUIT_WEAPONS[math.random(1, #MIS.PURSUIT_WEAPONS)] end

local function pursuersOf(m, v)
    local n = 0
    for _, r in pairs(m.pursuers) do
        if r.van == v and not r.engaged and isElement(r.veh) then n = n + 1 end
    end
    return n
end

local function unseen(x, y, z)
    if not M.running("ai_peds") then return true end
    return not exports.ai_peds:isPointSeenByPlayers(x, y, z, 500, 0)
end

local function spawnPursuer(m, v)
    if not M.running("ai_land_traffic") or not isElement(v.veh) then return false end
    local vx, vy, vz = getElementPosition(v.veh)
    for _ = 1, 12 do
        local a = math.random() * math.pi * 2
        local d = M.rand(MIS.PURSUIT_SPAWN)
        local x, y = vx + math.cos(a) * d, vy + math.sin(a) * d
        if unseen(x, y, vz) then
            local skin = M.pick(MIS.PURSUIT_SKINS)
            local veh, driver = exports.ai_land_traffic:createScriptedVehicle(M.pick(MIS.PURSUIT_MODELS), x, y, vz, {
                skin = skin, speedFactor = 1.4,
                pursuit = { target = v.veh, engageDist = 22, closeDist = 55 },
            })
            if veh then
                local rec = { veh = veh, driver = driver, van = v, passengers = {} }
                local seats = getVehicleMaxPassengers(veh) or 1
                for seat = 1, math.min(seats, M.rand(MIS.PURSUIT_PASSENGERS)) do
                    local ped = createPed(M.pick(MIS.PURSUIT_SKINS), x, y, vz + 1)
                    if ped and warpPedIntoVehicle(ped, veh, seat) then
                        rec.passengers[#rec.passengers + 1] = ped
                    elseif ped then
                        destroyElement(ped)
                    end
                end
                m.pursuers[veh] = rec
                return true
            end
        end
    end
    return false
end

function ENEMY.tick(m)
    if not m.attacked or not m.moving or (m.wavesLeft or 0) <= 0 then return end
    if getTickCount() < (m.nextWave or 0) then return end
    local candidates = {}
    for _, v in ipairs(SELL.activeVans(m)) do
        if v.driver and isElement(v.veh) and pursuersOf(m, v) < MIS.PURSUERS_PER_VAN then candidates[#candidates + 1] = v end
    end
    m.nextWave = getTickCount() + M.rand(MIS.WAVE_GAP) * 1000
    if #candidates == 0 then return end
    local v = candidates[math.random(1, #candidates)]
    if spawnPursuer(m, v) then
        m.wavesLeft = m.wavesLeft - 1
        M.notifyTeam(m, "biz_missions.sell.enemies")
    end
end

--- culprit of an ambush: the van's driver, else the nearest team member
local function culpritOf(m, rec)
    local van = rec.van and rec.van.veh
    local d = isElement(van) and getVehicleOccupant(van, 0)
    if d and getElementType(d) == "player" then return d end
    local x, y, z = getElementPosition(rec.veh)
    local best, bestD
    for _, p in ipairs(M.team(m)) do
        local px, py, pz = getElementPosition(p)
        local dd = getDistanceBetweenPoints3D(x, y, z, px, py, pz)
        if dd < 150 and (not bestD or dd < bestD) then best, bestD = p, dd end
    end
    return best
end

local function arm(ped)
    if not isElement(ped) or not M.running("ai_peds") then return end
    local w = weapon()
    exports.ai_peds:giveAIPedWeapon(ped, w[1], w[2])
end

local function engage(m, rec)
    rec.engaged = true
    local culprit = culpritOf(m, rec)
    local veh = rec.veh
    exports.ai_land_traffic:engageScriptedVehicle(veh, culprit, "enemy")
    local x, y, z = getElementPosition(veh)
    arm(rec.driver)
    for _, ped in ipairs(rec.passengers) do
        if isElement(ped) then
            -- the server does not move seated peds with their vehicle: put them where the vehicle really is
            setElementPosition(ped, x, y, z + 0.6, false)
            setElementSyncer(ped, true)
            if M.running("ai_peds") then
                exports.ai_peds:adoptTrafficDriver(ped, veh, { reason = "ambush", culprit = culprit, behaviour = "enemy" })
                arm(ped)
            end
        end
    end
end

addEvent("onTrafficVehiclePursuitEngage", false)
addEventHandler("onTrafficVehiclePursuitEngage", root, function(veh)
    for _, m in pairs(M.list) do
        local rec = m.pursuers and m.pursuers[veh]
        if rec and not rec.engaged then return engage(m, rec) end
    end
end)

addEvent("onTrafficVehiclePursuitLost", false)
addEventHandler("onTrafficVehiclePursuitLost", root, function(veh)
    for _, m in pairs(M.list) do
        local rec = m.pursuers and m.pursuers[veh]
        if rec then
            m.pursuers[veh] = nil
            for _, ped in ipairs(rec.passengers) do if isElement(ped) then destroyElement(ped) end end
            if M.running("ai_land_traffic") then exports.ai_land_traffic:destroyScriptedVehicle(veh) end
            return
        end
    end
end)

--- mission over: chasing cars go, the ones that already attacked stay with ai_peds / traffic cleanup
function ENEMY.cleanup(m)
    for veh, rec in pairs(m.pursuers or {}) do
        if not rec.engaged then
            for _, ped in ipairs(rec.passengers) do if isElement(ped) then destroyElement(ped) end end
            if M.running("ai_land_traffic") and isElement(veh) then exports.ai_land_traffic:destroyScriptedVehicle(veh) end
        end
    end
    m.pursuers = {}
end
