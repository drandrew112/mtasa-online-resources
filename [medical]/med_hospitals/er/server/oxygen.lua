-- Oxygen of the ER patients. Wall oxygen (shock room, ICU, the ward beds) supplies a patient without limit
-- and refills the stretcher's tank. Everywhere else (corridor, wound / cast room, CT, X-ray, the way
-- between the rooms) the patient breathes from the tank of his hospital stretcher: it drains while the
-- mask is on / the patient is intubated, and when it is empty the mask comes off (the tube has no effect
-- until oxygen is back, medsys noOxygen). The tank level (%) is element data "er.o2" of the stretcher.
-- medsys asks the level through er/server/stock.lua getHospitalEquipment (stock.oxygen).

local TANK_MINUTES = 20            -- full tank = this many minutes of mask time
local DRAIN = 100 / (TANK_MINUTES * 60)   -- %/s
local REFILL = 100 / 90            -- %/s on wall oxygen: empty -> full in 90 s
local LOW = 20                     -- % warning

local function ms() return ER.running("medsys") and exports.medsys or nil end
local function eq() return ER.running("med_equipments") and exports.med_equipments or nil end

local level = setmetatable({}, { __mode = "k" })   -- stretcher -> exact % (a new stretcher starts full)

function ER.stretcherOf(c)
    local m = eq()
    local obj = m and isElement(c.ped) and m:getPatientStretcher(c.ped)
    return isElement(obj) and obj or nil
end

local function tankOf(obj)
    if not obj then return nil end
    if level[obj] == nil then level[obj] = tonumber(getElementData(obj, "er.o2")) or 100 end
    return level[obj]
end

local function setTank(obj, v)
    v = math.max(0, math.min(100, v))
    level[obj] = v
    local shown = math.floor(v + 0.5)
    if getElementData(obj, "er.o2") ~= shown then setElementData(obj, "er.o2", shown) end
end

-- Is the patient on wall oxygen? Shock room, ICU, a ward bed.
function ER.hasWallOxygen(c)
    local loc = tostring(c.location or "")
    return loc:find("^shock") ~= nil or loc:find("^icu") ~= nil or c.bed ~= nil
end

-- % of oxygen the patient can draw now (medsys stock.oxygen): wall = full, otherwise the stretcher tank
function ER.oxygenAvailable(c)
    if ER.hasWallOxygen(c) then return 100 end
    local obj = ER.stretcherOf(c)
    if not obj then return 0 end
    return math.floor(tankOf(obj) + 0.5)
end

setTimer(function()
    local med = ms()
    if not med then return end
    for ped, c in pairs(ER.cases) do
        if isElement(ped) and not c.dead then
            local obj = ER.stretcherOf(c)
            local wall = ER.hasWallOxygen(c)
            local snap = med:getMedicalState(ped) or {}
            local breathing = snap.oxygenMask == true or snap.intubated == true
            if wall then
                if obj and tankOf(obj) < 100 then setTank(obj, tankOf(obj) + REFILL) end
                if snap.intubated and snap.noOxygen then
                    med:restorePatientEquipment(ped, "oxygen", L.msg("med_hospitals.oxygen.connected"))
                end
            elseif obj then
                local v = tankOf(obj)
                if breathing then
                    local before = v
                    v = v - DRAIN
                    setTank(obj, v)
                    if before > LOW and v <= LOW then
                        ER.notifyStaff(c.hospital, function(p) return L.forPlayer(p, "med_hospitals.oxygen.low", { name = c.name or "?" }) end, true)
                    end
                    if v <= 0 and not snap.noOxygen then
                        med:removePatientEquipment(ped, "oxygen", L.msg("med_hospitals.oxygen.tank_empty"))
                    end
                elseif v > 0 and snap.intubated and snap.noOxygen then
                    med:restorePatientEquipment(ped, "oxygen", L.msg("med_hospitals.oxygen.connected"))
                end
            elseif breathing and not snap.noOxygen then
                -- no stretcher, no wall (should not happen): nothing supplies the oxygen
                med:removePatientEquipment(ped, "oxygen", L.msg("med_hospitals.oxygen.no_source"))
            end
        end
    end
end, 1000, 0)
