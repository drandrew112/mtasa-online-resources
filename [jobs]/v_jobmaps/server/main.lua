-- v_jobmaps (server): reads the maps of maps/index.json once and loads / unloads them for the players
-- other resources ask for (exports below). The files are downloaded by everybody (meta.xml) but the
-- models are only put into the game, and the objects only created, for the players a map is loaded for.
--
-- Object record sent to the clients (array): { model, x, y, z, rx, ry, rz, interior, scale, alpha,
--   collisions, doublesided, frozen }   model = custom model name (string) or GTA model id (number)
-- Removal record: { model, lodModel, radius, x, y, z, interior }

local LOG_PREFIX = "[v_jobmaps] "
local maps = {}        -- name -> { name, title, models, txds, objects, removes, center, size }
local order = {}       -- names in index order
local loaded = {}      -- player -> { [name] = { opts = {...}, ready = bool } }

local function log(msg) outputServerLog(LOG_PREFIX .. msg) end

addEvent("onJobMapReady")       -- source = player, (name)
addEvent("onJobMapFailed")      -- source = player, (name, reason)
addEvent("onJobMapUnloaded")    -- source = player, (name)
addEvent(EV_READY, true)
addEvent(EV_FAILED, true)
addEvent(EV_REQUEST, true)

---------------------------------------------------------------------------- reading files

local function readText(path)
    if not fileExists(path) then return nil end
    local f = fileOpen(path, true)
    if not f then return nil end
    local text = fileRead(f, fileGetSize(f))
    fileClose(f)
    return text
end

local function num(v, default) return tonumber(v) or default end

local function flag(v)
    if v == nil then return -1 end
    return (v == "true" or v == "1") and 1 or 0
end

-- -> map table, or nil + error
local function parseMap(name)
    local base = JOBMAPS.MAPS_DIR .. "/" .. name .. "/"
    local meta = fromJSON(readText(base .. "map.json") or "")
    if type(meta) ~= "table" then return nil, base .. "map.json is missing or not valid JSON" end
    local models = type(meta.models) == "table" and meta.models or {}
    local txds = type(meta.txds) == "table" and meta.txds or {}

    local root = xmlLoadFile(base .. name .. ".map", true)
    if not root then return nil, base .. name .. ".map is missing or not valid XML" end

    local m = { name = name, title = tostring(meta.title or name), models = {}, txds = {}, objects = {}, removes = {} }
    local x1, y1, z1, x2, y2, z2 = math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge
    local usedModels, problems = {}, {}

    for _, node in ipairs(xmlNodeGetChildren(root)) do
        local tag = xmlNodeGetName(node)
        local a = xmlNodeGetAttributes(node)
        if tag == "object" then
            local x, y, z = num(a.posX), num(a.posY), num(a.posZ)
            local model = tonumber(a.model) or tostring(a.model)
            if x and y and z and a.model then
                if type(model) == "string" then
                    if models[model] then
                        usedModels[model] = true
                    else
                        problems[#problems + 1] = "unknown model " .. model
                        model = nil
                    end
                end
                if model then
                    m.objects[#m.objects + 1] = {
                        model, x, y, z, num(a.rotX, 0), num(a.rotY, 0), num(a.rotZ, 0),
                        num(a.interior, 0), num(a.scale, 1), num(a.alpha, 255),
                        flag(a.collisions), flag(a.doublesided), flag(a.frozen),
                    }
                    x1, y1, z1 = math.min(x1, x), math.min(y1, y), math.min(z1, z)
                    x2, y2, z2 = math.max(x2, x), math.max(y2, y), math.max(z2, z)
                end
            end
        elseif tag == "removeWorldObject" then
            local model = tonumber(a.model)
            if model then
                m.removes[#m.removes + 1] = { model, num(a.lodModel, 0), num(a.radius, 1),
                    num(a.posX, 0), num(a.posY, 0), num(a.posZ, 0), num(a.interior, -1) }
            end
        end
    end
    xmlUnloadFile(root)

    -- only the models / texture archives the objects use go to the clients
    for mn in pairs(usedModels) do
        local d = models[mn]
        if type(d) == "table" and d.dff and d.col and txds[d.txd] then
            m.models[mn] = { dff = d.dff, col = d.col, txd = d.txd, distance = num(d.distance, 299),
                             doublesided = d.doublesided ~= false, alpha = d.alpha == true }
            m.txds[d.txd] = txds[d.txd]
        else
            problems[#problems + 1] = "model " .. mn .. " is incomplete in map.json"
        end
    end
    for _, p in ipairs(problems) do log(name .. ": " .. p) end

    if x1 <= x2 then
        m.center = { (x1 + x2) / 2, (y1 + y2) / 2, (z1 + z2) / 2 }
        m.size = { x2 - x1, y2 - y1, z2 - z1 }
    else
        m.center, m.size = { 0, 0, 0 }, { 0, 0, 0 }
    end
    return m
end

local function readAll()
    local index = fromJSON(readText(JOBMAPS.INDEX_FILE) or "")
    if type(index) ~= "table" or type(index.maps) ~= "table" then
        log(JOBMAPS.INDEX_FILE .. " missing - run: python -I tools/build.py meta")
        return
    end
    for _, name in ipairs(index.maps) do
        local m, err = parseMap(name)
        if m then
            maps[name] = m
            order[#order + 1] = name
            local models = 0
            for _ in pairs(m.models) do models = models + 1 end
            log(("%s: %d objects, %d custom models, %d removals"):format(name, #m.objects, models, #m.removes))
        else
            log(name .. ": " .. err)
        end
    end
end

---------------------------------------------------------------------------- helpers

-- player or table of players -> array of valid players
local function playerList(players)
    local out = {}
    if isElement(players) then
        if getElementType(players) == "player" then out[1] = players end
    elseif type(players) == "table" then
        for _, p in pairs(players) do
            if isElement(p) and getElementType(p) == "player" then out[#out + 1] = p end
        end
    end
    return out
end

local function cleanOptions(o)
    o = type(o) == "table" and o or {}
    local off = type(o.offset) == "table" and o.offset or {}
    return {
        dimension = math.floor(num(o.dimension, 0)),
        interior = math.floor(num(o.interior, 0)),
        offset = { num(off[1] or off.x, 0), num(off[2] or off.y, 0), num(off[3] or off.z, 0) },
    }
end

local function payloadFor(m, opts)
    return { name = m.name, title = m.title, models = m.models, txds = m.txds, objects = m.objects,
             removes = m.removes, opts = opts }
end

---------------------------------------------------------------------------- exports

-- loadJobMap(name, players [, { dimension, interior, offset = { x, y, z } }]) -> true | false, error
-- players = a player or a table of players; asking again for a loaded map only re-applies the options
function loadJobMap(name, players, options)
    local m = maps[name]
    if not m then return false, "unknown map " .. tostring(name) end
    local list = playerList(players)
    if #list == 0 then return false, "no valid player" end
    local opts = cleanOptions(options)
    local payload = payloadFor(m, opts)
    for _, p in ipairs(list) do
        loaded[p] = loaded[p] or {}
        local rec = loaded[p][name]
        loaded[p][name] = { opts = opts, ready = rec and rec.ready or false }
    end
    triggerClientEvent(list, EV_LOAD, resourceRoot, payload)
    return true
end

-- unloadJobMap(name, players) -> true when at least one player had it loaded
function unloadJobMap(name, players)
    local any = false
    for _, p in ipairs(playerList(players)) do
        if loaded[p] and loaded[p][name] then
            loaded[p][name] = nil
            any = true
            triggerClientEvent(p, EV_UNLOAD, resourceRoot, name)
            triggerEvent("onJobMapUnloaded", p, name)
        end
    end
    return any
end

-- unloadAllJobMaps(players) -> number of unloaded maps
function unloadAllJobMaps(players)
    local count = 0
    for _, p in ipairs(playerList(players)) do
        local names = {}
        for name in pairs(loaded[p] or {}) do names[#names + 1] = name end
        for _, name in ipairs(names) do
            if unloadJobMap(name, p) then count = count + 1 end
        end
    end
    return count
end

-- getJobMaps() -> { name = { title, center = {x,y,z}, size = {x,y,z}, models, objects } }
function getJobMaps()
    local out = {}
    for _, name in ipairs(order) do
        local m = maps[name]
        local models = 0
        for _ in pairs(m.models) do models = models + 1 end
        out[name] = { title = m.title, center = { unpack(m.center) }, size = { unpack(m.size) },
                      models = models, objects = #m.objects }
    end
    return out
end

function getJobMapInfo(name)
    local all = getJobMaps()
    return all[name] or false
end

-- loaded = the server sent it, ready = the client built the models and objects
function isJobMapLoaded(name, player)
    return loaded[player] ~= nil and loaded[player][name] ~= nil
end

function isJobMapReady(name, player)
    local rec = loaded[player] and loaded[player][name]
    return rec ~= nil and rec.ready == true
end

function getPlayerJobMaps(player)
    local out = {}
    for name in pairs(loaded[player] or {}) do out[#out + 1] = name end
    table.sort(out)
    return out
end

function getJobMapLoadedPlayers(name)
    local out = {}
    for p, byName in pairs(loaded) do
        if byName[name] then out[#out + 1] = p end
    end
    return out
end

---------------------------------------------------------------------------- client replies

addEventHandler(EV_READY, resourceRoot, function(name)
    local rec = client and loaded[client] and loaded[client][tostring(name)]
    if not rec then return end
    rec.ready = true
    triggerEvent("onJobMapReady", client, tostring(name))
end)

addEventHandler(EV_FAILED, resourceRoot, function(name, reason)
    if not client then return end
    name = tostring(name)
    log(("%s failed for %s: %s"):format(name, getPlayerName(client), tostring(reason)))
    if loaded[client] and loaded[client][name] then
        loaded[client][name] = nil
        triggerEvent("onJobMapFailed", client, name, tostring(reason))
    end
end)

-- a client resource restart: send the maps this player should have again
addEventHandler(EV_REQUEST, resourceRoot, function()
    if not client or not loaded[client] then return end
    for name, rec in pairs(loaded[client]) do
        rec.ready = false
        triggerClientEvent(client, EV_LOAD, resourceRoot, payloadFor(maps[name], rec.opts))
    end
end)

---------------------------------------------------------------------------- test command

-- /jobmap                  list the maps and which are on for you
-- /jobmap <name> [tp]      toggle a map for yourself (tp: teleport above its centre once it is built)
-- /jobmap off              unload everything for yourself
-- admin level JOBMAPS.ADMIN_LEVEL, answers in the console (F8)
local function say(player, text) outputConsole("[jobmap] " .. text, player) end

addCommandHandler("jobmap", function(player, _, name, opt)
    if getElementData(player, "isLogged") ~= true then return end
    local ok, level = pcall(function() return exports.v_mysql:getAccData(player, "admin_level") end)
    if not ok or (tonumber(level) or 0) < JOBMAPS.ADMIN_LEVEL then return say(player, "Access denied.") end

    if not name or name == "" then
        for _, n in ipairs(order) do
            local m = maps[n]
            say(player, ("%s (%s): %d objects - %s"):format(n, m.title, #m.objects,
                isJobMapReady(n, player) and "ON" or (isJobMapLoaded(n, player) and "loading" or "off")))
        end
        return say(player, "usage: /jobmap <name> [tp]  |  /jobmap off")
    end
    name = name:lower()
    if name == "off" then
        return say(player, unloadAllJobMaps(player) .. " map(s) unloaded")
    end
    local m = maps[name]
    if not m then return say(player, "unknown map " .. name) end
    if isJobMapLoaded(name, player) then
        unloadJobMap(name, player)
        return say(player, name .. " unloaded")
    end
    local okLoad, err = loadJobMap(name, player, { dimension = getElementDimension(player), interior = 0 })
    if not okLoad then return say(player, tostring(err)) end
    say(player, name .. " loading...")
    if opt == "tp" then
        local handler
        handler = function(readyName)
            if readyName ~= name or source ~= player then return end
            removeEventHandler("onJobMapReady", root, handler)
            setElementPosition(player, m.center[1], m.center[2], m.center[3] + 30)
            say(player, name .. " ready, teleported to the centre")
        end
        addEventHandler("onJobMapReady", root, handler)
    else
        local handler
        handler = function(readyName)
            if readyName ~= name or source ~= player then return end
            removeEventHandler("onJobMapReady", root, handler)
            say(player, name .. " ready")
        end
        addEventHandler("onJobMapReady", root, handler)
    end
end)

addEventHandler("onPlayerQuit", root, function()
    loaded[source] = nil
end)

addEventHandler("onResourceStart", resourceRoot, readAll)
