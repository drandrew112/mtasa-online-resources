-- maps_loader (client): creates the objects of the maps the server sends (server/main.lua).
--
--  * world model removals (removeWorldObject) are applied once for every map, reference counted
--    (two maps removing the same building no longer restore it when one of them stops)
--  * a map's objects exist only while the camera is near it (drawdistance far clip + margin)
--  * indoor objects (settings.json "indoor" boxes) exist only while the camera is near that box
--  * low LOD clones are asked from drawdistance (exports.drawdistance:registerLowLOD) for exterior
--    objects of at least MAPLOADER.LOD_MIN_RADIUS only; small props and indoor objects never get one
--  * copies in other dimensions (loadMapInDimension) are built while the local player is in that dimension
--
-- Record layout: see server/main.lua.

local maps = {}             -- array of { def, active, objects = {element}, zoneObjects = { [zone] = {element} }, zoneOn = {} }
local removals = {}         -- key -> { count, args }
local copyObjects = {}      -- name -> { dim, mode, elements }
local received, reported, loadingStarted = false, false, false
local checkMaps, checkZones   -- defined below

-- the GTA streamer loads models in the background (was in DOUBLE_ZEBRA/client.lua, kept as it was)
engineSetAsynchronousLoading(true, false)

---------------------------------------------------------------------------- helpers

local function drawdistanceRunning()
    local res = getResourceFromName("drawdistance")
    return res and getResourceState(res) == "running"
end

local function farClip()
    if drawdistanceRunning() then
        local ok, v = pcall(function() return exports.drawdistance:getFarClip() end)
        if ok and tonumber(v) then return v end
    end
    return MAPLOADER.ACTIVE_FALLBACK
end

local function boxDistance2D(b, x, y)
    local dx = math.max(b[1] - x, 0, x - b[3])
    local dy = math.max(b[2] - y, 0, y - b[4])
    return math.sqrt(dx * dx + dy * dy)
end

local function boxDistance3D(z, x, y, h)
    local mn, mx = z[1], z[2]
    local dx = math.max(mn[1] - x, 0, x - mx[1])
    local dy = math.max(mn[2] - y, 0, y - mx[2])
    local dz = math.max(mn[3] - h, 0, h - mx[3])
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function hexColor(s)
    s = tostring(s):gsub("#", "")
    local r, g, b, a = tonumber(s:sub(1, 2), 16), tonumber(s:sub(3, 4), 16), tonumber(s:sub(5, 6), 16), tonumber(s:sub(7, 8), 16)
    return r or 255, g or 255, b or 255, a or 255
end

---------------------------------------------------------------------------- objects

-- record -> element. dim: dimension override (copies)
local function createRecord(o, dim)
    local obj = createObject(o[1], o[2], o[3], o[4], o[5], o[6], o[7])
    if not obj then return nil end
    if o[8] ~= 0 then setElementInterior(obj, o[8]) end
    local d = dim or o[9]
    if d ~= 0 then setElementDimension(obj, d) end
    if o[10] ~= 1 then setObjectScale(obj, o[10]) end
    if o[11] ~= 255 then setElementAlpha(obj, o[11]) end
    if o[12] == 0 then setElementCollisionsEnabled(obj, false) end
    if o[13] == 1 then setElementDoubleSided(obj, true) end
    if o[14] ~= -1 then setObjectBreakable(obj, o[14] == 1) end
    if o[15] == 1 then setElementFrozen(obj, true) end
    return obj
end

local function wantsLowLOD(m, o, obj)
    if m.def.lod == "none" or o[8] ~= 0 or o[16] ~= 0 or o[11] ~= 255 then return false end
    local r = getElementRadius(obj)
    return r and r * o[10] >= MAPLOADER.LOD_MIN_RADIUS
end

local function registerLOD(obj)
    if drawdistanceRunning() then
        pcall(function() exports.drawdistance:registerLowLOD(obj) end)
    end
end

local function destroyList(list)
    for i = 1, #list do
        if isElement(list[i]) then destroyElement(list[i]) end
        list[i] = nil
    end
end

local function activate(m)
    if m.active then return end
    m.active = true
    for _, o in ipairs(m.def.objects) do
        if o[16] == 0 or o[17] == 1 then
            local obj = createRecord(o)
            if obj then
                m.objects[#m.objects + 1] = obj
                m.lodCheck[#m.lodCheck + 1] = { obj, o }
                if wantsLowLOD(m, o, obj) then registerLOD(obj) end
            end
        end
    end
    for _, k in ipairs(m.def.markers) do
        local r, g, b, a = hexColor(k[6])
        local mk = createMarker(k[2], k[3], k[4], k[1], k[5], r, g, b, a)
        if mk then
            if k[7] ~= 0 then setElementInterior(mk, k[7]) end
            if k[8] ~= 0 then setElementDimension(mk, k[8]) end
            m.objects[#m.objects + 1] = mk
        end
    end
end

local function setZone(m, zi, on)
    if (m.zoneOn[zi] or false) == on then return end
    m.zoneOn[zi] = on
    local list = m.zoneObjects[zi]
    if on then
        for _, o in ipairs(m.def.objects) do
            if o[16] == zi and o[17] == 0 then
                local obj = createRecord(o)
                if obj then list[#list + 1] = obj end
            end
        end
    else
        destroyList(list)
    end
end

local function deactivate(m)
    if not m.active then return end
    m.active = false
    destroyList(m.objects)
    m.lodCheck = {}
    for zi in pairs(m.zoneObjects) do setZone(m, zi, false) end
end

---------------------------------------------------------------------------- removals

local function removalKey(r)
    return table.concat(r, ",")
end

local function applyRemovals(def)
    for _, r in ipairs(def.removes) do
        local key = removalKey(r)
        local e = removals[key]
        if e then
            e.count = e.count + 1
        else
            removals[key] = { count = 1, r = r }
            removeWorldModel(r[1], r[3], r[4], r[5], r[6], r[7])
            if r[2] and r[2] > 0 and r[2] ~= r[1] then removeWorldModel(r[2], r[3], r[4], r[5], r[6], r[7]) end
        end
    end
end

-- releases one map's references; the world model comes back when nobody else removes it
local function releaseRemovals(def)
    for _, r in ipairs(def.removes) do
        local key = removalKey(r)
        local e = removals[key]
        if e then
            e.count = e.count - 1
            if e.count <= 0 then
                restoreWorldModel(r[1], r[3], r[4], r[5], r[6], r[7])
                if r[2] and r[2] > 0 and r[2] ~= r[1] then restoreWorldModel(r[2], r[3], r[4], r[5], r[6], r[7]) end
                removals[key] = nil
            end
        end
    end
end

local function restoreAllRemovals()
    for key, e in pairs(removals) do
        local r = e.r
        restoreWorldModel(r[1], r[3], r[4], r[5], r[6], r[7])
        if r[2] and r[2] > 0 and r[2] ~= r[1] then restoreWorldModel(r[2], r[3], r[4], r[5], r[6], r[7]) end
        removals[key] = nil
    end
end

---------------------------------------------------------------------------- copies in other dimensions

-- event maps (def.event) exist only while the server has them switched on
local function setEnabled(m, on)
    if m.enabled == on then return end
    m.enabled = on
    if on then
        applyRemovals(m.def)
    else
        deactivate(m)
        releaseRemovals(m.def)
    end
end

local function syncEvents()
    local state = getElementData(resourceRoot, DATA_EVENTS)
    state = type(state) == "table" and state or {}
    for _, m in ipairs(maps) do
        if m.def.event then setEnabled(m, state[m.def.name] == true) end
    end
end

local function syncCopies()
    local dims = getElementData(resourceRoot, DATA_DIMS)
    dims = type(dims) == "table" and dims or {}
    local myDim = getElementDimension(localPlayer)
    for _, m in ipairs(maps) do
        local name = m.def.name
        local byDim = dims[name]
        local mode = type(byDim) == "table" and (byDim[myDim] or byDim[tostring(myDim)]) or nil
        local cur = copyObjects[name]
        if cur and (not mode or cur.dim ~= myDim or cur.mode ~= mode) then
            destroyList(cur.elements)
            copyObjects[name], cur = nil, nil
        end
        if mode and myDim ~= 0 and not cur then
            cur = { dim = myDim, mode = mode, elements = {} }
            for _, o in ipairs(m.def.objects) do
                if mode == "all" or o[8] ~= 0 then
                    local obj = createRecord(o, myDim)
                    if obj then cur.elements[#cur.elements + 1] = obj end
                end
            end
            copyObjects[name] = cur
        end
    end
end

addEventHandler("onClientElementDataChange", resourceRoot, function(key)
    if key == DATA_DIMS then syncCopies() end
    if key == DATA_EVENTS then
        syncEvents()
        checkMaps()
        checkZones()
    end
end, false)
addEventHandler("onClientElementDimensionChange", localPlayer, function() syncCopies() end, false)

---------------------------------------------------------------------------- distance checks

local lastZoneCheck = 0

function checkMaps()
    local cx, cy = getCameraMatrix()
    local range = farClip() + MAPLOADER.ACTIVE_MARGIN
    for _, m in ipairs(maps) do
        local d = boxDistance2D(m.def.bbox, cx, cy)
        if not m.enabled then
            -- switched-off event map: nothing to build
        elseif not m.active and d <= range then
            activate(m)
        elseif m.active and d > range + MAPLOADER.ACTIVE_HYSTERESIS then
            deactivate(m)
        end
    end
end

function checkZones()
    local cx, cy, cz = getCameraMatrix()
    for _, m in ipairs(maps) do
        for zi, z in ipairs(m.def.zones) do
            setZone(m, zi, m.active and boxDistance3D(z, cx, cy, cz) <= z[3])
        end
    end
end

local zoneTimer, mapTimer

local function report()
    if reported or not received or not loadingStarted then return end
    reported = true
    pcall(function() exports.v_loading:resourceReady() end)
end

addEvent(EV_DATA, true)
addEventHandler(EV_DATA, resourceRoot, function(data)
    -- a second payload (server restart of the data) replaces everything
    for _, m in ipairs(maps) do deactivate(m) end
    for name, c in pairs(copyObjects) do destroyList(c.elements); copyObjects[name] = nil end
    restoreAllRemovals()
    maps = {}
    for i, def in ipairs(type(data) == "table" and data.maps or {}) do
        local m = { def = def, enabled = false, active = false, objects = {}, lodCheck = {}, zoneObjects = {}, zoneOn = {} }
        for zi in ipairs(def.zones) do m.zoneObjects[zi] = {} end
        maps[i] = m
    end
    for _, m in ipairs(maps) do
        if not m.def.event then setEnabled(m, true) end
    end
    syncEvents()
    checkMaps()
    checkZones()
    syncCopies()
    if not mapTimer then mapTimer = setTimer(checkMaps, MAPLOADER.CHECK_INTERVAL, 0) end
    if not zoneTimer then zoneTimer = setTimer(checkZones, MAPLOADER.INDOOR_CHECK, 0) end
    received = true
    report()
end)

---------------------------------------------------------------------------- drawdistance cooperation

-- drawdistance (re)started: every active exterior object asks for its low LOD clone again
addEventHandler("onClientResourceStart", root, function(res)
    if getResourceName(res) ~= "drawdistance" then return end
    for _, m in ipairs(maps) do
        for _, pair in ipairs(m.lodCheck) do
            if isElement(pair[1]) and wantsLowLOD(m, pair[2], pair[1]) then registerLOD(pair[1]) end
        end
    end
end)

---------------------------------------------------------------------------- lifecycle

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent(EV_REQUEST, resourceRoot)
    if getElementData(localPlayer, "loaded") then loadingStarted = true end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    restoreAllRemovals()
end)

-- v_loading: ready once the maps are built and the loading screen asked
addEvent("onClientLoadingStarted", true)
addEventHandler("onClientLoadingStarted", root, function() loadingStarted = true report() end)
addEvent("onClientReadyCheck")
addEventHandler("onClientReadyCheck", root, function() loadingStarted = true report() end)

-- exported (client): -> name, ... of the maps whose objects exist right now
function getActiveMaps()
    local out = {}
    for _, m in ipairs(maps) do
        if m.active then out[#out + 1] = m.def.name end
    end
    return out
end

-- exported (client): the settings.json "indoor" boxes of the active maps (all = true: of every map),
-- so other resources can treat them as indoors (wx_snow: no snow on the floors, no snowfall inside).
-- -> array of { minX, minY, minZ, maxX, maxY, maxZ, map = name }
function getIndoorZones(all)
    local out = {}
    for _, m in ipairs(maps) do
        if m.active or all then
            for _, z in ipairs(m.def.zones) do
                local mn, mx = z[1], z[2]
                out[#out + 1] = { mn[1], mn[2], mn[3], mx[1], mx[2], mx[3], map = m.def.name }
            end
        end
    end
    return out
end
