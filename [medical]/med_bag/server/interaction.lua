-- ui_interactobject menus: one side-door menu per ambulance (on the invisible anchor) and a pick-up
-- menu on every item lying on the ground. Every selection is re-checked here before
-- server/kits.lua acts. Also: the put-down key, restocking in a hospital bay, admin commands.

addEvent("onInteractMenuSelect")
addEvent("bag:drop", true)

local IO_RESOURCE = "ui_interactobject"
local MEDSYS = "medsys"
local menuKit = {}   -- menu id -> kit
local menuItem = {}  -- menu id -> item (ground)
local Restocking = {} -- player -> { timer, kit, x, y, z }

local function isRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

-- ---------------------------------------------------------------------------------------------
-- Medic role (medsys). With the role required, only medics see and use the menus.
-- ---------------------------------------------------------------------------------------------

local roleRequired -- nil = not asked yet

local function isRoleRequired()
    if roleRequired == nil and isRunning(MEDSYS) then
        roleRequired = exports[MEDSYS]:isMedicRoleRequired() == true
    end
    return roleRequired == true
end

function hasEquipmentAccess(player)
    if not isRoleRequired() then return true end
    return isRunning(MEDSYS) and exports[MEDSYS]:isPlayerMedic(player) == true
end

function getMenuVisibility()
    if not isRoleRequired() then return nil end
    return isRunning(MEDSYS) and exports[MEDSYS]:getMedicPlayers() or {}
end

-- ---------------------------------------------------------------------------------------------
-- Hospital bay (med_hospitals)
-- ---------------------------------------------------------------------------------------------

function isKitInHospitalBay(kit)
    if not isRunning("med_hospitals") or not isElement(kit.vehicle) then return false end
    return exports.med_hospitals:getVehicleHospitalBay(kit.vehicle) and true or false
end

-- ---------------------------------------------------------------------------------------------
-- Menu contents
-- ---------------------------------------------------------------------------------------------

local STATE_TEXT = { carried = "Carried by someone", ground = "On the ground", stowed = "In the vehicle",
    stretcher = "On the stretcher" }

local function kitItems(kit)
    local bag, monitor = kit.items.bag, kit.items.monitor
    local bagIn, monIn = bag.state == "stowed", monitor.state == "stowed"
    local inBay = isKitInHospitalBay(kit)
    return {
        { label = "Take medical bag", value = "take_bag", disabled = not bagIn,
            desc = bagIn and "Drugs, IV kits, oxygen" or STATE_TEXT[bag.state] },
        { label = "Take monitor / defibrillator", value = "take_monitor", disabled = not monIn,
            desc = monIn and "ECG, defibrillator" or STATE_TEXT[monitor.state] },
        { label = "Take both", value = "take_both", disabled = not (bagIn and monIn) },
        { label = "Put medical bag back", value = "put_bag", disabled = bagIn,
            desc = bagIn and "In the vehicle" or "Carry it here, or put it down next to the door" },
        { label = "Put monitor back", value = "put_monitor", disabled = monIn,
            desc = monIn and "In the vehicle" or "Carry it here, or put it down next to the door" },
        { label = "Put everything back", value = "put_all", disabled = bagIn and monIn },
        { label = "Restock bag", value = "restock", disabled = not (inBay and bagIn),
            desc = not inBay and "Only in a hospital ambulance bay" or (not bagIn and "The bag must be in the vehicle")
                or "Refill drugs, IV kits and oxygen" },
        { label = "Check contents", value = "contents", desc = "What is left in the bag" },
    }
end

local function kitDef(kit)
    return {
        title = "Ambulance equipment (" .. kitLabel(kit) .. ")",
        range = BAG.MENU_RANGE,
        priority = 15,
        lineOfSight = false,   -- the anchor sits in the door
        items = kitItems(kit),
    }
end

local function groundDef(item)
    return {
        title = bagItemName(item.kind) .. " (" .. kitLabel(item.kit) .. ")",
        range = BAG.GROUND_MENU_RANGE,
        priority = 12,
        lineOfSight = false,   -- the model origins sit off-centre / under the ground (would hide the menu)
        items = { { label = "Pick up", value = "pickup", desc = item.kind == "bag" and "Left hand" or "Right hand" } },
    }
end

-- ---------------------------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------------------------

local function registerKit(kit)
    if not isRunning(IO_RESOURCE) or not isElement(kit.anchor) then return end
    kit.menuId = exports[IO_RESOURCE]:addInteractMenu(kit.anchor, kitDef(kit), getMenuVisibility())
    if kit.menuId then menuKit[kit.menuId] = kit end
end

local function registerGround(item)
    if not isRunning(IO_RESOURCE) or not isElement(item.object) then return end
    item.menuId = exports[IO_RESOURCE]:addInteractMenu(item.object, groundDef(item), getMenuVisibility())
    if item.menuId then menuItem[item.menuId] = item end
end

local function removeGroundMenu(item)
    if not item.menuId then return end
    menuItem[item.menuId] = nil
    if isRunning(IO_RESOURCE) then exports[IO_RESOURCE]:removeInteractMenu(item.menuId) end
    item.menuId = nil
end

function refreshKitMenu(kit)
    if kit.menuId and isRunning(IO_RESOURCE) then
        exports[IO_RESOURCE]:setInteractMenuItems(kit.menuId, kitItems(kit))
    end
end

function onKitCreated(kit)
    registerKit(kit)
end

function onKitDestroyed(kit)
    if kit.menuId then
        menuKit[kit.menuId] = nil
        if isRunning(IO_RESOURCE) then exports[IO_RESOURCE]:removeInteractMenu(kit.menuId) end
        kit.menuId = nil
    end
    onKitWatchGone(kit)
    onKitStretcherGone(kit)
end

function onItemObjectGone(item)
    removeGroundMenu(item)
end

-- Hook of server/kits.lua after every state change
function onItemChanged(item, oldState)
    if item.state == "ground" and not item.menuId then registerGround(item) end
    refreshKitMenu(item.kit)
    onItemWatchChanged(item, oldState)
    onItemStretcherChanged(item, oldState)
end

function onStockChanged(item)
    refreshCarriedStock(item)
end

-- ui_interactobject (re)started: register everything again
addEventHandler("onResourceStart", root, function(started)
    local name = getResourceName(started)
    if name == IO_RESOURCE then
        menuKit, menuItem = {}, {}
        for _, kit in eachKit() do
            registerKit(kit)
            for _, item in pairs(kit.items) do
                item.menuId = nil
                if item.state == "ground" then registerGround(item) end
            end
        end
    elseif name == MEDSYS then
        roleRequired = nil
        updateMenuVisibility()
    end
end)

addEventHandler("onResourceStop", root, function(stopped)
    if getResourceName(stopped) ~= IO_RESOURCE then return end
    menuKit, menuItem = {}, {}
    for _, kit in eachKit() do
        kit.menuId = nil
        for _, item in pairs(kit.items) do item.menuId = nil end
    end
end)

function updateMenuVisibility()
    if not isRunning(IO_RESOURCE) then return end
    local visible = getMenuVisibility()
    for id in pairs(menuKit) do exports[IO_RESOURCE]:setInteractMenuVisibleTo(id, visible) end
    for id in pairs(menuItem) do exports[IO_RESOURCE]:setInteractMenuVisibleTo(id, visible) end
    setStretcherMenusVisibleTo(visible)
end

addEventHandler("onPlayerMedicChange", root, function()
    if isRoleRequired() then updateMenuVisibility() end
end)

-- The bay state changes the Restock line: refresh the menus now and then (cheap, few ambulances)
setTimer(function()
    for _, kit in eachKit() do
        local inBay = isKitInHospitalBay(kit)
        if inBay ~= kit.inBay then
            kit.inBay = inBay
            refreshKitMenu(kit)
        end
    end
end, 2000, 0)

-- ---------------------------------------------------------------------------------------------
-- Rules
-- ---------------------------------------------------------------------------------------------

function canHandleEquipment(player)
    if isPedDead(player) or isPedInVehicle(player) then return false, "You cannot do that now." end
    if not hasEquipmentAccess(player) then return false, "Only medics can use the ambulance equipment." end
    if Restocking[player] then return false, "You are restocking the bag." end
    return true
end

local function nearSidePoint(kit, element, range)
    if not isElement(element) or not bagSameWorld(element, kit.vehicle) then return false end
    local sx, sy, sz = bagSideWorld(kit.vehicle)
    local x, y, z = getElementPosition(element)
    return getDistanceBetweenPoints3D(sx, sy, sz, x, y, z) <= range
end

local function take(kit, player, kinds)
    local taken = {}
    for _, kind in ipairs(kinds) do
        local item = kit.items[kind]
        if item.state ~= "stowed" then
            notify(player, bagItemName(kind) .. " is not in the vehicle.")
        elseif getCarried(player, kind) then
            notify(player, "You already carry a " .. bagItemName(kind):lower() .. ".")
        else
            takeItem(item, player)
            taken[#taken + 1] = bagItemName(kind)
        end
    end
    if #taken > 0 then
        local a = BAG.TAKE_ANIM
        setPedAnimation(player, a[1], a[2], a[3], false, false, false, false)
        openSideDoor(kit)
    end
end

local function putBack(kit, player, kinds)
    local done, foreign = 0, nil
    for _, kind in ipairs(kinds) do
        local own = kit.items[kind]
        local carried = getCarried(player, kind)
        if carried and carried.kit ~= kit then
            foreign = carried
        elseif own.state == "carried" and own.carrier == player then
            stowItem(own)
            done = done + 1
        elseif own.state == "ground" and nearSidePoint(kit, own.object, BAG.PUT_BACK_RANGE) then
            stowItem(own)
            done = done + 1
        elseif own.state ~= "stowed" and #kinds == 1 then
            notify(player, "Bring the " .. bagItemName(kind):lower() .. " here first.")
        end
    end
    if foreign then
        notify(player, ("This %s belongs to %s."):format(bagItemName(foreign.kind):lower(), kitLabel(foreign.kit)))
    end
    if done > 0 then
        local a = BAG.PUT_ANIM
        setPedAnimation(player, a[1], a[2], a[3], false, false, false, false)
        openSideDoor(kit)
    end
end

-- ---------------------------------------------------------------------------------------------
-- Restock (hospital bay, the bag in the vehicle)
-- ---------------------------------------------------------------------------------------------

local MOVE_CONTROLS = { "forwards", "backwards", "left", "right", "jump", "sprint" }

local function endRestock(player, finished)
    local r = Restocking[player]
    if not r then return end
    Restocking[player] = nil
    if isTimer(r.timer) then killTimer(r.timer) end
    if isElement(player) then
        for _, control in ipairs(MOVE_CONTROLS) do toggleControl(player, control, true) end
        setPedAnimation(player)
        triggerClientEvent(player, "bag:progress", resourceRoot, false)
    end
    if finished then
        local bag = r.kit.items.bag
        if Items[bag.id] and bag.state == "stowed" and isKitInHospitalBay(r.kit) then
            restock(bag)
            notify(player, "Medical bag restocked.")
        else
            notify(player, "Restocking failed.")
        end
    end
end

local function startRestock(kit, player)
    if not isKitInHospitalBay(kit) then return notify(player, "Park the ambulance in a hospital bay first.") end
    if kit.items.bag.state ~= "stowed" then return notify(player, "Put the bag back into the vehicle first.") end
    if Restocking[player] then return end
    for _, control in ipairs(MOVE_CONTROLS) do toggleControl(player, control, false) end
    setPedAnimation(player, "INT_SHOP", "shop_loop", -1, true, false, false, false)
    Restocking[player] = {
        kit = kit,
        timer = setTimer(function() endRestock(player, true) end, BAG.RESTOCK_TIME * 1000, 1),
    }
    triggerClientEvent(player, "bag:progress", resourceRoot, BAG.RESTOCK_TIME * 1000, "Restocking the medical bag...")
end

addEventHandler("onPlayerQuit", root, function() endRestock(source, false) end)
addEventHandler("onPlayerWasted", root, function() endRestock(source, false) end)

-- ---------------------------------------------------------------------------------------------
-- Contents
-- ---------------------------------------------------------------------------------------------

-- The bag's stock in a window on the player's screen (client/hud.lua; the chat is not shown on
-- this server)
local function showContents(kit, player)
    local bag = kit.items.bag
    local stock = bag.stock
    local ids = {}
    for id in pairs(BAG.STOCK.drugs) do ids[#ids + 1] = id end
    local drugs = {}
    for _, id in ipairs(ids) do
        drugs[#drugs + 1] = { drugName(id), stock.drugs[id] or 0, BAG.STOCK.drugs[id] }
    end
    table.sort(drugs, function(a, b) return a[1] < b[1] end)
    triggerClientEvent(player, "bag:contents", resourceRoot, {
        title = "Medical bag (" .. kitLabel(kit) .. ")",
        where = STATE_TEXT[bag.state],
        ivKits = { stock.ivKits, BAG.STOCK.ivKits },
        oxygen = math.floor(stock.oxygen + 0.5),
        drugs = drugs,
        monitor = STATE_TEXT[kit.items.monitor.state],
    })
end

-- ---------------------------------------------------------------------------------------------
-- Selections
-- ---------------------------------------------------------------------------------------------

local KIT_ACTIONS = {
    take_bag = function(kit, p) take(kit, p, { "bag" }) end,
    take_monitor = function(kit, p) take(kit, p, { "monitor" }) end,
    take_both = function(kit, p) take(kit, p, { "bag", "monitor" }) end,
    put_bag = function(kit, p) putBack(kit, p, { "bag" }) end,
    put_monitor = function(kit, p) putBack(kit, p, { "monitor" }) end,
    put_all = function(kit, p) putBack(kit, p, { "bag", "monitor" }) end,
    restock = startRestock,
    contents = showContents,
}

addEventHandler("onInteractMenuSelect", root, function(menuId, value)
    local player = source
    local kit = menuKit[menuId]
    if kit then
        local action = KIT_ACTIONS[value]
        if not action or Kits[kit.vehicle] ~= kit then return end
        if value ~= "contents" then
            local ok, reason = canHandleEquipment(player)
            if not ok then return notify(player, reason) end
        end
        return action(kit, player)
    end
    local item = menuItem[menuId]
    if item and value == "pickup" and item.state == "ground" then
        local ok, reason = canHandleEquipment(player)
        if not ok then return notify(player, reason) end
        if getCarried(player, item.kind) then
            return notify(player, "You already carry a " .. bagItemName(item.kind):lower() .. ".")
        end
        pickUpItem(item, player)
    end
end)

-- Put-down key (client/carry.lua)
addEventHandler("bag:drop", resourceRoot, function()
    local player = client
    if not getHands(player) or isPedInVehicle(player) then return end
    dropCarried(player)
end)

-- ---------------------------------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------------------------------

local function isAdmin(player)
    if not isRunning("v_mysql") then return false end
    local ok, level = pcall(function() return exports.v_mysql:getAccData(player, "admin_level") end)
    return ok and (tonumber(level) or 0) > BAG.ADMIN_LEVEL
end

local function nearestKit(player, maxDistance)
    local px, py, pz = getElementPosition(player)
    local best, bestD
    for vehicle, kit in eachKit() do
        if bagSameWorld(vehicle, player) then
            local x, y, z = getElementPosition(vehicle)
            local d = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
            if d <= maxDistance and (not bestD or d < bestD) then best, bestD = kit, d end
        end
    end
    return best
end

-- /bagpos: the player's offset from the nearest ambulance, for BAG.SIDE_POINT
addCommandHandler("bagpos", function(player)
    if not isAdmin(player) then return end
    local kit = nearestKit(player, 10)
    if not kit then return notify(player, "No ambulance within 10 m.", "med_bag", true) end
    local x, y, z = getElementPosition(player)
    local lx, ly, lz = bagWorldToLocal(kit.vehicle, x, y, z)
    local text = ("model %d: SIDE_POINT = { %.2f, %.2f, %.2f }"):format(getElementModel(kit.vehicle), lx, ly, lz)
    notify(player, text, "med_bag")
    outputServerLog("[med_bag] /bagpos " .. text)
end)

-- /bagreset: every item of the nearest ambulance goes back into it (stock kept)
addCommandHandler("bagreset", function(player)
    if not isAdmin(player) then return end
    local kit = nearestKit(player, 15)
    if not kit then return notify(player, "No ambulance within 15 m.", "med_bag", true) end
    for _, item in pairs(kit.items) do returnItemToVehicle(item, false) end
    notify(player, "Equipment of " .. kitLabel(kit) .. " returned.", "med_bag")
end)
