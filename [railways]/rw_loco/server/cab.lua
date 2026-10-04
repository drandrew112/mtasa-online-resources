-- Cab access for locomotives with a `cab` definition (LOCO.TYPES): the game's own enter /
-- exit is blocked; each cab door is an invisible object attached to the lead with a
-- ui_interactobject menu ("Enter the cab"), and leaving puts the driver down beside the cab,
-- on the platform side when the train stands at a station, otherwise on the side away from
-- other tracks.

local core = exports.rw_core
local Doors = {}        -- [consistId] = { lead, objs = {}, menus = {} }
local menuOwner = {}    -- [menuId] = consistId

local function running(name)
    local r = getResourceFromName(name)
    return r and getResourceState(r) == "running"
end

local function tell(player, text)
    if isElement(player) then triggerClientEvent(player, "rw:loco:notify", resourceRoot, text) end
end

-- -> consistId, info, typeDef when the vehicle is the lead of a loco with a cab definition
local function cabOf(vehicle)
    if not isElement(vehicle) then return nil end
    local id = core:getVehicleConsist(vehicle)
    if not id then return nil end
    local info = core:getConsist(id)
    if not info or info.lead ~= vehicle then return nil end
    local def = LOCO.TYPES[info.loco]
    if not def or not def.cab then return nil end
    return id, info, def
end

local function removeDoors(id)
    local d = Doors[id]
    if not d then return end
    for _, m in ipairs(d.menus) do
        menuOwner[m] = nil
        if running("ui_interactobject") then pcall(function() exports.ui_interactobject:removeInteractMenu(m) end) end
    end
    for _, o in ipairs(d.objs) do if isElement(o) then destroyElement(o) end end
    Doors[id] = nil
end

local function registerMenus(id)
    local d = Doors[id]
    if not d or not running("ui_interactobject") then return end
    for _, m in ipairs(d.menus) do menuOwner[m] = nil end
    d.menus = {}
    for _, o in ipairs(d.objs) do
        if isElement(o) then
            local m = exports.ui_interactobject:addInteractMenu(o, {
                title = "Locomotive cab", range = 2.6, priority = 8, lineOfSight = false,
                items = { { label = "Enter the cab", value = "enter", desc = "Take the driver's seat" } },
            })
            if m then d.menus[#d.menus + 1] = m menuOwner[m] = id end
        end
    end
end

local function addDoors(id)
    removeDoors(id)
    local info = core:getConsist(id)
    if not info or not isElement(info.lead) then return end
    local def = LOCO.TYPES[info.loco]
    if not def or not def.cab then return end
    local d = { lead = info.lead, objs = {}, menus = {} }
    for _, p in ipairs(def.cab.doors) do
        local o = createObject(LOCO.CAB_DOOR_MODEL, 0, 0, -50)
        if o then
            setElementAlpha(o, 0)
            setElementCollisionsEnabled(o, false)
            attachElements(o, info.lead, p.x, p.y, p.z)
            d.objs[#d.objs + 1] = o
        end
    end
    Doors[id] = d
    -- the clients need the objects before the menus can bind to them
    setTimer(registerMenus, 600, 1, id)
end

addEventHandler("onInteractMenuSelect", root, function(menuId, value)
    local id = menuOwner[menuId]
    if not id or value ~= "enter" then return end
    local player = source
    local info = core:getConsist(id)
    if not info or not isElement(info.lead) or isPedInVehicle(player) then return end
    if info.auto then tell(player, "Automatic train - the cab is locked. Passengers can board the coaches.") return end
    if info.driver or getVehicleOccupant(info.lead, 0) then tell(player, "Somebody is already driving this locomotive.") return end
    -- the network train takes the driver (its driver seat, controller input)
    local ok, err = exports.rw_customtracks:setNetTrainDriver(player, id)
    if not ok then tell(player, tostring(err)) end
end)

-- the game's own entering is not allowed on these locomotives
addEventHandler("onVehicleStartEnter", root, function()
    if cabOf(source) then cancelEvent() end
end)

-- world point beside the cab: sign -1 = left of the loco's front, 1 = right
local function besideCab(veh, def, sign)
    local m = getElementMatrix(veh)
    local px, py, pz = getElementPosition(veh)
    local lat, cabY = def.cab.exitLateral, def.cab.doors[1].y
    local x = px + m[1][1] * sign * lat + m[2][1] * cabY
    local y = py + m[1][2] * sign * lat + m[2][2] * cabY
    return x, y, pz, m
end

local function exitSide(id, veh, def)
    if running("rw_timetable") then
        local ok, side = exports.rw_timetable:canOpenDoors(id)
        if ok and side == "left" then return -1 end
        if ok and side == "right" then return 1 end
    end
    -- not at a known platform: the side without another track next to it
    for _, sign in ipairs({ -1, 1 }) do
        local x, y = besideCab(veh, def, sign)
        if not core:projectToTrack(x, y, nil, 2.0) then return sign end
    end
    return -1
end

-- leaving: the driver is put down beside the cab instead of the game's exit
addEventHandler("onVehicleStartExit", root, function(player, seat)
    local id, info, def = cabOf(source)
    if not id then return end
    cancelEvent()
    if seat ~= 0 then return end
    if info.speed > LOCO.CAB_EXIT_MAX_SPEED then
        tell(player, "Stop the train before leaving the cab.")
        return
    end
    local sign = exitSide(id, source, def)
    local x, y, pz, m = besideCab(source, def, sign)
    local z = pz + 1.5
    local rz = math.deg(math.atan2(m[1][2] * sign, m[1][1] * sign)) - 90   -- facing away from the loco
    removePedFromVehicle(player)
    setElementPosition(player, x, y, z)
    triggerClientEvent(player, "rw:loco:placed", resourceRoot, x, y, z, rz)
end)

addEventHandler("onRailConsistSpawn", root, function(id) addDoors(id) end)
addEventHandler("onRailConsistChange", root, function(id) setTimer(addDoors, 200, 1, id) end)
addEventHandler("onRailConsistDestroy", root, function(id) removeDoors(id) end)

addEventHandler("onResourceStart", root, function(res)
    if res == resource then
        for _, info in ipairs(core:getConsists()) do addDoors(info.id) end
    elseif getResourceName(res) == "ui_interactobject" then
        for id in pairs(Doors) do setTimer(registerMenus, 600, 1, id) end
    end
end)
