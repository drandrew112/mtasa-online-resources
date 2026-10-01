-- Duty markers and duty vehicle markers, created by the work resources through exports.
-- The markers belong to work_core (the client finds them under its resourceRoot) but are
-- destroyed when the work is unregistered or the resource that created them stops.

Markers = {}                       -- marker -> { kind, work, owner, blip, vehicles, spawns }

local function num(v) return tonumber(v) end

local function placeInWorld(el, interior, dimension)
    setElementInterior(el, interior)
    setElementDimension(el, dimension)
end

local function baseMarker(kind, workId, x, y, z, opts, defaultSize, alpha)
    local work = Works[workId]
    if not work then
        outputDebugString(("[work_core] create %s marker: work '%s' is not registered"):format(kind, tostring(workId)), 2)
        return false
    end
    x, y, z = num(x), num(y), num(z)
    if not (x and y and z) then
        outputDebugString("[work_core] create marker: x, y, z expected", 2)
        return false
    end
    opts = type(opts) == "table" and opts or {}

    local size = num(opts.size) or defaultSize
    local c = type(opts.color) == "table" and opts.color or work.color
    local marker = createMarker(x, y, z, "cylinder", size,
        num(c[1]) or 255, num(c[2]) or 255, num(c[3]) or 255, num(c[4]) or alpha)
    if not marker then return false end

    local int, dim = num(opts.interior) or 0, num(opts.dimension) or 0
    placeInWorld(marker, int, dim)
    setElementData(marker, WORK_DATA.MARKER_KIND, kind)
    setElementData(marker, WORK_DATA.MARKER_WORK, workId)

    local m = { marker = marker, kind = kind, work = workId, owner = getCallerResourceName() }
    if num(opts.blip) then
        m.blip = createBlipAttachedTo(marker, num(opts.blip), 2, 255, 255, 255, 255, 0,
            num(opts.blipDistance) or 300)
        if m.blip then placeInWorld(m.blip, int, dim) end
    end
    Markers[marker] = m

    addEventHandler("onElementDestroy", marker, function()
        local data = Markers[source]
        Markers[source] = nil
        if data and isElement(data.blip) then destroyElement(data.blip) end
    end, false)
    return marker, m
end

-- createDutyMarker(workId, x, y, z [, opts]) -> marker | false
--   opts: size, color {r,g,b[,a]} (default: work colour), interior, dimension,
--         blip (icon id), blipDistance
function createDutyMarker(workId, x, y, z, opts)
    local marker = baseMarker("duty", workId, x, y, z, opts, WORK.DUTY_MARKER_SIZE, WORK.DUTY_MARKER_ALPHA)
    return marker or false
end

-- vehicles = { 416, { model = 416, name = "Ambulance", color = { r,g,b, r,g,b, ... },
--                     plate = "EMS", data = { key = value } }, ... }
--   platePrefix = "A-" instead of plate: a unique plate of the prefix + random digits
--   (plateDigits, default: fills the 8 plate characters)
local function normaliseVehicles(list)
    local out = {}
    if type(list) ~= "table" then return out end
    for _, v in ipairs(list) do
        local def = type(v) == "table" and v or { model = v }
        local model = num(def.model or def[1])
        if model and model >= 400 and model <= 611 then
            model = math.floor(model)
            local prefix = def.platePrefix and tostring(def.platePrefix):sub(1, 7) or nil
            if prefix == "" then prefix = nil end
            local room = prefix and 8 - #prefix or 0
            local digits = math.max(1, math.min(room, math.floor(num(def.plateDigits) or room)))
            out[#out + 1] = {
                model = model,
                name = def.name and tostring(def.name) or getVehicleNameFromModel(model),
                color = type(def.color) == "table" and def.color or nil,
                plate = def.plate and tostring(def.plate) or nil,
                platePrefix = prefix,
                plateDigits = prefix and digits or nil,
                data = type(def.data) == "table" and def.data or nil,
            }
        end
    end
    return out
end

-- spawns = { x, y, z, rz } | { { x, y, z, rz }, ... }  (also accepts x=, y=, z=, rot=)
local function normaliseSpawns(spawns, x, y, z, rot)
    local list = {}
    if type(spawns) == "table" then
        local single = num(spawns[1] or spawns.x) and true or false
        for _, s in ipairs(single and { spawns } or spawns) do
            if type(s) == "table" then
                local sx, sy, sz = num(s[1] or s.x), num(s[2] or s.y), num(s[3] or s.z)
                if sx and sy and sz then
                    list[#list + 1] = { sx, sy, sz, num(s[4] or s.rot or s.rz) or 0 }
                end
            end
        end
    end
    if #list == 0 then
        list[1] = { x, y, z + WORK.SPAWN_Z_OFFSET, rot or 0 }
    end
    return list
end

-- createDutyVehicleMarker(workId, x, y, z, vehicles [, opts]) -> marker | false
--   Only players on duty in the work see and use it (opts.public = true: everyone sees it).
--   opts: size, color, interior, dimension, blip, blipDistance, public,
--         spawns (one point or a list; the first free one is used; default: the marker),
--         rotation (vehicle rotation when spawning at the marker)
function createDutyVehicleMarker(workId, x, y, z, vehicles, opts)
    local list = normaliseVehicles(vehicles)
    if #list == 0 then
        outputDebugString(("[work_core] createDutyVehicleMarker(%s): no valid vehicle models"):format(tostring(workId)), 2)
        return false
    end
    opts = type(opts) == "table" and opts or {}
    local marker, m = baseMarker("vehicle", workId, x, y, z, opts, WORK.VEHICLE_MARKER_SIZE, WORK.VEHICLE_MARKER_ALPHA)
    if not marker then return false end

    m.vehicles = list
    m.spawns = normaliseSpawns(opts.spawns or opts.spawn, num(x), num(y), num(z), num(opts.rotation))
    local public = {}
    for i, v in ipairs(list) do public[i] = { model = v.model, name = v.name } end
    setElementData(marker, WORK_DATA.MARKER_VEHICLES, public)

    if not opts.public then
        setElementVisibleToWork(marker, workId)
        if m.blip then setElementVisibleToWork(m.blip, workId) end
    end
    return marker
end

function destroyWorkMarker(marker)
    if not Markers[marker] or not isElement(marker) then return false end
    return destroyElement(marker)
end

function getWorkMarkers(workId)
    local list = {}
    for marker, m in pairs(Markers) do
        if (workId == nil or m.work == workId) and isElement(marker) then
            list[#list + 1] = marker
        end
    end
    return list
end

function destroyMarkersOfWork(workId)
    for marker, m in pairs(Markers) do
        if m.work == workId and isElement(marker) then destroyElement(marker) end
    end
end

function destroyMarkersOfOwner(resourceName)
    for marker, m in pairs(Markers) do
        if m.owner == resourceName and isElement(marker) then destroyElement(marker) end
    end
end

-- Is the player (close enough to be) inside the marker? Lag tolerant, used for requests.
function isPlayerAtMarker(player, marker)
    if not isElement(marker) or not Markers[marker] then return false end
    if getElementDimension(player) ~= getElementDimension(marker)
        or getElementInterior(player) ~= getElementInterior(marker) then
        return false
    end
    local e = getPedOccupiedVehicle(player) or player
    local px, py, pz = getElementPosition(e)
    local x, y, z = getElementPosition(marker)
    local radius = getMarkerSize(marker) / 2 + WORK.REQUEST_EXTRA_RADIUS
    return getDistanceBetweenPoints2D(px, py, x, y) <= radius and math.abs(pz - z) <= WORK.MARKER_HEIGHT + 2
end

---------------------------------------------------------------- /workpos

local function isAdmin(player)
    local ok, level = pcall(function() return exports.v_mysql:getAccData(player, "admin_level") end)
    return ok and (tonumber(level) or 0) >= WORK.ADMIN_LEVEL
end

-- /workpos: on foot the ground position (marker), in a vehicle its centre + rotation (spawn).
-- Printed to the console and copied to the clipboard.
addCommandHandler("workpos", function(player)
    if not isAdmin(player) then return end
    local vehicle = getPedOccupiedVehicle(player)
    local e = vehicle or player
    local x, y, z = getElementPosition(e)
    local _, _, rz = getElementRotation(e)
    local text
    if vehicle then
        text = ("{ %.2f, %.2f, %.2f, %d }"):format(x, y, z, math.floor(rz + 0.5) % 360)
    else
        text = ("%.2f, %.2f, %.2f"):format(x, y, z - 1)
    end
    local int, dim = getElementInterior(e), getElementDimension(e)
    if int ~= 0 or dim ~= 0 then
        text = text .. ("  -- interior = %d, dimension = %d"):format(int, dim)
    end
    outputConsole("[workpos] " .. text, player)
    outputChatBox("[workpos] " .. text .. " (vágólapra másolva)", player, 200, 200, 200)
    if isPlayerReady(player) then
        triggerClientEvent(player, "work:clipboard", resourceRoot, text)
    end
end)
