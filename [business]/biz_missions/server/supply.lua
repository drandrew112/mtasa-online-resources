if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- biz_missions / server/supply.lua
-- Supply steal: armed guards hold a shipment somewhere in the country. Kill
-- them (or slip past), take the van or the crate to the property's entrance.
-- The crate is a world object, not an inventory item: walking into it picks it
-- up (it disappears, the player is the carrier). When the carrier dies or
-- leaves, the crate drops where they were and a radar objective marks it.
-- Units: WEED.STEAL_UNITS (biz_weed decides the cap).
-- Fails when the van is destroyed or the time is up; nothing is lost from the stock.

SUPPLY = {}

local CRATE_MODEL = 2912
local PICKUP_RADIUS = 2.0

local function entranceOf(unitId)
    local u = M.core():getUnit(unitId)
    local p = u and M.core():getProperty(u.propertyId)
    if not p then return nil end
    return p.x, p.y, p.z, p.name
end

local function spawnGuards(m, spot)
    if not M.running("ai_peds") then return 0 end
    local ai = exports.ai_peds
    ai:setAIGroupRelation(MIS.GUARD_GROUP, "player", "hostile")
    local fixed = spot.guards
    local n = fixed and #fixed or M.rand(MIS.GUARDS)
    local count = 0
    for i = 1, n do
        local x, y, z, rot
        if fixed then
            local g = fixed[i]
            x, y, z = g.x, g.y, g.z
            rot = g.rot or (math.deg(math.atan2(spot.y - y, spot.x - x)) - 90)
        else
            local a = (i / n) * math.pi * 2 + math.random() * 0.6
            local r = 3 + math.random() * 5
            x, y, z = spot.x + math.cos(a) * r, spot.y + math.sin(a) * r, spot.z
            rot = math.deg(a) + 90
        end
        local w = M.pick(MIS.GUARD_WEAPONS)
        local ped = ai:createAIPed(M.pick(MIS.GUARD_SKINS), x, y, z + 0.5, {
            rot = rot, behaviour = "enemy", group = MIS.GUARD_GROUP,
            weapon = w[1], ammo = w[2], accuracy = MIS.GUARD_ACCURACY, aggroRadius = 35, leash = 80,
            task = "guard", taskOpts = { x = x, y = y, z = z + 0.5, rot = rot },
            role = "free", keepBody = false,
        })
        if ped then
            m.peds[ped] = true
            count = count + 1
        end
    end
    m.guards = count
    return count
end

local function rows(m)
    local out = {}
    if (m.guardsAlive or 0) > 0 and m.phase == "steal" then
        out[#out + 1] = { id = "guards", label = L.msg("biz_missions.hud.guards"), value = tostring(m.guardsAlive) }
    end
    out[#out + 1] = { id = "units", label = L.msg("biz_missions.hud.supply"), value = tostring(m.units) }
    return out
end

local function refreshTeam(m)
    local ex, ey, ez = m.entrance[1], m.entrance[2], m.entrance[3]
    for _, p in ipairs(M.team(m)) do
        if m.phase == "steal" then
            M.objective(m, p, "target", m.spot.x, m.spot.y, m.spot.z, L.forPlayer(p, "biz_missions.obj.steal", { place = m.spot.name }))
        elseif m.dropped then
            local d = m.dropped
            M.objective(m, p, "target", d[1], d[2], d[3], L.forPlayer(p, "biz_missions.obj.crate_dropped"))
            M.objective(m, p, "deliver", ex, ey, ez, L.forPlayer(p, "biz_missions.obj.bring_supply", { place = m.entranceName }))
        else
            M.clearObjective(m, p, "target")
            M.objective(m, p, "deliver", ex, ey, ez, L.forPlayer(p, "biz_missions.obj.bring_supply", { place = m.entranceName }))
        end
        M.hud(m, p, rows(m))
    end
end

local function goDeliver(m, who)
    if m.phase == "deliver" then return end
    m.phase = "deliver"
    for _, id in ipairs(m.areas) do if M.running("v_radar") then exports.v_radar:removeCircleArea(id) end end
    m.areas = {}
    M.notifyTeam(m, "biz_missions.supply.taken", { player = M.name(who) })
    refreshTeam(m)
end

-- the crate lies on the ground at x, y, z (pick-up sphere + object)
local function placeCrate(m, x, y, z)
    m.crateObj = M.track(m, createObject(CRATE_MODEL, x, y, z, 0, 0, math.random(0, 359)))
    if m.crateObj then setObjectScale(m.crateObj, 0.6) end
    m.crateCol = M.track(m, createColSphere(x, y, z, PICKUP_RADIUS))
end

local function removeCrate(m)
    if isElement(m.crateObj) then destroyElement(m.crateObj) end
    if isElement(m.crateCol) then destroyElement(m.crateCol) end
    m.crateObj, m.crateCol = nil, nil
end

local function dropCrate(m, x, y, z)
    m.carrier = nil
    m.dropped = { x, y, z }
    placeCrate(m, x, y, z - 0.7)
    M.notifyTeam(m, "biz_missions.supply.dropped")
    refreshTeam(m)
end

local function pickUpCrate(m, player)
    removeCrate(m)
    m.carrier, m.dropped = player, nil
    if m.phase == "deliver" then
        M.notifyTeam(m, "biz_missions.supply.taken", { player = M.name(player) })
        refreshTeam(m)
    else
        goDeliver(m, player)
    end
end

local function update(m)
    -- the shipment: where is it
    local x, y, z
    if m.variant == "van" then
        if not isElement(m.van) or isVehicleBlown(m.van) then return M.finish(m, "failed", "van_destroyed") end
        x, y, z = getElementPosition(m.van)
        local driver = getVehicleOccupant(m.van, 0)
        if m.phase == "steal" and driver then goDeliver(m, driver) end
    else
        if not m.carrier then return end
        if not isElement(m.carrier) or isPedDead(m.carrier) then
            -- safety net: the quit / wasted handlers below normally drop it first
            local lx, ly, lz = unpack(m.lastPos or m.spot and { m.spot.x, m.spot.y, m.spot.z })
            return dropCrate(m, lx, ly, lz)
        end
        x, y, z = getElementPosition(m.carrier)
        m.lastPos = { x, y, z }
    end
    -- delivered?
    if m.phase == "deliver" and getDistanceBetweenPoints3D(x, y, z, m.entrance[1], m.entrance[2], m.entrance[3]) <= MIS.DELIVER_RADIUS then
        return M.finish(m, "success")
    end
    -- the HUD every 5 s (time left keeps counting on the client)
    m.tick = (m.tick or 0) + 1
    if m.tick % 5 == 0 then refreshTeam(m) end
end

local function onEnd(m, result, info)
    if result == "success" then
        local added = M.running("biz_weed") and exports.biz_weed:addSupply(m.unitId, m.units) or 0
        M.notifyTeam(m, "biz_missions.supply.delivered", { units = added })
        if isElement(m.founder) then
            M.core():addBizStat(m.founder, "biz_supply_stolen", added)
            M.core():addBizStat(m.founder, "biz_supply_runs", 1)
        end
    elseif result == "timeout" then
        M.notifyTeam(m, "biz_missions.supply.timeout")
    elseif result == "failed" then
        M.notifyTeam(m, "biz_missions.supply.van_destroyed")
    end
end

function SUPPLY.start(founder, unitId, state)
    local ex, ey, ez, ename = entranceOf(unitId)
    if not ex then return false, "activity_offline" end
    local spot = M.pick(MIS.SUPPLY_SPOTS)
    local m = M.create("supply", unitId, state.companyId, founder)
    m.spot, m.entrance, m.entranceName, m.phase = spot, { ex, ey, ez }, ename, "steal"
    m.units = M.rand({ 20, 30 })
    m.update, m.onEnd = update, onEnd
    m.variant = math.random() < 0.5 and "crate" or "van"

    if m.variant == "van" then
        local v = spot.van
        if v then
            m.van = M.track(m, createVehicle(MIS.SUPPLY_VAN, v.x, v.y, v.z + 1, 0, 0, v.rot or 0))
        else
            m.van = M.track(m, createVehicle(MIS.SUPPLY_VAN, spot.x + 2, spot.y + 2, spot.z + 1, 0, 0, math.random(0, 359)))
        end
        if m.van then
            setVehicleEngineState(m.van, false)
            setElementData(m.van, "biz:mission", m.id)
        else
            m.variant = "crate"
        end
    end
    if m.variant == "crate" then
        placeCrate(m, spot.x, spot.y, spot.z + 0.3)
        if not m.crateObj then
            M.finish(m, "cancelled")
            return false, "failed"
        end
    end

    spawnGuards(m, spot)
    m.guardsAlive = m.guards
    if M.running("v_radar") then
        local area = exports.v_radar:addCircleArea(M.team(m), spot.x, spot.y, MIS.STEAL_AREA_RADIUS, 230, 50, 50, 80, true)
        if area then m.areas[#m.areas + 1] = area end
    end
    M.notifyTeam(m, m.variant == "van" and "biz_missions.supply.start_van" or "biz_missions.supply.start_crate", { place = spot.name })
    refreshTeam(m)
    return true
end

-- crate pick-up: walk into it on foot
addEventHandler("onColShapeHit", root, function(el, matchingDim)
    if not matchingDim or getElementType(el) ~= "player" or isPedDead(el) or isPedInVehicle(el) then return end
    for _, m in pairs(M.list) do
        if m.kind == "supply" and m.crateCol == source then
            return pickUpCrate(m, el)
        end
    end
end)

-- the carrier dies or leaves: the crate drops there
local function carrierGone()
    for _, m in pairs(M.list) do
        if m.kind == "supply" and m.carrier == source then
            local x, y, z = getElementPosition(source)
            return dropCrate(m, x, y, z)
        end
    end
end
addEventHandler("onPlayerWasted", root, carrierGone)
addEventHandler("onPlayerQuit", root, carrierGone)

-- guard kills (HUD counter)
addEvent("onAIPedWasted", false)
addEventHandler("onAIPedWasted", root, function()
    for _, m in pairs(M.list) do
        if m.kind == "supply" and m.peds[source] then
            m.guardsAlive = math.max(0, (m.guardsAlive or 1) - 1)
            refreshTeam(m)
            return
        end
    end
end)
