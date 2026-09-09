-- Account System - save / load of the player's persistent state
--
-- All of it lives in the `accounts` table now, reached through
-- exports.v_mysql:getAccData / setAccData. save_all() batches the whole
-- snapshot into ONE write; the loaders read individually (v_mysql caches the
-- row, so the repeated getAccData calls cost one round trip).
--
-- Health is stored but only re-applied when > 0. Weapon skill stats are always
-- maxed on spawn regardless of what was saved.

local function getData(player, key)
    return exports.v_mysql:getAccData(player, key)
end

-- Ped stats we persist. stat1..stat3 (ids 21/23/24) are the ones loaded back.
local SAVED_STAT_IDS = { 21, 23, 24, 77, 71, 78, 76, 69, 73, 72, 70, 79, 74, 75 }

--------------------------------------------------------------------------------
-- Load
--------------------------------------------------------------------------------

function loadHealth(player)
    local health = tonumber(getData(player, "health"))
    if health and health > 0 then
        setElementHealth(player, health)
    end
end

function loadArmor(player)
    local armor = tonumber(getData(player, "armor"))
    if armor then
        setPedArmor(player, armor)
    end
end

function loadMoney(player)
    local money = tonumber(getData(player, "money-BETA"))
    if money then
        setPlayerMoney(player, money)
    end
end

function loadSkin(player)
    local skin = tonumber(getData(player, "skin"))
    if skin then
        setElementModel(player, skin)
    end
end

function loadPosition(player)
    local skin = tonumber(getData(player, "skin")) or 295
    local int  = tonumber(getData(player, "interior")) or 0
    local dim  = tonumber(getData(player, "dimension")) or 0
    local x = tonumber(getData(player, "x"))
    local y = tonumber(getData(player, "y"))
    local z = tonumber(getData(player, "z"))

    if x and y and z then
        spawnPlayer(player, x, y, z + 1, 0, skin, int, dim)
    else
        spawnPlayer(player, 1685.6845703125, -2330.2578125, -1.6796875, 0, skin, int, dim)
    end

    setElementInterior(player, int)
    setElementDimension(player, dim)
    setCameraTarget(player, player)
    fadeCamera(player, true)
end

function loadStats(player)
    local stat1 = getData(player, "stat1")
    local stat2 = getData(player, "stat2")
    local stat3 = getData(player, "stat3")
    if stat1 and stat2 and stat3 then
        setPedStat(player, 21, stat1)
        setPedStat(player, 23, stat2)
        setPedStat(player, 24, stat3)
    end
end

function loadWeapons(player)
    local weapons, ammo = {}, {}
    for slot = 0, 12 do
        weapons[slot] = getData(player, "weapon" .. slot)
        ammo[slot]    = getData(player, "ammo" .. slot)
        if weapons[slot] == nil or ammo[slot] == nil then return end
    end
    for slot = 0, 12 do
        giveWeapon(player, weapons[slot], ammo[slot])
    end
end

--------------------------------------------------------------------------------
-- Weapon skill stats - always maxed on spawn
--------------------------------------------------------------------------------

local WEAPON_STAT_IDS = { 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79 }
local MAX_WEAPON_STAT = 1000

function maxWeaponStats(player)
    for _, statID in ipairs(WEAPON_STAT_IDS) do
        setPedStat(player, statID, MAX_WEAPON_STAT)
    end
end

addEventHandler("onPlayerSpawn", root, function()
    maxWeaponStats(source)
end)

--------------------------------------------------------------------------------
-- Save - one batched write
--------------------------------------------------------------------------------

function save_all(player)
    if not isElement(player) or getElementData(player, "isLogged") ~= true then return end

    local d = {}
    d.health        = getElementHealth(player)
    d.armor         = getPedArmor(player)
    d["money-BETA"] = getPlayerMoney(player)
    d.skin          = getElementModel(player)

    local x, y, z = getElementPosition(player)
    d.x, d.y, d.z  = x, y, z
    d.interior     = getElementInterior(player)
    d.dimension    = getElementDimension(player)

    for i, statId in ipairs(SAVED_STAT_IDS) do
        d["stat" .. i] = getPedStat(player, statId)
    end

    for slot = 0, 12 do
        d["weapon" .. slot] = getPedWeapon(player, slot)
        d["ammo" .. slot]   = getPedTotalAmmo(player, slot)
    end

    exports.v_mysql:setAccData(player, d)
end
