-- ER (sürgősségi osztály) module core: per-hospital state from hospitals.json "er", the staff on duty
-- (work_hospital), the patient cases (one per ped, mirrored to the synced element data "er.case"),
-- corridor spots, the stretcher point and stretcher parking (bays).
--
-- case = { id, ped, hospital (id), name, gender, birth, age, arrival = { kind, unit, taskId, medics,
--          text, at }, triage (0 = none), treating = player | false, treatingName, location, status,
--          created, events = { { at, kind, text, by } } }

ER = {
    byHospital = {},   -- [hospitalId] = { h, cfg, markers = {}, menuIds = {} }
    cases = {},        -- [ped] = case
    nextId = 1,
    MARKER_ALPHA = 200, -- every ER marker (stretcher point, ward / ICU / OR / morgue handover points)
}

local ER_DATA = "er.case"
local parking = {} -- [stretcher] = true while we park it (its settle event is ours)

local function running(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end
ER.running = running

---------------------------------------------------------------- staff

function ER.staff(hospitalId)
    if not running("work_hospital") then return {} end
    return exports.work_hospital:getHospitalStaff(hospitalId) or {}
end

function ER.isStaff(player, hospitalId)
    return isElement(player) and getElementType(player) == "player" and running("work_hospital")
        and exports.work_hospital:isHospitalStaff(player, hospitalId) == true
end

-- er.* rank check: true | false, need name
function ER.can(player, activity)
    if not running("work_hospital") then return false end
    local ok, _, needName = exports.work_hospital:canStaffPerform(player, activity)
    return ok == true, needName
end

-- Is the ER of the hospital working (has an er block and staff on duty)?
function ER.active(hospitalId)
    local e = ER.byHospital[hospitalId]
    return e ~= nil and #ER.staff(hospitalId) > 0
end

-- points: the base (code table) points. The player gets them * ERC.POINT_MULT; the case's pointsTotal
-- keeps the base: it is the care value the state pays at the close (er/server/pay.lua) and the base of
-- the treating doctor's case bonus (which is multiplied again when it is paid).
-- c (optional): the case
function ER.points(player, code, points, label, c)
    points = tonumber(points) or 0
    if type(c) == "table" then c.pointsTotal = (c.pointsTotal or 0) + points end
    local paid = math.floor(points * (ERC.POINT_MULT or 1) + 0.5)
    if running("work_hospital") then exports.work_hospital:addHospitalPoints(player, code, paid, label) end
end

---------------------------------------------------------------- notifications (ui_core on the client)

function ER.notify(player, text, alert)
    if isElement(player) and getElementType(player) == "player" then
        triggerClientEvent(player, "hosp:er:notify", resourceRoot, text, alert == true)
    end
end

-- text: a function(player) -> string (so each player gets their own language), or a string
function ER.notifyStaff(hospitalId, text, alert, except)
    for _, p in ipairs(ER.staff(hospitalId)) do
        if p ~= except then ER.notify(p, type(text) == "function" and text(p) or text, alert) end
    end
end

---------------------------------------------------------------- cases

local function caseView(c)
    local open = 0
    for _, o in ipairs(c.orders or {}) do if o.status ~= "done" then open = open + 1 end end
    return {
        orders = open,
        id = c.id, hospital = c.hospital, name = c.name, triage = c.triage, treating = c.treatingName or false,
        status = c.status, location = c.location, age = c.age, gender = c.gender, dead = c.dead or false,
    }
end

function ER.syncCase(c)
    if isElement(c.ped) then setElementData(c.ped, ER_DATA, caseView(c)) end
    if ERDB then ERDB.saveCase(c) end
    if ER.onCaseChanged then ER.onCaseChanged(c) end
end

-- the patient pathway (betegút): in the case and in hosp_events
function ER.log(c, kind, text, by)
    local actor = isElement(by) and (getElementData(by, "displayName") or getPlayerName(by)) or by or false
    -- staff who worked on the case (work_hospital hosp.patients: the Resident exam needs them)
    if isElement(by) and getElementType(by) == "player" then
        c.staff = c.staff or {}
        c.staff[by] = true
    end
    c.events[#c.events + 1] = { at = getRealTime().timestamp, kind = kind, text = text, by = actor }
    if ERDB then ERDB.event(c, kind, text, actor) end
end

local function ageOf(birth)
    local y, m, d = tostring(birth or ""):match("^(%d%d%d%d)-(%d%d)-(%d%d)")
    if not y then return nil end
    local t = getRealTime()
    local age = (t.year + 1900) - tonumber(y)
    if (t.month + 1) < tonumber(m) or ((t.month + 1) == tonumber(m) and t.monthday < tonumber(d)) then age = age - 1 end
    return age
end

local function setIdentity(c, id)
    if type(id) ~= "table" then return end
    c.name = id.name or c.name
    c.gender = id.gender or c.gender
    c.birth = id.birth or c.birth
    c.age = ageOf(c.birth) or c.age
    c.citizenId = id.cid
    ER.syncCase(c)
end

function ER.createCase(ped, hospitalId, arrival)
    if ER.cases[ped] then return ER.cases[ped] end
    local male = true
    if running("police_system") then
        local ok, g = pcall(function() return exports.police_system:getSkinGender(getElementModel(ped)) end)
        if ok and g then male = g ~= "f" end
    end
    local c = {
        id = ER.nextId, ped = ped, hospital = hospitalId, triage = 0, treating = false, treatingName = false,
        name = false, gender = male and "male" or "female", arrival = arrival or { kind = "brought" },
        location = "corridor", status = "waiting", created = getRealTime().timestamp, events = {},
    }
    ER.nextId = ER.nextId + 1
    ER.cases[ped] = c
    if ERDB then ERDB.insertCase(c) end
    ER.log(c, "arrival", arrival and arrival.kind or "brought")
    ER.syncCase(c)
    -- the name / birth date of the NPC (police_system makes or loads the citizen record)
    local known = getElementData(ped, "pol.identity")
    if known then
        setIdentity(c, known)
    elseif running("police_system") then
        pcall(function() exports.police_system:requestNPCIdentity(ped) end)
    end
    return c
end

addEvent("onNPCIdentityReady")
addEventHandler("onNPCIdentityReady", root, function(id)
    local c = ER.cases[source]
    if c then setIdentity(c, id) end
end)

function ER.closeCase(c, outcome)
    if not c then return end
    c.status = outcome or "closed"
    ER.log(c, "close", c.status)
    -- the treating doctor's closed cases (work_hospital hosp.cases: the Physician exam needs them)
    if c.status ~= "interrupted" and not c.caseCounted and isElement(c.treating) and ER.running("work_hospital") then
        c.caseCounted = true
        pcall(function() exports.work_hospital:addHospitalTreatedCase(c.treating) end)
    end
    if c.status ~= "interrupted" and not c.staffCounted and ER.running("work_hospital") then
        c.staffCounted = true
        if isElement(c.treating) then c.staff = c.staff or {} c.staff[c.treating] = true end
        for p in pairs(c.staff or {}) do
            if isElement(p) then pcall(function() exports.work_hospital:addHospitalAssistedCase(p) end) end
        end
    end
    if ERDB then ERDB.closeCase(c, outcome) end
    ER.cases[c.ped] = nil
    if isElement(c.ped) then removeElementData(c.ped, ER_DATA) end
    if ER.onCaseClosed then ER.onCaseClosed(c) end
end

function ER.caseOf(ped) return ER.cases[ped] end

function ER.setTriage(c, level, by)
    level = math.floor(tonumber(level) or 0)
    if level < 1 or level > 4 then return false end
    local first = c.triage == 0
    c.triage = level
    if c.status == "waiting" then c.status = "triaged" end
    ER.log(c, "triage", tostring(level), by)
    ER.syncCase(c)
    if first and isElement(by) then ER.points(by, "HK-A01", 4, L.forPlayer(by, "med_hospitals.er.code_a01"), c) end
    return true
end

function ER.setTreating(c, player)
    c.treating = isElement(player) and player or false
    c.treatingName = isElement(player) and (getElementData(player, "displayName") or getPlayerName(player)) or false
    ER.log(c, "treating", c.treatingName or "-", player)
    ER.syncCase(c)
end

-- A treating player leaving duty / the game: their patients have nobody, the others are told
local function dropTreating(player)
    for _, c in pairs(ER.cases) do
        if c.treating == player then
            c.treating, c.treatingName = false, false
            ER.syncCase(c)
            ER.notifyStaff(c.hospital, function(p) return L.forPlayer(p, "med_hospitals.er.patient_has_no_treating", { name = c.name or "?" }) end, false, player)
        end
    end
end

addEvent("onPlayerWorkDutyEnd")
addEventHandler("onPlayerWorkDutyEnd", root, function(workId) if workId == "hospital" then dropTreating(source) end end)
addEventHandler("onPlayerQuit", root, function() dropTreating(source) end)

-- the ped is gone (despawned, restart of its owner): the case ends
addEventHandler("onElementDestroy", root, function()
    local c = ER.cases[source]
    if c then
        ER.cases[source] = nil
        -- an open case whose patient vanished (despawn, its owner resource stopped): interrupted care
        if not c.outcome then
            c.status, c.outcome = "interrupted", "interrupted"
            if ER.writeAmbulatory then ER.writeAmbulatory(c, "interrupted") end
        end
        if ERDB then ERDB.closeCase(c, c.outcome) end
        if ER.onCaseClosed then ER.onCaseClosed(c) end
    end
end)

---------------------------------------------------------------- rules on medsys procedures (medsys onHostTreatmentCheck)

-- before triage only life-saving (K10): CPR, airway, bleeding control, oxygen, the monitor and the
-- examinations; in cardiac arrest everything (resuscitation drugs need IV access)
local LIFE_SAVING = { cpr = true, airway = true, bandage = true, oxygen = true, monitor = true, neuro = true, glucometer = true }

-- export: -> true | false, reason (in the medic's language)
function canTreatPatient(target, medic, action, option)
    local c = ER.cases[target]
    if not c then return true end
    if c.triage == 0 and not LIFE_SAVING[action] then
        local m = ER.running("medsys") and exports.medsys:getMedicalState(target)
        if not (m and (m.clinicalDeath or m.dead)) then
            return false, L.forPlayer(medic, "med_hospitals.er.triage_first_life_saving")
        end
    end
    if ER.roomRule then return ER.roomRule(c, medic, action, option) end
    return true
end

-- export (medsys hostAllowsAction): a drug ordered for this patient may be given by any staff member
function allowsByOrder(target, medic, key)
    local c = ER.cases[target]
    if not c or not ER.isStaff(medic, c.hospital) then return false end
    local drug = tostring(key):match("^drug%.(.+)$")
    if not drug then return false end
    for _, o in ipairs(c.drugOrders or {}) do
        if o.drug == drug and o.status == "ordered" then return true end
    end
    return false
end

-- a given drug closes its order (the nurse gave what the doctor ordered)
addEvent("onMedicalTreatment")
addEventHandler("onMedicalTreatment", root, function(medic, action, success, option, dose)
    local c = ER.cases[source]
    if not c or action ~= "medication" or success ~= true then return end
    for _, o in ipairs(c.drugOrders or {}) do
        if o.drug == option and o.status == "ordered" then
            o.status, o.givenBy, o.givenAt, o.givenDose = "done", isElement(medic) and (getElementData(medic, "displayName") or getPlayerName(medic)) or "", getRealTime().timestamp, dose
            ER.log(c, "drug_given", tostring(option) .. (dose and (" " .. tostring(dose)) or ""), medic)
            ER.syncCase(c)
            break
        end
    end
end)

---------------------------------------------------------------- stretchers and spots

local function eq() return running("med_equipments") and exports.med_equipments or nil end

local function dist2(x1, y1, x2, y2) return ((x1 - x2) ^ 2 + (y1 - y2) ^ 2) ^ 0.5 end

-- Hospital stretchers (objects) of the hospital
function ER.stretchers(hospitalId)
    local m = eq()
    return m and m:getHospitalStretchers(hospitalId) or {}
end

-- Is anything (a hospital stretcher) standing on the spot?
function ER.spotTaken(hospitalId, spot)
    for _, obj in ipairs(ER.stretchers(hospitalId)) do
        local x, y = getElementPosition(obj)
        if dist2(x, y, spot.x, spot.y) < 1.2 then return obj end
    end
    return false
end

-- The first free corridor spot (index, spot) or false
function ER.freeCorridorSpot(hospitalId)
    local e = ER.byHospital[hospitalId]
    if not e then return false end
    for i, spot in ipairs(e.cfg.corridor or {}) do
        if not ER.spotTaken(hospitalId, spot) then return i, spot end
    end
    return false
end

function ER.freeCorridorCount(hospitalId)
    local e, n = ER.byHospital[hospitalId], 0
    for _, spot in ipairs(e and e.cfg.corridor or {}) do
        if not ER.spotTaken(hospitalId, spot) then n = n + 1 end
    end
    return n
end

function ER.park(obj, spot)
    local m = eq()
    if not m then return false end
    parking[obj] = true
    local ok = m:parkHospitalStretcher(obj, spot.x, spot.y, spot.z, spot.rot or 0)
    parking[obj] = nil
    return ok
end

function ER.patientOfStretcher(obj)
    local m = eq()
    local ped = m and m:getStretcherPatient(obj)
    return isElement(ped) and ped or false
end

-- A hospital stretcher was put down: if it is close to a bay or a corridor spot it snaps there
-- and the patient's location changes. Shock room: an untriaged patient gets T1 and is admitted, the
-- pusher becomes the treating one.
addEvent("onStretcherSettled")
addEventHandler("onStretcherSettled", root, function(snapper)
    local obj = source
    if parking[obj] then return end
    local m = eq()
    if not m or not m:isHospitalStretcher(obj) then return end
    local hid = m:getStretcherHospital(obj)
    local e = ER.byHospital[hid]
    if not e then return end
    local x, y = getElementPosition(obj)
    local target, where, room
    for name, bay in pairs(e.cfg.bays or {}) do
        if dist2(x, y, bay.x, bay.y) <= (bay.radius or 1.6) then target, where, room = bay, name, bay.room break end
    end
    if not target then
        for i, spot in ipairs(e.cfg.corridor or {}) do
            if dist2(x, y, spot.x, spot.y) <= 1.3 then target, where = spot, "F" .. i break end
        end
    end
    if not target then return end
    -- another stretcher already stands there
    for _, other in ipairs(ER.stretchers(hid)) do
        if other ~= obj then
            local ox, oy = getElementPosition(other)
            if dist2(ox, oy, target.x, target.y) < 0.6 then return end
        end
    end
    ER.park(obj, target)
    local ped = ER.patientOfStretcher(obj)
    local c = ped and ER.cases[ped]
    if ped and not c and ER.active(hid) then
        -- a patient brought in on a hospital stretcher (picked up in the ER): registered now
        c = ER.createCase(ped, hid, { kind = "brought", at = getRealTime().timestamp })
    end
    if not c then return end
    c.location = where
    ER.log(c, "move", where, snapper)
    if room == "shock" and c.triage == 0 then
        c.status = "triaged"
        ER.setTriage(c, 1, isElement(snapper) and snapper or nil)
        if not c.treating and isElement(snapper) and ER.isStaff(snapper, hid) then ER.setTreating(c, snapper) end
    end
    ER.syncCase(c)
end)

---------------------------------------------------------------- loading (hospitals.lua LoadHandlers)

local built = {}

local function clearBuilt()
    for _, el in ipairs(built) do if isElement(el) then destroyElement(el) end end
    built = {}
end

function ER.track(el)
    if el then built[#built + 1] = el end
    return el
end

-- ui_core marker cards on the ER markers (only for the hospital staff on duty: work = "hospital").
-- The card goes with its marker (ui_core drops it on onElementDestroy); cards[] re-registers them
-- when ui_core restarts.
local cards = {}   -- id -> def
local CARD_DEFAULTS = { type = "hosp_handover", work = "hospital", radius = 14, fullRadius = 5, minScale = 0.6, height = 1.2 }

function ER.markerCard(marker, id, def)
    if not isElement(marker) then return end
    local d = {}
    for k, v in pairs(CARD_DEFAULTS) do d[k] = v end
    for k, v in pairs(def) do d[k] = v end
    d.element = marker
    id = "er:" .. id
    cards[id] = d
    addEventHandler("onElementDestroy", marker, function() cards[id] = nil end, false)
    if running("ui_core") then exports.ui_core:createMarkerUI(id, d) end
end

addEvent("onMarkerUISystemStart")
addEventHandler("onMarkerUISystemStart", root, function()
    for id, d in pairs(cards) do
        if isElement(d.element) then exports.ui_core:createMarkerUI(id, d) else cards[id] = nil end
    end
end)

LoadHandlers[#LoadHandlers + 1] = function()
    clearBuilt()
    ER.byHospital = {}
    for _, h in ipairs(Hospitals.list) do
        if h.er then
            local e = { h = h, cfg = h.er }
            ER.byHospital[h.id] = e
            if ER.buildHospital then ER.buildHospital(e) end
        end
    end
    -- cases that survived a restart of this resource (peds keep the synced element data): the whole case
    -- comes back from hosp_cases; open cases without a ped are closed as interrupted
    local function restore()
        if ERDB and not ERDB.ready then return setTimer(restore, 500, 1) end
        local alive = {}
        for _, ped in ipairs(getElementsByType("ped")) do
            local v = getElementData(ped, ER_DATA)
            if type(v) == "table" and v.id and not ER.cases[ped] and ER.byHospital[v.hospital] then
                alive[v.id] = true
                local c = { id = v.id, ped = ped, hospital = v.hospital, triage = v.triage or 0, treating = false,
                            treatingName = false, name = v.name, age = v.age, gender = v.gender, arrival = { kind = "restored" },
                            location = v.location or "corridor", status = v.status or "waiting", created = getRealTime().timestamp, events = {} }
                ER.nextId = math.max(ER.nextId, v.id + 1)
                ER.cases[ped] = c
                if ERDB then
                    ERDB.loadCase(v.id, function(data)
                        if type(data) ~= "table" or ER.cases[ped] ~= c then return end
                        for k, val in pairs(data) do if c[k] == nil or k == "events" or k == "arrival" or k == "treatingName" then c[k] = val end end
                        c.treating = false
                        c.treatingName = false -- the treating player has to take it again
                        c.events = c.events or {}
                        ER.syncCase(c)
                    end)
                end
                ER.syncCase(c)
            end
        end
        if ERDB then ERDB.closeOrphans(alive) end
    end
    restore()
end

addEventHandler("onResourceStart", resourceRoot, function() if ERDB then ERDB.setup() end end)

UnloadHandlers[#UnloadHandlers + 1] = function() clearBuilt() end
