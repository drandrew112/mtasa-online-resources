-- Unit tests of the server logic with MTA stubbed (run: python tests/run.py)

local failures, passed = 0, 0
local function check(cond, name)
    if cond then passed = passed + 1 else failures = failures + 1 print("FAIL " .. name) end
end

-- ---------------------------------------------------------------------------------------------
-- MTA stubs
-- ---------------------------------------------------------------------------------------------

local elements = {}
local function newElement(kind, data)
    local e = { __type = kind, data = {}, pos = { 0, 0, 0 }, dim = 0, int = 0 }
    for k, v in pairs(data or {}) do e[k] = v end
    elements[e] = true
    return e
end

L = setmetatable({}, { __call = function(_, k) return k end })
function L.msg(k, p) return { t = k, p = p, __loc = true } end
L.text = L.msg

resource = { name = "v_inventory" }
resourceRoot = newElement("resource")
root = newElement("root")
sourceResource = nil
client = nil

local handlers = {}
local cancelled, cancelReason = false, nil
function addEvent() end
function addEventHandler(name, _, fn) handlers[name] = handlers[name] or {}; table.insert(handlers[name], fn) end
function triggerEvent(name, src, ...)
    cancelled, cancelReason = false, nil
    for _, fn in ipairs(handlers[name] or {}) do
        local old = source
        source = src
        fn(...)
        source = old
    end
    return not cancelled
end
function cancelEvent(_, reason) cancelled, cancelReason = true, reason end
function wasEventCancelled() return cancelled end
function getCancelReason() return cancelReason end
local clientEvents = {}
function triggerClientEvent(player, name, _, ...) clientEvents[#clientEvents + 1] = { player = player, name = name, args = { ... } } end
local timers = {}
function setTimer(fn, _, times, ...) local t = { fn = fn, args = { ... }, rep = times == 0 } timers[#timers + 1] = t return t end
local function runTimers()
    local list = timers
    timers = {}
    for _, t in ipairs(list) do
        if t.rep then timers[#timers + 1] = t else t.fn(unpack(t.args)) end
    end
end
function isTimer() return true end
function killTimer() end
function outputDebugString() end

function isElement(e) return type(e) == "table" and elements[e] == true end
function getElementType(e) return e.__type end
function getElementData(e, k) return e.data[k] end
function setElementData(e, k, v) e.data[k] = v return true end
function removeElementData(e, k) e.data[k] = nil end
function getElementPosition(e) return e.pos[1], e.pos[2], e.pos[3] end
function setElementPosition(e, x, y, z) e.pos = { x, y, z } end
function getElementRotation() return 0, 0, 0 end
function getElementDimension(e) return e.dim end
function getElementInterior(e) return e.int end
function setElementDimension(e, d) e.dim = d end
function setElementInterior(e, i) e.int = i end
function getElementAttachedTo(e) return e.attachedTo end
function attachElements(a, b) a.attachedTo = b end
function destroyElement(e) elements[e] = nil if handlers.onElementDestroy then for _, fn in ipairs(handlers.onElementDestroy) do source = e fn() end end end
function createObject(model, x, y, z) if model == 99999 then return false end return newElement("object", { model = model, pos = { x, y, z } }) end
function createMarker(x, y, z) return newElement("marker", { pos = { x, y, z } }) end
function setElementFrozen() end
function setElementCollisionsEnabled() end
function setElementAlpha() end
function setObjectScale() end
function setElementVisibleTo() end
function toggleControl() end
function setPedAnimation() end
function isPedDead() return false end
function isPedInVehicle() return false end
function getElementsByType(kind) local out = {} for e in pairs(elements) do if e.__type == kind then out[#out + 1] = e end end return out end
function getResourceFromName() return nil end
function getResourceName(r) return r.name end
function getResourceState() return "stopped" end
function getVehiclePlateText() return " AB-123 " end
function getDistanceBetweenPoints3D(x1, y1, z1, x2, y2, z2) return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2 + (z1 - z2) ^ 2) end
function getDistanceBetweenPoints2D(x1, y1, x2, y2) return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2) end
function addCommandHandler() end
exports = setmetatable({}, { __index = function() return setmetatable({}, { __index = function() return function() end end }) end })

-- ---------------------------------------------------------------------------------------------
-- Load the resource
-- ---------------------------------------------------------------------------------------------

local base = TEST_BASE
for _, f in ipairs({ "shared/config.lua", "shared/items.lua", "server/core.lua", "server/slots.lua", "server/world.lua",
    "server/ports.lua", "server/trunks.lua", "server/ui.lua", "server/exports.lua" }) do
    local chunk = assert(loadfile(base .. f))
    chunk()
end

local p1 = newElement("player", { name = "p1" })
local p2 = newElement("player", { name = "p2" })
local function key(r) return type(r) == "table" and r.t or r end

-- ---------------------------------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------------------------------

-- create + unknown id
check(createItem("nope") == false, "unknown id refused")
local bag = createItem("medical_bag", nil, { type = "none" })
check(type(bag) == "string" and Items[bag] ~= nil, "bag created")

-- contents, stacking, weight
local f1 = createItem("drug_fentanyl", nil, { type = "container", container = bag }, { amount = 2 })
local f2 = createItem("drug_fentanyl", nil, { type = "container", container = bag }, { amount = 1 })
check(f2 == f1 and Items[f1].amount == 3, "stacks merge on create")
check(#Items[bag].contents == 1, "one stack in the bag")
local cyl = createItem("medical_oxygen_cylinder", { oxygen = 100 }, { type = "container", container = bag })
local used, cap = getContainerWeight(bag)
check(math.abs(used - (0.15 + 3.0)) < 1e-6 and cap == 10, "container weight")

-- capacity
local tooMuch, why = createItem("drug_ketamine", nil, { type = "container", container = bag }, { amount = 200 })
check(tooMuch == false and key(why) == "v_inventory.msg.too_heavy", "capacity enforced")

-- accepts filter / container in container
local box = createItem("bt_blood_box", nil, { type = "none" })
local r, w = moveInventoryItem(cyl, { type = "container", container = box })
check(r == false and key(w) == "v_inventory.msg.does_not_fit_here", "accepts filter")
r, w = moveInventoryItem(box, { type = "container", container = bag })
check(r == false and key(w) == "v_inventory.msg.no_container_in_container", "no container in container")

-- slots
check(giveItemToPlayer(p1, bag) == bag, "bag into a hand")
check(Items[bag].loc.type == "slot" and Items[bag].loc.slot == "left", "bag in the preferred left hand")
local lp = createItem("lifepak15", nil, { type = "none" })
check(giveItemToPlayer(p1, lp) == lp and Items[lp].loc.slot == "right", "lifepak right hand")
local box2 = createItem("bt_blood_box", nil, { type = "none" })
r, w = giveItemToPlayer(p1, box2)
check(r == false and key(w) == "v_inventory.msg.hands_full", "hands full")
local pack = createItem("backpack", nil, { type = "none" })
check(giveItemToPlayer(p1, pack) == pack and Items[pack].loc.slot == "back", "backpack on the back")
r = moveInventoryItem(bag, { type = "slot", player = p1, slot = "back" })
check(r == false, "bag cannot go on the back")
runTimers()
local slotsData = p1.data[INV_DATA.SLOTS]
check(slotsData and slotsData.left and slotsData.left.d == "medical_bag" and slotsData.back.d == "backpack", "slot element data")

-- position through containers
p1.pos = { 10, 20, 3 }
local x, y, z, _, _, t = getItemPosition(f1)
check(x == 10 and y == 20 and t == "slot", "position through the hand")

-- player move: split one piece of a stack into the backpack
Sessions[p1] = { x = 10, y = 20, z = 3, dim = 0, int = 0 }
local ok = moveItem(Items[f1], { type = "container", item = Items[pack] }, { player = p1, amount = 1 })
check(ok and Items[f1].amount == 2 and #Items[pack].contents == 1 and Items[pack].contents[1].amount == 1, "split one piece")
-- and back: merges
local piece = Items[pack].contents[1]
ok = moveItem(piece, { type = "container", item = Items[bag] }, { player = p1 })
check(ok and Items[f1].amount == 3 and Items[piece.uid] == nil, "piece merges back")

-- not storable: lifepak cannot go into the backpack / a trunk by a player
ok, w = moveItem(Items[lp], { type = "container", item = Items[pack] }, { player = p1 })
check(not ok, "lifepak not into a container")

-- cancelable event
addEventHandler("onInventoryItemMove", resourceRoot, function(uid, def)
    if def == "glucometer" then cancelEvent(true, "nope") end
end)
local glu = createItem("glucometer", nil, { type = "none" })
r, w = moveInventoryItem(glu, { type = "container", container = bag })
check(r == false and w == "nope", "move cancelled by a handler")

-- ports: rules + suggestions
local port = createPort({ x = 0, y = 0, z = 0, capacity = 5, name = "Test" })
check(type(port) == "string", "port created")
local unit = createItem("bandage", nil, { type = "container", container = box2 }, { amount = 2 })
setPortRules(port, p2, { allowIn = { "splint" } })
ok, w = moveItem(Items[unit], { type = "port", port = port }, { player = p2 })
check(not ok and key(w) == "v_inventory.msg.not_accepted_here", "port rule refuses for p2")
ok = moveItem(Items[unit], { type = "port", port = port }, { player = p1 })
check(ok and #getPortItems(port) == 1, "p1 has no rule")
setPortRules(port, p1, { allowOut = false })
ok, w = moveItem(Items[unit], { type = "container", item = Items[box2] }, { player = p1 })
check(not ok and key(w) == "v_inventory.msg.cannot_take", "allowOut false")
check(moveInventoryItem(unit, { type = "container", container = box2 }) ~= false, "a script ignores the rules")
setPortSuggestions(port, p1, { bandage = "in" }, "Deliver")
check(portSuggestion(port, p1, Items[unit]) == "in" and portBanner(port, p1) == "Deliver", "suggestion")

-- vehicle store + tags, drop, attach
local veh = newElement("vehicle", { pos = { 100, 0, 0 } })
check(storeItemInVehicle(bag, veh, "aboard") == bag, "store in vehicle")
check(#getVehicleStoredItems(veh, "aboard") == 1 and #getVehicleStoredItems(veh, "x") == 0, "stored by tag")
local px = getItemPosition(f1)
check(px == 100, "contents follow the vehicle")
local stretcher = newElement("object", { pos = { 50, 5, 1 } })
check(attachItem(bag, stretcher, { 0, 1, 0 }) == bag and isElement(Items[bag].object), "attach creates an object")
check(getItemAttachedTo(bag) == stretcher, "attached to")
destroyElement(stretcher)
check(Items[bag].loc.type == "ground" and isElement(Items[bag].object), "attached item falls to the ground")
check(giveItemToPlayer(p2, bag) == bag and not Items[bag].object, "picked up: no world object")

-- player put-down
local n = dropPlayerItems(p2)
check(n == 1 and Items[bag].loc.type == "ground", "dropPlayerItems")

-- trunk access + destroy
check(createTrunk(veh, { capacity = 20, dataKey = "work" }) == true, "trunk created")
check(addTrunkItem(veh, box2) == box2, "box into trunk")
check(not hasTrunkAccess(Trunks[veh], p1), "no access without data")
p1.data.work = "x"
check(hasTrunkAccess(Trunks[veh], p1), "access with data")
destroyElement(veh)
check(Items[box2] == nil and Items[unit] == nil, "trunk items gone with the vehicle")

-- owner stop
sourceResource = { name = "other" }
local own = createItem("splint", nil, { type = "none" })
sourceResource = nil
for _, fn in ipairs(handlers.onResourceStop) do fn({ name = "other" }) end
check(Items[own] == nil, "items of a stopped resource are destroyed")

-- takeItemAmount
check(takeItemAmount(f1, 2) == 1 and takeItemAmount(f1, 1) == 0 and Items[f1] == nil, "takeItemAmount destroys at 0")

print(("passed %d, failed %d"):format(passed, failures))
return failures
