if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- biz_missions / server/sell.lua
-- Product delivery. PER_VEHICLE units per van; every associate online adds a
-- van (biz_weed checks the amount). Each van goes to a different buyer, all
-- within one 30 minute deadline; undelivered cargo is lost after it.
--
-- Who delivers decides the payout (biz_core paySaleDelivery): the founder ->
-- the company, an associate -> 80% his / 20% company, a stranger who took the
-- van -> 60% his, nothing to the company. Other players within VISIBLE_DIST
-- see the vans on the radar. A team driver disconnecting: his van goes, half
-- of its cargo returns to the stock; the founder leaving ends the mission the
-- same way for every van still out.

SELL = {}

local function bonus(dist)
    return 1 + math.min(MIS.DIST_BONUS_MAX, dist / 1000 * MIS.DIST_BONUS_PER_KM)
end

local function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(1, i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

--- n buyers far from the property and from each other (relaxed when the map runs out)
local function pickBuyers(n, ex, ey)
    local pool = {}
    for _, b in ipairs(MIS.BUYERS) do
        if getDistanceBetweenPoints2D(ex, ey, b.x, b.y) >= MIS.BUYER_MIN_DIST then pool[#pool + 1] = b end
    end
    shuffle(pool)
    local chosen = {}
    for _, spread in ipairs({ MIS.BUYER_SPREAD, MIS.BUYER_SPREAD / 2, 0 }) do
        for _, b in ipairs(pool) do
            if #chosen >= n then break end
            local ok = true
            for _, c in ipairs(chosen) do
                if c == b or getDistanceBetweenPoints2D(c.x, c.y, b.x, b.y) < spread then ok = false break end
            end
            if ok then chosen[#chosen + 1] = b end
        end
        if #chosen >= n then break end
    end
    return chosen
end

local function activeVans(m)
    local out = {}
    for _, v in ipairs(m.vans) do
        if v.state == "waiting" or v.state == "driving" then out[#out + 1] = v end
    end
    return out
end
SELL.activeVans = activeVans

--------------------------------------------------------------------------------
-- HUD / objectives / visibility
--------------------------------------------------------------------------------

local function counts(m)
    local done, total, units = 0, #m.vans, 0
    for _, v in ipairs(m.vans) do
        if v.state == "delivered" then done = done + 1 end
        if v.state == "waiting" or v.state == "driving" then units = units + v.units end
    end
    return done, total, units
end

local function refreshPlayers(m)
    local done, total, units = counts(m)
    local team = M.team(m)
    local teamSet = {}
    for _, p in ipairs(team) do teamSet[p] = true end

    for _, p in ipairs(team) do
        local mine
        for _, v in ipairs(activeVans(m)) do
            if v.driver == p then mine = v end
        end
        for _, v in ipairs(m.vans) do
            local key = "van" .. v.idx
            local active = v.state == "waiting" or v.state == "driving"
            if active and v ~= mine and isElement(v.veh) then
                local x, y, z = getElementPosition(v.veh)
                local label = v.thief and L.forPlayer(p, "biz_missions.obj.recover", { player = M.name(v.thief) })
                    or L.forPlayer(p, "biz_missions.obj.van", { n = v.idx })
                M.objective(m, p, key, x, y, z, label)
            else
                M.clearObjective(m, p, key)
            end
        end
        if mine then
            M.objective(m, p, "buyer", mine.buyer.x, mine.buyer.y, mine.buyer.z, L.forPlayer(p, "biz_missions.obj.buyer", { place = mine.buyer.name }))
        else
            M.clearObjective(m, p, "buyer")
        end
        M.hud(m, p, {
            { id = "deliveries", label = L.msg("biz_missions.hud.deliveries"), value = ("%d / %d"):format(done, total) },
            { id = "cargo", label = L.msg("biz_missions.hud.cargo"), value = tostring(units) },
        })
    end

    -- thieves: their own van only
    for _, v in ipairs(activeVans(m)) do
        if v.thief and isElement(v.thief) and not teamSet[v.thief] then
            M.objective(m, v.thief, "buyer", v.buyer.x, v.buyer.y, v.buyer.z, L.forPlayer(v.thief, "biz_missions.obj.buyer", { place = v.buyer.name }))
            M.hud(m, v.thief, { { id = "cargo", label = L.msg("biz_missions.hud.stolen_cargo"), value = tostring(v.units) } })
        end
    end
end
SELL.refresh = refreshPlayers

--- the vans' blips: always for the team, for other players within VISIBLE_DIST
local function visibility(m)
    local teamSet = {}
    for _, p in ipairs(M.team(m)) do teamSet[p] = true end
    for _, v in ipairs(activeVans(m)) do
        if isElement(v.blip) and isElement(v.veh) then
            local vx, vy, vz = getElementPosition(v.veh)
            v.seen = v.seen or {}
            for _, p in ipairs(getElementsByType("player")) do
                local show
                if teamSet[p] or p == v.thief then
                    show = true
                elseif getElementDimension(p) == 0 then
                    local px, py, pz = getElementPosition(p)
                    local d = getDistanceBetweenPoints3D(px, py, pz, vx, vy, vz)
                    if d <= MIS.VISIBLE_DIST then show = true
                    elseif d >= MIS.HIDE_DIST then show = false
                    else show = v.seen[p] and true or false end
                    if show and not v.seen[p] then
                        v.notified = v.notified or {}
                        if not v.notified[p] then
                            v.notified[p] = true
                            M.notify(p, "biz_missions.sell.nearby")
                        end
                    end
                else
                    show = false
                end
                if show ~= (v.seen[p] or false) then
                    v.seen[p] = show or nil
                    setElementVisibleTo(v.blip, p, show and true or false)
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- vans
--------------------------------------------------------------------------------

local function endVan(m, v, state)
    v.state = state
    M.track(m, v.veh)
    if isElement(v.blip) then destroyElement(v.blip) end
    for p in pairs(m.objectives) do M.clearObjective(m, p, "van" .. v.idx) end
    if v.driver then M.clearObjective(m, v.driver, "buyer") end
    if v.thief then
        M.clearObjectives(m, v.thief)
        if not M.isTeam(m, v.thief) then M.hudOff(m, v.thief) end
    end
    if isElement(v.veh) then
        local veh = v.veh
        setTimer(function() if isElement(veh) then destroyElement(veh) end end, state == "delivered" and 3000 or 100, 1)
    end
end

local function returnCargo(m, v)
    local back = math.floor(v.units * MIS.DISCONNECT_RETURN)
    if back > 0 and M.running("biz_weed") then exports.biz_weed:returnProduct(m.unitId, back) end
    return back
end

local function deliver(m, v, driver)
    local out = M.core():paySaleDelivery(m.companyId, driver, v.value, v.units, "weed")
    endVan(m, v, "delivered")
    if not out then return end
    m.payoutCompany = (m.payoutCompany or 0) + out.toCompany
    m.payouts = m.payouts or {}
    m.payouts[#m.payouts + 1] = { player = M.name(driver), role = out.role, toPlayer = out.toPlayer, toCompany = out.toCompany, units = v.units }
    if out.role == "stranger" then
        M.notify(driver, out.toPlayer > 0 and "biz_missions.sell.thief_paid" or "biz_missions.sell.thief_unpaid", { amount = out.toPlayer })
        M.notifyTeam(m, "biz_missions.sell.stolen_delivered", { player = M.name(driver), units = v.units })
        M.hudOff(m, driver)
    elseif out.role == "associate" then
        M.notify(driver, "biz_missions.sell.assoc_paid", { amount = out.toPlayer })
        M.notifyTeam(m, "biz_missions.sell.delivered_by", { player = M.name(driver), units = v.units, amount = out.toCompany })
    else
        M.notifyTeam(m, "biz_missions.sell.delivered_by", { player = M.name(driver), units = v.units, amount = out.toCompany })
    end
end

local function newDriver(m, v, driver)
    v.driver = driver
    v.driverIsTeam = M.isTeam(m, driver)   -- kept: the membership may end before our quit handler runs
    if v.state == "waiting" then v.state = "driving" end
    if not m.moving then
        m.moving = true
        if m.attacked then m.nextWave = getTickCount() + M.rand(MIS.WAVE_FIRST) * 1000 end
    end
    if M.isTeam(m, driver) then
        if v.thief then
            v.thief = nil
            M.notifyTeam(m, "biz_missions.sell.recovered", { player = M.name(driver) })
        end
    elseif v.thief ~= driver then
        v.thief = driver
        M.notify(driver, "biz_missions.sell.you_stole", { place = v.buyer.name })
        M.notifyTeam(m, "biz_missions.sell.stolen", { player = M.name(driver) })
    end
    refreshPlayers(m)
end

local function update(m)
    for _, v in ipairs(activeVans(m)) do
        if not isElement(v.veh) or isVehicleBlown(v.veh) or (isElementInWater(v.veh) and getElementHealth(v.veh) < 300) then
            endVan(m, v, "lost")
            M.notifyTeam(m, "biz_missions.sell.van_destroyed", { n = v.idx, units = v.units })
            if isElement(m.founder) then M.core():addBizStat(m.founder, "biz_deliveries_lost", 1) end
        else
            local driver = getVehicleOccupant(v.veh, 0)
            if driver and getElementType(driver) == "player" then
                if driver ~= v.driver then newDriver(m, v, driver) end
                local x, y, z = getElementPosition(v.veh)
                if getDistanceBetweenPoints3D(x, y, z, v.buyer.x, v.buyer.y, v.buyer.z) <= MIS.BUYER_RADIUS then
                    deliver(m, v, driver)
                end
            elseif v.driver and not isElement(v.driver) then
                v.driver = nil
            end
        end
    end
    if #activeVans(m) == 0 then
        local delivered = 0
        for _, v in ipairs(m.vans) do if v.state == "delivered" then delivered = delivered + 1 end end
        return M.finish(m, delivered > 0 and "success" or "failed")
    end
    visibility(m)
    ENEMY.tick(m)
    m.tick = (m.tick or 0) + 1
    if m.tick % 3 == 0 then refreshPlayers(m) end
end

local function onEnd(m, result)
    -- vans still out: lost (deadline) or half back (founder left / cancelled)
    for _, v in ipairs(activeVans(m)) do
        if result == "founder_left" or result == "cancelled" then
            returnCargo(m, v)
            endVan(m, v, "gone")
        else
            endVan(m, v, "lost")
        end
    end
    if result == "timeout" then M.notifyTeam(m, "biz_missions.sell.timeout") end
    local done, total = counts(m)
    if result ~= "founder_left" then M.notifyTeam(m, "biz_missions.sell.summary", { done = done, total = total }) end
    if isElement(m.founder) and done == total and total >= 2 and m.amount >= 80 then
        M.core():unlockBizAchievement(m.founder, "biz_convoy")
    end
    if isElement(m.founder) and done > 0 then M.core():unlockBizAchievement(m.founder, "biz_green_thumb") end
    ENEMY.cleanup(m)
    for _, v in ipairs(m.vans) do if isElement(v.blip) then destroyElement(v.blip) end end
end

--------------------------------------------------------------------------------

function SELL.start(founder, unitId, state, amount, unitValue, perVehicle)
    local u = M.core():getUnit(unitId)
    local p = u and M.core():getProperty(u.propertyId)
    if not p then return false, "activity_offline" end
    perVehicle = math.max(1, perVehicle or 40)
    local spawns = MIS.VAN_SPAWNS[u.building]
    if spawns then perVehicle = math.max(perVehicle, math.ceil(amount / #spawns)) end   -- one van per spawn spot at most
    local n = math.ceil(amount / perVehicle)
    local buyers = pickBuyers(n, p.x, p.y)
    if #buyers < n then return false, "failed" end

    local m = M.create("sell", unitId, state.companyId, founder)
    m.update, m.onEnd = update, onEnd
    m.amount, m.vehicleCount, m.vans = amount, n, {}
    m.attacked = math.random() < MIS.ATTACK_CHANCE
    m.wavesLeft = m.attacked and math.min(MIS.WAVE_CAP, MIS.WAVE_MAX + n - 1) or 0
    m.pursuers = {}

    local b = M.core():getBuildings()[u.building] or {}
    local rot = tonumber(b.rot) or 0
    local a = math.rad(rot)
    local fx, fy = -math.sin(a), math.cos(a)        -- forward
    local rx, ry = math.cos(a), math.sin(a)         -- right
    local left = amount
    for i = 1, n do
        local units = math.min(perVehicle, left)
        left = left - units
        local side = (i - (n + 1) / 2) * 4
        local x, y, z, vrot = p.x + fx * 7 + rx * side, p.y + fy * 7 + ry * side, p.z + 0.8, rot
        if spawns then
            local s = spawns[i]
            x, y, z, vrot = s.x, s.y, s.z + 1, s.rot
        end
        local veh = createVehicle(MIS.SELL_VAN, x, y, z, 0, 0, vrot)
        if veh then
            setElementData(veh, "biz:mission", m.id)
            setVehicleColor(veh, 40, 40, 40, 40, 40, 40)
            local buyer = buyers[i]
            local value = math.floor(units * unitValue * bonus(getDistanceBetweenPoints2D(p.x, p.y, buyer.x, buyer.y)))
            local blip = createBlipAttachedTo(veh, MIS.VAN_BLIP, 2, 255, 255, 255, 255, 0, 99999, root)
            setElementVisibleTo(blip, root, false)
            m.vans[#m.vans + 1] = { idx = i, veh = veh, units = units, value = value, buyer = buyer, state = "waiting", blip = blip }
        else
            -- no vehicle: that part of the cargo goes back at once
            if M.running("biz_weed") then exports.biz_weed:returnProduct(unitId, units) end
        end
    end
    if #m.vans == 0 then
        M.finish(m, "cancelled")
        return false, "failed"
    end
    -- everyone inside the unit goes out to the entrance
    if M.running("biz_int") then
        for _, pl in ipairs(exports.biz_int:getPlayersInUnit(unitId) or {}) do
            exports.biz_int:exitUnit(pl)
        end
    end
    local warnKey = #m.vans > 1 and "biz_missions.sell.start_many" or "biz_missions.sell.start_one"
    M.notifyTeam(m, warnKey, { vans = #m.vans, units = amount })
    visibility(m)
    refreshPlayers(m)
    return true
end

--------------------------------------------------------------------------------
-- disconnects / the founder leaving
--------------------------------------------------------------------------------

addEventHandler("onPlayerQuit", root, function()
    local player = source
    for _, m in pairs(M.list) do
        if m.kind == "sell" then
            for _, v in ipairs(activeVans(m)) do
                if v.driver == player and v.driverIsTeam and isElement(v.veh) and getVehicleOccupant(v.veh, 0) == player then
                    local back = returnCargo(m, v)
                    endVan(m, v, "gone")
                    M.notifyTeam(m, "biz_missions.sell.driver_left", { player = M.name(player), units = back })
                end
                if v.thief == player then v.thief = nil end
                if v.seen then v.seen[player] = nil end
                if v.notified then v.notified[player] = nil end
            end
            m.hudPlayers[player] = nil
            m.objectives[player] = nil
        end
    end
end)
