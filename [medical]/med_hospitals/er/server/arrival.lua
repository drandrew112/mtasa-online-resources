-- ER arrival: the EMS handover (server/handover.lua) asks ER.gateHandover before the 5 s progress and
-- calls ER.receivePatient instead of removing the patient, while the hospital's ER has staff:
--   * a short description of the patient is mandatory (ui_core text input on the medic's client);
--     it goes into the anamnesis and the EMS case sheet ("Mi történt?")
--   * no free corridor spot (F1-F5) = no handover: the medic is told to go to another hospital
--   * the patient moves onto a new hospital stretcher on a free corridor spot with every medsys
--     parameter kept; the EMS stretcher stays empty with the crew

local MIN_TEXT = 15
local MAX_TEXT = 300
local TEXT_VALID = 180000   -- ms a typed description stays valid for the next handover
local ASK_AGAIN = 12000     -- ms before the text input is offered again

local texts = {}            -- [player] = { text, at }
local asking = {}           -- [player] = tick

addEvent("hosp:er:handoverText", true)
addEventHandler("hosp:er:handoverText", resourceRoot, function(text)
    local player = client
    asking[player] = nil
    if type(text) ~= "string" then return end
    text = text:gsub("[%c]", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if #text < MIN_TEXT then
        ER.notify(player, L.forPlayer(player, "med_hospitals.er.description_too_short", { min = MIN_TEXT }), true)
        return
    end
    texts[player] = { text = text:sub(1, MAX_TEXT), at = getTickCount() }
end)

addEventHandler("onPlayerQuit", root, function() texts[source], asking[source] = nil, nil end)

-- Nearest other hospital that can take the patient (has free spots or no ER staff)
local function alternative(h)
    local best, bestD
    for _, other in ipairs(Hospitals.list) do
        if other ~= h then
            local ok = not ER.active(other.id) or ER.freeCorridorCount(other.id) > 0
            if ok then
                local d = getDistanceBetweenPoints2D(h.x, h.y, other.x, other.y)
                if not bestD or d < bestD then best, bestD = other, d end
            end
        end
    end
    return best
end

-- a hospital transfer (ERM task meta.kind "transfer"): the request's note is the handover text
local function transferTask(player)
    if not ER.running("med_erm") then return nil end
    local unit = exports.med_erm:getUnitData(player)
    local task = unit and unit.task and unit.task ~= 0 and exports.med_erm:getTask(unit.task)
    local meta = type(task) == "table" and task.meta
    return type(meta) == "table" and meta.kind == "transfer" and meta or nil
end

local function transferText(meta)
    local from = Hospitals.byId[meta.from]
    local text = L.text("med_hospitals.erc.transfer_handover_text", { from = from and from.name or "?", class = meta.transferClass or "" })
    if type(meta.note) == "string" and meta.note ~= "" then text = text .. " " .. meta.note end
    return text
end

-- -> true, data | false, reason (refused, shown once) | false, nil (waiting for the description)
function ER.gateHandover(player, point, data)
    local h = point.hospital
    if getElementType(data.patient) == "player" then return true, data end -- player patients: old way

    if ER.active(h.id) and not ER.freeCorridorSpot(h.id) then
        local alt = alternative(h)
        local text = alt and L.forPlayer(player, "med_hospitals.er.no_free_place_go_to", { name = h.name, other = alt.name })
            or L.forPlayer(player, "med_hospitals.er.no_free_place", { name = h.name })
        ER.notify(player, text, true)
        return false, text
    end

    local t = texts[player]
    if t and getTickCount() - t.at <= TEXT_VALID then
        data.text = t.text
        return true, data
    end
    local tm = transferTask(player)
    if tm then
        data.text = transferText(tm)
        texts[player] = { text = data.text, at = getTickCount(), transfer = tm }
        return true, data
    end
    if not asking[player] or getTickCount() - asking[player] > ASK_AGAIN then
        asking[player] = getTickCount()
        triggerClientEvent(player, "hosp:er:askHandoverText", resourceRoot, MAX_TEXT)
    end
    return false, nil
end

-- The handover finished (server/handover.lua completeProc). -> true when the ER took the patient.
function ER.receivePatient(h, player, patient, emsStretcher, unit, taskId)
    if not ER.active(h.id) or not isElement(patient) or getElementType(patient) ~= "ped" then return false end
    local m = ER.running("med_equipments") and exports.med_equipments
    if not m then return false end
    local idx, spot = ER.freeCorridorSpot(h.id)
    if not spot then return false end

    local obj, err = m:createHospitalStretcher(h.id, spot.x, spot.y, spot.z, spot.rot or 180, h.dimension, h.interior)
    if not obj then
        -- limit: reuse an empty, idle one
        for _, other in ipairs(ER.stretchers(h.id)) do
            if not ER.patientOfStretcher(other) and m:getStretcherState(other) == "ground" then
                obj = other
                ER.park(obj, spot)
                break
            end
        end
    end
    if not obj then return false end

    m:takePatientOff(emsStretcher)
    m:putPatientOnStretcher(obj, patient)
    -- admitted: from now on the hospital owns the patient; the scene manager cleanup must not remove it
    setElementData(patient, "hosp.admitted", true, false)

    local t = texts[player]
    texts[player] = nil
    local medics = {}
    for _, name in ipairs(unit and unit.members or {}) do medics[#medics + 1] = type(name) == "table" and name.name or tostring(name) end
    local tm = t and t.transfer
    local c = ER.createCase(patient, h.id, {
        kind = tm and "transfer" or "ems", from = tm and tm.from or nil, transferClass = tm and tm.transferClass or nil, unit = unit and unit.callsign or false, taskId = taskId or false, medics = medics,
        medic = (getElementData(player, "displayName") or getPlayerName(player)), text = t and t.text or "", at = getRealTime().timestamp,
    })
    c.location = "F" .. idx
    c.anamnesis = t and t.text or ""
    -- dead on arrival: on the hospital stretcher as dead, the Physician records the death (Hullakezelés)
    local snap = ER.running("medsys") and exports.medsys:getMedicalState(patient) or {}
    if snap.dead then
        c.dead, c.doa, c.status = true, true, "dead"
        ER.log(c, "doa", "")
    end
    ER.syncCase(c)
    ER.notifyStaff(h.id, function(p)
        if c.doa then return L.forPlayer(p, "med_hospitals.erc.doa_arrived", { unit = unit and unit.callsign or "?", spot = "F" .. idx }) end
        if tm then return L.forPlayer(p, "med_hospitals.erc.transfer_arrived", { name = c.name or "?" }) end
        return L.forPlayer(p, "med_hospitals.er.new_ems_patient", { unit = unit and unit.callsign or "?", spot = "F" .. idx })
    end, true)
    return true
end

-- the old gov_health charge runs only without ER staff (with staff the interventions are paid)
function ER.chargesOldWay(h) return not ER.active(h.id) end
