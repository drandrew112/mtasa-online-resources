-- Walk-in patients: only gap fillers while the ER has staff. If the ambulances keep bringing
-- patients, nobody (or almost nobody) walks in.
--   interval = BASE * 0.8^(staff - 1) (at least MIN) * 1.7^(EMS units on duty)
--   each EMS handover in the last 10 minutes: 35 % chance the next walk-in is skipped;
--   handovers >= staff: paused; at most MAX_WAITING walk-ins waiting; paused when <= 1 corridor place is free

local BASE, MIN, MAX_WAITING = 360, 150, 3
-- the plan's walk-in cases: { injuries = { { type, severity, part } }, set = { { medsys key, value } }, weight }
local TEMPLATES = {
    { injuries = { { "sprain", 1, "leg" } }, weight = 5 },                 -- rándulás
    { injuries = { { "fracture", 1, "arm" } }, weight = 4 },               -- csuklótörés
    { injuries = { { "laceration", 1, "arm" } }, weight = 4 },             -- vágott seb
    { injuries = { { "burn", 1 } }, weight = 2 },                          -- égés
    { injuries = { { "acs", 1 } }, weight = 2 },                           -- mellkasi fájdalom (NSTEMI)
    { injuries = { { "acs", 2 } }, weight = 1 },                           -- mellkasi fájdalom (STEMI)
    { injuries = { { "appendicitis", 1 } }, weight = 2 },                  -- hasi fájdalom
    { injuries = { { "renal_colic", 2 } }, weight = 2 },                   -- vesekólika
    { injuries = { { "asthma", 1 } }, weight = 2 },                        -- asztma
    { injuries = {}, set = { { "glucose", 48 } }, weight = 2 },            -- hipoglikémia
    { injuries = { { "alcohol", 2 } }, weight = 2 },                       -- ittasság
    { injuries = { { "head_injury", 1 } }, weight = 3 },                   -- fejsérülés
}
local SKINS = { 7, 9, 10, 11, 12, 14, 15, 17, 19, 20, 21, 22, 23, 24, 25, 26, 29, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41 }

local EMPTY_REMOVE = 300000 -- ms without any staff: the NPC patients left in the ER disappear (as before the ER)
local emptySince = {}  -- [hospitalId] = tick
local handovers = {}  -- [hospitalId] = { tick, ... }
local nextAt = {}     -- [hospitalId] = tick
local skipNext = {}   -- [hospitalId] = true

addEventHandler("onHospitalPatientHandover", root, function(hospitalId)
    local list = handovers[hospitalId] or {}
    handovers[hospitalId] = list
    list[#list + 1] = getTickCount()
    if math.random() < 0.35 then skipNext[hospitalId] = true end
end)

local function recentHandovers(hid)
    local t, n, list = getTickCount(), 0, handovers[hid] or {}
    for i = #list, 1, -1 do
        if t - list[i] > 600000 then table.remove(list, i) else n = n + 1 end
    end
    return n
end

local function emsUnits()
    if not ER.running("med_erm") then return 0 end
    return #(exports.med_erm:getUnits() or {})
end

local function waiting(hid)
    local n = 0
    for _, c in pairs(ER.cases) do
        if c.hospital == hid and c.arrival and c.arrival.kind == "walk" and c.location == "waiting" then n = n + 1 end
    end
    return n
end

local function pick()
    local total = 0
    for _, t in ipairs(TEMPLATES) do total = total + t.weight end
    local r = math.random() * total
    for _, t in ipairs(TEMPLATES) do
        r = r - t.weight
        if r <= 0 then return t end
    end
    return TEMPLATES[1]
end

local function spawnWalkIn(e)
    local spots = e.cfg.walkIn or {}
    if #spots == 0 then return end
    local spot = spots[math.random(#spots)]
    -- not on top of somebody
    for _, ped in ipairs(getElementsWithinRange(spot.x, spot.y, spot.z + 1, 0.8, "ped")) do return end
    local h = e.h
    local ped = createPed(SKINS[math.random(#SKINS)], spot.x, spot.y, spot.z + 1, spot.rot or 0)
    if not ped then return end
    setElementInterior(ped, h.interior) setElementDimension(ped, h.dimension)
    local tpl = pick()
    setElementData(ped, "medic.status", "injured")
    for _, inj in ipairs(tpl.injuries) do exports.medsys:applyInjury(ped, inj[1], inj[2], inj[3]) end
    for _, kv in ipairs(tpl.set or {}) do exports.medsys:setMedicalState(ped, kv[1], kv[2]) end
    local c = ER.createCase(ped, h.id, { kind = "walk", at = getRealTime().timestamp })
    c.location = "waiting"
    ER.syncCase(c)
    ER.notifyStaff(h.id, function(p) return L.forPlayer(p, "med_hospitals.erc.walk_in") end)
end

ER.spawnWalkIn = spawnWalkIn

setTimer(function()
    local t = getTickCount()
    for hid, e in pairs(ER.byHospital) do
        local staff = #ER.staff(hid)
        if staff == 0 then
            emptySince[hid] = emptySince[hid] or t
            if t - emptySince[hid] >= EMPTY_REMOVE then
                emptySince[hid] = t
                local m = ER.running("med_equipments") and exports.med_equipments
                for ped, c in pairs(ER.cases) do
                    if c.hospital == hid and not c.bed and c.status ~= "surgery" and isElement(ped) and getElementType(ped) == "ped" then
                        local st = m and m:getPatientStretcher(ped)
                        ER.closeCase(c, "interrupted")
                        destroyElement(ped)
                        if st and m:isHospitalStretcher(st) then setTimer(function() if isElement(st) then m:destroyHospitalStretcher(st) end end, 200, 1) end
                    end
                end
            end
        else
            emptySince[hid] = nil
        end
        if staff == 0 or not ER.running("medsys") then
            nextAt[hid] = nil
        else
            if not nextAt[hid] then
                local interval = math.max(MIN, BASE * 0.8 ^ (staff - 1)) * 1.7 ^ emsUnits()
                nextAt[hid] = t + interval * 1000 * (0.7 + math.random() * 0.6)
            elseif t >= nextAt[hid] then
                nextAt[hid] = nil
                local paused = recentHandovers(hid) >= staff or waiting(hid) >= MAX_WAITING or ER.freeCorridorCount(hid) <= 1
                if skipNext[hid] then skipNext[hid], paused = nil, true end
                if not paused then spawnWalkIn(e) end
            end
        end
    end
end, 5000, 0)
