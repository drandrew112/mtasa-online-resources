if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Client side of the weapon handling: mirrors the server state, keeps GTA's own weapon switching
-- off, blocks firing with an "empty" weapon (0 ammo, held with 1 fake bullet), reports the ammo of
-- the equipped weapon and handles the manual reload (R).

local RELOAD_KEY = "r"
local AMMO_POLL_MS = 250
local SWITCH_CONTROLS = { "next_weapon", "previous_weapon" }
local HANDS_KEY = "inv.slots" -- v_inventory locks "fire" itself while a hand is full

local weapons = {}     -- { {id=, ammo=, clip=}, ... } the active set
local byId = {}
local current, empty, temp = 0, false, false
local fireOff = false  -- the fire control was switched off by us
local reported = {}    -- id -> "ammo:clip" last sent

addEvent("wp:state", true)
addEvent("wp:notify", true)
addEvent("onClientWeaponsChanged") -- source: localPlayer; the selector refreshes on it

local function handsBusy()
    local slots = getElementData(localPlayer, HANDS_KEY)
    return type(slots) == "table" and (slots.left or slots.right) and true or false
end

local function updateFire()
    local want = current ~= 0 and empty
    if want and not fireOff then
        toggleControl("fire", false)
        fireOff = true
    elseif not want and fireOff then
        fireOff = false
        if not handsBusy() then toggleControl("fire", true) end
    end
end

-- Live ammo of the equipped weapon -> ammo, clip (nil when GTA does not hold it)
local function liveAmmo(id)
    local slot = getSlotFromWeapon(id)
    if not slot or getPedWeapon(localPlayer, slot) ~= id then return nil end
    return getPedTotalAmmo(localPlayer, slot), getPedAmmoInClip(localPlayer, slot)
end

-- Sends the ammo of the equipped weapon when it changed
local function reportAmmo()
    if current == 0 or empty or isPedDead(localPlayer) then return end
    local def = WP.WEAPONS[current]
    if not def or def.kind == "melee" then return end
    local ammo, clip = liveAmmo(current)
    if not ammo then
        -- GTA dropped the weapon (the last bullet / grenade is gone): report 0. A drop done by the
        -- server itself (switch, holster) is ignored there, its current weapon is another one.
        ammo, clip = 0, 0
    end
    local key = ammo .. ":" .. clip
    if reported[current] == key then return end
    reported[current] = key
    triggerServerEvent("wp:ammo", resourceRoot, current, ammo, clip)
end
setTimer(reportAmmo, AMMO_POLL_MS, 0)

addEventHandler("wp:state", resourceRoot, function(list, cur, isEmpty, isTemp)
    weapons, byId = list or {}, {}
    for _, w in ipairs(weapons) do byId[w.id] = w end
    current, empty, temp = tonumber(cur) or 0, isEmpty == true, isTemp == true
    reported = {}
    updateFire()
    triggerEvent("onClientWeaponsChanged", localPlayer)
end)

addEventHandler("wp:notify", resourceRoot, function(text)
    local res = getResourceFromName("ui_core")
    if res and getResourceState(res) == "running" then
        exports.ui_core:addNotification(L("wp_manager.ui.title"), L.resolve(text), false)
    end
end)

-- GTA's own weapon switching stays off (other resources, e.g. v_inventory, switch it back on)
addEventHandler("onClientRender", root, function()
    for _, control in ipairs(SWITCH_CONTROLS) do
        if isControlEnabled(control) then toggleControl(control, false) end
    end
    if fireOff and isControlEnabled("fire") then toggleControl("fire", false) end
end)

bindKey(RELOAD_KEY, "down", function()
    if current == 0 or empty or isPedDead(localPlayer) or isPedInVehicle(localPlayer) then return end
    local def = WP.WEAPONS[current]
    if not def or def.kind ~= "gun" then return end
    local ammo, clip = liveAmmo(current)
    local max = WP.maxClip(current)
    if not ammo or not max or clip >= max or ammo <= clip then return end
    triggerServerEvent("wp:reload", resourceRoot)
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("wp:requestState", resourceRoot)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for _, control in ipairs(SWITCH_CONTROLS) do toggleControl(control, true) end
    if fireOff and not handsBusy() then toggleControl("fire", true) end
end)

--------------------------------------------------------------------------------
-- Client exports (wp_selector)
--------------------------------------------------------------------------------

-- { {id=, ammo=, clip=}, ... } of the active set; the equipped one with live ammo
function getWeapons()
    local out = {}
    for i, w in ipairs(weapons) do
        local ammo, clip = w.ammo, w.clip
        if w.id == current and not empty then
            local a, c = liveAmmo(w.id)
            if a then ammo, clip = a, c end
        end
        out[i] = { id = w.id, ammo = ammo, clip = clip }
    end
    return out
end

function getCurrentWeapon()
    return current
end

function isCurrentWeaponEmpty()
    return current ~= 0 and empty
end

function hasTempLoadout()
    return temp
end

-- Asks the server to equip a weapon (0 = unarmed). The ammo of the old one goes first.
function equipWeapon(id)
    id = tonumber(id) or 0
    if id ~= 0 and not byId[id] then return false end
    if id == current then return true end
    reportAmmo()
    triggerServerEvent("wp:equip", resourceRoot, id)
    return true
end

function getWeaponDefs()
    return WP.CATEGORIES, WP.LIST
end
