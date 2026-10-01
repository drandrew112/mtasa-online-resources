-- Tutorial handovers (work_ems tutorial): a private copy of one hospital's bay and handover
-- markers in another dimension, for a single player. There is no ERM unit and no case: a patient
-- pushed on the stretcher of the given ambulance into the handover marker is handed over after
-- HOSP.HANDOVER_TIME. Bays only look like the real ones (no handover status, no fines).
--
-- createTutorialHandover(player, hospitalId, dimension [, vehicle]) -> id | false, error
-- destroyTutorialHandover(id) -> bool
-- Event onHospitalTutorialHandover (id, patient, hospitalId), source = the player. Fired before
-- the patient is removed: a ped is destroyed, a player patient is taken off the stretcher.

addEvent("onHospitalTutorialHandover", false)

local sessions = {}   -- id -> { id, player, hospital, dimension, interior, vehicle, bays, handover, elements, proc, refused }
local byPlayer = {}   -- player -> id
local nextId = 0

local function buildTutorialPoint(t, raw, kind, color)
    local marker = createMarker(raw.x, raw.y, raw.z, "cylinder", raw.size, color[1], color[2], color[3], color[4], t.player)
    local radius = raw.size / 2 + 0.6
    local col = createColTube(raw.x, raw.y, raw.z - 1, radius, kind == "bay" and HOSP.BAY_HEIGHT or 3)
    if not marker or not col then
        if marker then destroyElement(marker) end
        if col then destroyElement(col) end
        return nil
    end
    for _, e in ipairs({ marker, col }) do
        setElementDimension(e, t.dimension)
        setElementInterior(e, t.interior)
        t.elements[#t.elements + 1] = e
    end
    setElementData(marker, HOSP_DATA.KIND, kind)
    setElementData(marker, HOSP_DATA.NAME, t.hospital.name)
    if kind == "bay" then setElementData(marker, HOSP_DATA.OCCUPIED, false) end
    return { marker = marker, col = col, kind = kind }
end

local function inTutorialPoint(t, element, point)
    return isElement(element) and getElementDimension(element) == t.dimension
        and getElementInterior(element) == t.interior and isElementWithinColShape(element, point.col)
end

function destroyTutorialHandover(id)
    local t = sessions[tonumber(id) or -1]
    if not t then return false end
    sessions[t.id] = nil
    if byPlayer[t.player] == t.id then byPlayer[t.player] = nil end
    if t.proc then stopProgress(t.player) end
    for _, e in ipairs(t.elements) do
        if isElement(e) then destroyElement(e) end
    end
    return true
end

function createTutorialHandover(player, hospitalId, dimension, vehicle)
    if not isElement(player) or getElementType(player) ~= "player" then return false, "invalid player" end
    local h = Hospitals.byId[tostring(hospitalId)]
    if not h then return false, "unknown hospital" end
    if #h.handover == 0 then return false, h.id .. " has no handover marker" end
    dimension = tonumber(dimension)
    if not dimension then return false, "invalid dimension" end

    if byPlayer[player] then destroyTutorialHandover(byPlayer[player]) end
    nextId = nextId + 1
    local t = {
        id = nextId, player = player, hospital = h,
        dimension = dimension, interior = h.interior,
        vehicle = isElement(vehicle) and vehicle or nil,
        bays = {}, handover = {}, elements = {},
    }
    for _, raw in ipairs(h.bays) do
        local p = buildTutorialPoint(t, raw, "bay", HOSP.BAY_COLOR)
        if p then t.bays[#t.bays + 1] = p end
    end
    for _, raw in ipairs(h.handover) do
        local p = buildTutorialPoint(t, raw, "handover", HOSP.HANDOVER_COLOR)
        if p then t.handover[#t.handover + 1] = p end
    end
    sessions[t.id] = t
    byPlayer[player] = t.id
    return t.id
end

-- -> true, obj, patient | false, reason
local function checkTutorialHandover(t)
    local player = t.player
    local obj = getElementData(player, "stretcher.pushing")
    if not isElement(obj) or not isResourceRunning("med_stretcher") then
        return false, "Bring the patient here on the stretcher."
    end
    local ms = exports.med_stretcher
    if ms:getStretcherState(obj) ~= "pushing" then return false, "Bring the patient here on the stretcher." end
    local patient = ms:getStretcherPatient(obj)
    if not isElement(patient) or ms:getPatientStretcher(patient) ~= obj then
        return false, "There is no patient on the stretcher."
    end
    if t.vehicle and ms:getStretcherVehicle(obj) ~= t.vehicle then
        return false, "Use the stretcher of your ambulance."
    end
    return true, obj, patient
end

local function complete(t)
    local p = t.proc
    t.proc = nil
    stopProgress(t.player)
    triggerEvent("onHospitalTutorialHandover", t.player, t.id, p.patient, t.hospital.id)
    if isElement(p.obj) then exports.med_stretcher:takePatientOff(p.obj) end
    if isElement(p.patient) and getElementType(p.patient) == "ped" then destroyElement(p.patient) end
end

local function updateSession(t)
    local player = t.player
    for _, bay in ipairs(t.bays) do
        local occupied = t.vehicle and inTutorialPoint(t, t.vehicle, bay) or false
        if occupied ~= bay.occupied then
            bay.occupied = occupied
            local c = HOSP.BAY_COLOR
            setMarkerColor(bay.marker, c[1], c[2], c[3], occupied and 0 or c[4])
            setElementData(bay.marker, HOSP_DATA.OCCUPIED, occupied)
        end
    end

    local inside
    if not isPedDead(player) and not getPedOccupiedVehicle(player) then
        for _, point in ipairs(t.handover) do
            if inTutorialPoint(t, player, point) then inside = point break end
        end
    end
    if not inside then
        if t.proc then
            t.proc = nil
            stopProgress(player)
            notify(player, "Handover cancelled: you left the handover marker.")
        end
        t.refused = nil
        return
    end

    local ok, obj, patient = checkTutorialHandover(t)
    if t.proc then
        if not ok or obj ~= t.proc.obj or patient ~= t.proc.patient then
            t.proc = nil
            stopProgress(player)
            notify(player, "Handover cancelled: " .. (ok and "the patient changed." or obj))
            t.refused = inside
        elseif getTickCount() >= t.proc.ends then
            complete(t)
        end
    elseif ok then
        t.refused = nil
        t.proc = { obj = obj, patient = patient, ends = getTickCount() + HOSP.HANDOVER_TIME }
        startProgress(player, inside.marker, HOSP.HANDOVER_TIME, "Handing over the patient")
    elseif t.refused ~= inside then
        t.refused = inside
        notify(player, obj)
    end
end

addEventHandler("onResourceStart", resourceRoot, function()
    setTimer(function()
        for id, t in pairs(sessions) do
            if isElement(t.player) then
                updateSession(t)
            else
                destroyTutorialHandover(id)
            end
        end
    end, HOSP.TICK, 0)
end)

addEventHandler("onPlayerQuit", root, function()
    if byPlayer[source] then destroyTutorialHandover(byPlayer[source]) end
end)
