-- Marker UI, server side: the registry of the 3D marker cards that server resources register.
-- The definitions (static fields) reach every client once; the meta (dynamic, per player
-- fields such as work level / XP) reaches a client only while it is within the card's radius
-- (the client streams the card in / out, see client/markers.lua).
--
-- Exports (the id is per calling resource, two resources may use the same id):
--   createMarkerUI(id, def) -> true | false       (re-creating an id replaces it)
--   updateMarkerUI(id, fields) -> bool            (merges static fields, false clears one)
--   setMarkerUIMeta(id, meta [, player]) -> bool  (replaces the global / per-player meta layer)
--   removeMarkerUI(id) -> bool
--   getMarkerUIPlayers(id) -> { player, ... }     (players within the radius right now)
-- Events, triggered on the owner's resourceRoot:
--   onMarkerUIStreamIn (id, player) / onMarkerUIStreamOut (id, player)
--   onMarkerUISystemStart ()       (on root, after ui_core started: register again)

local Entries = {}      -- key -> { owner, id, def, meta, pmeta = { player -> meta }, subs = { player -> true } }
local Ready = {}        -- player -> true once the client asked for the list
local pending = {}      -- ops waiting for the next flush: { op, key, data }
local flushTimer

addEvent("onMarkerUIStreamIn")
addEvent("onMarkerUIStreamOut")
addEvent("onMarkerUISystemStart")

local function caller()
    return sourceResource and getResourceName(sourceResource) or getResourceName(resource)
end

local function keyOf(owner, id) return owner .. "/" .. tostring(id) end

local function ownerRoot(owner)
    local res = getResourceFromName(owner)
    return res and getResourceState(res) == "running" and getResourceRootElement(res) or nil
end

local function readyList()
    local list = {}
    for p in pairs(Ready) do
        if isElement(p) then list[#list + 1] = p else Ready[p] = nil end
    end
    return list
end

-- Creations / updates / removals of the same server frame go out in one event.
local function flush()
    flushTimer = nil
    if #pending == 0 then return end
    local ops = pending
    pending = {}
    local players = readyList()
    if #players > 0 then
        triggerLatentClientEvent(players, "ui_core:mk:ops", 50000, false, resourceRoot, ops)
    end
end

local function queue(op, key, data)
    pending[#pending + 1] = { op, key, data }
    if not flushTimer then flushTimer = setTimer(flush, 50, 1) end
end

-- the meta a player sees: the global layer, the player's own layer on top
local function metaFor(e, player)
    local p = e.pmeta[player]
    if not p then return e.meta end
    if not e.meta then return p end
    local m = {}
    for k, v in pairs(e.meta) do m[k] = v end
    for k, v in pairs(p) do m[k] = v end
    return m
end

local function sendMeta(e, key, player)
    triggerClientEvent(player, "ui_core:mk:meta", resourceRoot, key, metaFor(e, player) or false)
end

local function unsubscribe(e, key, player)
    if not e.subs[player] then return end
    e.subs[player] = nil
    local r = ownerRoot(e.owner)
    if r then triggerEvent("onMarkerUIStreamOut", r, e.id, player) end
end

local function remove(key)
    local e = Entries[key]
    if not e then return false end
    Entries[key] = nil
    for p in pairs(e.subs) do unsubscribe(e, key, p) end
    queue("del", key)
    return true
end

---------------------------------------------------------------- exports

function createMarkerUI(id, def)
    if id == nil or type(def) ~= "table" then
        outputDebugString(("[ui_core] createMarkerUI (%s): id and a def table expected"):format(caller()), 2)
        return false
    end
    if def.element ~= nil and not isElement(def.element) then
        outputDebugString(("[ui_core] createMarkerUI (%s, %s): element does not exist"):format(caller(), tostring(id)), 2)
        return false
    end
    if not def.element and not (tonumber(def.x) and tonumber(def.y) and tonumber(def.z)) then
        outputDebugString(("[ui_core] createMarkerUI (%s, %s): element or x, y, z expected"):format(caller(), tostring(id)), 2)
        return false
    end
    local owner = caller()
    local key = keyOf(owner, id)
    if Entries[key] then remove(key) end
    local copy = {}
    for k, v in pairs(def) do copy[k] = v end
    Entries[key] = { owner = owner, id = id, def = copy, pmeta = {}, subs = {} }
    queue("set", key, copy)

    if copy.element then
        addEventHandler("onElementDestroy", copy.element, function()
            local e = Entries[key]
            if e and e.def.element == source then remove(key) end
        end, false)
    end
    return true
end

function updateMarkerUI(id, fields)
    local key = keyOf(caller(), id)
    local e = Entries[key]
    if not e or type(fields) ~= "table" then return false end
    local diff = {}
    for k, v in pairs(fields) do
        if v == false and k ~= "hidden" and k ~= "los" then v = nil end
        e.def[k] = v
        diff[k] = v == nil and false or v
    end
    queue("upd", key, diff)
    return true
end

function setMarkerUIMeta(id, meta, player)
    local key = keyOf(caller(), id)
    local e = Entries[key]
    if not e then return false end
    if type(meta) ~= "table" then meta = nil end
    if player ~= nil then
        if not isElement(player) then return false end
        e.pmeta[player] = meta
        if e.subs[player] then sendMeta(e, key, player) end
    else
        e.meta = meta
        for p in pairs(e.subs) do sendMeta(e, key, p) end
    end
    return true
end

function removeMarkerUI(id)
    return remove(keyOf(caller(), id))
end

function getMarkerUIPlayers(id)
    local e = Entries[keyOf(caller(), id)]
    local list = {}
    if e then
        for p in pairs(e.subs) do
            if isElement(p) then list[#list + 1] = p end
        end
    end
    return list
end

---------------------------------------------------------------- client requests

addEvent("ui_core:mk:ready", true)
addEventHandler("ui_core:mk:ready", resourceRoot, function()
    local player = client
    Ready[player] = true
    -- a restarted client streams everything in again
    for key, e in pairs(Entries) do unsubscribe(e, key, player) end
    local list = {}
    for key, e in pairs(Entries) do list[#list + 1] = { "set", key, e.def } end
    if #list > 0 then
        triggerLatentClientEvent(player, "ui_core:mk:ops", 50000, false, resourceRoot, list)
    end
end)

-- inKeys / outKeys: the cards that came within / left their radius since the last report
addEvent("ui_core:mk:stream", true)
addEventHandler("ui_core:mk:stream", resourceRoot, function(inKeys, outKeys)
    local player = client
    if type(outKeys) == "table" then
        for _, key in ipairs(outKeys) do
            local e = Entries[key]
            if e then unsubscribe(e, key, player) end
        end
    end
    if type(inKeys) == "table" then
        for _, key in ipairs(inKeys) do
            local e = Entries[key]
            if e and not e.subs[player] then
                e.subs[player] = true
                if metaFor(e, player) then sendMeta(e, key, player) end
                local r = ownerRoot(e.owner)
                if r then triggerEvent("onMarkerUIStreamIn", r, e.id, player) end
            end
        end
    end
end)

addEventHandler("onPlayerQuit", root, function()
    Ready[source] = nil
    for _, e in pairs(Entries) do
        e.subs[source] = nil
        e.pmeta[source] = nil
    end
end)

addEventHandler("onResourceStop", root, function(res)
    if res == resource then return end
    local name = getResourceName(res)
    for key, e in pairs(Entries) do
        if e.owner == name then remove(key) end
    end
end)

addEventHandler("onResourceStart", resourceRoot, function()
    triggerEvent("onMarkerUISystemStart", root)
end)
