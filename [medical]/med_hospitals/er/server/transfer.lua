-- ER transfers (ERM task type "szállítás"): S1 immediate, S2 within 3 h (30 min in the game).
-- The treating doctor requests it in the HIS (outcome); needs (oxygen / drugs on the way /
-- ventilated) restrict it to ALS units (med_erm auto: meta.needsALS, S1 after P2, S2 after P3).
--   * a suitable unit is logged in (any status): an ERM task is made at the hospital; the crew takes
--     the patient over at the "transferPickup" point (their stretcher next to the hospital one, 5 s),
--     then hands over at the target hospital as usual
--   * no suitable unit logged in: automatic transfer after ERC.TIMES.transferS1 / S2; the patient
--     appears at the target hospital on a stretcher if its ER has staff, otherwise just leaves

local ALS_TYPES = { ALS = true, DOC = true, HELI = true }
local pending = {}   -- [case] = { class, target, needs, taskId, at, auto = timer }
local PICKUP_RANGE = 3.0
local PICKUP_TIME = 5000

local function eq() return ER.running("med_equipments") and exports.med_equipments or nil end
local function erm() return ER.running("med_erm") and exports.med_erm or nil end

-- the "Beteg átvétele" point for the EMS crews (work "ems"): marker + ui_core card
local oldBuild = ER.buildHospital
ER.buildHospital = function(e)
    if oldBuild then oldBuild(e) end
    local p, h = e.cfg.transferPickup, e.h
    if not p then return end
    local mk = ER.track(createMarker(p.x, p.y, p.z - 0.05, "cylinder", 1.6, 150, 80, 220, ER.MARKER_ALPHA))
    setElementInterior(mk, h.interior) setElementDimension(mk, h.dimension)
    if ER.running("work_core") then exports.work_core:setElementVisibleToWork(mk, "ems") end
    ER.markerCard(mk, h.id .. ":transfer_pickup", { work = "ems", name = h.name or "", color = { 170, 110, 235 },
        title = L.msg("med_hospitals.erc.transfer_pickup_title"), hint = L.msg("med_hospitals.erc.transfer_pickup_hint") })
end

local function suitableLoggedIn(needsALS)
    local e = erm()
    if not e then return false end
    for _, u in ipairs(e:getUnits() or {}) do
        if (not needsALS and (u.type == "BLS" or ALS_TYPES[u.type])) or (needsALS and ALS_TYPES[u.type]) then return true end
    end
    return false
end

local function targetHospital(fromId, wanted)
    local from = Hospitals.byId[fromId]
    if wanted and Hospitals.byId[wanted] and wanted ~= fromId then return Hospitals.byId[wanted] end
    local best, bestD
    for _, h in ipairs(Hospitals.list) do
        if h.id ~= fromId then
            local d = getDistanceBetweenPoints2D(from.x, from.y, h.x, h.y)
            if not bestD or d < bestD then best, bestD = h, d end
        end
    end
    return best
end

-- the patient leaves; at the target ER (with staff) a new ped with the same injuries arrives
local function autoTransfer(c)
    local p = pending[c]
    pending[c] = nil
    if not p or not ER.cases[c.ped] or not isElement(c.ped) then return end
    local ped, m = c.ped, eq()
    local snap = ER.running("medsys") and exports.medsys:getMedicalState(ped) or {}
    local skin = getElementModel(ped)
    local identity = { name = c.name, age = c.age, gender = c.gender }
    local injuries = {}
    for _, i in ipairs(snap.injuries or {}) do if not i.treated then injuries[#injuries + 1] = { i.type, i.severity } end end
    for _, i in ipairs(snap.conditions or {}) do injuries[#injuries + 1] = { i.type, i.severity } end
    local st = m and m:getPatientStretcher(ped)
    c.outcome = "transfer"
    ER.log(c, "transfer", p.class .. " auto -> " .. p.target.id)
    if ER.writeAmbulatory then ER.writeAmbulatory(c, "transfer") end
    ER.closeCase(c, "transfer")
    destroyElement(ped)
    if st and m:isHospitalStretcher(st) then setTimer(function() if isElement(st) then m:destroyHospitalStretcher(st) end end, 200, 1) end

    local h = p.target
    if not ER.active(h.id) then return end
    local idx, spot = ER.freeCorridorSpot(h.id)
    if not spot then return end
    local obj = m:createHospitalStretcher(h.id, spot.x, spot.y, spot.z, spot.rot or 180, h.dimension, h.interior)
    if not obj then return end
    local np = createPed(skin, spot.x, spot.y, spot.z + 1)
    setElementDimension(np, h.dimension) setElementInterior(np, h.interior)
    for _, inj in ipairs(injuries) do exports.medsys:applyInjury(np, inj[1], inj[2]) end
    m:putPatientOnStretcher(obj, np)
    local nc = ER.createCase(np, h.id, { kind = "transfer", from = c.hospital, at = getRealTime().timestamp, text = c.anamnesis or "" })
    nc.name, nc.age, nc.gender, nc.location = identity.name, identity.age, identity.gender, "F" .. idx
    nc.anamnesis = c.anamnesis
    ER.syncCase(nc)
    ER.notifyStaff(h.id, function(pl) return L.forPlayer(pl, "med_hospitals.erc.transfer_arrived", { name = nc.name or "?" }) end, true)
end

-- arg = { needs = { oxygen, drugs, ventilated, monitor }, target = hospital id, note = text } (patient panel)
function ER.requestTransfer(c, player, class, arg)
    if pending[c] then return ER.notify(player, L.forPlayer(player, "med_hospitals.erc.transfer_pending"), true) end
    arg = type(arg) == "table" and arg or {}
    local needs = {}
    for _, k in ipairs({ "oxygen", "drugs", "ventilated", "monitor" }) do needs[k] = type(arg.needs) == "table" and arg.needs[k] == true end
    c.transferNote = type(arg.note) == "string" and arg.note:gsub("[%c]", " "):sub(1, 200) or ""
    local snap = ER.running("medsys") and exports.medsys:getMedicalState(c.ped) or {}
    -- the patient's state decides too: intubated / on oxygen / a running infusion
    if snap.intubated then needs.ventilated = true end
    if snap.oxygenMask then needs.oxygen = true end
    if snap.infusion then needs.drugs = true end
    local needsALS = needs.oxygen or needs.drugs or needs.ventilated or needs.monitor
    local h = Hospitals.byId[c.hospital]
    local target = targetHospital(c.hospital, type(arg.target) == "string" and arg.target or nil)
    if not target then return end
    local p = { class = class, target = target, needs = needs, at = getRealTime().timestamp, by = player }
    pending[c] = p
    c.pending = { kind = "transfer", class = class }
    local o = ERC.OUTCOMES[class == "S1" and "transfer_s1" or "transfer_s2"]
    ER.points(player, o.code, o.points, L.forPlayer(player, "med_hospitals.erc.outcome_transfer_" .. class:lower()), c)
    ER.log(c, "transfer", class .. " -> " .. target.id, player)

    if suitableLoggedIn(needsALS) then
        local pick = ER.byHospital[c.hospital].cfg.transferPickup or h
        local title = L.text("med_hospitals.erc.transfer_task_title", { class = class, from = h.name, to = target.name })
        local desc = L.text("med_hospitals.erc.transfer_task_desc", { name = c.name or "?", to = target.name,
            needs = needsALS and L.text("med_hospitals.erc.transfer_needs_als") or "BLS" })
        local id = erm():createTask(title, desc, pick.x, pick.y, pick.z, h.name, class == "S1" and 2 or 3,
            { kind = "transfer", transferClass = class, needsALS = needsALS, from = h.id, to = target.id, caseId = c.id,
              needs = needs, note = c.transferNote or "", destination = { x = target.x, y = target.y, z = target.z, name = target.name } })
        p.taskId = id
        ER.notify(player, L.forPlayer(player, "med_hospitals.erc.transfer_task_made", { class = class }))
    else
        local delay = class == "S1" and ERC.TIMES.transferS1 or ERC.TIMES.transferS2
        p.auto = setTimer(function() autoTransfer(c) end, delay * 1000, 1)
        ER.notify(player, L.forPlayer(player, "med_hospitals.erc.transfer_auto", { min = math.ceil(delay / 60) }))
    end
    ER.syncCase(c)
end

-- the last suitable unit left before the task was taken: automatic transfer instead
setTimer(function()
    for c, p in pairs(pending) do
        if not ER.cases[c.ped] then
            pending[c] = nil
        elseif p.taskId and not p.pickedUp and not suitableLoggedIn(p.needs.oxygen or p.needs.drugs or p.needs.ventilated) then
            if erm() then erm():closeTask(p.taskId, "no unit") end
            p.taskId = nil
            local delay = p.class == "S1" and ERC.TIMES.transferS1 or ERC.TIMES.transferS2
            p.auto = setTimer(function() autoTransfer(c) end, delay * 1000, 1)
        end
    end
end, 15000, 0)

---------------------------------------------------------------- pickup by the EMS crew

local procs = {}  -- [medic] = { case, ends }

setTimer(function()
    local m = eq()
    if not m or not erm() then return end
    local t = getTickCount()
    for c, p in pairs(pending) do
        local e = ER.byHospital[c.hospital]
        local pt = e and e.cfg.transferPickup
        local st = pt and isElement(c.ped) and m:getPatientStretcher(c.ped)
        if st and p.taskId then
            local sx, sy, sz = getElementPosition(st)
            -- an EMS medic of the assigned unit pushing their ambulance stretcher next to it
            for _, pl in ipairs(getElementsByType("player")) do
                local push = getElementData(pl, "stretcher.pushing")
                local unit = erm():getUnitData(pl)
                if isElement(push) and not m:isHospitalStretcher(push) and unit and unit.task == p.taskId then
                    local px, py, pz = getElementPosition(push)
                    if getDistanceBetweenPoints3D(px, py, pz, sx, sy, sz) <= PICKUP_RANGE and
                       getDistanceBetweenPoints2D(sx, sy, pt.x, pt.y) <= 3.0 and not m:getStretcherPatient(push) then
                        local pr = procs[pl]
                        if not pr then
                            procs[pl] = { case = c, ends = t + PICKUP_TIME }
                            ER.notify(pl, L.forPlayer(pl, "med_hospitals.erc.pickup_started"))
                        elseif t >= pr.ends then
                            procs[pl] = nil
                            p.pickedUp = true
                            m:putPatientOnStretcher(push, c.ped)
                            c.outcome = "transfer"
                            ER.log(c, "transfer", "picked up by " .. tostring(unit.callsign))
                            if ER.writeAmbulatory then ER.writeAmbulatory(c, "transfer") end
                            pending[c] = nil
                            ER.closeCase(c, "transfer")
                            setTimer(function() if isElement(st) then m:destroyHospitalStretcher(st) end end, 200, 1)
                            ER.notify(pl, L.forPlayer(pl, "med_hospitals.erc.pickup_done", { to = p.target.name }))
                        end
                    else
                        procs[pl] = nil
                    end
                end
            end
        end
    end
end, 500, 0)

addEventHandler("onPlayerQuit", root, function() procs[source] = nil end)

function ER.transferOf(c) return pending[c] end
