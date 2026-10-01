-- Client menu registry: menus registered locally by other client scripts and the ones the server
-- synced down live in one table, so the scan/render code does not care where a menu came from.
-- `remote` only decides where a selection is sent.

addEvent("io:sync", true)
addEvent("io:syncAll", true)
addEvent("io:remove", true)
addEvent("io:forceClose", true)
addEvent("onClientInteractMenuSelect")
addEvent("onClientInteractMenuOpen")
addEvent("onClientInteractMenuClose")

Menus = {}         -- id -> { id, element | elementType, def, raw, remote, resource, order }
ElementMenus = {}  -- element -> { [id] = true }
TypeMenus = {}     -- elementType -> { [id] = true }

local order = 0
local nextLocalId = 0
local disabledBy = {}  -- resource -> true (setInteractionDisabled)

local function indexOf(menu)
    if menu.element then return ElementMenus, menu.element end
    return TypeMenus, menu.elementType
end

local function unlink(menu)
    local index, key = indexOf(menu)
    local set = index[key]
    if not set then return end
    set[menu.id] = nil
    if not next(set) then index[key] = nil end
end

local function link(menu)
    local index, key = indexOf(menu)
    index[key] = index[key] or {}
    index[key][menu.id] = true
end

local function storeMenu(id, target, def, raw, remote, owner)
    local old = Menus[id]
    if old then unlink(old) end
    if not old then order = order + 1 end
    local menu = { id = id, def = def, raw = raw, remote = remote, resource = owner, order = old and old.order or order }
    if type(target) == "string" then menu.elementType = target else menu.element = target end
    Menus[id] = menu
    link(menu)
    requestScan()
    return menu
end

local function dropMenu(id)
    local menu = Menus[id]
    if not menu then return false end
    unlink(menu)
    Menus[id] = nil
    requestScan()
    return true
end

function isInteractionDisabled()
    return next(disabledBy) ~= nil
end

-- ---------------------------------------------------------------------------------------------
-- Exports (local menus)
-- ---------------------------------------------------------------------------------------------

local function createLocal(target, def)
    local clean = ioSanitizeDef(def)
    if not clean then return false end
    nextLocalId = nextLocalId + 1
    local id = "c" .. nextLocalId
    storeMenu(id, target, clean, ioShallowCopy(def), false, sourceResource or resource)
    return id
end

local function localMenu(id)
    local menu = Menus[id]
    if menu and not menu.remote then return menu end
end

function addInteractMenu(element, def)
    if not isElement(element) then return false end
    return createLocal(element, def)
end

function addInteractTypeMenu(elementType, def)
    if type(elementType) ~= "string" then return false end
    return createLocal(elementType, def)
end

function updateInteractMenu(id, def)
    local menu = localMenu(id)
    if not menu or type(def) ~= "table" then return false end
    local raw = ioShallowCopy(menu.raw)
    for k, v in pairs(def) do raw[k] = v end
    local clean = ioSanitizeDef(raw)
    if not clean then return false end
    menu.raw, menu.def = raw, clean
    requestScan()
    return true
end

function setInteractMenuItems(id, items)
    return updateInteractMenu(id, { items = items })
end

function setInteractMenuEnabled(id, state)
    return updateInteractMenu(id, { enabled = state ~= false })
end

function removeInteractMenu(id)
    if not localMenu(id) then return false end
    return dropMenu(id)
end

function isInteractMenu(id)
    return Menus[id] ~= nil
end

function isInteractMenuOpen()
    return State.open
end

-- element (focused target or false), isOpen
function getInteractTarget()
    return State.focus or false, State.open
end

function closeInteractMenu()
    if not State.open then return false end
    closeMenu()
    return true
end

-- Lets another script hide every interaction menu (e.g. while its own panel/minigame runs).
-- Tracked per calling resource, released automatically when that resource stops.
function setInteractionDisabled(state)
    disabledBy[sourceResource or resource] = state and true or nil
    requestScan()
    return true
end

-- ---------------------------------------------------------------------------------------------
-- Server sync
-- ---------------------------------------------------------------------------------------------

-- Menus whose element has not arrived on this client yet (created in the same tick, or during the
-- owner resource's start). MTA delivers an unknown element as nil, so the client cannot wait for
-- it: it asks the server to resend those menus until the element exists or they expire.
local pending = {}        -- id -> expires (tick)
local pendingTimer
local PENDING_RETRY = 500 -- ms
local PENDING_TTL = 10000 -- ms

local function requestResend()
    local now, ids = getTickCount(), {}
    for id, expires in pairs(pending) do
        if now > expires then pending[id] = nil else ids[#ids + 1] = id end
    end
    if #ids > 0 then triggerServerEvent("io:resend", resourceRoot, ids) end
    if not next(pending) and isTimer(pendingTimer) then
        killTimer(pendingTimer)
        pendingTimer = nil
    end
end

local function storeRemote(p)
    if type(p) ~= "table" or type(p.def) ~= "table" or not p.id then return end
    if p.bound then
        if not isElement(p.element) then
            pending[p.id] = pending[p.id] or (getTickCount() + PENDING_TTL)
            if not isTimer(pendingTimer) then pendingTimer = setTimer(requestResend, PENDING_RETRY, 0) end
            return
        end
        pending[p.id] = nil
        storeMenu(p.id, p.element, p.def, nil, true)
    elseif type(p.elementType) == "string" then
        storeMenu(p.id, p.elementType, p.def, nil, true)
    end
end

addEventHandler("io:sync", resourceRoot, storeRemote)

addEventHandler("io:syncAll", resourceRoot, function(list)
    pending = {}
    for id, menu in pairs(Menus) do
        if menu.remote then dropMenu(id) end
    end
    for _, p in ipairs(list or {}) do storeRemote(p) end
end)

addEventHandler("io:remove", resourceRoot, function(id)
    pending[id] = nil
    local menu = Menus[id]
    if menu and menu.remote then dropMenu(id) end
end)

addEventHandler("io:forceClose", resourceRoot, function()
    closeMenu()
end)

-- ---------------------------------------------------------------------------------------------
-- Cleanup
-- ---------------------------------------------------------------------------------------------

addEventHandler("onClientElementDestroy", root, function()
    local set = ElementMenus[source]
    if not set then return end
    for id in pairs(set) do dropMenu(id) end
end)

addEventHandler("onClientResourceStop", root, function(stopped)
    if stopped == resource then return end
    disabledBy[stopped] = nil
    for id, menu in pairs(Menus) do
        if not menu.remote and menu.resource == stopped then dropMenu(id) end
    end
    requestScan()
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("io:ready", resourceRoot)
end)
