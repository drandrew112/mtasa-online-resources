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
--        inside  = { x=, y=, z=, rot=0 }  (optional) arrival point when entering, default: the exit marker
--        outside = { x=, y=, z=, rot=0 }  (optional) arrival point when leaving, default: the enter marker
--    })
--
--  Walking into a marker shows a 3D label (client/markers.lua); the
--  player has to press INT.key inside it to go through. The player is
--  teleported onto the opposite marker (or the inside / outside point).
--  Interiors are removed when the registering resource stops. This
--  resource fires "world_interiors:ready" (root) when it starts, so
--  registering resources should register on their own onResourceStart
--  AND on that event, so a restart of world_interiors loses nothing.
-- ============================================================

local interiors = {}   -- id -> record
local busy      = {}   -- player -> getTickCount() of the last transfer (fade in progress / cooldown)
local savedOut  = {}   -- player -> true while our "save.position" (the outside point) is set

addEvent("world_interiors:ready", false)
addEvent("world_interiors:use", true)

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

local function makeMarker(p, dim, color, id, kind, name)
    local m = createMarker(p.x, p.y, p.z - 1, INT.markerType, INT.markerSize, color[1], color[2], color[3], color[4])
    setElementInterior(m, p.interior)
    setElementDimension(m, dim)
    -- synced: read by the client label + key handler
    setElementData(m, "interior:id", id)
    setElementData(m, "interior:kind", kind)
    setElementData(m, "interior:name", name)
    setElementData(m, "interior:color", { color[1], color[2], color[3] })   -- shader_markers hides the real marker colour
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

    -- arrival points: interior of the marker on that side
    local inside, outside = cleanPoint(data.inside, true), cleanPoint(data.outside, true)
    if inside then inside.interior = exit.interior end
    if outside then outside.interior = enter.interior end

    local rec = {
        id = id, name = tostring(data.name or id), dimension = dim,
        enter = enter, exit = exit,
        inside = inside or exit, outside = outside or enter,
        resource = sourceResource and getResourceName(sourceResource) or "?",
        resElement = sourceResource,
    }
    rec.enterMarker = makeMarker(enter, enter.dimension, data.enterColor or INT.enterColor, id, "enter", rec.name)
    rec.exitMarker  = makeMarker(exit, dim, data.exitColor or INT.exitColor, id, "exit", rec.name)
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

-- acc_savesys saves "save.position" instead of the real position: a player who quits
-- inside an interior comes back at its enter marker (like biz_int)
local function setSavedOutside(player, rec)
    local o = rec.outside
    setElementData(player, "save.position", { o.x, o.y, o.z, o.interior, rec.enter.dimension }, false)
    savedOut[player] = true
end

local function clearSavedOutside(player)
    if not savedOut[player] then return end
    savedOut[player] = nil
    if isElement(player) then removeElementData(player, "save.position") end
end

local function teleport(player, p, dim)
    clearSavedOutside(player)
    setElementPosition(player, p.x, p.y, p.z)
    setElementRotation(player, 0, 0, p.rot or 0)
    setElementInterior(player, p.interior)
    setElementDimension(player, dim)
    setCameraTarget(player, player)
    setCameraInterior(player, p.interior)
end

local function doTransfer(player, rec, toInside)
    if not isElement(player) then return end
    local p = toInside and rec.inside or rec.outside
    teleport(player, p, toInside and rec.dimension or rec.enter.dimension)
    if toInside then setSavedOutside(player, rec) end
    triggerClientEvent(player, "world_interiors:fadeIn", resourceRoot)
end

local function startTransfer(player, rec, toInside)
    if not rec or not isElement(player) or getElementType(player) ~= "player" then return false end
    local now = getTickCount()
    if busy[player] and now - busy[player] < INT.fadeMs + INT.cooldownMs then return false end
    busy[player] = now
    triggerClientEvent(player, "world_interiors:fadeOut", resourceRoot)
    setTimer(doTransfer, INT.fadeMs, 1, player, rec, toInside)
    return true
end

--- Teleport a player into / out of an interior with a fade. Returns true if started.
function enterInterior(player, id)
    return startTransfer(player, interiors[id], true)
end

function exitInterior(player, id)
    return startTransfer(player, interiors[id or getPlayerInterior(player)], false)
end

-- Key press in a marker (client/markers.lua). Re-checked here: the player must really stand in it.
addEventHandler("world_interiors:use", resourceRoot, function(marker)
    local p = client
    if not isElement(marker) or getElementType(marker) ~= "marker" then return end
    local id, kind = getElementData(marker, "interior:id"), getElementData(marker, "interior:kind")
    local rec = interiors[id]
    if not rec or (marker ~= rec.enterMarker and marker ~= rec.exitMarker) then return end
    if isPedInVehicle(p) or isPedDead(p) then return end
    if getElementDimension(p) ~= getElementDimension(marker) or getElementInterior(p) ~= getElementInterior(marker) then return end
    if not isElementWithinMarker(p, marker) then return end
    if kind == "enter" then enterInterior(p, id) else exitInterior(p, id) end
end)

-- only the table entry goes on quit: acc_savesys still saves the outside point from the element data
addEventHandler("onPlayerQuit", root, function() busy[source] = nil; savedOut[source] = nil end)
-- respawned somewhere else (death): the outside point no longer applies
addEventHandler("onPlayerSpawn", root, function() clearSavedOutside(source) end)

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
