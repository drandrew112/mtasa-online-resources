-- Server-owned menus. Every menu is synced to the players allowed to see it; the client only
-- reports "menu id + item path + target", and the server re-checks everything before it fires
-- onInteractMenuSelect, so the value a handler receives always comes from the server's own copy.

addEvent("io:ready", true)
addEvent("io:select", true)
addEvent("io:resend", true)
addEvent("onInteractMenuSelect")

local menus = {}          -- id -> { id, element | elementType, def, raw, visibleTo, resource }
local boundElements = {}  -- element -> { [id] = true }
local ready = {}          -- player -> true once its client registry is up
local lastSelect = {}     -- player -> tick
local nextId = 0

local function packet(menu)
    -- bound: the menu belongs to one element (the client may receive it as nil if it does not know
    -- that element yet, and then asks for a resend through io:resend)
    return { id = menu.id, element = menu.element, elementType = menu.elementType, def = menu.def,
        bound = menu.element ~= nil or nil }
end

local function canSee(menu, player)
    return not menu.visibleTo or menu.visibleTo[player] == true
end

-- nil = everyone, false = invalid input, table = set of players.
local function toVisibleSet(visibleTo)
    if visibleTo == nil then return nil end
    if isElement(visibleTo) then return { [visibleTo] = true } end
    if type(visibleTo) ~= "table" then return false end
    local set = {}
    for k, v in pairs(visibleTo) do
        if isElement(v) then set[v] = true
        elseif isElement(k) and v then set[k] = true end
    end
    return set
end

local function readyList()
    local list = {}
    for player in pairs(ready) do list[#list + 1] = player end
    return list
end

local function broadcast(menu)
    local show, hide = {}, {}
    for player in pairs(ready) do
        if canSee(menu, player) then show[#show + 1] = player else hide[#hide + 1] = player end
    end
    if #show > 0 then triggerClientEvent(show, "io:sync", resourceRoot, packet(menu)) end
    if #hide > 0 then triggerClientEvent(hide, "io:remove", resourceRoot, menu.id) end
end

local function dropMenu(id)
    local menu = menus[id]
    if not menu then return false end
    menus[id] = nil
    if menu.element then
        local set = boundElements[menu.element]
        if set then
            set[id] = nil
            if not next(set) then boundElements[menu.element] = nil end
        end
    end
    local list = readyList()
    if #list > 0 then triggerClientEvent(list, "io:remove", resourceRoot, id) end
    return true
end

local function createMenu(target, def, visibleTo)
    local clean = ioSanitizeDef(def)
    if not clean then return false end
    local set = toVisibleSet(visibleTo)
    if set == false then return false end

    nextId = nextId + 1
    local menu = {
        id = "s" .. nextId, def = clean, raw = ioShallowCopy(def), visibleTo = set,
        resource = sourceResource or resource,
    }
    if type(target) == "string" then
        menu.elementType = target
    else
        menu.element = target
        boundElements[target] = boundElements[target] or {}
        boundElements[target][menu.id] = true
    end
    menus[menu.id] = menu
    broadcast(menu)
    return menu.id
end

-- ---------------------------------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------------------------------

function addInteractMenu(element, def, visibleTo)
    if not isElement(element) then return false end
    return createMenu(element, def, visibleTo)
end

function addInteractTypeMenu(elementType, def, visibleTo)
    if type(elementType) ~= "string" then return false end
    return createMenu(elementType, def, visibleTo)
end

-- Merges the given fields into the menu's definition (items are replaced as a whole).
function updateInteractMenu(id, def)
    local menu = menus[id]
    if not menu or type(def) ~= "table" then return false end
    local raw = ioShallowCopy(menu.raw)
    for k, v in pairs(def) do raw[k] = v end
    local clean = ioSanitizeDef(raw)
    if not clean then return false end
    menu.raw, menu.def = raw, clean
    broadcast(menu)
    return true
end

function setInteractMenuItems(id, items)
    return updateInteractMenu(id, { items = items })
end

function setInteractMenuEnabled(id, state)
    return updateInteractMenu(id, { enabled = state ~= false })
end

function setInteractMenuVisibleTo(id, visibleTo)
    local menu = menus[id]
    if not menu then return false end
    local set = toVisibleSet(visibleTo)
    if set == false then return false end
    menu.visibleTo = set
    broadcast(menu)
    return true
end

function removeInteractMenu(id)
    return dropMenu(id)
end

function isInteractMenu(id)
    return menus[id] ~= nil
end

function closeInteractMenuFor(player)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    triggerClientEvent(player, "io:forceClose", resourceRoot)
    return true
end

-- ---------------------------------------------------------------------------------------------
-- Client sync + selection
-- ---------------------------------------------------------------------------------------------

addEventHandler("io:ready", resourceRoot, function()
    local player = client
    ready[player] = true
    local list = {}
    for _, menu in pairs(menus) do
        if canSee(menu, player) then list[#list + 1] = packet(menu) end
    end
    triggerClientEvent(player, "io:syncAll", resourceRoot, list)
end)

-- The client got these menus before their element; send them again (or tell it they are gone).
addEventHandler("io:resend", resourceRoot, function(ids)
    local player = client
    if not player or not ready[player] or type(ids) ~= "table" then return end
    local count = 0
    for _, id in ipairs(ids) do
        count = count + 1
        if count > 64 then break end
        local menu = menus[id]
        if menu and canSee(menu, player) then
            triggerClientEvent(player, "io:sync", resourceRoot, packet(menu))
        else
            triggerClientEvent(player, "io:remove", resourceRoot, id)
        end
    end
end)

local function validPath(path)
    if type(path) ~= "table" or #path == 0 or #path > IO.MAX_SUBMENU_DEPTH + 1 then return false end
    for _, index in ipairs(path) do
        if type(index) ~= "number" then return false end
    end
    return true
end

addEventHandler("io:select", resourceRoot, function(id, path, target)
    local player = client
    if not player then return end

    local now = getTickCount()
    if lastSelect[player] and now - lastSelect[player] < IO.SELECT_COOLDOWN then return end
    lastSelect[player] = now

    local menu = menus[id]
    if not menu or not menu.def.enabled or not canSee(menu, player) then return end
    if not isElement(target) or target == player then return end
    if menu.element then
        if target ~= menu.element then return end
    elseif getElementType(target) ~= menu.elementType then
        return
    end

    local def = menu.def
    if not ioDataMatches(def, target) then return end
    if def.selfDataKey and not ioTruthy(getElementData(player, def.selfDataKey)) then return end
    if isPedDead(player) then return end
    if isPedInVehicle(player) and not def.allowInVehicle then return end
    if getElementDimension(player) ~= getElementDimension(target)
        or getElementInterior(player) ~= getElementInterior(target) then return end

    local px, py, pz = getElementPosition(player)
    local tx, ty, tz = getElementPosition(target)
    if getDistanceBetweenPoints3D(px, py, pz, tx, ty, tz) > def.range + IO.SERVER_RANGE_TOLERANCE then return end

    if not validPath(path) then return end
    local item, blocked = ioResolvePath(def.items, path)
    if not item or item.items or blocked then return end

    triggerEvent("onInteractMenuSelect", player, id, item.value, target, path)
end)

-- ---------------------------------------------------------------------------------------------
-- Cleanup
-- ---------------------------------------------------------------------------------------------

local function dropBound(element)
    local set = boundElements[element]
    if not set then return end
    for id in pairs(set) do dropMenu(id) end
end

addEventHandler("onElementDestroy", root, function()
    dropBound(source)
end)

addEventHandler("onPlayerQuit", root, function()
    ready[source], lastSelect[source] = nil, nil
    dropBound(source)
    for _, menu in pairs(menus) do
        if menu.visibleTo then menu.visibleTo[source] = nil end
    end
end)

addEventHandler("onResourceStop", root, function(stopped)
    if stopped == resource then return end
    for id, menu in pairs(menus) do
        if menu.resource == stopped then dropMenu(id) end
    end
end)
