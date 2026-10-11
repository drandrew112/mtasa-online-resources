-- ============================================================
--  world_interiors / server/registry.lua
--  Interior registry. Other resources register interiors via exports:
--
--    exports.world_interiors:registerInterior("clothes_ls", {
--        name      = "Binco",
--        dimension = 101,                                          -- fixed inside dimension (required)
--        enter = { x=, y=, z=, interior=0, dimension=0, rot=0 },   -- outside marker
--        exit  = { x=, y=, z=, interior=15,            rot=0 },    -- inside marker
--        enterColor / exitColor = {r,g,b,a}  (optional)
--    })
--
--  The player is teleported onto the opposite marker; the marker must
--  be left before it triggers again.
--  Interiors are removed when the registering resource stops. This
--  resource fires "world_interiors:ready" (root) when it starts, so
--  registering resources should register on their own onResourceStart
--  AND on that event, so a restart of world_interiors loses nothing.
-- ============================================================

local interiors = {}   -- id -> record
local locked    = {}   -- player -> marker they are standing on / just arrived on

addEvent("world_interiors:ready", false)

local function num(v, d) return tonumber(v) or d end

local function cleanPoint(p, isExit)
    if type(p) ~= "table" then return false end
    local x, y, z = tonumber(p.x or p[1]), tonumber(p.y or p[2]), tonumber(p.z or p[3])
    if not (x and y and z) then return false end
    return {
        x = x, y = y, z = z,
        rot = num(p.rot or p[4], 0),
        interior  = math.floor(num(p.interior, 0)),
        dimension = (not isExit) and math.floor(num(p.dimension, 0)) or nil,
    }
end

local function destroyRecord(rec)
    if isElement(rec.enterMarker) then destroyElement(rec.enterMarker) end
    if isElement(rec.exitMarker) then destroyElement(rec.exitMarker) end
end

local function makeMarker(p, dim, color, id, kind)
    local m = createMarker(p.x, p.y, p.z - 1, INT.markerType, INT.markerSize, color[1], color[2], color[3], color[4])
    setElementInterior(m, p.interior)
    setElementDimension(m, dim)
    setElementData(m, "interior:id", id, false)
    setElementData(m, "interior:kind", kind, false)
    return m
end

function registerInterior(id, data)
    if type(id) ~= "string" or id == "" or type(data) ~= "table" then return false end
    local enter, exit = cleanPoint(data.enter, false), cleanPoint(data.exit, true)
    local dim = tonumber(data.dimension)
    if not enter or not exit or not dim then
        outputDebugString("[world_interiors] registerInterior('" .. id .. "'): enter/exit/dimension missing or invalid", 1)
        return false
    end
    dim = math.floor(dim)
    if dim < 0 or dim > 65535 then return false end

    if interiors[id] then destroyRecord(interiors[id]) end
    for oid, o in pairs(interiors) do
        if oid ~= id and o.dimension == dim and o.exit.interior == exit.interior
            and getDistanceBetweenPoints3D(o.exit.x, o.exit.y, o.exit.z, exit.x, exit.y, exit.z) < 1 then
            outputDebugString("[world_interiors] '" .. id .. "' shares dimension " .. dim .. " with '" .. oid .. "' at the same exit", 2)
        end
    end

    local rec = {
        id = id, name = tostring(data.name or id), dimension = dim,
        enter = enter, exit = exit,
        resource = sourceResource and getResourceName(sourceResource) or "?",
        resElement = sourceResource,
    }
    rec.enterMarker = makeMarker(enter, enter.dimension, data.enterColor or INT.enterColor, id, "enter")
    rec.exitMarker  = makeMarker(exit, dim, data.exitColor or INT.exitColor, id, "exit")
    interiors[id] = rec
    return true
end

function unregisterInterior(id)
    local rec = interiors[id]
    if not rec then return false end
    destroyRecord(rec)
    interiors[id] = nil
    return true
end

local function publicCopy(rec)
    return {
        id = rec.id, name = rec.name, dimension = rec.dimension, resource = rec.resource,
        enter = { x = rec.enter.x, y = rec.enter.y, z = rec.enter.z, rot = rec.enter.rot, interior = rec.enter.interior, dimension = rec.enter.dimension },
        exit  = { x = rec.exit.x, y = rec.exit.y, z = rec.exit.z, rot = rec.exit.rot, interior = rec.exit.interior },
    }
end

function getInterior(id)
    local rec = interiors[id]
    return rec and publicCopy(rec) or false
end

function getInteriors()
    local out = {}
    for _, rec in pairs(interiors) do out[#out + 1] = publicCopy(rec) end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

function getInteriorDimension(id)
    return interiors[id] and interiors[id].dimension or false
end

--- Id of the interior the player is inside (its fixed dimension, nearest exit marker), or false.
function getPlayerInterior(player)
    if not isElement(player) then return false end
    local dim = getElementDimension(player)
    if dim == 0 then return false end
    local px, py, pz = getElementPosition(player)
    local best, bestD
    for id, rec in pairs(interiors) do
        if rec.dimension == dim then
            local d = getDistanceBetweenPoints3D(px, py, pz, rec.exit.x, rec.exit.y, rec.exit.z)
            if not bestD or d < bestD then best, bestD = id, d end
        end
    end
    return best or false
end

local function teleport(player, p, dim)
    setElementPosition(player, p.x, p.y, p.z)
    setElementRotation(player, 0, 0, p.rot or 0)
    setElementInterior(player, p.interior)
    setElementDimension(player, dim)
    setCameraTarget(player, player)
    setCameraInterior(player, p.interior)
end

local function doTransfer(player, rec, toInside)
    if not isElement(player) then return end
    local p = toInside and rec.exit or rec.enter
    locked[player] = toInside and rec.exitMarker or rec.enterMarker
    teleport(player, p, toInside and rec.dimension or rec.enter.dimension)
    triggerClientEvent(player, "world_interiors:fadeIn", resourceRoot)
end

--- Teleport a player into / out of an interior with a fade. Returns true if started.
function enterInterior(player, id)
    local rec = interiors[id]
    if not rec or not isElement(player) or getElementType(player) ~= "player" then return false end
    triggerClientEvent(player, "world_interiors:fadeOut", resourceRoot)
    setTimer(doTransfer, INT.fadeMs, 1, player, rec, true)
    return true
end

function exitInterior(player, id)
    local rec = interiors[id or getPlayerInterior(player)]
    if not rec or not isElement(player) or getElementType(player) ~= "player" then return false end
    triggerClientEvent(player, "world_interiors:fadeOut", resourceRoot)
    setTimer(doTransfer, INT.fadeMs, 1, player, rec, false)
    return true
end

addEventHandler("onMarkerHit", resourceRoot, function(hit, matchingDim)
    if not matchingDim or getElementType(hit) ~= "player" then return end
    if isPedInVehicle(hit) or isPedDead(hit) then return end
    if locked[hit] == source then return end
    local id, kind = getElementData(source, "interior:id"), getElementData(source, "interior:kind")
    if not interiors[id] then return end
    locked[hit] = source           -- blocks double triggers during the fade
    if kind == "enter" then enterInterior(hit, id) else exitInterior(hit, id) end
end)

addEventHandler("onMarkerLeave", resourceRoot, function(leaver)
    if locked[leaver] == source then locked[leaver] = nil end
end)

addEventHandler("onPlayerQuit", root, function() locked[source] = nil end)

addEventHandler("onResourceStop", root, function(res)
    if res == resource then return end
    for id, rec in pairs(interiors) do
        if rec.resElement == res then
            destroyRecord(rec)
            interiors[id] = nil
        end
    end
end)

addEventHandler("onResourceStart", resourceRoot, function()
    triggerEvent("world_interiors:ready", root)
end)

-- shared with server/admin.lua
WI = { interiors = function() return interiors end, teleport = teleport }
