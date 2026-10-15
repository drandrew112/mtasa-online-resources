if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Ports: storage markers created by other scripts (the blood transport). A player standing in the
-- marker with a container (in a hand or on the back) opens the transfer window with E.
-- Who sees a port at all: visibleTo (a player list, nil = everyone) and / or dataKey (+ dataValue)
-- on the player. Per-player rules (allowIn / allowOut) and suggestions are set by the scripts;
-- several players can have different rules on the same port.

addEvent("inv:openPort", true)
addEvent("inv:requestPorts", true)
addEvent("onPortOpen")       -- source: resourceRoot; (portId, player) cancelable
addEvent("onPortItemMoved")  -- source: resourceRoot; (portId, player, uid, "in" | "out")

Ports = {}               -- id -> port
local nextId = 0
local watchedKeys = {}   -- element data key -> number of ports filtering on it

-- ---------------------------------------------------------------------------------------------
-- Visibility
-- ---------------------------------------------------------------------------------------------

function portVisibleFor(port, player)
    if port.visibleTo and not port.visibleTo[player] then return false end
    return hasDataAccess(player, port.dataKey, port.dataValue)
end

local function portInfo(port)
    return {
        id = port.id, marker = port.marker, x = port.x, y = port.y, z = port.z, dim = port.dim, int = port.int,
        radius = port.radius, name = port.name, title = port.title, color = port.color, icon = port.icon,
    }
end

-- Sends the player the ports they see and shows them the markers
local function refreshFor(player)
    if not isElement(player) then return end
    local list = {}
    for _, port in pairs(Ports) do
        local visible = portVisibleFor(port, player)
        if isElement(port.marker) then setElementVisibleTo(port.marker, player, visible) end
        if visible then list[#list + 1] = portInfo(port) end
    end
    triggerClientEvent(player, "inv:ports", resourceRoot, list)
end

local refreshPending = false
function refreshPortsAll()
    if refreshPending then return end
    refreshPending = true
    setTimer(function()
        refreshPending = false
        for _, player in ipairs(getElementsByType("player")) do refreshFor(player) end
    end, 50, 1)
end

addEventHandler("inv:requestPorts", resourceRoot, function() refreshFor(client) end)

addEventHandler("onElementDataChange", root, function(key)
    if watchedKeys[key] and getElementType(source) == "player" then refreshFor(source) end
end)

local function watchKey(key, delta)
    if not key then return end
    watchedKeys[key] = (watchedKeys[key] or 0) + delta
    if watchedKeys[key] <= 0 then watchedKeys[key] = nil end
end

-- ---------------------------------------------------------------------------------------------
-- Rules / suggestions
-- ---------------------------------------------------------------------------------------------

-- nil / true = allowed, false = nothing, table = only the listed uids / item ids
local function ruleAllows(rule, item)
    if rule == nil or rule == true then return true end
    if rule == false then return false end
    return rule[item.uid] == true or rule[item.def] == true
end

function portAllows(portId, player, item, direction)
    local port = Ports[portId]
    if not port then return false end
    local rules = port.rules[player]
    if not rules then return true end
    return ruleAllows(direction == "in" and rules.allowIn or rules.allowOut, item)
end

-- "in" | "out" | nil
function portSuggestion(portId, player, item)
    local port = Ports[portId]
    local s = port and port.suggestions[player]
    if not s then return nil end
    return s.items[item.uid] or s.items[item.def]
end

function portBanner(portId, player)
    local port = Ports[portId]
    local s = port and port.suggestions[player]
    return s and s.banner or nil
end

-- A list ({ "uid", "defId" } or { uid = true }) -> set
local function toSet(list)
    if list == nil or list == true or list == false then return list end
    if type(list) ~= "table" then return nil end
    local set = {}
    for k, v in pairs(list) do
        if type(k) == "number" then set[tostring(v)] = true elseif v then set[tostring(k)] = true end
    end
    return set
end

-- ---------------------------------------------------------------------------------------------
-- API (server/exports.lua)
-- ---------------------------------------------------------------------------------------------

local function num(v) return tonumber(v) end

function createPortFrom(opts, owner)
    local x, y, z = num(opts.x), num(opts.y), num(opts.z)
    if not (x and y and z) then return false, "x, y, z expected" end
    nextId = nextId + 1
    local color = type(opts.color) == "table" and opts.color or INV.PORT_COLOR
    local port = {
        id = "p" .. nextId, x = x, y = y, z = z, dim = num(opts.dimension) or 0, int = num(opts.interior) or 0,
        radius = num(opts.radius) or INV.PORT_RADIUS,
        name = opts.name, title = opts.title, icon = opts.icon and tostring(opts.icon) or "P",
        color = { num(color[1]) or 215, num(color[2]) or 55, num(color[3]) or 65 },
        capacity = num(opts.capacity), accepts = type(opts.accepts) == "table" and toSet(opts.accepts) or nil,
        items = {}, rules = {}, suggestions = {}, owner = owner,
        dataKey = type(opts.dataKey) == "string" and opts.dataKey or nil, dataValue = opts.dataValue,
    }
    if type(opts.visibleTo) == "table" then
        port.visibleTo = {}
        for _, p in ipairs(opts.visibleTo) do if isElement(p) then port.visibleTo[p] = true end end
    end
    local c = port.color
    port.marker = createMarker(x, y, z, "cylinder", port.radius, c[1], c[2], c[3], 120)
    if port.marker then
        setElementDimension(port.marker, port.dim)
        setElementInterior(port.marker, port.int)
        setElementData(port.marker, INV_DATA.PORT, port.id)
        setElementVisibleTo(port.marker, root, false)
    end
    watchKey(port.dataKey, 1)
    Ports[port.id] = port
    refreshPortsAll()
    return port.id
end

function destroyPortById(id)
    local port = Ports[id]
    if not port then return false end
    for i = #port.items, 1, -1 do
        if port.items[i] then destroyItem(port.items[i]) end
    end
    closeSessionsOf({ type = "port", port = id })
    Ports[id] = nil
    watchKey(port.dataKey, -1)
    if isElement(port.marker) then destroyElement(port.marker) end
    refreshPortsAll()
    return true
end

function setPortVisibility(id, visibleTo, dataKey, dataValue)
    local port = Ports[id]
    if not port then return false end
    if visibleTo == nil or visibleTo == false then
        port.visibleTo = nil
    elseif type(visibleTo) == "table" then
        port.visibleTo = {}
        for k, v in pairs(visibleTo) do
            local p = type(k) == "number" and v or k
            if isElement(p) then port.visibleTo[p] = true end
        end
    end
    if dataKey ~= nil then
        watchKey(port.dataKey, -1)
        port.dataKey = dataKey ~= false and tostring(dataKey) or nil
        port.dataValue = dataValue
        watchKey(port.dataKey, 1)
    end
    refreshPortsAll()
    for _, player in ipairs(getElementsByType("player")) do
        if not portVisibleFor(port, player) then closeSessionsOf({ type = "port", port = id }, player) end
    end
    return true
end

function setPortRulesFor(id, player, rules)
    local port = Ports[id]
    if not port or not isElement(player) then return false end
    if rules == nil or rules == false then
        port.rules[player] = nil
    else
        port.rules[player] = { allowIn = toSet(rules.allowIn), allowOut = toSet(rules.allowOut) }
    end
    touchLoc({ type = "port", port = id })
    return true
end

function setPortSuggestionsFor(id, player, items, banner)
    local port = Ports[id]
    if not port or not isElement(player) then return false end
    if items == nil or items == false then
        port.suggestions[player] = nil
    else
        local map = {}
        for k, v in pairs(type(items) == "table" and items or {}) do
            if v == "in" or v == "out" then map[tostring(k)] = v end
        end
        port.suggestions[player] = { items = map, banner = banner }
    end
    touchLoc({ type = "port", port = id })
    return true
end

-- ---------------------------------------------------------------------------------------------
-- Opening
-- ---------------------------------------------------------------------------------------------

function isPlayerAtPort(port, player)
    if getElementDimension(player) ~= port.dim or getElementInterior(player) ~= port.int then return false end
    local x, y, z = getElementPosition(player)
    return getDistanceBetweenPoints2D(x, y, port.x, port.y) <= port.radius + 1.0 and math.abs(z - port.z) < 3.5
end

local function hasContainer(player)
    local slots = getSlots(player)
    if not slots then return false end
    for _, item in pairs(slots) do
        if isContainer(item) then return true end
    end
    return false
end

addEventHandler("inv:openPort", resourceRoot, function(id)
    local player = client
    local port = Ports[id]
    if not port or not portVisibleFor(port, player) then return end
    if isPedDead(player) or isPedInVehicle(player) or not isPlayerAtPort(port, player) then return end
    if not hasContainer(player) then
        return notify(player, L.msg("v_inventory.msg.need_container"), true)
    end
    triggerEvent("onPortOpen", resourceRoot, id, player)
    if wasEventCancelled() then
        local why = getCancelReason()
        if why and why ~= "" then notify(player, why, true) end
        return
    end
    openSession(player, { type = "port", port = id })
end)

-- Moves that touch a port (for the scripts that watch deliveries)
addEventHandler("onInventoryItemMoved", resourceRoot, function(uid, defId, from, to, player)
    if to.type == "port" and Ports[to.port] then
        triggerEvent("onPortItemMoved", resourceRoot, to.port, player, uid, "in")
    end
    if from.type == "port" and Ports[from.port] then
        triggerEvent("onPortItemMoved", resourceRoot, from.port, player, uid, "out")
    end
end)

-- ---------------------------------------------------------------------------------------------
-- Lifetime
-- ---------------------------------------------------------------------------------------------

addEventHandler("onPlayerQuit", root, function()
    for _, port in pairs(Ports) do
        port.rules[source], port.suggestions[source] = nil, nil
        if port.visibleTo then port.visibleTo[source] = nil end
    end
end)

addEventHandler("onResourceStop", root, function(res)
    if res == resource then return end
    local name = getResourceName(res)
    for id, port in pairs(Ports) do
        if port.owner == name then destroyPortById(id) end
    end
end)
