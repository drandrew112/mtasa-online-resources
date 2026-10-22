if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- biz_missions / server/supply.lua
-- Supply steal: armed guards hold a shipment somewhere in the country. Kill
-- them (or slip past), take the van or carry the crate (v_inventory item) to
-- the property's entrance. Units: WEED.STEAL_UNITS (biz_weed decides the cap).
-- Fails when the van is destroyed, the crate is gone or the time is up;
-- nothing is lost from the stock.

SUPPLY = {}

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
    local n = M.rand(MIS.GUARDS)
    local count = 0
    for i = 1, n do
        local a = (i / n) * math.pi * 2 + math.random() * 0.6
        local r = 3 + math.random() * 5
        local x, y = spot.x + math.cos(a) * r, spot.y + math.sin(a) * r
        local w = M.pick(MIS.GUARD_WEAPONS)
        local ped = ai:createAIPed(M.pick(MIS.GUARD_SKINS), x, y, spot.z + 0.5, {
            rot = math.deg(a) + 90, behaviour = "enemy", group = MIS.GUARD_GROUP,
            weapon = w[1], ammo = w[2], accuracy = MIS.GUARD_ACCURACY, aggroRadius = 35, leash = 80,
            task = "guard", taskOpts = { x = x, y = y, z = spot.z + 0.5, rot = math.deg(a) + 90 },
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

local function update(m)
    -- the shipment: where is it
    local x, y, z
    if m.variant == "van" then
        if not isElement(m.van) or isVehicleBlown(m.van) then return M.finish(m, "failed", "van_destroyed") end
        x, y, z = getElementPosition(m.van)
        local driver = getVehicleOccupant(m.van, 0)
        if m.phase == "steal" and driver then goDeliver(m, driver) end
    else
        if not M.running("v_inventory") or not exports.v_inventory:isItem(m.crate) then return M.finish(m, "failed", "crate_lost") end
        local cx, cy, cz, dim, _, locType = exports.v_inventory:getItemPosition(m.crate)
        if not cx or dim ~= 0 then return end
        x, y, z = cx, cy, cz
        if m.phase == "steal" and locType ~= "ground" then
            local item = exports.v_inventory:getItem(m.crate)
            local holder = item and item.loc and item.loc.player
            goDeliver(m, holder)
        end
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
        M.notifyTeam(m, info == "crate_lost" and "biz_missions.supply.crate_lost" or "biz_missions.supply.van_destroyed")
    end
    if m.crate and M.running("v_inventory") and exports.v_inventory:isItem(m.crate) then
        exports.v_inventory:destroyInventoryItem(m.crate)
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
    m.variant = (M.running("v_inventory") and math.random() < 0.5) and "crate" or "van"

    if m.variant == "van" then
        m.van = M.track(m, createVehicle(MIS.SUPPLY_VAN, spot.x + 2, spot.y + 2, spot.z + 1, 0, 0, math.random(0, 359)))
        if m.van then
            setVehicleEngineState(m.van, false)
            setElementData(m.van, "biz:mission", m.id)
        else
            m.variant = "crate"
        end
    end
    if m.variant == "crate" then
        local uid = exports.v_inventory:createItem(MIS.CRATE_ITEM, { display = { { label = "Units", value = tostring(m.units) } } }, { type = "none" })
        if not uid or not exports.v_inventory:dropItem(uid, spot.x, spot.y, spot.z, 0, 0, 0) then
            M.finish(m, "cancelled")
            return false, "failed"
        end
        m.crate = uid
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
