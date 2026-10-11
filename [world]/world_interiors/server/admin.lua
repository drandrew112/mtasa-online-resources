-- world_interiors / server/admin.lua — admin browsers (server side)
--   /interiors : registered interiors
--   /intwatch  : stock GTA interiors from data/stock_interiors.json (view only, never registered)

addEvent("world_interiors:adminRequest", true)
addEvent("world_interiors:adminTeleport", true)
addEvent("world_interiors:adminBack", true)

local returnPos = {}   -- player -> { x, y, z, interior, dimension }
local stock     = {}   -- array of { name, aliases, inside = point, entrances = { point + id } }

local function isAllowed(p)
    return isElement(p) and getElementData(p, "isLogged") == true
        and (tonumber(getElementData(p, "admin_level")) or 0) >= INT.adminLevel
end

local function loadStock()
    local f = fileOpen(INT.stockFile, true)
    if not f then
        outputDebugString("[world_interiors] cannot open " .. INT.stockFile, 2)
        return
    end
    local data = fromJSON(fileRead(f, fileGetSize(f)))
    fileClose(f)
    stock = type(data) == "table" and type(data.interiors) == "table" and data.interiors or {}
    outputDebugString(("[world_interiors] %d stock interiors loaded"):format(#stock))
end
addEventHandler("onResourceStart", resourceRoot, loadStock)

local function sendList(p, mode)
    local list = mode == "stock" and stock or getInteriors()
    triggerClientEvent(p, "world_interiors:adminList", resourceRoot, mode, list, returnPos[p] and true or false)
end

addCommandHandler(INT.command, function(p)
    if isAllowed(p) then sendList(p, "registered") end
end)

addCommandHandler(INT.stockCommand, function(p)
    if isAllowed(p) then sendList(p, "stock") end
end)

addEventHandler("world_interiors:adminRequest", root, function(mode)
    if isAllowed(client) then sendList(client, mode) end
end)

-- Resolves the target point + dimension of a teleport request.
local function resolveTarget(mode, id, where)
    if mode == "stock" then
        local g = stock[tonumber(id)]
        if not g then return end
        if where == "inside" then return g.inside, g.inside.dimension end
        local e = g.entrances[tonumber(where)]
        if e then return e, e.dimension end
    else
        local rec = WI.interiors()[id]
        if not rec then return end
        if where == "exit" then return rec.exit, rec.dimension end
        if where == "enter" then return rec.enter, rec.enter.dimension end
    end
end

addEventHandler("world_interiors:adminTeleport", root, function(mode, id, where)
    local p = client
    if not isAllowed(p) then return end
    local point, dim = resolveTarget(mode, id, where)
    if not point then return end
    if not returnPos[p] then
        local x, y, z = getElementPosition(p)
        returnPos[p] = { x = x, y = y, z = z, interior = getElementInterior(p), dimension = getElementDimension(p) }
    end
    if isPedInVehicle(p) then removePedFromVehicle(p) end
    WI.teleport(p, point, dim)
end)

addEventHandler("world_interiors:adminBack", root, function()
    local p = client
    local r = returnPos[p]
    if not isAllowed(p) or not r then return end
    returnPos[p] = nil
    WI.teleport(p, { x = r.x, y = r.y, z = r.z, rot = 0, interior = r.interior }, r.dimension)
end)

addEventHandler("onPlayerQuit", root, function() returnPos[source] = nil end)
