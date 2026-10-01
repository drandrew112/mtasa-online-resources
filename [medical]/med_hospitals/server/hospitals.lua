-- Loads hospitals.json and builds the world elements of every hospital:
--   bays      ambulance parking markers (handover status of the unit, server/handover.lua)
--   handover  stretcher handover markers (patient handed over, server/handover.lua)
--   heal      free treatment marker (server/heal.lua)
--
-- hospital = { id, name, interior, dimension, x, y, z (objective point),
--              bays = { point }, handover = { point }, heal = point | nil, release = point | nil }
-- point    = { hospital, kind, index, x, y, z, size, marker, col }   (+ bay: vehicle, parked)

Hospitals = {
    list = {},      -- in file order
    byId = {},
}

local elements = {} -- every element created for the hospitals (destroyed on reload)

-- Functions run before the hospitals are rebuilt (running processes reference the old points)
UnloadHandlers = {}

function isResourceRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

-- Progress bar under a marker's 3D label, for one player (client/labels.lua)
function startProgress(player, marker, duration, text)
    triggerClientEvent(player, "hosp:progress", resourceRoot, marker, duration, text)
end

function stopProgress(player)
    if isElement(player) then triggerClientEvent(player, "hosp:progressStop", resourceRoot) end
end

function notify(player, text)
    if isElement(player) and getElementType(player) == "player" then
        outputChatBox("#e0474c[Hospital] #ffffff" .. text, player, 255, 255, 255, true)
    end
end

local function track(element)
    if element then elements[#elements + 1] = element end
    return element
end

local function inWorld(element, h)
    setElementInterior(element, h.interior)
    setElementDimension(element, h.dimension)
    return element
end

-- Is the element in this point's colshape (and in the hospital's world)?
function isInPoint(element, point)
    if not isElement(element) or not isElement(point.col) then return false end
    local h = point.hospital
    return getElementDimension(element) == h.dimension and getElementInterior(element) == h.interior
        and isElementWithinColShape(element, point.col)
end

-- Elements of a type inside the point, in the hospital's world.
function elementsInPoint(point, elementType)
    local out = {}
    if not isElement(point.col) then return out end
    local h = point.hospital
    for _, e in ipairs(getElementsWithinColShape(point.col, elementType)) do
        if getElementDimension(e) == h.dimension and getElementInterior(e) == h.interior then
            out[#out + 1] = e
        end
    end
    return out
end

---------------------------------------------------------------- loading

local function readFile(path)
    if not fileExists(path) then return nil, path .. " not found" end
    local f = fileOpen(path, true)
    if not f then return nil, "cannot open " .. path end
    local text = fileRead(f, fileGetSize(f))
    fileClose(f)
    return text
end

local function parsePoint(raw, defaultSize)
    if type(raw) ~= "table" then return nil end
    local x, y, z = tonumber(raw.x), tonumber(raw.y), tonumber(raw.z)
    if not x or not y or not z then return nil end
    return { x = x, y = y, z = z, size = tonumber(raw.size) or defaultSize, rot = tonumber(raw.rot) or 0 }
end

local function parseHospital(raw, index)
    if type(raw) ~= "table" then return nil, "entry #" .. index .. " is not an object" end
    local id = tostring(raw.id or ""):gsub("%s", "")
    if id == "" then return nil, "entry #" .. index .. " has no id" end
    local name = tostring(raw.name or "")
    if name == "" then name = id end

    local h = {
        id = id,
        name = name,
        interior = tonumber(raw.interior) or 0,
        dimension = tonumber(raw.dimension) or 0,
        bays = {},
        handover = {},
    }
    for i, p in ipairs(type(raw.bays) == "table" and raw.bays or {}) do
        local point = parsePoint(p, HOSP.BAY_SIZE)
        if not point then return nil, id .. ": bay #" .. i .. " needs x, y, z" end
        h.bays[#h.bays + 1] = point
    end
    for i, p in ipairs(type(raw.handover) == "table" and raw.handover or {}) do
        local point = parsePoint(p, HOSP.HANDOVER_SIZE)
        if not point then return nil, id .. ": handover #" .. i .. " needs x, y, z" end
        h.handover[#h.handover + 1] = point
    end
    if raw.heal ~= nil then
        h.heal = parsePoint(raw.heal, HOSP.HEAL_SIZE)
        if not h.heal then return nil, id .. ": heal needs x, y, z" end
    end
    if raw.release ~= nil then
        h.release = parsePoint(raw.release, 0)
        if not h.release then return nil, id .. ": release needs x, y, z" end
    end

    -- objective point: the first bay (ambulances), else the heal / handover marker
    local main = h.bays[1] or h.heal or h.handover[1]
    if not main then return nil, id .. ": no bays, handover or heal marker" end
    h.x, h.y, h.z = main.x, main.y, main.z
    return h
end

---------------------------------------------------------------- world elements

local function buildPoint(h, point, kind, index, color)
    point.hospital, point.kind, point.index = h, kind, index
    local marker = track(createMarker(point.x, point.y, point.z, "cylinder", point.size,
        color[1], color[2], color[3], color[4]))
    local radius = point.size / 2 + 0.6
    local height = kind == "bay" and HOSP.BAY_HEIGHT or 3
    local col = track(createColTube(point.x, point.y, point.z - 1, radius, height))
    if not marker or not col then return false end
    inWorld(marker, h)
    inWorld(col, h)
    setElementData(marker, HOSP_DATA.KIND, kind)
    setElementData(marker, HOSP_DATA.NAME, h.name)
    point.marker, point.col = marker, col
    return true
end

local function buildHospital(h)
    for i, bay in ipairs(h.bays) do
        buildPoint(h, bay, "bay", i, HOSP.BAY_COLOR)
        bay.vehicle, bay.parked = nil, false
        setElementData(bay.marker, HOSP_DATA.OCCUPIED, false)
    end
    for i, point in ipairs(h.handover) do
        buildPoint(h, point, "handover", i, HOSP.HANDOVER_COLOR)
    end
    if h.heal then buildPoint(h, h.heal, "heal", 1, HOSP.HEAL_COLOR) end
end

-- Bay visuals: an occupied bay's marker is invisible (alpha 0).
function setBayOccupied(bay, occupied)
    if not isElement(bay.marker) then return end
    local c = HOSP.BAY_COLOR
    setMarkerColor(bay.marker, c[1], c[2], c[3], occupied and 0 or c[4])
    setElementData(bay.marker, HOSP_DATA.OCCUPIED, occupied and true or false)
end

local function destroyAll()
    for _, e in ipairs(elements) do
        if isElement(e) then destroyElement(e) end
    end
    elements = {}
end

-- (Re)loads hospitals.json. Returns count | false, error. On error the old hospitals stay.
function loadHospitals()
    local text, err = readFile(HOSP.FILE)
    if not text then return false, err end
    local data = fromJSON(text)
    if type(data) ~= "table" or type(data.hospitals) ~= "table" then
        return false, HOSP.FILE .. ": invalid JSON or missing \"hospitals\" array"
    end

    local list, byId = {}, {}
    for i, raw in ipairs(data.hospitals) do
        local h, perr = parseHospital(raw, i)
        if not h then return false, HOSP.FILE .. ": " .. perr end
        if byId[h.id] then return false, HOSP.FILE .. ": duplicate id \"" .. h.id .. "\"" end
        list[#list + 1] = h
        byId[h.id] = h
    end

    for _, fn in ipairs(UnloadHandlers) do fn() end
    destroyAll()
    Hospitals.list, Hospitals.byId = list, byId
    for _, h in ipairs(list) do buildHospital(h) end
    return #list
end

-- Iterates every point of a kind: for point, hospital in eachPoint("bay") do ... end
function eachPoint(kind)
    local out = {}
    for _, h in ipairs(Hospitals.list) do
        if kind == "bay" then
            for _, p in ipairs(h.bays) do out[#out + 1] = p end
        elseif kind == "handover" then
            for _, p in ipairs(h.handover) do out[#out + 1] = p end
        elseif kind == "heal" and h.heal then
            out[#out + 1] = h.heal
        end
    end
    local i = 0
    return function()
        i = i + 1
        local p = out[i]
        if p then return p, p.hospital end
    end
end

addEventHandler("onResourceStart", resourceRoot, function()
    -- elements created during the start reach the clients later than handlers expect;
    -- build once the start has finished (same as med_stretcher)
    setTimer(function()
        local count, err = loadHospitals()
        if count then
            outputDebugString("[med_hospitals] " .. count .. " hospital(s) loaded")
        else
            outputDebugString("[med_hospitals] " .. err, 1)
        end
    end, 500, 1)
end)
