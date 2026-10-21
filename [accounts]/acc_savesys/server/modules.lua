-- Save modules. Each module owns some accData keys and may have:
--   profile(player, out)      read-only, before the spawn (account menu)
--   apply(player, ctx)        at the spawn (ctx.mode = "normal" | "fresh")
--   save(player, d)           fills the batched snapshot table `d`
-- Everything lives in the `accounts` table through exports.v_mysql:getAccData /
-- setAccData; the loaders read individually (v_mysql caches the row), the save
-- is ONE setAccData(player, d) write (main.lua).

MODULES = {}

function getData(player, key)
    return exports.v_mysql:getAccData(player, key)
end

local function resourceRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

--------------------------------------------------------------------------------
-- position (+ skin, the spawn itself)
--------------------------------------------------------------------------------

-- the saved place, or nil
local function savedPosition(player)
    local x, y, z = tonumber(getData(player, "x")), tonumber(getData(player, "y")), tonumber(getData(player, "z"))
    if not (x and y and z) then return nil end
    return { x = x, y = y, z = z,
             interior = tonumber(getData(player, "interior")) or 0,
             dimension = tonumber(getData(player, "dimension")) or 0 }
end

MODULES[#MODULES + 1] = {
    id = "position",
    profile = function(player, out)
        local p = savedPosition(player)
        if p then p.zone = getZoneName(p.x, p.y, p.z, false) end
        out.position = p or false
        out.skin = tonumber(getData(player, "skin")) or SAVE.DEFAULT_SKIN
    end,
    apply = function(player, ctx)
        local skin = tonumber(getData(player, "skin")) or SAVE.DEFAULT_SKIN
        local d = SAVE.DEFAULT_SPAWN
        local x, y, z, rot, int, dim = d.x, d.y, d.z, d.rot, 0, 0

        if ctx.mode ~= "fresh" then
            local saved = savedPosition(player)
            local random = getPreference(player, "spawnLocation") == "random"
            local rx, ry, rz, rrot
            if random and resourceRunning("v_spawnmanager") then
                rx, ry, rz, rrot = exports.v_spawnmanager:getRandomFreeRespawnPoint()
            end
            if rx then
                x, y, z, rot = rx, ry, rz, rrot or 0
            elseif saved then
                x, y, z, int, dim = saved.x, saved.y, saved.z + 1, saved.interior, saved.dimension
            end
        end

        spawnPlayer(player, x, y, z, rot, skin, int, dim)
        setElementInterior(player, int)
        setElementDimension(player, dim)
        setCameraTarget(player, player)
        fadeCamera(player, true)
        ctx.x, ctx.y, ctx.z, ctx.rot = x, y, z, rot
    end,
    save = function(player, d)
        -- on duty (work_core): save the civilian skin, not the work outfit
        d.skin = tonumber(getElementData(player, "work.civilSkin")) or getElementModel(player)

        -- a script may keep the player somewhere temporary (e.g. the work_ems tutorial in its own
        -- dimension): server-only data "save.position" = { x, y, z, interior, dimension } is saved instead
        local saved = getElementData(player, "save.position")
        if type(saved) == "table" and tonumber(saved[1]) and tonumber(saved[2]) and tonumber(saved[3]) then
            d.x, d.y, d.z = tonumber(saved[1]), tonumber(saved[2]), tonumber(saved[3])
            d.interior    = tonumber(saved[4]) or 0
            d.dimension   = tonumber(saved[5]) or 0
        else
            local x, y, z = getElementPosition(player)
            d.x, d.y, d.z = x, y, z
            d.interior    = getElementInterior(player)
            d.dimension   = getElementDimension(player)
        end
    end,
}

--------------------------------------------------------------------------------
-- health / armor
--------------------------------------------------------------------------------

MODULES[#MODULES + 1] = {
    id = "vitals",
    apply = function(player, ctx)
        if ctx.mode == "fresh" then return end
        local health = tonumber(getData(player, "health"))
        if health and health > 0 then setElementHealth(player, health) end
        local armor = tonumber(getData(player, "armor"))
        if armor then setPedArmor(player, armor) end
    end,
    save = function(player, d)
        d.health = getElementHealth(player)
        d.armor  = getPedArmor(player)
    end,
}

--------------------------------------------------------------------------------
-- money
--------------------------------------------------------------------------------

MODULES[#MODULES + 1] = {
    id = "money",
    profile = function(player, out)
        out.money = tonumber(getData(player, "money-BETA")) or 0
        -- bank_money is owned by v_bank (saved on every change), read for the menu only
        out.bank = math.floor(tonumber(getData(player, "bank_money")) or 0)
    end,
    apply = function(player)
        local money = tonumber(getData(player, "money-BETA"))
        if money then setPlayerMoney(player, money) end
    end,
    save = function(player, d)
        d["money-BETA"] = getPlayerMoney(player)
    end,
}

--------------------------------------------------------------------------------
-- level / played time (owned by v_levelsys / v_playedtime, read for the menu only)
--------------------------------------------------------------------------------

MODULES[#MODULES + 1] = {
    id = "progress",
    profile = function(player, out)
        out.level = tonumber(getData(player, "level")) or 1
        out.xp = tonumber(getData(player, "xp")) or 0
        local nextXp = resourceRunning("v_levelsys") and tonumber(exports.v_levelsys:getNextXp(out.level)) or nil
        out.nextXp = nextXp or false
        local hours = tonumber(getData(player, "Online.hours")) or 0
        local minutes = tonumber(getData(player, "Online.minutes")) or 0
        out.playtime = ("%02dh %02dm"):format(hours, minutes)
        out.playMinutes = hours * 60 + minutes
    end,
}

--------------------------------------------------------------------------------
-- ped stats: stat1..stat3 (ids 21/23/24) are loaded back; weapon skills are maxed
--------------------------------------------------------------------------------

local SAVED_STAT_IDS = { 21, 23, 24, 77, 71, 78, 76, 69, 73, 72, 70, 79, 74, 75 }

MODULES[#MODULES + 1] = {
    id = "pedstats",
    apply = function(player, ctx)
        if ctx.mode == "fresh" then return end
        local stat1, stat2, stat3 = getData(player, "stat1"), getData(player, "stat2"), getData(player, "stat3")
        if stat1 and stat2 and stat3 then
            setPedStat(player, 21, stat1)
            setPedStat(player, 23, stat2)
            setPedStat(player, 24, stat3)
        end
    end,
    save = function(player, d)
        for i, statId in ipairs(SAVED_STAT_IDS) do
            d["stat" .. i] = getPedStat(player, statId)
        end
    end,
}

--------------------------------------------------------------------------------
-- weapons: [weapon]/wp_manager. "weapons" = JSON { {id=, ammo=, clip=}, ... };
-- accounts saved before it still have the old weaponN / ammoN keys, read once as a fallback.
--------------------------------------------------------------------------------

function weaponManagerRunning()
    return resourceRunning("wp_manager")
end

function loadWeapons(player)
    if not weaponManagerRunning() then return end
    local list = fromJSON(tostring(getData(player, "weapons") or ""))
    if type(list) ~= "table" then
        list = {}
        for slot = 0, 12 do
            local weapon, ammo = tonumber(getData(player, "weapon" .. slot)), tonumber(getData(player, "ammo" .. slot))
            if weapon and weapon > 0 and ammo and ammo > 0 then list[#list + 1] = { id = weapon, ammo = ammo } end
        end
    end
    exports.wp_manager:setPlayerWeapons(player, list)
end

MODULES[#MODULES + 1] = {
    id = "weapons",
    apply = function(player, ctx)
        if ctx.mode == "fresh" then return end
        loadWeapons(player)
    end,
    save = function(player, d)
        -- false = wp_manager has not loaded this player's weapons: keep the stored copy
        if weaponManagerRunning() then
            local weapons = exports.wp_manager:getPlayerWeapons(player)
            if type(weapons) == "table" then d.weapons = toJSON(weapons, true) end
        end
    end,
}

--------------------------------------------------------------------------------
-- collectibles: accData "collectibles" = JSON { [id] = count }, mirrored to element data
--------------------------------------------------------------------------------

COLLECTED = {}   -- [player] = { [id] = count }

function loadCollectibles(player)
    local t = fromJSON(tostring(getData(player, "collectibles") or ""))
    local counts = {}
    for _, def in ipairs(COLLECTIBLES) do
        local n = type(t) == "table" and tonumber(t[def.id]) or nil
        counts[def.id] = n and math.max(0, math.floor(n)) or 0
        setElementData(player, def.data, counts[def.id])
    end
    COLLECTED[player] = counts
    return counts
end

MODULES[#MODULES + 1] = {
    id = "collectibles",
    profile = function(player, out)
        out.collectibles = COLLECTED[player] or loadCollectibles(player)
    end,
    save = function(player, d)
        local counts = COLLECTED[player]
        if counts then d.collectibles = toJSON(counts, true) end
    end,
}

--------------------------------------------------------------------------------
-- preferences: accData "pref.<id>", element data "pref.<id>" (written by the server only)
--------------------------------------------------------------------------------

function loadPreferences(player)
    local out = {}
    for id, def in pairs(PREFERENCES) do
        local v = getData(player, "pref." .. id)
        if not def.values[v] then v = def.default end
        out[id] = v
        setElementData(player, "pref." .. id, v)
    end
    return out
end

MODULES[#MODULES + 1] = {
    id = "preferences",
    profile = function(player, out)
        local prefs = {}
        for id in pairs(PREFERENCES) do prefs[id] = getPreference(player, id) end
        out.preferences = prefs
    end,
}
