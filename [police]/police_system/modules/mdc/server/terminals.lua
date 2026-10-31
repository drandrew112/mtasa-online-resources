-- police_system / modules/mdc/server/terminals.lua
-- MDC computers: the full MDC without a unit sign-in (J on foot next to one, with the police right; the MDC requests
-- only check the right). Placed by admins (admin_level >= POLICE.ADMIN_LEVEL), stored in POLICE.TERMINALS.FILE
-- (JSON, resource folder).
--   /mdcpc         the mouse placement editor on / off (client/terminal_editor.lua, like gov_office /govpcs):
--                  place, pick up + move, rotate, raise, delete; every change is re-checked here
--   /mdcpc list    every computer (F8)
-- terminal = { id, x, y, z, rz, interior, dimension, model, by, at }

local T = POL.module("terminals", { list = {}, objects = {}, editing = {} })
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
    local obj = createObject(tonumber(e.model) or C.MODEL, e.x, e.y, e.z, 0, 0, tonumber(e.rz) or 0)
    if not obj then return end
    setElementInterior(obj, tonumber(e.interior) or 0)
    setElementDimension(obj, tonumber(e.dimension) or 0)
    setElementFrozen(obj, true)
    setElementData(obj, "pol:terminal", e.id)   -- the editor picks it by this
    T.objects[e.id] = obj
end

-- the list for the clients (the J hint + the range check)
local function sync(to)
    POL.send(to or root, "terminals", T.list)
end

function T.get(id)
    for i, e in ipairs(T.list) do if e.id == id then return e, i end end
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

------------------------------------------------------------------------ editor (/mdcpc)

local function editor(player, on)
    T.editing[player] = on or nil
    POL.send(player, "terminals:editor", on and true or false)
end

addCommandHandler("mdcpc", function(player, sub)
    if not isAdmin(player) then return end
    if sub == "list" then
        for _, e in ipairs(T.list) do
            outputConsole(("#%d  %.2f, %.2f, %.2f  rot %d  int %d dim %d"):format(e.id, e.x, e.y, e.z,
                math.floor(tonumber(e.rz) or 0), tonumber(e.interior) or 0, tonumber(e.dimension) or 0), player)
        end
        return POL.notify(player, "police_system.terminals.list", { count = #T.list })
    end
    editor(player, not T.editing[player])
end)

local function checkEdit(player)
    if not T.editing[player] then return false end
    if not isAdmin(player) then editor(player, false) return false end
    return true
end

local function within(player, x, y, z)
    local px, py, pz = getElementPosition(player)
    return math.sqrt((px - x) ^ 2 + (py - y) ^ 2 + (pz - z) ^ 2) <= C.EDIT_RANGE
end

-- (id | false, x, y, z, rz): a new computer, or the picked one moved, in the admin's interior / dimension
POL.net("terminals:place", function(player, id, x, y, z, rz)
    if not checkEdit(player) then return end
    x, y, z, rz = tonumber(x), tonumber(y), tonumber(z), tonumber(rz)
    if not (x and y and z and rz) then return end
    if not within(player, x, y, z) then return POL.notify(player, "police_system.terminals.too_far") end
    rz = rz % 360
    local int, dim = getElementInterior(player), getElementDimension(player)
    id = tonumber(id)
    if id then
        local e = T.get(id)
        if not e then return end
        e.x, e.y, e.z, e.rz, e.interior, e.dimension = x, y, z, rz, int, dim
        spawn(e)
        POL.notify(player, "police_system.terminals.moved", { id = id })
    else
        local nid = 0
        for _, e in ipairs(T.list) do nid = math.max(nid, tonumber(e.id) or 0) end
        nid = nid + 1
        local e = { id = nid, x = x, y = y, z = z, rz = rz, interior = int, dimension = dim, model = C.MODEL,
                    by = POL.accountOf(player) or "", at = POL.now() }
        T.list[#T.list + 1] = e
        spawn(e)
        POL.notify(player, "police_system.terminals.placed", { id = nid })
    end
    save()
    sync()
end)

POL.net("terminals:delete", function(player, id)
    if not checkEdit(player) then return end
    local e, idx = T.get(tonumber(id))
    if not e then return end
    table.remove(T.list, idx)
    if isElement(T.objects[e.id]) then destroyElement(T.objects[e.id]) end
    T.objects[e.id] = nil
    save()
    sync()
    POL.notify(player, "police_system.terminals.removed", { id = e.id })
end)

POL.net("terminals:stopEdit", function(player) T.editing[player] = nil end)
addEventHandler("onPlayerQuit", root, function() T.editing[source] = nil end)

function T.start()
    load()
    for _, e in ipairs(T.list) do spawn(e) end
end
