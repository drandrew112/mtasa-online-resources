-- Public API for other resources (see README.md) + admin commands.

local function copyPoint(p)
    if not p then return nil end
    return { x = p.x, y = p.y, z = p.z, size = p.size, rot = p.rot }
end

local function publicHospital(h, full)
    local out = {
        id = h.id, name = h.name, x = h.x, y = h.y, z = h.z,
        interior = h.interior, dimension = h.dimension,
        bays = #h.bays, handoverMarkers = #h.handover, heal = h.heal ~= nil,
    }
    if full then
        out.bays, out.handover = {}, {}
        for i, b in ipairs(h.bays) do
            local p = copyPoint(b)
            p.vehicle = isElement(b.vehicle) and b.vehicle or false
            out.bays[i] = p
        end
        for i, p in ipairs(h.handover) do out.handover[i] = copyPoint(p) end
        out.heal = copyPoint(h.heal) or false
        out.release = copyPoint(h.release) or false
    end
    return out
end

-- getHospitals() -> { { id, name, x, y, z, interior, dimension, bays (count), handoverMarkers (count), heal (bool) }, ... }
function getHospitals()
    local out = {}
    for i, h in ipairs(Hospitals.list) do out[i] = publicHospital(h) end
    return out
end

-- getHospital(id) -> hospital with every point | false
--   bays = { {x, y, z, size, vehicle | false} }, handover = { {x, y, z, size} }, heal, release
function getHospital(id)
    local h = Hospitals.byId[tostring(id)]
    return h and publicHospital(h, true) or false
end

-- getNearestHospital(element | x, y, z) -> id, name, distance | false
-- With an element only hospitals in its interior / dimension count.
function getNearestHospital(x, y, z)
    local int, dim
    if isElement(x) then
        int, dim = getElementInterior(x), getElementDimension(x)
        x, y, z = getElementPosition(x)
    end
    x, y, z = tonumber(x), tonumber(y), tonumber(z) or 0
    if not x or not y then return false end
    local h, dist = findNearestHospital(x, y, z, int, dim)
    if not h then return false end
    return h.id, h.name, dist
end

-- setObjectiveToNearestHospital(player [, label [, keep]]) -> hospitalId, objectiveId | false, error
-- v_radar objective (yellow blip + route) to the nearest hospital's first ambulance bay.
-- Replaces the player's previous hospital objective; removed on arrival, or with keep = true
-- only by removeHospitalObjective.
function setObjectiveToNearestHospital(player, label, keep)
    if not isElement(player) or getElementType(player) ~= "player" then return false, "Invalid player" end
    local x, y, z = getElementPosition(player)
    local h = findNearestHospital(x, y, z, getElementInterior(player), getElementDimension(player))
        or findNearestHospital(x, y, z)
    if not h then return false, "No hospitals" end
    local id, err = setPlayerObjective(player, h, label, keep)
    if not id then return false, err end
    return h.id, id
end

-- setObjectiveToHospital(player, hospitalId [, label [, keep]]) -> objectiveId | false, error
function setObjectiveToHospital(player, hospitalId, label, keep)
    local h = Hospitals.byId[tostring(hospitalId)]
    if not h then return false, "Hospital not found" end
    return setPlayerObjective(player, h, label, keep)
end

-- removeHospitalObjective(player) -> bool
function removeHospitalObjective(player)
    return removePlayerObjective(player)
end

-- getVehicleHospitalBay(vehicle) -> hospitalId, bayIndex | false   (parked in a bay)
function getVehicleHospitalBay(vehicle)
    if not isElement(vehicle) then return false end
    for bay, h in eachPoint("bay") do
        if bay.vehicle == vehicle then return h.id, bay.index end
    end
    return getTutorialVehicleBay(vehicle) -- the private bays of a work_ems tutorial (server/tutorial.lua)
end

-- getUnitHospitalHandover(unitId) -> hospitalId | false   (ERM unit in a hospital handover)
function getUnitHospitalHandover(unitId)
    local h = getActiveHandover(unitId)
    return h and h.id or false
end

-- isPlayerHealing(player) -> bool   (standing in a treatment marker, timer running)
function isPlayerHealing(player)
    return isHealing(player)
end

-- reloadHospitals() -> count | false, error   (re-reads hospitals.json)
function reloadHospitals()
    return loadHospitals()
end

---------------------------------------------------------------- admin commands

local function adminLevel(player)
    if isResourceRunning("v_mysql") then
        return tonumber(exports.v_mysql:getAccData(player, "admin_level")) or 0
    end
    return 0
end

local function isAdmin(player)
    return adminLevel(player) >= HOSP.ADMIN_LEVEL
end

-- /hospreload: re-reads hospitals.json
addCommandHandler("hospreload", function(player)
    if not isAdmin(player) then return end
    local count, err = loadHospitals()
    if count then
        notify(player, count .. " hospital(s) loaded from " .. HOSP.FILE .. ".")
    else
        notify(player, "#e0474cReload failed: #ffffff" .. err)
    end
end)

-- /hosppos [fields]: current position (ground level, for markers; the vehicle's in a vehicle)
-- as a hospitals.json point, printed and copied to the clipboard.
--   /hosppos            { "x": 1179.30, "y": -1308.60, "z": 13.00, "rot": 90 }
--   /hosppos x,y,z      { "x": 1179.30, "y": -1308.60, "z": 13.00 }
--   /hosppos x,y,z,rot  { "x": 1179.30, "y": -1308.60, "z": 13.00, "rot": 90 }
-- fields: x, y, z, rot (rz), int, dim - any order / subset
local POS_FIELDS = {
    x   = { "x",         function(p) return ("%.2f"):format(p.x) end },
    y   = { "y",         function(p) return ("%.2f"):format(p.y) end },
    z   = { "z",         function(p) return ("%.2f"):format(p.z) end },
    rot = { "rot",       function(p) return ("%d"):format(p.rot) end },
    int = { "interior",  function(p) return tostring(p.int) end },
    dim = { "dimension", function(p) return tostring(p.dim) end },
}
POS_FIELDS.rz = POS_FIELDS.rot

addCommandHandler("hosppos", function(player, _, format)
    if not isAdmin(player) then return end
    local vehicle = getPedOccupiedVehicle(player)
    local e = vehicle or player
    local x, y, z = getElementPosition(e)
    local _, _, rz = getElementRotation(e)
    local p = {
        x = x, y = y, z = z - (vehicle and 0.9 or 1.0), -- marker on the ground
        rot = math.floor(rz + 0.5) % 360,
        int = getElementInterior(e), dim = getElementDimension(e),
    }

    if not format or format == "" then format = "x,y,z,rot" end
    local parts = {}
    for field in format:lower():gmatch("[^,%s]+") do
        local f = POS_FIELDS[field]
        if not f then
            notify(player, "Unknown field '" .. field .. "'. Use x, y, z, rot, int, dim - e.g. /hosppos x,y,z,rot")
            return
        end
        parts[#parts + 1] = ('"%s": %s'):format(f[1], f[2](p))
    end
    if #parts == 0 then return end
    local line = "{ " .. table.concat(parts, ", ") .. " }"

    triggerClientEvent(player, "hosp:clipboard", resourceRoot, line)
    notify(player, line .. "  #aaaaaa(copied to clipboard · int " .. p.int .. ", dim " .. p.dim .. ")")
    outputServerLog("[med_hospitals] /hosppos " .. getPlayerName(player) .. ": " .. line)
end)
