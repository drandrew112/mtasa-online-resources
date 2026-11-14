-- v_collectibles client: streams the objects of the uncollected items, picks them up within PICKUP_RANGE,
-- shows the ui_core banner and keeps the LOCAL element data COLLECT.DATA_KEY for the ui_inac Collectibles menu.
-- Lists with a "sound" play it as a very quiet 3D loop at the nearest uncollected item within COLLECT.SOUND_RANGE.

local uicore = exports.ui_core

Collect = {
    lists = {},         -- [listId] = { id, name, event, spin, sound, total, found, items = { [itemId] = item } }
    order = {},         -- list ids in server order
    objects = {},       -- [key] = object      key = listId .. "#" .. itemId
    keyInfo = {},       -- [key] = { listId, item }
    pending = {},       -- [key] = true: pickup sent, waiting for the server
    suspended = false,  -- the editor hides the gameplay objects
    loop = nil,         -- { key, sound } proximity loop of the nearest item
}

local C = Collect

local function key(listId, itemId) return listId .. "#" .. itemId end

local function destroyObject(k)
    local o = C.objects[k]
    if isElement(o) then destroyElement(o) end
    C.objects[k] = nil
    C.keyInfo[k] = nil
end

---------------------------------------------------------------------------- proximity loop

local function stopLoop()
    local l = C.loop
    if l and isElement(l.sound) then destroyElement(l.sound) end
    C.loop = nil
end

local function soundTick()
    if C.suspended or getElementData(localPlayer, "loaded") ~= true then return stopLoop() end
    local px, py, pz = getElementPosition(localPlayer)
    local bestKey, bestInfo, bestD
    for k, info in pairs(C.keyInfo) do         -- streamed items only: same dimension / interior, within STREAM_IN
        local list = C.lists[info.listId]
        if list and list.sound and list.sound ~= "" and not C.pending[k] then
            local it = info.item
            local d = getDistanceBetweenPoints3D(px, py, pz, it.x, it.y, it.z)
            if d < COLLECT.SOUND_RANGE and (not bestD or d < bestD) then
                bestKey, bestInfo, bestD = k, info, d
            end
        end
    end
    if not bestKey then return stopLoop() end
    if C.loop and C.loop.key == bestKey and isElement(C.loop.sound) then return end
    stopLoop()
    local it = bestInfo.item
    local snd = playSound3D(COLLECT.SOUND_FOLDER .. C.lists[bestInfo.listId].sound, it.x, it.y, it.z, true)
    if not snd then return end
    setElementInterior(snd, it.int)
    setElementDimension(snd, it.dim)
    setSoundMinDistance(snd, COLLECT.SOUND_FULL)
    setSoundMaxDistance(snd, COLLECT.SOUND_RANGE)
    setSoundVolume(snd, COLLECT.SOUND_VOLUME)
    C.loop = { key = bestKey, sound = snd }
end

local function destroyAll()
    for k in pairs(C.objects) do destroyObject(k) end
    stopLoop()
end

---------------------------------------------------------------------------- ui_inac menu data

-- { { id, name, event, count, total }, ... } as local element data; ui_inac rebuilds its Collectibles menu from it
local function publishMenuData()
    local out = {}
    for _, id in ipairs(C.order) do
        local l = C.lists[id]
        if l then out[#out + 1] = { id = id, name = l.name, event = l.event, count = l.found, total = l.total } end
    end
    setElementData(localPlayer, COLLECT.DATA_KEY, out, false)
end

---------------------------------------------------------------------------- streaming

local function streamTick()
    if C.suspended then return end
    local px, py = getElementPosition(localPlayer)
    local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)
    for _, id in ipairs(C.order) do
        local list = C.lists[id]
        for itemId, it in pairs(list and list.items or {}) do
            local k = key(id, itemId)
            local d = getDistanceBetweenPoints2D(px, py, it.x, it.y)
            local here = it.dim == dim and it.int == int
            local obj = C.objects[k]
            if obj then
                if not here or d > COLLECT.STREAM_OUT then destroyObject(k) end
            elseif here and d <= COLLECT.STREAM_IN and not C.pending[k] then
                local o = createObject(it.model, it.x, it.y, it.z, it.rx, it.ry, it.rz)
                if o then
                    setElementInterior(o, it.int)
                    setElementDimension(o, it.dim)
                    setElementCollisionsEnabled(o, false)
                    C.objects[k] = o
                    C.keyInfo[k] = { listId = id, item = it, spin = list.spin }
                end
            end
        end
    end
end

local function pickupTick()
    if C.suspended or isPedDead(localPlayer) or getElementData(localPlayer, "loaded") ~= true then return end
    local px, py, pz = getElementPosition(localPlayer)
    for k, info in pairs(C.keyInfo) do
        local it = info.item
        if not C.pending[k] and getDistanceBetweenPoints3D(px, py, pz, it.x, it.y, it.z) < COLLECT.PICKUP_RANGE then
            C.pending[k] = true
            if C.loop and C.loop.key == k then stopLoop() end
            local o = C.objects[k]
            if isElement(o) then destroyElement(o) end
            C.objects[k] = nil
            C.keyInfo[k] = nil
            triggerServerEvent("v_collectibles:collect", resourceRoot, info.listId, it.id)
        end
    end
end

local spinAngle = 0
addEventHandler("onClientPreRender", root, function(dt)
    if C.suspended then return end
    spinAngle = (spinAngle + COLLECT.SPIN_SPEED * dt / 1000) % 360
    for k, info in pairs(C.keyInfo) do
        if info.spin then
            local o = C.objects[k]
            if isElement(o) and isElementStreamedIn(o) then
                setElementRotation(o, info.item.rx, info.item.ry, (info.item.rz + spinAngle) % 360)
            end
        end
    end
end)

---------------------------------------------------------------------------- server events

addEvent("v_collectibles:sync", true)
addEventHandler("v_collectibles:sync", resourceRoot, function(data)
    destroyAll()
    C.lists, C.order, C.pending = {}, {}, {}
    for _, l in ipairs(type(data) == "table" and data or {}) do
        local items = {}
        for _, it in ipairs(l.items or {}) do items[it.id] = it end
        C.lists[l.id] = { id = l.id, name = l.name, event = l.event, spin = l.spin, sound = l.sound,
            total = l.total, found = l.found, items = items }
        C.order[#C.order + 1] = l.id
    end
    publishMenuData()
    streamTick()
end)

addEvent("v_collectibles:collected", true)
addEventHandler("v_collectibles:collected", resourceRoot, function(listId, itemId, count, total)
    local k = key(listId, itemId)
    C.pending[k] = nil
    local list = C.lists[listId]
    if not list then return end
    list.items[itemId] = nil
    list.found, list.total = count, total
    publishMenuData()
    uicore:setBanner(list.name, L("v_collectibles.main.progress", { count = count, total = total }))
end)

-- the server refused (too far / lag): the item comes back
addEvent("v_collectibles:rejected", true)
addEventHandler("v_collectibles:rejected", resourceRoot, function(listId, itemId)
    C.pending[key(listId, tonumber(itemId) or 0)] = nil
end)

---------------------------------------------------------------------------- editor hooks

function Collect.suspend(on)
    C.suspended = on and true or false
    if on then destroyAll() else streamTick() end
end

---------------------------------------------------------------------------- start

setTimer(streamTick, COLLECT.STREAM_MS, 0)
setTimer(pickupTick, COLLECT.PICKUP_MS, 0)
setTimer(soundTick, COLLECT.SOUND_MS, 0)

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("v_collectibles:clientReady", resourceRoot)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    setElementData(localPlayer, COLLECT.DATA_KEY, false, false)
end)
