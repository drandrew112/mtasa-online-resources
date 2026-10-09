-- Left-behind watch. Every BAG.WATCH_INTERVAL an item lying on the ground is "left behind" when
-- no medic is near it and its ambulance is far away (or driving away). The crew is warned (repeated
-- every BAG.WARN_REPEAT s) and sees a blip on the item; after BAG.ABANDON_TIME s it is returned to
-- the ambulance with an empty stock. An ambulance in a hospital bay with an item out shows
-- "Equipment missing" over its side door (BAG_DATA.MISSING on the anchor, client/hud.lua).

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
    for _, player in ipairs(getKitCrew(kit)) do notify(player, text, "EMS equipment", alert) end
end

-- ---------------------------------------------------------------------------------------------
-- Blips
-- ---------------------------------------------------------------------------------------------

local function removeBlip(item)
    local blip = Blips[item]
    Blips[item] = nil
    if isElement(blip) then destroyElement(blip) end
end

local function showBlip(item, crew)
    if not isElement(item.object) then return end
    local blip = Blips[item]
    if not isElement(blip) then
        local b = BAG.BLIP
        blip = createBlipAttachedTo(item.object, b.icon, b.size, b.color[1], b.color[2], b.color[3], 255, 0, 99999.0,
            getRootElement())
        if not blip then return end
        Blips[item] = blip
        setElementVisibleTo(blip, root, false)
    end
    for _, player in ipairs(crew) do setElementVisibleTo(blip, player, true) end
end

-- ---------------------------------------------------------------------------------------------
-- Detection
-- ---------------------------------------------------------------------------------------------

local function medicNear(item)
    local x, y, z = itemPosition(item)
    local players = getElementsWithinRange(x, y, z, BAG.LEFT_GUARD_RADIUS, "player",
        getElementInterior(item.object), getElementDimension(item.object))
    for _, player in ipairs(players) do
        if not isPedDead(player) and hasEquipmentAccess(player) then return true end
    end
    return false
end

local function vehicleSpeed(vehicle)
    local vx, vy, vz = getElementVelocity(vehicle)
    return math.sqrt(vx * vx + vy * vy + vz * vz) * 180 -- km/h
end

-- On the ground or on a stretcher that is out of the ambulance
local function isLeftBehind(item)
    if (item.state ~= "ground" and item.state ~= "stretcher") or not isElement(item.object) then return false end
    local vehicle = item.kit.vehicle
    if not isElement(vehicle) then return false end
    if medicNear(item) then return false end
    if not bagSameWorld(vehicle, item.object) then return true end
    local x, y, z = itemPosition(item)
    local vx, vy, vz = getElementPosition(vehicle)
    local d = getDistanceBetweenPoints3D(x, y, z, vx, vy, vz)
    if d > BAG.LEFT_DISTANCE then return true end
    return d > BAG.LEFT_MOVING_DISTANCE and vehicleSpeed(vehicle) > BAG.LEFT_MOVING_SPEED
end

local function zoneOf(item)
    local x, y, z = itemPosition(item)
    return getZoneName(x, y, z)
end

local function watch()
    local now = getTickCount()
    for _, kit in eachKit() do
        local leftNames, crew = {}, nil
        for _, kind in ipairs(BAG.KINDS) do
            local item = kit.items[kind]
            if isLeftBehind(item) then
                crew = crew or getKitCrew(kit)
                if not item.leftTick then
                    item.leftTick, item.warnTick = now, nil
                end
                if now - item.leftTick >= BAG.ABANDON_TIME * 1000 then
                    removeBlip(item)
                    item.leftTick, item.warnTick = nil, nil
                    returnItemToVehicle(item, true)
                    notifyCrew(kit, ("%s was recovered by dispatch and returned to %s%s."):format(
                        bagItemName(kind), kitLabel(kit), kind == "bag" and " - EMPTY, restock it at a hospital" or ""), true)
                else
                    showBlip(item, crew)
                    if not item.warnTick or now - item.warnTick >= BAG.WARN_REPEAT * 1000 then
                        item.warnTick = now
                        leftNames[#leftNames + 1] = bagItemName(kind):lower() .. " (" .. zoneOf(item) .. ")"
                    end
                end
            elseif item.leftTick then
                item.leftTick, item.warnTick = nil, nil
                removeBlip(item)
            end
        end
        if #leftNames > 0 then
            notifyCrew(kit, ("Equipment left at the scene: %s. Go back for it."):format(table.concat(leftNames, ", ")), true)
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
            if kit.items[kind].state ~= "stowed" then missing[#missing + 1] = bagItemName(kind) end
        end
    end
    local text = #missing > 0 and table.concat(missing, ", ") or nil
    if text ~= kit.missingText then
        kit.missingText = text
        if text then
            setElementData(kit.anchor, BAG_DATA.MISSING, text)
            notifyCrew(kit, "Equipment missing from " .. kitLabel(kit) .. ": " .. text .. ".", true)
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
