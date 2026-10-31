-- police_system / modules/mdc/server/terminals.lua
-- MDC computers: the full MDC without a unit sign-in (J on foot next to one, with the police right; the MDC requests
-- only check the right). Placed by admins (admin_level >= POLICE.ADMIN_LEVEL) with /mdcpc (client/terminals.lua finds
-- the surface in front of the admin), stored in POLICE.TERMINALS.FILE (JSON, resource folder).
--   /mdcpc add [model]   a computer in front of the admin, facing them (model 0: no object, a computer of the map)
--   /mdcpc remove        the nearest one
--   /mdcpc turn [deg]    turns the nearest one (default 90)
--   /mdcpc list          every computer (F8)
-- terminal = { id, x, y, z, rz, interior, dimension, model }

local T = POL.module("terminals", { list = {}, objects = {} })
local C = POLICE.TERMINALS

local function isAdmin(p) return (tonumber(getElementData(p, "admin_level")) or 0) >= POLICE.ADMIN_LEVEL end

local function load()
    T.list = {}
    if not fileExists(C.FILE) then return end
    local f = fileOpen(C.FILE, true)
    if not f then return end
    local s = fileRead(f, fileGetSize(f))
    fileClose(f)
    local ok, t = pcall(fromJSON, s)
    if not ok or type(t) ~= "table" then
        outputDebugString("[police_system] " .. C.FILE .. " is not valid JSON", 2)
        return
    end
    for _, e in ipairs(t) do
        if tonumber(e.id) and tonumber(e.x) and tonumber(e.y) and tonumber(e.z) then T.list[#T.list + 1] = e end
    end
end

local function save()
    local f = fileCreate(C.FILE)
    if not f then return outputDebugString("[police_system] cannot write " .. C.FILE, 1) end
    fileWrite(f, toJSON(T.list, false, "spaces"))
    fileClose(f)
end

local function spawn(e)
    local old = T.objects[e.id]
    if old and isElement(old) then destroyElement(old) end
    T.objects[e.id] = nil
    local model = tonumber(e.model) or 0
    if model <= 0 then return end
    local obj = createObject(model, e.x, e.y, e.z, 0, 0, tonumber(e.rz) or 0)
    if not obj then return end
    setElementInterior(obj, tonumber(e.interior) or 0)
    setElementDimension(obj, tonumber(e.dimension) or 0)
    setElementFrozen(obj, true)
    T.objects[e.id] = obj
end

-- the list for the clients (the J hint + the range check)
local function sync(to)
    POL.send(to or root, "terminals", T.list)
end

local function nearest(player, range)
    local x, y, z = getElementPosition(player)
    local int, dim = getElementInterior(player), getElementDimension(player)
    local best, bd
    for i, e in ipairs(T.list) do
        if (tonumber(e.interior) or 0) == int and (tonumber(e.dimension) or 0) == dim then
            local d = math.sqrt((e.x - x) ^ 2 + (e.y - y) ^ 2 + (e.z - z) ^ 2)
            if d <= range and (not bd or d < bd) then best, bd = i, d end
        end
    end
    return best and T.list[best], best
end

function T.get(id)
    for _, e in ipairs(T.list) do if e.id == id then return e end end
    return nil
end

-- the client asks to open the MDC of a computer
POL.net("mdc:terminal", function(player, id)
    local e = T.get(tonumber(id))
    if not e or not POL.rights.has(player) or getPedOccupiedVehicle(player) then return end
    if getElementInterior(player) ~= (tonumber(e.interior) or 0) or getElementDimension(player) ~= (tonumber(e.dimension) or 0) then return end
    local x, y, z = getElementPosition(player)
    if math.sqrt((e.x - x) ^ 2 + (e.y - y) ^ 2 + (e.z - z) ^ 2) > C.RANGE + 1 then return end
    POL.send(player, "mdc:terminalOpen", e.id)
end)

POL.net("terminals:ready", function(player) sync(player) end)

-- /mdcpc from the client: sub, arg, and for "add" the surface point + heading found there
POL.net("terminals:cmd", function(player, sub, arg, x, y, z, rz)
    if not isAdmin(player) then return end
    if sub == "add" then
        x, y, z, rz = tonumber(x), tonumber(y), tonumber(z), tonumber(rz)
        if not (x and y and z and rz) then return POL.notify(player, "police_system.terminals.no_surface") end
        local px, py, pz = getElementPosition(player)
        if math.sqrt((px - x) ^ 2 + (py - y) ^ 2 + (pz - z) ^ 2) > 5 then return end
        local id = 0
        for _, e in ipairs(T.list) do id = math.max(id, tonumber(e.id) or 0) end
        id = id + 1
        local model = tonumber(arg)
        local e = { id = id, x = x, y = y, z = z + C.Z_OFFSET, rz = rz % 360, interior = getElementInterior(player),
                    dimension = getElementDimension(player), model = model and math.floor(model) or C.MODEL,
                    by = POL.accountOf(player) or "", at = POL.now() }
        T.list[#T.list + 1] = e
        spawn(e)
        save()
        sync()
        POL.notify(player, "police_system.terminals.placed", { id = id })
    elseif sub == "remove" or sub == "turn" then
        local e, idx = nearest(player, 4)
        if not e then return POL.notify(player, "police_system.terminals.none") end
        if sub == "remove" then
            table.remove(T.list, idx)
            if isElement(T.objects[e.id]) then destroyElement(T.objects[e.id]) end
            T.objects[e.id] = nil
            POL.notify(player, "police_system.terminals.removed", { id = e.id })
        else
            e.rz = ((tonumber(e.rz) or 0) + (tonumber(arg) or 90)) % 360
            spawn(e)
            POL.notify(player, "police_system.terminals.turned", { id = e.id, rot = math.floor(e.rz) })
        end
        save()
        sync()
    elseif sub == "list" then
        for _, e in ipairs(T.list) do
            outputConsole(("#%d  %.2f, %.2f, %.2f  rot %d  int %d dim %d  model %d"):format(e.id, e.x, e.y, e.z,
                math.floor(tonumber(e.rz) or 0), tonumber(e.interior) or 0, tonumber(e.dimension) or 0, tonumber(e.model) or 0), player)
        end
        POL.notify(player, "police_system.terminals.list", { count = #T.list })
    else
        POL.notify(player, "police_system.terminals.usage")
    end
end)

function T.start()
    load()
    for _, e in ipairs(T.list) do spawn(e) end
end
