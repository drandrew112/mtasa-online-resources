if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Left-behind watch. Every BAG.WATCH_INTERVAL an item lying on the ground (or riding on a stretcher
-- that is out) is "left behind" when no medic is near it and its ambulance is far away (or driving
-- away). The crew is warned (repeated every BAG.WARN_REPEAT s) and sees a blip on the item; after
-- BAG.ABANDON_TIME s it is returned to the ambulance with an empty stock. An ambulance in a
-- hospital bay with an item out shows "Equipment missing" over its side door (BAG_DATA.MISSING on
-- the anchor, client/hud.lua).

local Blips = {} -- item -> blip

-- ---------------------------------------------------------------------------------------------
-- Crew
-- ---------------------------------------------------------------------------------------------

local function isRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

-- The ERM unit of the ambulance (med_erm), else its occupants; plus whoever handled the items last
function getKitCrew(kit)
    local list, seen = {}, {}
    local function add(player)
        if isElement(player) and getElementType(player) == "player" and not seen[player] then
            seen[player] = true
            list[#list + 1] = player
        end
    end
    local vehicle = kit.vehicle
    if isElement(vehicle) then
        if isRunning("med_erm") then
            local unit = exports.med_erm:getVehicleUnit(vehicle)
            if unit and unit.members then
                for _, name in ipairs(unit.members) do add(getPlayerFromName(name)) end
            end
        end
        for _, occupant in pairs(getVehicleOccupants(vehicle) or {}) do add(occupant) end
    end
    for _, item in pairs(kit.items) do
        add(item.carrier)
        add(item.lastHolder)
    end
    return list
end

function notifyCrew(kit, text, alert)
    for _, player in ipairs(getKitCrew(kit)) do notify(player, text, L.msg("med_bag.kits.ems_equipment"), alert) end
end

-- ---------------------------------------------------------------------------------------------
-- Blips (at the item's position, moved every watch tick)
-- ---------------------------------------------------------------------------------------------

local function removeBlip(item)
    local blip = Blips[item]
    Blips[item] = nil
    if isElement(blip) then destroyElement(blip) end
end

local function showBlip(item, crew, x, y, z, dim, int)
    local blip = Blips[item]
    if not isElement(blip) then
        local b = BAG.BLIP
        blip = createBlip(x, y, z, b.icon, b.size, b.color[1], b.color[2], b.color[3], 255, 0, 99999.0, root)
        if not blip then return end
        Blips[item] = blip
        setElementVisibleTo(blip, root, false)
    else
        setElementPosition(blip, x, y, z)
    end
    setElementDimension(blip, dim or 0)
    setElementInterior(blip, int or 0)
    for _, player in ipairs(crew) do setElementVisibleTo(blip, player, true) end
end

-- ---------------------------------------------------------------------------------------------
-- Detection
-- ---------------------------------------------------------------------------------------------

local function medicNear(x, y, z, dim, int)
    local players = getElementsWithinRange(x, y, z, BAG.LEFT_GUARD_RADIUS, "player", int, dim)
    for _, player in ipairs(players) do
        if not isPedDead(player) and hasEquipmentAccess(player) then return true end
    end
    return false
end

local function vehicleSpeed(vehicle)
    local vx, vy, vz = getElementVelocity(vehicle)
    return math.sqrt(vx * vx + vy * vy + vz * vz) * 180 -- km/h
end

-- On the ground or on a stretcher that is out of the ambulance -> left, x, y, z, dim, int
local function isLeftBehind(item)
    if item.state ~= "ground" and item.state ~= "stretcher" then return false end
    local vehicle = item.kit.vehicle
    if not isElement(vehicle) then return false end
    local x, y, z, dim, int = itemPosition(item)
    if not x then return false end
    if medicNear(x, y, z, dim, int) then return false end
    if dim ~= getElementDimension(vehicle) or int ~= getElementInterior(vehicle) then return true, x, y, z, dim, int end
    local vx, vy, vz = getElementPosition(vehicle)
    local d = getDistanceBetweenPoints3D(x, y, z, vx, vy, vz)
    if d > BAG.LEFT_DISTANCE then return true, x, y, z, dim, int end
    return d > BAG.LEFT_MOVING_DISTANCE and vehicleSpeed(vehicle) > BAG.LEFT_MOVING_SPEED, x, y, z, dim, int
end

local function watch()
    local now = getTickCount()
    for _, kit in eachKit() do
        local leftNames, crew = {}, nil
        for _, kind in ipairs(BAG.KINDS) do
            local item = kit.items[kind]
            local left, x, y, z, dim, int = false
            if item then left, x, y, z, dim, int = isLeftBehind(item) end
            if left then
                crew = crew or getKitCrew(kit)
                if not item.leftTick then
                    item.leftTick, item.warnTick = now, nil
                end
                if now - item.leftTick >= BAG.ABANDON_TIME * 1000 then
                    removeBlip(item)
                    item.leftTick, item.warnTick = nil, nil
                    returnItemToVehicle(item, true)
                    notifyCrew(kit, L.msg("med_bag.watch.was_recovered_by_dispatch_and_returned", { kind = bagItemName(kind), kit = kitLabel(kit), kind2 = kind == "bag" and L.msg("med_bag.watch.empty_restock_it_at_hospital") or "" }), true)
                else
                    showBlip(item, crew, x, y, z, dim, int)
                    if not item.warnTick or now - item.warnTick >= BAG.WARN_REPEAT * 1000 then
                        item.warnTick = now
                        leftNames[#leftNames + 1] = bagItemName(kind):lower() .. " (" .. getZoneName(x, y, z) .. ")"
                    end
                end
            elseif item and item.leftTick then
                item.leftTick, item.warnTick = nil, nil
                removeBlip(item)
            end
        end
        if #leftNames > 0 then
            notifyCrew(kit, L.msg("med_bag.watch.equipment_left_at_scene_go_back", { left_names = table.concat(leftNames, ", ") }), true)
        end
        updateMissing(kit)
    end
end

-- "Equipment missing" over the side door while the ambulance stands in a hospital bay
function updateMissing(kit)
    if not isElement(kit.anchor) then return end
    local missing = {}
    if isKitInHospitalBay(kit) then
        for _, kind in ipairs(BAG.KINDS) do
            local item = kit.items[kind]
            if item and item.state ~= "stowed" then missing[#missing + 1] = bagItemName(kind) end
        end
    end
    local text = #missing > 0 and table.concat(missing, ", ") or nil
    if text ~= kit.missingText then
        kit.missingText = text
        if text then
            setElementData(kit.anchor, BAG_DATA.MISSING, text)
            notifyCrew(kit, L.msg("med_bag.watch.equipment_missing_from", { kit = kitLabel(kit), text = text }), true)
        else
            removeElementData(kit.anchor, BAG_DATA.MISSING)
        end
    end
end

addEventHandler("onResourceStart", resourceRoot, function()
    setTimer(watch, BAG.WATCH_INTERVAL, 0)
end)

-- Hooks of server/interaction.lua
function onItemWatchChanged(item, oldState)
    if item.state ~= "ground" and item.state ~= "stretcher" then
        item.leftTick, item.warnTick = nil, nil
        removeBlip(item)
    end
    updateMissing(item.kit)
end

function onKitWatchGone(kit)
    for _, item in pairs(kit.items) do removeBlip(item) end
end
