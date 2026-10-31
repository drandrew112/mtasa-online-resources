-- police_system / modules/history/server/npc.lua
-- NPC background: generated at the first police contact (stop, query, plate search) and stored in pol_citizens /
-- pol_vehicles; afterwards the same element gives the same data (server-only element data pol.cid / pol.vid).
-- The name follows the skin's gender (shared/skins.lua). Chances: POLICE.HISTORY. Generated earlier items are dated
-- in the past with the officer "SAPD Records".

local H = POL.module("history", {})
local C = POLICE.HISTORY
local random, floor = math.random, math.floor

local waiting = {}   -- [element] = { cb, ... } while the row is being made

local function chance(p) return random() < p end

local function pick(list) return list[random(#list)] end

local function isNight()
    local h = getTime()
    return h >= 22 or h < 5
end

local function dateOf(ts)
    local t = getRealTime(ts)
    return ("%04d-%02d-%02d"):format(t.year + 1900, t.month + 1, t.monthday)
end

-- random penal code items (fines) that fit an NPC's past
local function pastFineIds()
    local out = {}
    for _, e in ipairs(POL.btk.items) do
        if not e.warning and not e.arrestable and (e.cat == "traffic" or e.cat == "parking" or e.cat == "vehicle"
            or e.cat == "pedestrian" or e.cat == "public") then out[#out + 1] = e.id end
    end
    return out
end

local function warningIds()
    local out = {}
    for _, e in ipairs(POL.btk.items) do if e.warning then out[#out + 1] = e.id end end
    return out
end

local function crimeIds()
    local out = {}
    for _, e in ipairs(POL.btk.items) do if e.warrant then out[#out + 1] = e.id end end
    return out
end

local function addPast(citizenId, kind, btkId, amount, vehicleId)
    POL.db.create("pol_records", {
        type = kind, btk_id = btkId, amount = amount or 0, paid = 1, citizen_id = citizenId, vehicle_id = vehicleId,
        officer = "", officer_name = "SAPD Records", unit = "", created_at = POL.now() - random(3, 420) * 86400 - random(0, 86000),
    })
end

local function finish(el, row)
    local list = waiting[el]
    waiting[el] = nil
    for _, cb in ipairs(list or {}) do pcall(cb, row) end
end

-- the citizen row of an NPC ped (made now if needed): cb(row | false)
function H.npc(ped, cb)
    if not isElement(ped) or getElementType(ped) ~= "ped" then return cb(false) end
    local cid = getElementData(ped, "pol.cid")
    if cid then return POL.records.citizen(cid, cb) end
    if waiting[ped] then table.insert(waiting[ped], cb); return end
    waiting[ped] = { cb }

    local skin = getElementModel(ped)
    local gender = policeSkinGender(skin)
    local name = pick(POLICE_NAMES[gender]) .. " " .. pick(POLICE_NAMES.last)
    local now = POL.now()
    local age = random(C.AGE[1], C.AGE[2])
    -- by the calendar: getRealTime refuses timestamps before 1970 (anyone older than ~56)
    local birth = dateOf(now - random(0, 364) * 86400)
    birth = ("%04d"):format(tonumber(birth:sub(1, 4)) - age) .. birth:sub(5)
    if birth:sub(6) == "02-29" then birth = birth:sub(1, 5) .. "02-28" end
    local warrant = chance(C.WARRANT)
    local flags = {
        licence = chance(C.SUSPENDED) and "suspended" or "valid",
        bac = chance(isNight() and C.ALCOHOL_NIGHT or C.ALCOHOL) and (floor((0.2 + random() * 1.4) * 100) / 100) or 0,
        drug = chance(C.DRUG),
        flee = chance(warrant and C.FLEE_WARRANT or C.FLEE),
    }
    local row = { kind = "npc", name = name, gender = gender, birth_date = birth, skin = skin, flags = POL.db.json(flags),
                  generated = 1, created_at = now, last_seen = now }
    POL.db.create("pol_citizens", row, function(id)
        if not id then return finish(ped, false) end
        row.id = id
        if isElement(ped) then setElementData(ped, "pol.cid", id, false) end
        -- the generated past
        if chance(C.FINES) then
            local ids = pastFineIds()
            for _ = 1, random(1, 3) do
                local fid = pick(ids)
                addPast(id, "fine", fid, POL.btk.amount(fid))
            end
        end
        if chance(C.WARNINGS) then
            local ids = warningIds()
            for _ = 1, random(1, 2) do addPast(id, "warning", pick(ids), 0) end
        end
        if warrant then
            local reason = pick(crimeIds())
            POL.warrants.create(id, { reason }, "", "en", nil, true)
        end
        POL.records.cacheCitizen(row)
        finish(ped, row)
    end)
end

-- the vehicle row of an NPC (traffic) vehicle, with its driver as the owner: cb(row | false)
function H.npcVehicle(veh, cb)
    if not isElement(veh) or getElementType(veh) ~= "vehicle" then return cb(false) end
    local vid = getElementData(veh, "pol.vid")
    if vid then return POL.records.vehicle(vid, cb) end
    if waiting[veh] then table.insert(waiting[veh], cb); return end
    waiting[veh] = { cb }
    local function make(owner)
        local now = POL.now()
        local r, g, b = getVehicleColor(veh, true)
        local flags = {
            registration = "valid",
            inspection = chance(C.EXPIRED_INSPECTION) and ("expired " .. dateOf(now - random(10, 300) * 86400):sub(1, 7))
                or ("valid " .. dateOf(now + random(60, 700) * 86400):sub(1, 7)),
            stolen = chance(C.STOLEN),
        }
        local row = { kind = "npc", owner_citizen_id = owner and owner.id or nil, plate = getVehiclePlateText(veh),
                      model = getElementModel(veh), color = ("%d,%d,%d"):format(r or 0, g or 0, b or 0),
                      flags = POL.db.json(flags), created_at = now }
        POL.db.create("pol_vehicles", row, function(id)
            if not id then return finish(veh, false) end
            row.id = id
            if isElement(veh) then setElementData(veh, "pol.vid", id, false) end
            POL.records.cacheVehicle(row)
            finish(veh, row)
        end)
    end
    local driver = getVehicleController(veh)
    if driver and getElementType(driver) == "ped" then H.npc(driver, make) else make(nil) end
end
