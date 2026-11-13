-- v_collectibles server: active lists, per-player collected state (MySQL collectibles_found), sync, pickup.
--
-- A list is ACTIVE when enabled and (not an event list, or switched on by events_core).
-- Every player only gets the items he has not collected yet. The data goes to the client once
-- v_loading has finished (element data "loaded") AND the client script is running (clientReady),
-- and again whenever the set of active lists or a list's content changes.

if not MYSQL then loadstring(exports.v_mysql:importAsync())() end -- v_mysql async lib (PERF-01)

local TABLE = "collectibles_found"

local eventOn = {}      -- [listId] = true: switched on by events_core (setEventListEnabled)
local found = {}        -- [player] = { [listId] = { [itemId] = true } } (nil = not loaded yet)
local clientReady = {}  -- [player] = true
local loading = {}      -- [player] = true while the DB query runs
local foundFor = {}     -- [player] = account name the found[player] state belongs to

local function log(text) outputServerLog("[v_collectibles] " .. text) end

local function accName(player)
    local n = getElementData(player, "accName")
    return type(n) == "string" and n ~= "" and n or nil
end

function isListActive(id)
    local list = Lists[id]
    if not list or not list.enabled then return false end
    if list.event and not eventOn[id] then return false end
    return true
end

local function foundCount(player, list)
    local f = found[player] and found[player][list.id]
    if not f then return 0 end
    local n = 0
    for itemId in pairs(f) do
        if list.byId[itemId] then n = n + 1 end    -- items deleted in the editor do not count
    end
    return n
end

---------------------------------------------------------------------------- sync

local function isReady(player)
    return isElement(player) and clientReady[player] and found[player] ~= nil and getElementData(player, "loaded") == true
end

--- sends the active lists (uncollected items only) to one player
function syncPlayer(player)
    if not isReady(player) then return end
    local out = {}
    local mine = found[player]
    for _, id in ipairs(ListOrder) do
        local list = Lists[id]
        if isListActive(id) then
            local f = mine[id] or {}
            local items = {}
            for _, it in ipairs(list.items) do
                if not f[it.id] then items[#items + 1] = it end
            end
            out[#out + 1] = {
                id = id, name = list.name, event = list.event, spin = list.spin,
                total = #list.items, found = foundCount(player, list), items = items,
            }
        end
    end
    triggerLatentClientEvent(player, "v_collectibles:sync", 500000, false, resourceRoot, out)
end

function syncAll()
    for _, p in ipairs(getElementsByType("player")) do syncPlayer(p) end
end

---------------------------------------------------------------------------- collected state (DB)

-- v_mysql may still be connecting right after a server start: retried a few times
local function ensureTable(cb, try)
    try = try or 1
    MYSQL.query(function(ok, err)
        if ok == false then
            log(("could not create table %s (try %d): %s"):format(TABLE, try, tostring(err)))
            if try < 6 then return setTimer(function() ensureTable(cb, try + 1) end, 10000, 1) end
        end
        if cb then cb() end
    end, [[CREATE TABLE IF NOT EXISTS `collectibles_found` (
        `account`  VARCHAR(64) NOT NULL,
        `list_id`  VARCHAR(32) NOT NULL,
        `item_id`  INT UNSIGNED NOT NULL,
        `found_at` INT UNSIGNED NOT NULL,
        PRIMARY KEY (`account`, `list_id`, `item_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
end

local function loadPlayer(player)
    local name = accName(player)
    if not name or loading[player] then return end
    loading[player] = true
    MYSQL.query(function(rows)
        if not isElement(player) then return end
        loading[player] = nil
        if accName(player) ~= name then return end     -- logged into another account meanwhile
        local mine = {}
        if type(rows) == "table" then
            for _, r in ipairs(rows) do
                local l, i = tostring(r.list_id), tonumber(r.item_id)
                if i then
                    mine[l] = mine[l] or {}
                    mine[l][i] = true
                end
            end
        else
            log("could not load the collected items of " .. name)
        end
        found[player] = mine
        foundFor[player] = name
        syncPlayer(player)
    end, "SELECT `list_id`, `item_id` FROM `" .. TABLE .. "` WHERE `account` = ?", name)
end

addEvent("onPlayerLoaded")
addEventHandler("onPlayerLoaded", root, function()
    -- may fire twice (v_mapcam); another account = fresh state
    if found[source] and foundFor[source] == accName(source) then return syncPlayer(source) end
    found[source] = nil
    loadPlayer(source)
end)

addEvent("v_collectibles:clientReady", true)
addEventHandler("v_collectibles:clientReady", resourceRoot, function()
    clientReady[client] = true
    if found[client] and foundFor[client] == accName(client) then syncPlayer(client) else loadPlayer(client) end
end)

addEventHandler("onPlayerQuit", root, function()
    found[source], clientReady[source], loading[source], foundFor[source] = nil, nil, nil, nil
end)

---------------------------------------------------------------------------- pickup

addEvent("onPlayerCollectibleFound")            -- (listId, itemId, count, total), source = player
addEvent("onPlayerCollectibleListCompleted")    -- (listId, total), source = player

addEvent("v_collectibles:collect", true)
addEventHandler("v_collectibles:collect", resourceRoot, function(listId, itemId)
    local player = client
    local list = Lists[listId]
    itemId = tonumber(itemId)
    local item = list and itemId and list.byId[itemId]
    local mine = found[player]
    local name = accName(player)
    local function reject()
        triggerClientEvent(player, "v_collectibles:rejected", resourceRoot, listId, itemId)
    end
    if not item or not mine or not name or not isListActive(listId) or isPedDead(player) then return reject() end
    if mine[listId] and mine[listId][itemId] then return end   -- double send
    if getElementDimension(player) ~= item.dim or getElementInterior(player) ~= item.int then return reject() end
    local x, y, z = getElementPosition(player)
    if getDistanceBetweenPoints3D(x, y, z, item.x, item.y, item.z) > COLLECT.SERVER_RANGE then return reject() end

    mine[listId] = mine[listId] or {}
    mine[listId][itemId] = true
    MYSQL.query(function(ok, err)
        if ok == false then log(("could not save %s #%d of %s: %s"):format(listId, itemId, name, tostring(err))) end
    end, "INSERT IGNORE INTO `" .. TABLE .. "` (`account`, `list_id`, `item_id`, `found_at`) VALUES (?, ?, ?, ?)",
        name, listId, itemId, getRealTime().timestamp)

    local count, total = foundCount(player, list), #list.items
    local reward = list.reward or 0
    if reward > 0 then
        givePlayerMoney(player, reward)
        pcall(function() exports.ui_core:showMoney(player, "add", reward, "cash") end)
    end
    triggerClientEvent(player, "v_collectibles:collected", resourceRoot, listId, itemId, count, total, reward)
    triggerEvent("onPlayerCollectibleFound", player, listId, itemId, count, total)
    if count >= total then triggerEvent("onPlayerCollectibleListCompleted", player, listId, total) end
end)

---------------------------------------------------------------------------- events_core

--- events_core pushes the lists of its events: setEventListEnabled(listId, on) -> bool
--- false = no such list or not an event list ("event": true missing); the state is kept anyway,
--- so a list created later in the editor follows the event at once.
function setEventListEnabled(listId, on)
    if type(listId) ~= "string" then return false end
    on = on == true or nil
    local changed = eventOn[listId] ~= on
    eventOn[listId] = on
    local list = Lists[listId]
    if changed and pushEditors then pushEditors() end
    if changed and list and list.event then
        log(("event list %s %s"):format(listId, on and "ON" or "OFF"))
        syncAll()
    end
    return list ~= nil and list.event == true
end

function isEventListEnabled(listId) return eventOn[tostring(listId)] == true end

---------------------------------------------------------------------------- queries (exports)

--- getLists() -> { { id, name, event, enabled, active, total, models, reward }, ... }
function getLists()
    local out = {}
    for _, id in ipairs(ListOrder) do
        local l = Lists[id]
        out[#out + 1] = { id = id, name = l.name, event = l.event, enabled = l.enabled,
            active = isListActive(id), total = #l.items, models = l.models, reward = l.reward }
    end
    return out
end

--- getPlayerProgress(player, listId) -> count, total | false
function getPlayerProgress(player, listId)
    local list = Lists[listId]
    if not list or not isElement(player) or not found[player] then return false end
    return foundCount(player, list), #list.items
end

---------------------------------------------------------------------------- start

addEvent("onCollectiblesStart")     -- root: events_core pushes the event lists again

addEventHandler("onResourceStart", resourceRoot, function()
    loadAllLists()
    ensureTable(function()
        -- restart with players online: the client scripts report clientReady themselves,
        -- the ones already loaded get their state here
        for _, p in ipairs(getElementsByType("player")) do
            if getElementData(p, "loaded") == true then loadPlayer(p) end
        end
    end)
    triggerEvent("onCollectiblesStart", root)
end)

-- the menu data is local client element data; nothing to clean up on stop
