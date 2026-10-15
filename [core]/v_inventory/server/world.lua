if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- World objects of items on the ground (frozen, with a ui_interactobject "Pick up" / "Open" menu)
-- and of attached items (attached to any element, e.g. a stretcher). Items in a slot have no server
-- object: every client draws them on the bones (client/hands.lua).

addEvent("onInteractMenuSelect")
addEvent("inv:snapResult", true)

local IO_RESOURCE = "ui_interactobject"
local byObject = {}       -- object -> item
local menuItem = {}       -- menu id -> item
local models = {}         -- defId -> model that can be created (model or fallback), false = none

local function isRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

-- ---------------------------------------------------------------------------------------------
-- Models
-- ---------------------------------------------------------------------------------------------

local function tryCreate(model, x, y, z, rx, ry, rz)
    if not model then return nil end
    return createObject(model, x, y, z, rx or 0, ry or 0, rz or 0) or nil
end

-- The model of the item that the server can create (its model, else its fallback) | nil
function resolvedModel(defId)
    local def = ITEMS[defId]
    if not def or not def.model then return nil end
    if models[defId] == nil then
        models[defId] = false
        for _, model in ipairs({ def.model, def.fallback }) do
            local obj = tryCreate(model, 0, 0, -100)
            if obj then
                destroyElement(obj)
                models[defId] = model
                if model ~= def.model then
                    outputDebugString(("[v_inventory] model %d (%s) is not available, using %d"):format(def.model, defId, model), 2)
                end
                break
            end
        end
    end
    return models[defId] or nil
end

-- ---------------------------------------------------------------------------------------------
-- Ground menu
-- ---------------------------------------------------------------------------------------------

local function itemName(item)
    return L.msg("v_inventory.item." .. item.def .. ".name")
end

local function groundDef(item)
    local def = defOf(item)
    local items = {}
    if def.holdable or def.back then
        items[#items + 1] = { label = L.msg("v_inventory.ui.pick_up"), value = "pickup" }
    end
    if def.container then
        items[#items + 1] = { label = L.msg("v_inventory.ui.open"), value = "open" }
    end
    local title = itemName(item)
    if item.amount > 1 then title = L.msg("v_inventory.ui.name_amount", { name = title, amount = item.amount }) end
    return {
        title = title,
        range = INV.GROUND_MENU_RANGE,
        priority = 12,
        lineOfSight = false,     -- model origins sit off-centre / under the ground
        selfDataKey = item.access and item.access.dataKey or nil,
        items = items,
    }
end

local function registerMenu(item)
    if not isRunning(IO_RESOURCE) or not isElement(item.object) or item.loc.type ~= "ground" then return end
    item.menuId = exports[IO_RESOURCE]:addInteractMenu(item.object, groundDef(item))
    if item.menuId then menuItem[item.menuId] = item end
end

local function removeMenu(item)
    if not item.menuId then return end
    menuItem[item.menuId] = nil
    if isRunning(IO_RESOURCE) then exports[IO_RESOURCE]:removeInteractMenu(item.menuId) end
    item.menuId = nil
end

-- The amount / title changed
function refreshGroundMenu(item)
    if item.menuId and isRunning(IO_RESOURCE) then
        exports[IO_RESOURCE]:updateInteractMenu(item.menuId, groundDef(item))
    end
end

-- ---------------------------------------------------------------------------------------------
-- Objects (hooks of server/core.lua)
-- ---------------------------------------------------------------------------------------------

function createWorldObject(item, loc)
    local def = defOf(item)
    local model = resolvedModel(item.def)
    if not model then return false end
    local obj
    if loc.type == "ground" then
        local g = def.offsets and def.offsets.ground or { 0, 0, 0, 0, 0, 0 }
        obj = tryCreate(model, loc.x + g[1], loc.y + g[2], loc.z + g[3], g[4], g[5], (loc.rz or 0) + g[6])
        if not obj then return false end
        setElementDimension(obj, loc.dim or 0)
        setElementInterior(obj, loc.int or 0)
        setElementFrozen(obj, true)
    else
        local x, y, z = getElementPosition(loc.element)
        obj = tryCreate(model, x, y, z)
        if not obj then return false end
        setElementDimension(obj, getElementDimension(loc.element))
        setElementInterior(obj, getElementInterior(loc.element))
        setElementCollisionsEnabled(obj, false)
        local o = loc.offset
        attachElements(obj, loc.element, o[1], o[2], o[3], o[4], o[5], o[6])
    end
    if def.scale and def.scale ~= 1 then setObjectScale(obj, def.scale) end
    setElementData(obj, INV_DATA.ITEM, item.uid)
    item.object = obj
    byObject[obj] = item
    if loc.type == "ground" then registerMenu(item) end
    return true
end

function removeWorldObject(item)
    removeMenu(item)
    local obj = item.object
    item.object = nil
    if obj then
        byObject[obj] = nil
        if isElement(obj) then destroyElement(obj) end
    end
end

function getItemByObject(obj) return byObject[obj] end

-- ---------------------------------------------------------------------------------------------
-- Dropping
-- ---------------------------------------------------------------------------------------------

-- On the ground at x, y, z (foot level). `snapper`'s client corrects the height to the real ground
-- (the server has no ground data). opts: moveItem options. -> true, uid | false, reason
function dropItemAt(item, x, y, z, rz, dim, int, snapper, opts)
    if z < INV.GROUND_MIN_Z and isElement(snapper) then
        x, y, z = getElementPosition(snapper)
        z = z - 1.0
    end
    local ok, result = moveItem(item, { type = "ground", x = x, y = y, z = z, rz = rz or 0, dim = dim or 0, int = int or 0 },
        opts or { force = true })
    if ok and isElement(snapper) and isElement(item.object) then
        local g = defOf(item).offsets and defOf(item).offsets.ground or { 0, 0, 0 }
        triggerClientEvent(snapper, "inv:snap", resourceRoot, item.object, g[3])
    end
    return ok, result
end

addEventHandler("inv:snapResult", resourceRoot, function(obj, z)
    local item = byObject[obj]
    if not item or type(z) ~= "number" or not isElement(obj) then return end
    local cx, cy, cz = getElementPosition(client)
    local x, y, oldZ = getElementPosition(obj)
    if getDistanceBetweenPoints3D(cx, cy, cz, x, y, oldZ) > 15 or math.abs(z - oldZ) > 2.5 then return end
    setElementPosition(obj, x, y, z)
end)

-- ---------------------------------------------------------------------------------------------
-- Menus
-- ---------------------------------------------------------------------------------------------

addEventHandler("onInteractMenuSelect", root, function(menuId, value)
    local item = menuItem[menuId]
    if not item or not Items[item.uid] or item.loc.type ~= "ground" or not isElement(item.object) then return end
    local player = source
    if isPedDead(player) or isPedInVehicle(player) then return end
    local x, y, z = getElementPosition(item.object)
    local px, py, pz = getElementPosition(player)
    if getDistanceBetweenPoints3D(x, y, z, px, py, pz) > INV.GROUND_MENU_RANGE + 1.5 then return end
    if not canPlayerHandle(player, item) then return notify(player, L.msg("v_inventory.msg.no_access"), true) end
    if value == "pickup" then
        local ok, reason = giveToPlayer(item, player, nil, { player = player })
        if not ok then notify(player, reason, true) end
    elseif value == "open" then
        openSession(player, { type = "container", item = item })
    end
end)

addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) ~= IO_RESOURCE then return end
    menuItem = {}
    for _, item in pairs(Items) do
        item.menuId = nil
        if item.loc.type == "ground" then registerMenu(item) end
    end
end)

addEventHandler("onResourceStop", root, function(res)
    if getResourceName(res) ~= IO_RESOURCE then return end
    menuItem = {}
    for _, item in pairs(Items) do item.menuId = nil end
end)

-- ---------------------------------------------------------------------------------------------
-- Destruction from outside
-- ---------------------------------------------------------------------------------------------

addEventHandler("onElementDestroy", root, function()
    local source = source -- nested events may replace the global
    local item = byObject[source]
    if item then
        -- somebody else destroyed the item's object: the item stays as data (its creator decides)
        byObject[source] = nil
        item.object = nil
        removeMenu(item)
        if Items[item.uid] then moveItem(item, { type = "none" }, { force = true }) end
        return
    end
    -- an element with items attached disappears: they fall to the ground there
    local x, y, z, dim, int
    for _, it in pairs(Items) do
        if it.loc.type == "attached" and it.loc.element == source then
            if not x then x, y, z, dim, int = rootPosition(source) end
            dropItemAt(it, x, y, z - 0.45, 0, dim, int, nil)
        end
    end
end)
