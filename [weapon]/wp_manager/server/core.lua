if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- The server is the only authority over the weapons. A player owns a set of weapons
-- ({ [id] = { ammo = total, clip = in the magazine | nil } }), and the ped only ever holds the
-- equipped one (GTA slots 0..10; 11 and 12 are left alone). A weapon with 0 ammo is still owned:
-- it is handed to GTA with 1 bullet and the client switches the fire control off ("empty").
--
-- Two sets per player: `base` is the persistent one (v_accounts saves it through
-- getPlayerWeapons), `temp` is a temporary loadout of a minigame (Jobs, the job creator) that
-- hides `base` until it is cleared. Every ammo change goes to the active set.
--
-- Lent weapons (duty weapons of a work, lendPlayerWeapon): they sit in `base` like the others, but
-- `lent[id]` names the resource they belong to. They are never part of getPlayerWeapons (so never
-- saved); an own weapon of the same id is parked in `own[id]` while the lent one is held, and comes
-- back when it is returned. The owner resource stopping returns its weapons.

addEvent("wp:equip", true)
addEvent("wp:ammo", true)
addEvent("wp:reload", true)
addEvent("wp:requestState", true)
addEvent("onPlayerWeaponEquip")        -- source: player; (newId, oldId) cancelable, 0 = unarmed
addEvent("onPlayerWeaponAmmoChange")   -- source: player; (id, ammo, clip)

Players = {}  -- player -> { base = {}, temp = nil | {}, current = id | nil, empty = bool, loaded = bool,
              --             lent = { [id] = owner resource name }, own = { [id] = parked own entry } }

local BACKUP_KEY = "wp.backup"

local function state(player)
    local s = Players[player]
    if not s then
        s = { base = {}, current = nil, empty = false, loaded = false, lent = {}, own = {} }
        Players[player] = s
    end
    return s
end

local function activeSet(s) return s.temp or s.base end

local function isPlayer(player)
    return isElement(player) and getElementType(player) == "player"
end

function notify(player, key)
    if isPlayer(player) then triggerClientEvent(player, "wp:notify", resourceRoot, L.msg(key)) end
end

-- A clean set entry, or nil for an unknown weapon
local function newEntry(id, ammo, clip)
    local def = WP.WEAPONS[id]
    if not def then return nil end
    if def.kind == "melee" then return { ammo = 1 } end
    ammo = math.max(0, math.min(math.floor(tonumber(ammo) or 0), WP.MAX_AMMO))
    clip = tonumber(clip)
    clip = clip and math.max(0, math.min(math.floor(clip), ammo)) or nil
    return { ammo = ammo, clip = clip }
end

-- Accepts { {id=, ammo=, clip=}, ... }, { {id, ammo, clip}, ... } or { [id] = ammo }
local function buildSet(list)
    local set = {}
    if type(list) ~= "table" then return set end
    for k, v in pairs(list) do
        local id, ammo, clip
        if type(v) == "table" then
            id, ammo, clip = tonumber(v.id or v[1]), v.ammo or v[2], v.clip or v[3]
        else
            id, ammo = tonumber(k), v
        end
        local entry = id and newEntry(id, ammo, clip)
        if entry and not (WP.WEAPONS[id].kind == "thrown" and entry.ammo <= 0) then set[id] = entry end
    end
    return set
end

-- lent: the lent table of the player -> the lent entries get `lent = true`
local function setToList(set, lent)
    local list = {}
    for id, e in pairs(set) do
        list[#list + 1] = { id = id, ammo = e.ammo, clip = e.clip, lent = (lent and lent[id]) and true or nil }
    end
    table.sort(list, function(a, b) return WP.WEAPONS[a.id].order < WP.WEAPONS[b.id].order end)
    return list
end

local function sendState(player)
    local s = Players[player]
    if not s or not isPlayer(player) then return end
    triggerClientEvent(player, "wp:state", resourceRoot, setToList(activeSet(s), not s.temp and s.lent), s.current or 0, s.empty, s.temp ~= nil)
end

-- Makes the ped hold exactly what the state says, then tells the client
function apply(player)
    local s = Players[player]
    if not s or not isPlayer(player) then return end
    local set = activeSet(s)
    if s.current and (not set[s.current] or not handsFree(player)) then s.current = nil end
    local cur = s.current
    local entry = cur and set[cur]
    local def = cur and WP.WEAPONS[cur]
    s.empty = (entry and def.kind ~= "melee" and entry.ammo <= 0) and true or false

    if not isPedDead(player) then
        for slot = 0, WP.MANAGED_SLOTS do
            local w = getPedWeapon(player, slot)
            if w and w > 0 and w ~= cur then takeWeapon(player, w) end
        end
        if cur then
            local slot = getSlotFromWeapon(cur)
            local give = (def.kind == "melee" or s.empty) and 1 or entry.ammo
            if getPedWeapon(player, slot) ~= cur then
                giveWeapon(player, cur, give, true)
            else
                setPedWeaponSlot(player, slot)
            end
            if def.kind ~= "melee" then
                local clip = s.empty and 1 or entry.clip or math.min(give, WP.maxClip(cur) or give)
                setWeaponAmmo(player, cur, give, clip)
            end
        else
            setPedWeaponSlot(player, 0)
        end
    end
    sendState(player)
end

-- Equips a weapon of the active set (0 = unarmed) -> true | false, reason key
function equip(player, id, byPlayer)
    local s = Players[player]
    if not s then return false, "wp_manager.msg.not_loaded" end
    id = tonumber(id) or 0
    local old = s.current or 0
    if id == old then return true end
    if id ~= 0 then
        if not activeSet(s)[id] then return false, "wp_manager.msg.not_owned" end
        if isPedDead(player) then return false, "wp_manager.msg.dead" end
        if not handsFree(player) then
            if byPlayer then notify(player, "wp_manager.msg.hands_full") end
            return false, "wp_manager.msg.hands_full"
        end
    end
    triggerEvent("onPlayerWeaponEquip", player, id, old)
    if wasEventCancelled() then
        sendState(player) -- the selector may already show the new one
        return false, "wp_manager.msg.cannot_now"
    end
    s.current = id ~= 0 and id or nil
    apply(player)
    return true
end

local function ammoChanged(player, id, e)
    triggerEvent("onPlayerWeaponAmmoChange", player, id, e and e.ammo or 0, e and e.clip or 0)
end

--------------------------------------------------------------------------------
-- Client requests
--------------------------------------------------------------------------------

addEventHandler("wp:requestState", resourceRoot, function()
    if Players[client] then sendState(client) end
end)

addEventHandler("wp:equip", resourceRoot, function(id)
    equip(client, id, true)
end)

-- The client reports the ammo of the equipped weapon. It may only go down.
addEventHandler("wp:ammo", resourceRoot, function(id, ammo, clip)
    local player = client
    local s = Players[player]
    id, ammo, clip = tonumber(id), tonumber(ammo), tonumber(clip)
    if not s or not id or not ammo or s.current ~= id or s.empty then return end
    local set = activeSet(s)
    local e, def = set[id], WP.WEAPONS[id]
    if not e or def.kind == "melee" then return end
    ammo = math.max(0, math.min(math.floor(ammo), e.ammo))
    if clip then e.clip = math.max(0, math.min(math.floor(clip), ammo)) end
    local changed = ammo ~= e.ammo
    e.ammo = ammo
    if ammo == 0 then
        if def.kind == "thrown" then
            set[id], s.current = nil, nil
        end
        apply(player)
    end
    if changed then ammoChanged(player, id, set[id]) end
end)

addEventHandler("wp:reload", resourceRoot, function()
    local player = client
    local s = Players[player]
    local cur = s and s.current
    if not cur or s.empty or WP.WEAPONS[cur].kind ~= "gun" then return end
    if isPedDead(player) or isPedInVehicle(player) then return end
    reloadPedWeapon(player)
end)

--------------------------------------------------------------------------------
-- Spawn, death, quit, restart
--------------------------------------------------------------------------------

addEventHandler("onPlayerSpawn", root, function()
    local player = source
    if not Players[player] then return end
    setTimer(function() if isElement(player) then apply(player) end end, 100, 1)
end)

addEventHandler("onPlayerWasted", root, function()
    local s = Players[source]
    if s and s.current then
        s.current = nil
        sendState(source)
    end
end)

-- v_accounts saves on quit: keep the state a moment longer so its handler can still read it
addEventHandler("onPlayerQuit", root, function()
    local player = source
    setTimer(function() Players[player] = nil end, 2000, 1)
end)

-- A restart keeps the weapons: the state is parked in server-only element data
addEventHandler("onResourceStop", resourceRoot, function()
    for player, s in pairs(Players) do
        if isPlayer(player) and s.loaded then
            local lent, own = {}, {}
            for id, owner in pairs(s.lent) do lent[tostring(id)] = owner end
            for id, e in pairs(s.own) do own[#own + 1] = { id = id, ammo = e.ammo, clip = e.clip } end
            setElementData(player, BACKUP_KEY, { base = setToList(s.base), temp = s.temp and setToList(s.temp), current = s.current,
                                                 lent = lent, own = own }, false)
        end
    end
end)

-- Runs at load time (before any onResourceStart handler), so v_accounts sees the restored players
-- as loaded and does not read the older DB copy over them.
for _, player in ipairs(getElementsByType("player")) do
    local b = getElementData(player, BACKUP_KEY)
    if type(b) == "table" then
        removeElementData(player, BACKUP_KEY)
        local s = state(player)
        s.base = buildSet(b.base)
        s.temp = b.temp and buildSet(b.temp) or nil
        s.current = tonumber(b.current)
        s.own = buildSet(b.own)
        for id, owner in pairs(type(b.lent) == "table" and b.lent or {}) do
            id = tonumber(id)
            if id and s.base[id] then s.lent[id] = owner end
        end
        s.loaded = true
    end
end

addEventHandler("onResourceStart", resourceRoot, function()
    for player in pairs(Players) do
        if isPlayer(player) then apply(player) end
    end
end)

--------------------------------------------------------------------------------
-- Exports
--------------------------------------------------------------------------------

-- The own set: the lent weapons left out, the parked own ones in their place
local function ownSet(s)
    if not next(s.lent) then return s.base end
    local set = {}
    for id, e in pairs(s.base) do
        if not s.lent[id] then set[id] = e end
    end
    for id, e in pairs(s.own) do set[id] = e end
    return set
end

-- The persistent weapons: { {id=, ammo=, clip=}, ... }, or false before setPlayerWeapons
-- (nothing loaded yet: a caller that saves must not overwrite the stored copy then).
-- Lent weapons are left out, unless includeLent (then the held set, lent ones with `lent = true`).
function getPlayerWeapons(player, includeLent)
    local s = Players[player]
    if not s or not s.loaded then return false end
    if includeLent then return setToList(s.base, s.lent) end
    return setToList(ownSet(s))
end

function isPlayerWeaponsLoaded(player)
    local s = Players[player]
    return s ~= nil and s.loaded
end

-- Replaces the persistent weapons (the equipped one stays if it is still owned)
function setPlayerWeapons(player, list)
    if not isPlayer(player) then return false end
    local s = state(player)
    local set = buildSet(list)
    s.own = {}
    for id in pairs(s.lent) do   -- the lent ones stay held, an own copy is parked
        s.own[id] = set[id]
        set[id] = s.base[id]
    end
    s.base, s.loaded = set, true
    if not s.temp then apply(player) end
    return true
end

function givePlayerWeapon(player, id, ammo, equipIt)
    id = tonumber(id)
    if not isPlayer(player) or not id or not WP.WEAPONS[id] then return false end
    local s = state(player)
    s.loaded = true
    if s.lent[id] then   -- a lent one is held: the parked own copy gets it
        local own = s.own[id]
        if own then
            if WP.WEAPONS[id].kind ~= "melee" then own.ammo = math.min(own.ammo + math.max(0, math.floor(tonumber(ammo) or 0)), WP.MAX_AMMO) end
        else
            own = newEntry(id, ammo)
            if WP.WEAPONS[id].kind == "thrown" and own.ammo <= 0 then return false end
            s.own[id] = own
        end
        return true
    end
    local e = s.base[id]
    if e then
        if WP.WEAPONS[id].kind ~= "melee" then e.ammo = math.min(e.ammo + math.max(0, math.floor(tonumber(ammo) or 0)), WP.MAX_AMMO) end
    else
        e = newEntry(id, ammo)
        if WP.WEAPONS[id].kind == "thrown" and e.ammo <= 0 then return false end
        s.base[id] = e
    end
    if not s.temp then
        if equipIt then equip(player, id) else apply(player) end
    end
    ammoChanged(player, id, e)
    return true
end

-- Takes an own weapon (a lent one of the same id stays: returnLentWeapon takes that back)
function takePlayerWeapon(player, id)
    local s = Players[player]
    id = tonumber(id)
    if not s or not id then return false end
    if s.lent[id] then
        if not s.own[id] then return false end
        s.own[id] = nil
        return true
    end
    if not s.base[id] then return false end
    s.base[id] = nil
    if not s.temp then apply(player) end
    return true
end

function clearPlayerWeapons(player)
    if not isPlayer(player) then return false end
    local s = state(player)
    local set = {}
    for id in pairs(s.lent) do set[id] = s.base[id] end   -- the lent ones are not the player's to lose
    s.base, s.own, s.loaded = set, {}, true
    if not s.temp then apply(player) end
    return true
end

-- Ammo of a weapon in the active set -> ammo, clip | false
function getPlayerWeaponAmmo(player, id)
    local s = Players[player]
    local e = s and activeSet(s)[tonumber(id)]
    if not e then return false end
    return e.ammo, e.clip or math.min(e.ammo, WP.maxClip(tonumber(id)) or e.ammo)
end

function setPlayerWeaponAmmo(player, id, ammo, clip)
    local s = Players[player]
    id = tonumber(id)
    local set = s and activeSet(s)
    if not set or not id or not set[id] then return false end
    if WP.WEAPONS[id].kind == "melee" then return true end
    local e = newEntry(id, ammo, clip)
    if WP.WEAPONS[id].kind == "thrown" and e.ammo <= 0 then
        set[id] = nil
    else
        set[id] = e
    end
    if s.current == id or not set[id] then apply(player) end
    ammoChanged(player, id, set[id])
    return true
end

function getPlayerCurrentWeapon(player)
    local s = Players[player]
    return s and s.current or 0
end

-- Script equip (no notification): -> true | false, reason key
function setPlayerCurrentWeapon(player, id)
    if not isPlayer(player) then return false end
    return equip(player, id, false)
end

-- A temporary loadout (Jobs, the job creator): hides the persistent weapons until cleared.
-- list as in setPlayerWeapons, equipId = the weapon to hold (optional).
function setPlayerTempLoadout(player, list, equipId)
    if not isPlayer(player) then return false end
    local s = state(player)
    s.temp = buildSet(list)
    s.current = nil
    apply(player)
    if equipId then equip(player, equipId) end
    return true
end

function clearPlayerTempLoadout(player)
    local s = Players[player]
    if not s or not s.temp then return false end
    s.temp, s.current = nil, nil
    apply(player)
    return true
end

function hasPlayerTempLoadout(player)
    local s = Players[player]
    return s ~= nil and s.temp ~= nil
end

function getWeaponCategory(id)
    local def = WP.WEAPONS[tonumber(id)]
    return def and def.cat or false
end

--------------------------------------------------------------------------------
-- Lent weapons (duty weapons of a work: work_police duty_weapons)
--------------------------------------------------------------------------------

local function callerName()
    return sourceResource and getResourceName(sourceResource) or getResourceName(resource)
end

-- Lends a weapon (not the player's own: never saved, taken back by returnLentWeapon(s)).
-- The owner is the calling resource. Lending an id that is already lent refills it.
function lendPlayerWeapon(player, id, ammo, equipIt)
    id = tonumber(id)
    if not isPlayer(player) or not id or not WP.WEAPONS[id] then return false end
    local s = state(player)
    local e = newEntry(id, ammo)
    if WP.WEAPONS[id].kind == "thrown" and e.ammo <= 0 then return false end
    if not s.lent[id] then s.own[id] = s.base[id] end
    s.base[id], s.lent[id] = e, callerName()
    if not s.temp then
        if equipIt then equip(player, id) else apply(player) end
    end
    ammoChanged(player, id, e)
    return true
end

local function giveBack(s, id)
    s.base[id], s.own[id], s.lent[id] = s.own[id], nil, nil
end

-- Takes one lent weapon back (the parked own one of the same id returns)
function returnLentWeapon(player, id)
    local s = Players[player]
    id = tonumber(id)
    if not s or not id or not s.lent[id] then return false end
    giveBack(s, id)
    if not s.temp then apply(player) end
    return true
end

-- Takes back every weapon lent by the calling resource (owner "*" = every lent weapon) -> count
function returnLentWeapons(player, owner)
    local s = Players[player]
    if not s then return 0 end
    owner = owner or callerName()
    local n = 0
    for id, o in pairs(s.lent) do
        if owner == "*" or o == owner then
            giveBack(s, id)
            n = n + 1
        end
    end
    if n > 0 and not s.temp then apply(player) end
    return n
end

function isPlayerWeaponLent(player, id)
    local s = Players[player]
    return s ~= nil and s.lent[tonumber(id)] ~= nil
end

-- { {id=, ammo=, clip=, owner=}, ... } the lent weapons the player holds
function getPlayerLentWeapons(player)
    local s = Players[player]
    local out = {}
    if not s then return out end
    for id, owner in pairs(s.lent) do
        local e = s.base[id]
        if e then out[#out + 1] = { id = id, ammo = e.ammo, clip = e.clip, owner = owner } end
    end
    return out
end

-- The owner of lent weapons stopped: they go back
addEventHandler("onResourceStop", root, function(res)
    if not res or res == resource then return end
    local name = getResourceName(res)
    for player, s in pairs(Players) do
        local n = 0
        for id, o in pairs(s.lent) do
            if o == name then giveBack(s, id); n = n + 1 end
        end
        if n > 0 and not s.temp and isPlayer(player) then apply(player) end
    end
end)
