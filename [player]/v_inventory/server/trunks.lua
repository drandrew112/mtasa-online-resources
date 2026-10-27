if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Trunks: storage on a vehicle, created by other scripts. A ui_interactobject menu on an invisible
-- anchor at the rear opens the transfer window. Access: players with the dataKey element data
-- (truthy, or exactly dataValue); nil = everyone.

addEvent("onInteractMenuSelect")

Trunks = {}            -- vehicle -> trunk
local menuTrunk = {}   -- menu id -> trunk
local IO_RESOURCE = "ui_interactobject"

local function isRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function plate(vehicle)
    local text = getVehiclePlateText(vehicle) or ""
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function menuDef(trunk)
    local p = plate(trunk.vehicle)
    return {
        title = p ~= "" and L.msg("v_inventory.ui.trunk_plate", { plate = p }) or L.msg("v_inventory.ui.trunk"),
        range = INV.TRUNK_MENU_RANGE,
        priority = 8,
        lineOfSight = false,          -- the anchor sits in the bodywork
        selfDataKey = trunk.dataKey,
        items = { { label = L.msg("v_inventory.ui.open_trunk"), value = "open" } },
    }
end

local function registerMenu(trunk)
    if not isRunning(IO_RESOURCE) or not isElement(trunk.anchor) then return end
    trunk.menuId = exports[IO_RESOURCE]:addInteractMenu(trunk.anchor, menuDef(trunk))
    if trunk.menuId then menuTrunk[trunk.menuId] = trunk end
end

local function removeMenu(trunk)
    if not trunk.menuId then return end
    menuTrunk[trunk.menuId] = nil
    if isRunning(IO_RESOURCE) then exports[IO_RESOURCE]:removeInteractMenu(trunk.menuId) end
    trunk.menuId = nil
end

function hasTrunkAccess(trunk, player)
    return hasDataAccess(player, trunk.dataKey, trunk.dataValue)
end

-- ---------------------------------------------------------------------------------------------
-- API (server/exports.lua)
-- ---------------------------------------------------------------------------------------------

function createTrunkFor(vehicle, opts, owner)
    if Trunks[vehicle] then return false, "the vehicle already has a trunk" end
    opts = type(opts) == "table" and opts or {}
    local o = type(opts.offset) == "table" and opts.offset or INV.TRUNK_OFFSET
    local x, y, z = getElementPosition(vehicle)
    -- a marker, not an object: an alpha-0 object still casts a shadow blob behind the car
    local anchor = createMarker(x, y, z, "corona", 0.1, 0, 0, 0, 0)
    if not anchor then return false, "cannot create the anchor" end
    setElementDimension(anchor, getElementDimension(vehicle))
    setElementInterior(anchor, getElementInterior(vehicle))
    attachElements(anchor, vehicle, tonumber(o[1]) or 0, tonumber(o[2]) or 0, tonumber(o[3]) or 0)
    local trunk = {
        vehicle = vehicle, anchor = anchor, items = {}, owner = owner,
        capacity = tonumber(opts.capacity),
        dataKey = type(opts.dataKey) == "string" and opts.dataKey or nil, dataValue = opts.dataValue,
        title = opts.title,
    }
    Trunks[vehicle] = trunk
    registerMenu(trunk)
    return true
end

function destroyTrunkOf(vehicle)
    local trunk = Trunks[vehicle]
    if not trunk then return false end
    closeSessionsOf({ type = "trunk", vehicle = vehicle })
    for i = #trunk.items, 1, -1 do
        if trunk.items[i] then destroyItem(trunk.items[i]) end
    end
    removeMenu(trunk)
    Trunks[vehicle] = nil
    if isElement(trunk.anchor) then destroyElement(trunk.anchor) end
    return true
end

function setTrunkAccessFor(vehicle, dataKey, dataValue)
    local trunk = Trunks[vehicle]
    if not trunk then return false end
    trunk.dataKey = (dataKey and dataKey ~= false) and tostring(dataKey) or nil
    trunk.dataValue = dataValue
    if trunk.menuId and isRunning(IO_RESOURCE) then exports[IO_RESOURCE]:updateInteractMenu(trunk.menuId, menuDef(trunk)) end
    for _, player in ipairs(getElementsByType("player")) do
        if not hasTrunkAccess(trunk, player) then closeSessionsOf({ type = "trunk", vehicle = vehicle }, player) end
    end
    return true
end

-- ---------------------------------------------------------------------------------------------
-- Menu
-- ---------------------------------------------------------------------------------------------

addEventHandler("onInteractMenuSelect", root, function(menuId, value)
    local trunk = menuTrunk[menuId]
    if not trunk or value ~= "open" or Trunks[trunk.vehicle] ~= trunk then return end
    local player = source
    if isPedDead(player) or isPedInVehicle(player) then return end
    if not hasTrunkAccess(trunk, player) then return notify(player, L.msg("v_inventory.msg.no_access"), true) end
    local x, y, z = getElementPosition(trunk.anchor)
    local px, py, pz = getElementPosition(player)
    if getDistanceBetweenPoints3D(x, y, z, px, py, pz) > INV.TRUNK_MENU_RANGE + 1.5 then return end
    openSession(player, { type = "trunk", vehicle = trunk.vehicle })
end)

addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) ~= IO_RESOURCE then return end
    menuTrunk = {}
    for _, trunk in pairs(Trunks) do
        trunk.menuId = nil
        registerMenu(trunk)
    end
end)

addEventHandler("onResourceStop", root, function(res)
    if res == resource then return end
    local name = getResourceName(res)
    if name == IO_RESOURCE then
        menuTrunk = {}
        for _, trunk in pairs(Trunks) do trunk.menuId = nil end
        return
    end
    for vehicle, trunk in pairs(Trunks) do
        if trunk.owner == name then destroyTrunkOf(vehicle) end
    end
end)

-- ---------------------------------------------------------------------------------------------
-- The vehicle
-- ---------------------------------------------------------------------------------------------

addEventHandler("onElementDestroy", root, function()
    if Trunks[source] then destroyTrunkOf(source) end
end)

local function followWorld()
    local trunk = Trunks[source]
    if trunk and isElement(trunk.anchor) then
        setElementDimension(trunk.anchor, getElementDimension(source))
        setElementInterior(trunk.anchor, getElementInterior(source))
    end
end
addEventHandler("onElementDimensionChange", root, followWorld)
addEventHandler("onElementInteriorChange", root, followWorld)
