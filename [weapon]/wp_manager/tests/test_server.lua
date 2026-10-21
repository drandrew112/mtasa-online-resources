-- Unit tests of the wp_manager server logic with MTA stubbed (run: python tests/run.py)

local failures, passed = 0, 0
local function check(cond, name)
    if cond then passed = passed + 1 else failures = failures + 1 print("FAIL " .. name) end
end

-- ---------------------------------------------------------------------------------------------
-- MTA stubs
-- ---------------------------------------------------------------------------------------------

local elements = {}
local function newElement(kind, data)
    local e = { __type = kind, data = {}, weapons = {}, slot = 0, dead = false }
    for k, v in pairs(data or {}) do e[k] = v end
    elements[e] = true
    return e
end

L = setmetatable({}, { __call = function(_, k) return k end })
function L.msg(k, p) return { t = k, p = p, __loc = true } end
function L.forPlayer(_, k) return "text:" .. k end

resourceRoot = newElement("resource")
root = newElement("root")
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
local clientEvents = {}
function triggerClientEvent(player, name, _, ...) clientEvents[#clientEvents + 1] = { player = player, name = name, args = { ... } } end
local function lastClient(name)
    for i = #clientEvents, 1, -1 do if clientEvents[i].name == name then return clientEvents[i] end end
end
local timers = {}
function setTimer(fn, _, times, ...) timers[#timers + 1] = { fn = fn, args = { ... } } return true end
local function runTimers()
    local list = timers
    timers = {}
    for _, t in ipairs(list) do t.fn(unpack(t.args)) end
end

function isElement(e) return type(e) == "table" and elements[e] == true end
function getElementType(e) return e.__type end
function getElementData(e, k) return e.data[k] end
function setElementData(e, k, v) e.data[k] = v return true end
function removeElementData(e, k) e.data[k] = nil end
local players = {}
function getElementsByType(kind) return kind == "player" and players or {} end

-- GTA weapon slots
local SLOT = {}
local function slots(slot, ids) for _, id in ipairs(ids) do SLOT[id] = slot end end
slots(0, { 0, 1 }); slots(1, { 2, 3, 4, 5, 6, 7, 8, 9 }); slots(2, { 22, 23, 24 }); slots(3, { 25, 26, 27 })
slots(4, { 28, 29, 32 }); slots(5, { 30, 31 }); slots(6, { 33, 34 }); slots(7, { 35, 36, 37, 38 })
slots(8, { 16, 17, 18, 39 }); slots(9, { 41, 42, 43 }); slots(10, { 10, 11, 12, 13, 14, 15 })
slots(11, { 44, 45, 46 }); slots(12, { 40 })
local CLIP = { [22] = 17, [23] = 17, [24] = 7, [25] = 1, [26] = 4, [27] = 7, [28] = 50, [29] = 30, [30] = 30, [31] = 50, [32] = 50, [33] = 1, [34] = 1 }

function getSlotFromWeapon(id) return SLOT[id] end
function getWeaponProperty(id, _, prop) if prop == "maximum_clip_ammo" then return CLIP[id] or false end end
function getPedWeapon(p, slot)
    if slot == nil then slot = p.slot end
    local w = p.weapons[slot]
    return w and w.id or 0
end
function takeWeapon(p, id) local s = SLOT[id] if p.weapons[s] and p.weapons[s].id == id then p.weapons[s] = nil end return true end
function giveWeapon(p, id, ammo, current)
    local s = SLOT[id]
    local w = p.weapons[s]
    if w and w.id == id then w.ammo = w.ammo + ammo else p.weapons[s] = { id = id, ammo = ammo, clip = math.min(ammo, CLIP[id] or ammo) } end
    if current then p.slot = s end
    return true
end
function setPedWeaponSlot(p, slot) p.slot = slot return true end
function setWeaponAmmo(p, id, total, clip)
    local w = p.weapons[SLOT[id]]
    if w and w.id == id then w.ammo, w.clip = total, clip end
    return true
end
local reloads = 0
function reloadPedWeapon() reloads = reloads + 1 return true end
function isPedDead(p) return p.dead end
function isPedInVehicle(p) return p.inVehicle == true end

-- v_inventory stub
local handsBusy = {}
local inventoryRunning = true
function getResourceFromName(name) if name == "v_inventory" then return "invres" end end
function getResourceState(res) return (res == "invres" and inventoryRunning) and "running" or "loaded" end
exports = { v_inventory = { isPlayerHandsFree = function(_, p) return not handsBusy[p] end } }

-- ---------------------------------------------------------------------------------------------
-- Load the resource
-- ---------------------------------------------------------------------------------------------

local function load(path)
    local f = assert(io.open(TEST_BASE .. path, "r"))
    local src = f:read("*a")
    f:close()
    assert(loadstring(src, "@" .. path))()
end

local p = newElement("player")
players[1] = p
p.weapons[11] = { id = 46, ammo = 1, clip = 1 } -- parachute: not managed

load("shared/weapons.lua")
load("server/core.lua")
load("server/inventory.lua")
triggerEvent("onResourceStart", resourceRoot)

local function fire(name, player, ...)
    client = player
    triggerEvent(name, resourceRoot, ...)
    client = nil
end

-- ---------------------------------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------------------------------

check(getPlayerWeapons(p) == false, "not loaded -> false (acc_savesys keeps its copy)")
p.weapons[5] = { id = 30, ammo = 90, clip = 30 } -- a stray GTA weapon from another script
check(setPlayerWeapons(p, { { id = 31, ammo = 200, clip = 50 }, { 29, 120 }, { id = 16, ammo = 2 }, { id = 4, ammo = 0 }, { id = 17, ammo = 0 }, { id = 99, ammo = 5 } }), "setPlayerWeapons")
check(isPlayerWeaponsLoaded(p), "loaded")
local list = getPlayerWeapons(p)
check(#list == 4, "unknown id and 0 thrown dropped (" .. #list .. ")")
check(list[1].id == 4 and list[1].ammo == 1, "melee ammo forced to 1, sorted by WP.LIST")
check(p.weapons[5] == nil, "stray weapon taken")
check(p.weapons[11] and p.weapons[11].id == 46, "parachute (slot 11) untouched")
check(p.slot == 0, "unarmed")
local st = lastClient("wp:state")
check(st and #st.args[1] == 4 and st.args[2] == 0, "state sent to the client")

-- equip
fire("wp:equip", p, 31)
check(getPlayerCurrentWeapon(p) == 31, "equipped 31")
check(p.weapons[5] and p.weapons[5].id == 31 and p.weapons[5].ammo == 200 and p.weapons[5].clip == 50, "ped holds M4 200/50")
check(p.slot == 5, "weapon slot active")
fire("wp:equip", p, 38)
check(getPlayerCurrentWeapon(p) == 31, "not owned weapon refused")

-- ammo reports
fire("wp:ammo", p, 31, 150, 0)
check(getPlayerWeaponAmmo(p, 31) == 150, "ammo went down")
fire("wp:ammo", p, 31, 500, 50)
check(getPlayerWeaponAmmo(p, 31) == 150, "ammo cannot go up from the client")
fire("wp:ammo", p, 29, 1, 1)
check(getPlayerWeaponAmmo(p, 29) == 120, "report of a weapon not equipped ignored")

-- reload
reloads = 0
fire("wp:reload", p)
check(reloads == 1, "reload of a gun")

-- out of ammo -> empty but still held
fire("wp:ammo", p, 31, 0, 0)
check(getPlayerWeaponAmmo(p, 31) == 0, "0 ammo stored")
check(getPlayerCurrentWeapon(p) == 31, "empty weapon still equipped")
check(p.weapons[5] and p.weapons[5].id == 31 and p.weapons[5].ammo == 1, "held with 1 fake bullet")
st = lastClient("wp:state")
check(st.args[3] == true, "client told: empty")
reloads = 0
fire("wp:reload", p)
check(reloads == 0, "no reload with an empty weapon")
fire("wp:ammo", p, 31, 0, 0)
check(getPlayerWeaponAmmo(p, 31) == 0, "report while empty ignored")
setPlayerWeaponAmmo(p, 31, 60)
check(p.weapons[5].ammo == 60 and lastClient("wp:state").args[3] == false, "refill: real ammo back, not empty")

-- switch
fire("wp:equip", p, 29)
check(p.weapons[5] == nil and p.weapons[4] and p.weapons[4].id == 29, "switch takes the old weapon, gives the new")

-- thrown weapon removed at 0
fire("wp:equip", p, 16)
check(p.weapons[8] and p.weapons[8].id == 16 and p.weapons[8].ammo == 2, "grenades held")
fire("wp:ammo", p, 16, 0, 0)
check(getPlayerCurrentWeapon(p) == 0 and not getPlayerWeaponAmmo(p, 16), "last grenade: removed and unarmed")
check(p.weapons[8] == nil, "grenade slot empty")

-- hands rule: item in hand -> no weapon
handsBusy[p] = true
local before = #clientEvents
fire("wp:equip", p, 31)
check(getPlayerCurrentWeapon(p) == 0, "hands full: refused")
check(lastClient("wp:notify") and #clientEvents > before, "hands full: notified")
handsBusy[p] = nil

-- hands rule: weapon drawn -> no item into a hand
fire("wp:equip", p, 31)
local ok = triggerEvent("onInventoryItemMove", resourceRoot, 1, "box", { type = "ground" }, { type = "slot", player = p, slot = "right" }, p, 1)
check(not ok and cancelReason == "text:wp_manager.msg.holster_first", "item move into a hand cancelled")
ok = triggerEvent("onInventoryItemMove", resourceRoot, 1, "bag", { type = "ground" }, { type = "slot", player = p, slot = "back" }, p, 1)
check(ok, "back slot allowed")

-- forced item into a hand -> weapon put away
triggerEvent("onElementDataChange", p, "inv.slots", nil, { left = { d = "box" } })
check(getPlayerCurrentWeapon(p) == 0 and p.weapons[5] == nil, "forced item: holstered")

-- cancelable equip event
addEventHandler("onPlayerWeaponEquip", root, function(id) if id == 24 then cancelEvent() end end)
givePlayerWeapon(p, 24, 21)
fire("wp:equip", p, 24)
check(getPlayerCurrentWeapon(p) == 0, "onPlayerWeaponEquip cancel")

-- give adds ammo
givePlayerWeapon(p, 29, 30)
check(getPlayerWeaponAmmo(p, 29) == 150, "give adds to the owned weapon")

-- temporary loadout
setPlayerTempLoadout(p, { { id = 34, ammo = 10 } }, 34)
check(getPlayerCurrentWeapon(p) == 34 and p.weapons[6].id == 34, "temp loadout equipped")
check(hasPlayerTempLoadout(p), "temp active")
fire("wp:equip", p, 31)
check(getPlayerCurrentWeapon(p) == 34, "base weapon hidden during temp")
fire("wp:ammo", p, 34, 3, 1)
local found
for _, w in ipairs(getPlayerWeapons(p)) do if w.id == 34 then found = true end end
check(not found, "temp weapon not in the persistent list")
check(getPlayerWeaponAmmo(p, 34) == 3, "ammo goes to the temp set")
clearPlayerTempLoadout(p)
check(getPlayerCurrentWeapon(p) == 0 and not hasPlayerTempLoadout(p), "temp cleared, unarmed")
check(p.weapons[6] == nil and getPlayerWeaponAmmo(p, 31) == 60, "base back")

-- death and spawn
fire("wp:equip", p, 31)
p.dead = true
triggerEvent("onPlayerWasted", p)
check(getPlayerCurrentWeapon(p) == 0, "death holsters")
p.dead, p.weapons = false, {}
triggerEvent("onPlayerSpawn", p)
runTimers()
check(#getPlayerWeapons(p) == 4 and lastClient("wp:state").args[2] == 0, "after spawn: still owned")

-- restart keeps the state
fire("wp:equip", p, 31)
triggerEvent("onResourceStop", resourceRoot)
check(type(p.data["wp.backup"]) == "table", "state parked in element data")
Players = nil
handlers = {}
load("server/core.lua")
load("server/inventory.lua")
triggerEvent("onResourceStart", resourceRoot)
check(p.data["wp.backup"] == nil, "backup consumed")
check(isPlayerWeaponsLoaded(p) and #getPlayerWeapons(p) == 4 and getPlayerCurrentWeapon(p) == 31, "state restored after restart")

-- quit: kept until acc_savesys saved, then dropped
triggerEvent("onPlayerQuit", p)
check(getPlayerWeapons(p) ~= false, "still readable in the quit handlers")
runTimers()
check(getPlayerWeapons(p) == false, "dropped after quit")

print(("wp_manager tests: %d passed, %d failed"):format(passed, failures))
return failures
