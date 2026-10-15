if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Items, locations and moves. The server is the only authority; nothing is stored across a restart
-- (other resources create every item through the exports).
--
-- An item is in exactly one location (item.loc):
--   { type = "none" }                                   data only, held by its creator
--   { type = "slot", player, slot }                     "left" | "right" | "back" (server/slots.lua)
--   { type = "container", item = <container item> }     inside a container item (item.contents)
--   { type = "ground", x, y, z, rz, dim, int }          a world object with a pick-up menu (server/world.lua)
--   { type = "attached", element, offset }              a world object attached to an element
--   { type = "port", port = id }                        a port's storage (server/ports.lua)
--   { type = "trunk", vehicle }                         a trunk (server/trunks.lua)
--   { type = "vehicle", vehicle, tag }                  stored in a vehicle without a trunk
-- Exports see the same tables with `container = uid` instead of the item table.
-- Every move goes through moveItem: rules, weight, the cancelable onInventoryItemMove event, then
-- onInventoryItemMoved. Containers carry their contents with them.

addEvent("onInventoryItemMove")       -- source: resourceRoot; (uid, defId, from, to, player|false, amount) cancelable
addEvent("onInventoryItemMoved")      -- source: resourceRoot; (uid, defId, from, to, player|false, amount)
addEvent("onInventoryItemDestroyed")  -- source: resourceRoot; (uid, defId, owner)
addEvent("onInventoryItemChanged")    -- source: resourceRoot; (uid, defId, what = "meta" | "amount")
addEvent("onInventoryReady")          -- source: resourceRoot; v_inventory (re)started: create the items again

Items = {}            -- uid -> item
local nextUid = 0

-- ---------------------------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------------------------

function defOf(item) return ITEMS[item.def] end

function isContainer(item) return defOf(item).container ~= nil end

local function removeFrom(list, item)
    for i = #list, 1, -1 do
        if list[i] == item then table.remove(list, i) return true end
    end
    return false
end

-- Position of an element from the top of its attachment chain (server positions of attached
-- elements are not reliable)
function rootPosition(element)
    local top, guard = element, 0
    while guard < 5 do
        local parent = getElementAttachedTo(top)
        if not parent then break end
        top, guard = parent, guard + 1
    end
    local x, y, z = getElementPosition(top)
    return x, y, z, getElementDimension(top), getElementInterior(top)
end

-- The outermost item of a nesting (an item in a container -> the container)
function topItem(item)
    local guard = 0
    while item.loc.type == "container" and guard < 4 do
        item, guard = item.loc.item, guard + 1
    end
    return item
end

-- -> x, y, z, dimension, interior | false
function itemWorldPosition(item)
    local top = topItem(item)
    local loc = top.loc
    if loc.type == "slot" and isElement(loc.player) then
        local x, y, z = getElementPosition(loc.player)
        return x, y, z, getElementDimension(loc.player), getElementInterior(loc.player)
    elseif loc.type == "ground" then
        if isElement(top.object) then
            local x, y, z = getElementPosition(top.object)
            return x, y, z, loc.dim, loc.int
        end
        return loc.x, loc.y, loc.z, loc.dim, loc.int
    elseif loc.type == "attached" and isElement(loc.element) then
        return rootPosition(loc.element)
    elseif loc.type == "port" then
        local port = Ports[loc.port]
        if port then return port.x, port.y, port.z, port.dim, port.int end
    elseif (loc.type == "trunk" or loc.type == "vehicle") and isElement(loc.vehicle) then
        return rootPosition(loc.vehicle)
    end
    return false
end

-- ---------------------------------------------------------------------------------------------
-- Public location tables (exports / events)
-- ---------------------------------------------------------------------------------------------

function toPublicLoc(loc)
    local out = {}
    for k, v in pairs(loc) do out[k] = v end
    if loc.type == "container" then
        out.item, out.container = nil, loc.item.uid
    end
    return out
end

-- Validates an export location -> internal loc | nil, error
function fromPublicLoc(p)
    if type(p) ~= "table" then return nil, "location table expected" end
    local t = p.type
    if t == "none" then return { type = "none" } end
    if t == "slot" then
        if not isElement(p.player) or getElementType(p.player) ~= "player" then return nil, "player expected" end
        if p.slot ~= "left" and p.slot ~= "right" and p.slot ~= "back" then return nil, "slot must be left / right / back" end
        return { type = "slot", player = p.player, slot = p.slot }
    elseif t == "container" then
        local c = Items[p.container]
        if not c or not isContainer(c) then return nil, "container uid expected" end
        return { type = "container", item = c }
    elseif t == "ground" then
        local x, y, z = tonumber(p.x), tonumber(p.y), tonumber(p.z)
        if not (x and y and z) then return nil, "x, y, z expected" end
        return { type = "ground", x = x, y = y, z = z, rz = tonumber(p.rz) or 0,
            dim = tonumber(p.dim) or 0, int = tonumber(p.int) or 0 }
    elseif t == "attached" then
        if not isElement(p.element) then return nil, "element expected" end
        local o = type(p.offset) == "table" and p.offset or {}
        return { type = "attached", element = p.element,
            offset = { tonumber(o[1]) or 0, tonumber(o[2]) or 0, tonumber(o[3]) or 0,
                tonumber(o[4]) or 0, tonumber(o[5]) or 0, tonumber(o[6]) or 0 } }
    elseif t == "port" then
        if not Ports[p.port] then return nil, "port id expected" end
        return { type = "port", port = p.port }
    elseif t == "trunk" then
        if not isElement(p.vehicle) or not Trunks[p.vehicle] then return nil, "vehicle with a trunk expected" end
        return { type = "trunk", vehicle = p.vehicle }
    elseif t == "vehicle" then
        if not isElement(p.vehicle) or getElementType(p.vehicle) ~= "vehicle" then return nil, "vehicle expected" end
        return { type = "vehicle", vehicle = p.vehicle, tag = p.tag ~= nil and tostring(p.tag) or nil }
    end
    return nil, "unknown location type " .. tostring(t)
end

local function sameLoc(a, b)
    if a.type ~= b.type then return false end
    if a.type == "slot" then return a.player == b.player and a.slot == b.slot end
    if a.type == "container" then return a.item == b.item end
    if a.type == "port" then return a.port == b.port end
    if a.type == "trunk" then return a.vehicle == b.vehicle end
    if a.type == "vehicle" then return a.vehicle == b.vehicle and a.tag == b.tag end
    return false  -- ground / attached / none: always a real move
end

-- ---------------------------------------------------------------------------------------------
-- Holders: the item lists of containers, ports, trunks and vehicles
-- ---------------------------------------------------------------------------------------------

VehicleStore = {} -- vehicle -> { items }

-- -> list, capacity (kg | nil), accepts ({ category = true } | nil)
function holderOf(loc)
    if loc.type == "container" then
        local c = defOf(loc.item).container
        return loc.item.contents, c.capacity, c.accepts
    elseif loc.type == "port" then
        local port = Ports[loc.port]
        if port then return port.items, port.capacity, port.accepts end
    elseif loc.type == "trunk" then
        local trunk = Trunks[loc.vehicle]
        if trunk then return trunk.items, trunk.capacity, nil end
    elseif loc.type == "vehicle" then
        VehicleStore[loc.vehicle] = VehicleStore[loc.vehicle] or {}
        return VehicleStore[loc.vehicle], nil, nil
    end
    return nil
end

-- ---------------------------------------------------------------------------------------------
-- Weight
-- ---------------------------------------------------------------------------------------------

function listWeight(list)
    local w = 0
    for _, it in ipairs(list) do w = w + itemWeight(it) end
    return w
end

function itemWeight(item)
    local w = (defOf(item).weight or 0) * item.amount
    if item.contents then w = w + listWeight(item.contents) end
    return w
end

-- ---------------------------------------------------------------------------------------------
-- Access (item.access = { dataKey, dataValue }: only such players may handle it)
-- ---------------------------------------------------------------------------------------------

function hasDataAccess(player, dataKey, dataValue)
    if not dataKey then return true end
    local v = getElementData(player, dataKey)
    if dataValue ~= nil then return v == dataValue end
    return v ~= nil and v ~= false
end

-- The player may touch the item (its own access and every container around it)
function canPlayerHandle(player, item)
    local guard = 0
    while item and guard < 5 do
        local a = item.access
        if a and not hasDataAccess(player, a.dataKey, a.dataValue) then return false end
        item = item.loc.type == "container" and item.loc.item or nil
        guard = guard + 1
    end
    return true
end

-- ---------------------------------------------------------------------------------------------
-- Rules
-- ---------------------------------------------------------------------------------------------

-- Can the item go to loc? opts: player (a player does it: player rules apply), amount, force
-- (a script: storable / port rules are skipped). -> true | false, reason (message object)
function checkPlace(item, loc, opts)
    opts = opts or {}
    local def = defOf(item)
    local player = opts.player
    local amount = opts.amount or item.amount

    if loc.type == "slot" then
        local slots = Slots[loc.player]
        local other = slots and slots[loc.slot]
        if other and other ~= item then return false, L.msg("v_inventory.msg.slot_taken") end
        if loc.slot == "back" then
            if not def.back then return false, L.msg("v_inventory.msg.not_for_back") end
        elseif not def.holdable then
            return false, L.msg("v_inventory.msg.not_holdable")
        end
        if player and loc.player ~= player then return false, L.msg("v_inventory.msg.not_yours") end
        if amount ~= item.amount then return false, L.msg("v_inventory.msg.whole_item_only") end
    elseif loc.type == "container" or loc.type == "port" or loc.type == "trunk" then
        if loc.type == "container" then
            if def.container then return false, L.msg("v_inventory.msg.no_container_in_container") end
            if loc.item == item then return false, L.msg("v_inventory.msg.cannot_do_that") end
        end
        if not def.storable and not opts.force then return false, L.msg("v_inventory.msg.not_storable") end
        local list, capacity, accepts = holderOf(loc)
        if not list then return false, L.msg("v_inventory.msg.cannot_do_that") end
        if accepts and not accepts[def.category] then return false, L.msg("v_inventory.msg.does_not_fit_here") end
        if capacity then
            local moving = (def.weight or 0) * amount + (item.contents and listWeight(item.contents) or 0)
            if listWeight(list) + moving > capacity + 1e-6 then return false, L.msg("v_inventory.msg.too_heavy") end
        end
        if loc.type == "port" and player and not opts.force then
            local ok = portAllows(loc.port, player, item, "in")
            if not ok then return false, L.msg("v_inventory.msg.not_accepted_here") end
        end
        if loc.type == "container" and player and not canPlayerHandle(player, loc.item) then
            return false, L.msg("v_inventory.msg.no_access")
        end
    elseif player then
        -- vehicle / attached / none: scripts only; ground: through the drop functions
        if loc.type ~= "ground" then return false, L.msg("v_inventory.msg.cannot_do_that") end
    end

    if player then
        if not canPlayerHandle(player, item) then return false, L.msg("v_inventory.msg.no_access") end
        if item.loc.type == "port" and not opts.force and not portAllows(item.loc.port, player, item, "out") then
            return false, L.msg("v_inventory.msg.cannot_take")
        end
    end
    return true
end

-- ---------------------------------------------------------------------------------------------
-- Placing / removing (no rules)
-- ---------------------------------------------------------------------------------------------

local function unplace(item)
    local loc = item.loc
    if loc.type == "slot" then
        local slots = Slots[loc.player]
        if slots and slots[loc.slot] == item then slots[loc.slot] = nil end
        onSlotsChanged(loc.player)
    elseif loc.type == "ground" or loc.type == "attached" then
        removeWorldObject(item)
    else
        local list = holderOf(loc)
        if list then removeFrom(list, item) end
    end
    touchLoc(loc)
    item.loc = { type = "none" }
end

local function place(item, loc)
    item.loc = loc
    if loc.type == "slot" then
        Slots[loc.player] = Slots[loc.player] or {}
        Slots[loc.player][loc.slot] = item
        onSlotsChanged(loc.player)
    elseif loc.type == "ground" or loc.type == "attached" then
        if not createWorldObject(item, loc) then
            -- cannot exist in the world (model): it stays as data
            item.loc = { type = "none" }
        end
    else
        local list = holderOf(loc)
        if list then list[#list + 1] = item end
    end
    touchLoc(item.loc)
end

-- A stack of the same item already in the list (merge target)
local function stackIn(list, item)
    if not list or not defOf(item).stackable or next(item.meta) then return nil end
    for _, it in ipairs(list) do
        if it ~= item and it.def == item.def and not next(it.meta) and it.owner == item.owner then return it end
    end
    return nil
end

-- ---------------------------------------------------------------------------------------------
-- Items
-- ---------------------------------------------------------------------------------------------

function newItem(defId, amount, meta, owner, access)
    nextUid = nextUid + 1
    local item = {
        uid = "i" .. nextUid, def = defId, amount = math.max(1, math.floor(tonumber(amount) or 1)),
        meta = type(meta) == "table" and meta or {}, owner = owner, access = access,
        loc = { type = "none" },
    }
    if not ITEMS[defId].stackable then item.amount = 1 end
    if ITEMS[defId].container then item.contents = {} end
    Items[item.uid] = item
    return item
end

-- Moves (a part of) the item. opts: player, amount, force, silent (no events).
-- -> true, uid (the moved item / the stack it merged into) | false, reason
function moveItem(item, loc, opts)
    opts = opts or {}
    if not Items[item.uid] then return false, L.msg("v_inventory.msg.cannot_do_that") end
    local amount = math.floor(tonumber(opts.amount) or item.amount)
    if amount < 1 or amount > item.amount then return false, L.msg("v_inventory.msg.cannot_do_that") end
    if sameLoc(item.loc, loc) then return true, item.uid end
    local ok, reason = checkPlace(item, loc, { player = opts.player, amount = amount, force = opts.force })
    if not ok then return false, reason end

    local from, to = toPublicLoc(item.loc), toPublicLoc(loc)
    if not opts.silent then
        triggerEvent("onInventoryItemMove", resourceRoot, item.uid, item.def, from, to, opts.player or false, amount)
        if wasEventCancelled() then
            local why = getCancelReason()
            return false, (why and why ~= "") and why or L.msg("v_inventory.msg.cannot_do_that")
        end
        if not Items[item.uid] then return false, L.msg("v_inventory.msg.cannot_do_that") end
    end

    local moving = item
    if amount < item.amount then
        -- split: a new stack goes, the rest stays
        moving = newItem(item.def, amount, nil, item.owner, item.access)
        item.amount = item.amount - amount
        touchLoc(item.loc)
    else
        unplace(item)
    end

    local list = holderOf(loc)
    local stack = stackIn(list, moving)
    if stack then
        stack.amount = stack.amount + moving.amount
        Items[moving.uid] = nil
        moving.loc = { type = "none" }
        touchLoc(stack.loc)
        moving = stack
    else
        place(moving, loc)
    end

    if not opts.silent then
        triggerEvent("onInventoryItemMoved", resourceRoot, moving.uid, moving.def, from, to, opts.player or false, amount)
    end
    return true, moving.uid
end

function destroyItem(item)
    if not Items[item.uid] then return false end
    if item.contents then
        for i = #item.contents, 1, -1 do destroyItem(item.contents[i]) end
    end
    unplace(item)
    Items[item.uid] = nil
    triggerEvent("onInventoryItemDestroyed", resourceRoot, item.uid, item.def, item.owner or false)
    return true
end

function setAmount(item, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return destroyItem(item) end
    if not defOf(item).stackable then amount = 1 end
    if amount == item.amount then return true end
    item.amount = amount
    touchLoc(item.loc)
    triggerEvent("onInventoryItemChanged", resourceRoot, item.uid, item.def, "amount")
    return true
end

function setMeta(item, key, value)
    item.meta[key] = value
    touchLoc(item.loc)
    triggerEvent("onInventoryItemChanged", resourceRoot, item.uid, item.def, "meta")
    return true
end

-- Every item of a location list that matches (recursion into containers: deep)
function findItemsIn(list, filter, out, deep)
    out = out or {}
    for _, it in ipairs(list) do
        if (not filter.def or it.def == filter.def) and (not filter.owner or it.owner == filter.owner) then
            out[#out + 1] = it
        end
        if deep and it.contents then findItemsIn(it.contents, filter, out, deep) end
    end
    return out
end

-- ---------------------------------------------------------------------------------------------
-- Lifetime
-- ---------------------------------------------------------------------------------------------

-- The creator stopped: its items are gone
addEventHandler("onResourceStop", root, function(res)
    if res == resource then return end
    local name = getResourceName(res)
    local gone = {}
    for _, item in pairs(Items) do
        if item.owner == name then gone[#gone + 1] = item end
    end
    for _, item in ipairs(gone) do
        if Items[item.uid] then destroyItem(item) end
    end
end)

-- A vehicle disappears with what is stored in it
addEventHandler("onElementDestroy", root, function()
    local source = source
    if getElementType(source) ~= "vehicle" then return end
    local list = VehicleStore[source]
    if list then
        for i = #list, 1, -1 do if list[i] then destroyItem(list[i]) end end
    end
    VehicleStore[source] = nil
end)

addEventHandler("onResourceStart", resourceRoot, function()
    setTimer(function() triggerEvent("onInventoryReady", resourceRoot) end, 100, 1)
end)
