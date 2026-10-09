-- The equipment on the stretcher (med_stretcher). Every stretcher belongs to one ambulance and only
-- that ambulance's bag / monitor can go on it (no mixing between ambulances).
--   push start           the pusher's carried items go onto the stretcher's side
--   stretcher menu       "Equipment" group: take off / put on (merged into the stretcher's menu)
--   loading              the items on it go into the ambulance (stowed, `aboard`)
--   take out + patient   the `aboard` items come out on it again (they follow the patient's bed)
--   take out, empty      `aboard` is cleared, the items stay in the ambulance
-- After a hospital handover the items stay on the stretcher until it is loaded.

addEvent("onStretcherPushStart")
addEvent("onStretcherTakeOut")
addEvent("onStretcherLoaded")
addEvent("onInteractMenuSelect")

local STRETCHER_RES = "med_stretcher"
local IO_RESOURCE = "ui_interactobject"
local menuStretcher = {} -- menu id -> kit

local function isRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

-- The kit whose ambulance owns this stretcher object
local function kitOfStretcher(obj)
    if not isRunning(STRETCHER_RES) or not isElement(obj) then return nil end
    local vehicle = exports[STRETCHER_RES]:getStretcherVehicle(obj)
    return vehicle and Kits[vehicle] or nil
end

local function stretcherOfKit(kit)
    if not isRunning(STRETCHER_RES) or not isElement(kit.vehicle) then return nil end
    local obj = exports[STRETCHER_RES]:getVehicleStretcher(kit.vehicle)
    return isElement(obj) and obj or nil
end

local function stretcherState(obj)
    return getElementData(obj, "stretcher.state")
end

-- Which items ride on this stretcher (client HUD for the pusher)
local function syncStretcherData(obj)
    if not isElement(obj) then return end
    local on = {}
    local any = false
    for _, item in pairs(Items) do
        if item.state == "stretcher" and item.stretcher == obj then
            on[item.kind] = true
            any = true
        end
    end
    if any then setElementData(obj, BAG_DATA.ON_STRETCHER, on) else removeElementData(obj, BAG_DATA.ON_STRETCHER) end
end

-- ---------------------------------------------------------------------------------------------
-- Stretcher menu ("Equipment" group, merged with med_stretcher's menu on the same object)
-- ---------------------------------------------------------------------------------------------

local function menuItems(kit, obj)
    local list = {}
    for _, kind in ipairs(BAG.KINDS) do
        local item = kit.items[kind]
        local name = bagItemName(kind)
        if item.state == "stretcher" and item.stretcher == obj then
            list[#list + 1] = { label = "Take " .. name:lower(), value = "off_" .. kind,
                desc = kind == "bag" and "Left hand" or "Right hand" }
        else
            local can = item.state == "carried" or item.state == "ground"
            list[#list + 1] = { label = "Put " .. name:lower() .. " on stretcher", value = "on_" .. kind,
                disabled = not can, desc = can and "Carried, or lying next to the stretcher"
                    or (item.state == "stowed" and "In the ambulance - take it at the side door" or nil) }
        end
    end
    return list
end

local function menuDef(kit, obj)
    local st = stretcherState(obj)
    return {
        title = "Equipment",
        range = 2.5,
        priority = 10,           -- under the stretcher's own items
        lineOfSight = false,
        enabled = st == "ground" or st == "pushing",
        items = menuItems(kit, obj),
    }
end

function refreshStretcherMenu(kit)
    local obj = stretcherOfKit(kit)
    if not isRunning(IO_RESOURCE) then
        kit.stretcherMenu, kit.stretcher = nil, obj
        return
    end
    local io = exports[IO_RESOURCE]
    if kit.stretcherMenu and (kit.stretcher ~= obj or not io:isInteractMenu(kit.stretcherMenu)) then
        menuStretcher[kit.stretcherMenu] = nil
        io:removeInteractMenu(kit.stretcherMenu)
        kit.stretcherMenu = nil
    end
    kit.stretcher = obj
    if not obj then return end
    if kit.stretcherMenu then
        io:updateInteractMenu(kit.stretcherMenu, menuDef(kit, obj))
    else
        kit.stretcherMenu = io:addInteractMenu(obj, menuDef(kit, obj), getMenuVisibility())
        if kit.stretcherMenu then menuStretcher[kit.stretcherMenu] = kit end
    end
end

function setStretcherMenusVisibleTo(visible)
    if not isRunning(IO_RESOURCE) then return end
    for id in pairs(menuStretcher) do exports[IO_RESOURCE]:setInteractMenuVisibleTo(id, visible) end
end

function onKitStretcherGone(kit)
    if kit.stretcherMenu then
        menuStretcher[kit.stretcherMenu] = nil
        if isRunning(IO_RESOURCE) then exports[IO_RESOURCE]:removeInteractMenu(kit.stretcherMenu) end
        kit.stretcherMenu = nil
    end
end

-- The stretcher can be created after the kit, re-created on a respawn, or the menu resource can
-- restart: keep every kit's stretcher menu in place
setTimer(function()
    for _, kit in eachKit() do
        local obj = stretcherOfKit(kit)
        if obj ~= kit.stretcher or (obj and not kit.stretcherMenu) then refreshStretcherMenu(kit) end
    end
end, 2000, 0)

-- The stretcher state decides whether the group is usable (not while stowed / sliding)
addEventHandler("onElementDataChange", root, function(key)
    if key ~= "stretcher.state" then return end
    local kit = kitOfStretcher(source)
    if kit then refreshStretcherMenu(kit) end
end)

addEventHandler("onResourceStart", root, function(res)
    local name = getResourceName(res)
    if name ~= IO_RESOURCE and name ~= STRETCHER_RES then return end
    menuStretcher = {}
    for _, kit in eachKit() do
        kit.stretcherMenu = nil
        refreshStretcherMenu(kit)
    end
end)

addEventHandler("onResourceStop", root, function(res)
    local name = getResourceName(res)
    if name ~= IO_RESOURCE and name ~= STRETCHER_RES then return end
    menuStretcher = {}
    for _, kit in eachKit() do kit.stretcherMenu = nil end
end)

addEventHandler("onInteractMenuSelect", root, function(menuId, value)
    local kit = menuStretcher[menuId]
    if not kit or type(value) ~= "string" then return end
    local player = source
    local obj = kit.stretcher
    if not isElement(obj) then return end
    local ok, reason = canHandleEquipment(player)
    if not ok then return notify(player, reason) end
    local action, kind = value:match("^(%a+)_(%a+)$")
    local item = kit.items[kind]
    if not item then return end

    if action == "off" then
        if item.state ~= "stretcher" or item.stretcher ~= obj then return end
        if getCarried(player, kind) then
            return notify(player, "You already carry a " .. bagItemName(kind):lower() .. ".")
        end
        pickUpItem(item, player)
    elseif action == "on" then
        if item.state == "carried" and item.carrier == player then
            putOnStretcher(item, obj)
        elseif item.state == "ground" and isElement(item.object) then
            local x, y, z = getElementPosition(item.object)
            local sx, sy, sz = getElementPosition(obj)
            if getDistanceBetweenPoints3D(x, y, z, sx, sy, sz) > 3 then
                return notify(player, "The " .. bagItemName(kind):lower() .. " is too far from the stretcher.")
            end
            putOnStretcher(item, obj)
        else
            local carried = getCarried(player, kind)
            if carried and carried.kit ~= kit then
                return notify(player, ("This %s belongs to %s, not to this stretcher."):format(
                    bagItemName(kind):lower(), kitLabel(carried.kit)))
            end
            notify(player, "Carry the " .. bagItemName(kind):lower() .. " here, or put it down next to the stretcher.")
        end
    end
end)

-- ---------------------------------------------------------------------------------------------
-- med_stretcher events
-- ---------------------------------------------------------------------------------------------

-- Both hands go on the handle: carried items of this ambulance go onto its stretcher, any other
-- ambulance's items are put down (nothing mixes)
addEventHandler("onStretcherPushStart", root, function(player)
    local stretcher = source -- nested events (item changes) may replace `source`
    local hands = getHands(player)
    if not hands then return end
    local kit = kitOfStretcher(stretcher)
    local foreign = false
    for _, kind in ipairs(BAG.KINDS) do
        local item = hands[kind]
        if item and kit and item.kit == kit then
            putOnStretcher(item, stretcher)
        elseif item then
            foreign = true
        end
    end
    if foreign then
        dropCarried(player)
        notify(player, "That equipment belongs to another ambulance - you put it down.")
    end
end)

-- The stretcher slides out: with a patient the `aboard` items come out on it
addEventHandler("onStretcherTakeOut", root, function(player, vehicle, patient)
    local stretcher = source
    local kit = Kits[vehicle]
    if not kit then return end
    for _, item in pairs(kit.items) do
        if item.state == "stowed" and item.aboard then
            if patient then putOnStretcher(item, stretcher) else item.aboard = nil end
        end
    end
end)

-- The stretcher is in: its items go into the ambulance, `aboard` only with a patient
addEventHandler("onStretcherLoaded", root, function(player, vehicle, patient)
    local stretcher = source
    local kit = Kits[vehicle]
    if not kit then return end
    local stowed = false
    for _, item in pairs(kit.items) do
        if item.state == "stretcher" and item.stretcher == stretcher then
            stowItem(item, patient and stretcher or nil)
            stowed = true
        end
    end
    if stowed then notifyCrew(kit, "Equipment loaded into " .. kitLabel(kit) .. " with the stretcher.") end
end)

-- Hook of server/interaction.lua (every item change)
function onItemStretcherChanged(item, oldState)
    if item.state == "stretcher" or oldState == "stretcher" then
        syncStretcherData(item.stretcher or item.lastStretcher)
    end
    item.lastStretcher = item.stretcher or item.lastStretcher
    local kit = item.kit
    if kit.stretcherMenu then refreshStretcherMenu(kit) end
end
