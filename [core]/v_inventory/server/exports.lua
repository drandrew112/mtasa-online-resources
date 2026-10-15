if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Server exports. Items are referred to by uid ("i42"), ports by id ("p3"), trunks by vehicle.
-- Locations are tables, see server/core.lua (a container is { type = "container", container = uid }).
-- Moves made through the exports are script moves: the storable flag and the port rules do not
-- apply, the weight limits and the cancelable onInventoryItemMove event do.

local function callerName()
    return sourceResource and getResourceName(sourceResource) or nil
end

local function get(uid)
    return type(uid) == "string" and Items[uid] or nil
end

-- ---------------------------------------------------------------------------------------------
-- Items
-- ---------------------------------------------------------------------------------------------

-- opts: amount, access = { dataKey, dataValue } (only such players may handle it)
-- -> uid | false, error
function createItem(defId, meta, loc, opts)
    if not ITEMS[defId] then return false, "unknown item id: " .. tostring(defId) end
    opts = type(opts) == "table" and opts or {}
    local target, err = fromPublicLoc(loc or { type = "none" })
    if not target then return false, err end
    local access
    if type(opts.access) == "table" and type(opts.access.dataKey) == "string" then
        access = { dataKey = opts.access.dataKey, dataValue = opts.access.dataValue }
    end
    local item = newItem(defId, opts.amount, meta, callerName(), access)
    if target.type == "none" then return item.uid end
    local ok, result = moveItem(item, target, { force = true, silent = true })
    if not ok then
        Items[item.uid] = nil
        return false, result
    end
    return result
end

function destroyInventoryItem(uid)
    local item = get(uid)
    return item and destroyItem(item) or false
end

-- -> { uid, def, amount, meta, owner, loc, weight, contents = { uid... } } | false
function getItem(uid)
    local item = get(uid)
    if not item then return false end
    local contents
    if item.contents then
        contents = {}
        for i, it in ipairs(item.contents) do contents[i] = it.uid end
    end
    return {
        uid = item.uid, def = item.def, amount = item.amount, meta = item.meta, owner = item.owner or false,
        loc = toPublicLoc(item.loc), weight = itemWeight(item), contents = contents,
        access = item.access or false,
    }
end

function getItemDef(defId)
    return ITEMS[defId] or false
end

function isItem(uid)
    return get(uid) ~= nil
end

function setItemMeta(uid, key, value)
    local item = get(uid)
    if not item or key == nil then return false end
    return setMeta(item, key, value)
end

function getItemMeta(uid, key)
    local item = get(uid)
    if not item then return false end
    if key == nil then return item.meta end
    return item.meta[key]
end

function setItemAmount(uid, amount)
    local item = get(uid)
    return item and setAmount(item, amount) or false
end

-- Takes n (default 1) from a stack; the stack is destroyed at 0. -> pieces left | false
function takeItemAmount(uid, n)
    local item = get(uid)
    if not item then return false end
    n = math.floor(tonumber(n) or 1)
    if n < 1 or n > item.amount then return false end
    local left = item.amount - n
    setAmount(item, left)
    return left
end

function setItemAccess(uid, dataKey, dataValue)
    local item = get(uid)
    if not item then return false end
    item.access = (dataKey and dataKey ~= false) and { dataKey = tostring(dataKey), dataValue = dataValue } or nil
    if item.loc.type == "ground" then refreshGroundMenu(item) end
    return true
end

-- opts: amount, player (the move counts as that player's: player rules apply)
-- -> uid (the moved item / the stack it merged into) | false, reason
function moveInventoryItem(uid, loc, opts)
    local item = get(uid)
    if not item then return false, "unknown uid" end
    local target, err = fromPublicLoc(loc)
    if not target then return false, err end
    opts = type(opts) == "table" and opts or {}
    local player = isElement(opts.player) and opts.player or nil
    local ok, result = moveItem(item, target, { amount = tonumber(opts.amount), player = player, force = player == nil })
    if not ok then return false, result end
    return result
end

-- -> x, y, z, dimension, interior, locType | false  (through containers, slots, vehicles, attachments)
function getItemPosition(uid)
    local item = get(uid)
    if not item then return false end
    local x, y, z, dim, int = itemWorldPosition(item)
    if not x then return false end
    return x, y, z, dim, int, topItem(item).loc.type
end

-- filter: { def, owner, deep } in a location (loc table) -> { uid... }
function findItems(loc, filter)
    filter = type(filter) == "table" and filter or {}
    local list
    if type(loc) == "table" and loc.type == "slot" then
        local slots = getSlots(loc.player)
        list = {}
        for _, slot in ipairs(INV.SLOTS) do
            if slots and slots[slot] and (not loc.slot or loc.slot == slot) then list[#list + 1] = slots[slot] end
        end
    else
        local target = fromPublicLoc(loc)
        list = target and holderOf(target) or {}
    end
    local out = {}
    for i, it in ipairs(findItemsIn(list, filter, nil, filter.deep == true)) do out[i] = it.uid end
    return out
end

-- Contents of a container -> { uid... } | false
function getContainerItems(uid)
    local item = get(uid)
    if not item or not item.contents then return false end
    local out = {}
    for i, it in ipairs(item.contents) do out[i] = it.uid end
    return out
end

-- Contents with their data in one call -> { { uid, def, amount, meta } ... } | false
function getContainerContents(uid)
    local item = get(uid)
    if not item or not item.contents then return false end
    local out = {}
    for i, it in ipairs(item.contents) do
        out[i] = { uid = it.uid, def = it.def, amount = it.amount, meta = it.meta }
    end
    return out
end

-- -> used, capacity | false
function getContainerWeight(uid)
    local item = get(uid)
    if not item or not item.contents then return false end
    return listWeight(item.contents), defOf(item).container.capacity
end

-- Destroys every item in the container
function clearContainer(uid)
    local item = get(uid)
    if not item or not item.contents then return false end
    for i = #item.contents, 1, -1 do
        if item.contents[i] then destroyItem(item.contents[i]) end
    end
    return true
end

-- ---------------------------------------------------------------------------------------------
-- Players
-- ---------------------------------------------------------------------------------------------

-- -> { left = uid, right = uid, back = uid } (missing = empty)
function getPlayerSlots(player)
    local slots = isElement(player) and getSlots(player)
    local out = {}
    if slots then
        for _, slot in ipairs(INV.SLOTS) do
            if slots[slot] then out[slot] = slots[slot].uid end
        end
    end
    return out
end

-- Into a free slot (slot = nil: the back for back-only items, else the preferred free hand)
-- -> uid | false, reason
function giveItemToPlayer(player, uid, slot)
    local item = get(uid)
    if not item or not isElement(player) then return false, "bad arguments" end
    local ok, result = giveToPlayer(item, player, slot, { force = true })
    if not ok then return false, result end
    return result
end

function isPlayerHandsFree(player)
    local slots = getSlots(player)
    return not (slots and (slots.left or slots.right))
end

-- Puts the player's items down. slots = { "left", "right", "back" } (default: the hands),
-- px, py = beside this point (e.g. a patient), uids = { uid... } only these -> count
function dropPlayerItems(player, slots, px, py, uids)
    if not isElement(player) then return 0 end
    local only
    if type(uids) == "table" then
        only = {}
        for _, uid in ipairs(uids) do only[uid] = true end
    end
    return dropPlayerSlots(player, type(slots) == "table" and slots or nil, tonumber(px), tonumber(py), only)
end

-- On the ground at a point. snapPlayer: whose client corrects the height (optional)
function dropItem(uid, x, y, z, rz, dimension, interior, snapPlayer)
    local item = get(uid)
    if not item then return false end
    local ok, result = dropItemAt(item, tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0, tonumber(rz) or 0,
        tonumber(dimension) or 0, tonumber(interior) or 0, isElement(snapPlayer) and snapPlayer or nil)
    if not ok then return false, result end
    return result
end

-- ---------------------------------------------------------------------------------------------
-- Attach / store in a vehicle
-- ---------------------------------------------------------------------------------------------

function attachItem(uid, element, offset)
    local item = get(uid)
    if not item or not isElement(element) then return false end
    local ok, result = moveItem(item, fromPublicLoc({ type = "attached", element = element, offset = offset }), { force = true })
    if not ok then return false, result end
    return result
end

-- -> the element the item is attached to | false
function getItemAttachedTo(uid)
    local item = get(uid)
    return item and item.loc.type == "attached" and item.loc.element or false
end

function storeItemInVehicle(uid, vehicle, tag)
    local item = get(uid)
    if not item or not isElement(vehicle) then return false end
    local ok, result = moveItem(item, { type = "vehicle", vehicle = vehicle, tag = tag ~= nil and tostring(tag) or nil }, { force = true })
    if not ok then return false, result end
    return result
end

-- -> { uid... } (tag = only those with this tag)
function getVehicleStoredItems(vehicle, tag)
    local out = {}
    for _, it in ipairs(VehicleStore[vehicle] or {}) do
        if tag == nil or it.loc.tag == tag then out[#out + 1] = it.uid end
    end
    return out
end

-- ---------------------------------------------------------------------------------------------
-- Ports
-- ---------------------------------------------------------------------------------------------

-- opts: x, y, z, dimension, interior, radius, name, title (strings or v_locals message objects),
-- icon (one letter), color { r, g, b }, capacity (kg), accepts { category... }, visibleTo { players },
-- dataKey, dataValue -> port id | false, error
function createPort(opts)
    if type(opts) ~= "table" then return false, "options table expected" end
    return createPortFrom(opts, callerName())
end

function destroyPort(id) return destroyPortById(id) end

-- visibleTo: { players } | nil (everyone); dataKey / dataValue: false clears the filter
function setPortVisibleTo(id, visibleTo, dataKey, dataValue)
    return setPortVisibility(id, visibleTo, dataKey, dataValue)
end

function addPortItem(id, uid)
    local item = get(uid)
    if not item or not Ports[id] then return false end
    local ok, result = moveItem(item, { type = "port", port = id }, { force = true })
    if not ok then return false, result end
    return result
end

-- Takes the item out of the port (to loc, default: none)
function removePortItem(id, uid, loc)
    local item = get(uid)
    if not item or item.loc.type ~= "port" or item.loc.port ~= id then return false end
    local target = fromPublicLoc(loc or { type = "none" })
    if not target then return false end
    local ok, result = moveItem(item, target, { force = true })
    if not ok then return false, result end
    return result
end

function getPortItems(id)
    local port = Ports[id]
    if not port then return false end
    local out = {}
    for i, it in ipairs(port.items) do out[i] = it.uid end
    return out
end

-- rules = { allowIn = true | false | { uid / defId... }, allowOut = ... } | nil (no rules) for one player
function setPortRules(id, player, rules) return setPortRulesFor(id, player, rules) end
function clearPortRules(id, player) return setPortRulesFor(id, player, nil) end

-- items = { [uid or defId] = "in" | "out" }, banner = text / message object | nil (clears)
function setPortSuggestions(id, player, items, banner) return setPortSuggestionsFor(id, player, items, banner) end

function isPlayerInPort(player, id)
    local port = Ports[id]
    return port ~= nil and isElement(player) and isPlayerAtPort(port, player)
end

-- ---------------------------------------------------------------------------------------------
-- Trunks
-- ---------------------------------------------------------------------------------------------

-- opts: capacity (kg), dataKey, dataValue (who may open it), offset { x, y, z } (vehicle-local menu
-- point), title
function createTrunk(vehicle, opts)
    if not isElement(vehicle) or getElementType(vehicle) ~= "vehicle" then return false, "vehicle expected" end
    return createTrunkFor(vehicle, opts, callerName())
end

function destroyTrunk(vehicle) return destroyTrunkOf(vehicle) end
function hasTrunk(vehicle) return Trunks[vehicle] ~= nil end
function setTrunkAccess(vehicle, dataKey, dataValue) return setTrunkAccessFor(vehicle, dataKey, dataValue) end

function addTrunkItem(vehicle, uid)
    local item = get(uid)
    if not item or not Trunks[vehicle] then return false end
    local ok, result = moveItem(item, { type = "trunk", vehicle = vehicle }, { force = true })
    if not ok then return false, result end
    return result
end

function removeTrunkItem(vehicle, uid, loc)
    local item = get(uid)
    if not item or item.loc.type ~= "trunk" or item.loc.vehicle ~= vehicle then return false end
    local target = fromPublicLoc(loc or { type = "none" })
    if not target then return false end
    local ok, result = moveItem(item, target, { force = true })
    if not ok then return false, result end
    return result
end

function getTrunkItems(vehicle)
    local trunk = Trunks[vehicle]
    if not trunk then return false end
    local out = {}
    for i, it in ipairs(trunk.items) do out[i] = it.uid end
    return out
end

-- ---------------------------------------------------------------------------------------------
-- Windows
-- ---------------------------------------------------------------------------------------------

-- Opens the window for the player. opts: container = uid (shown on the right), readOnly
function openInventory(player, opts)
    if not isElement(player) then return false end
    opts = type(opts) == "table" and opts or {}
    local other
    if opts.container then
        local item = get(opts.container)
        if not item or not item.contents then return false end
        other = { type = "container", item = item }
    end
    return openSession(player, other, { readOnly = opts.readOnly == true, external = true })
end

function closeInventory(player)
    closeSession(player, true)
    return true
end
