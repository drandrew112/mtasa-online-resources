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

-- skins of generated owners who are not on the scene (only the gender of the name follows them)
local OWNER_SKINS = { 7, 9, 11, 12, 15, 17, 20, 23, 29, 40, 41, 44, 46, 47, 48, 56 }

local function birthOf(age, now)
    -- by the calendar: getRealTime refuses timestamps before 1970 (anyone older than ~56)
    local birth = dateOf(now - random(0, 364) * 86400)
    birth = ("%04d"):format(tonumber(birth:sub(1, 4)) - age) .. birth:sub(5)
    if birth:sub(6) == "02-29" then birth = birth:sub(1, 5) .. "02-28" end
    return birth
end

-- a scene warrant text: { en, hu } -> one description (both languages when both are given), its language
local function warrantText(d)
    if type(d) ~= "table" then return "", "en" end
    local en, hu = d.en or "", d.hu or ""
    if en ~= "" and hu ~= "" and en ~= hu then return en .. " | " .. hu, "en" end
    if en ~= "" then return en, "en" end
    return hu, hu ~= "" and "hu" or "en"
end

-- the past of a new row: the scene profile (v_scenemanager "pol.profile") or the random chances of POLICE.HISTORY
local function fillPast(id, prof, warrant)
    if prof then
        for _, p in ipairs(prof.past or {}) do
            if POL.btk.get(p.btk) then
                local days = math.max(1, tonumber(p.daysAgo) or 30)
                POL.db.create("pol_records", {
                    type = p.type == "warning" and "warning" or "fine", btk_id = p.btk,
                    amount = p.type == "warning" and 0 or POL.btk.amount(p.btk), paid = 1, citizen_id = id,
                    officer = "", officer_name = "SAPD Records", unit = "", created_at = POL.now() - days * 86400 - random(0, 86000),
                })
            end
        end
        for _, w in ipairs(prof.warrants or {}) do
            local text, lang = warrantText(w.description)
            POL.warrants.create(id, w.reasons or {}, text, lang, nil, false)
        end
        return
    end
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
end

-- a new citizen row: gender by the skin, the profile's fields where given, the rest random. cb(row | false)
local function makeCitizen(skin, prof, cb)
    local gender = policeSkinGender(skin)
    local now = POL.now()
    local pf = prof and prof.flags or {}
    local name = (prof and type(prof.name) == "string" and prof.name ~= "") and prof.name
        or (pick(POLICE_NAMES[gender]) .. " " .. pick(POLICE_NAMES.last))
    local birth = prof and type(prof.birth) == "string" and prof.birth
        or birthOf(prof and tonumber(prof.age) or random(C.AGE[1], C.AGE[2]), now)
    local warrant = not prof and chance(C.WARRANT)
    local flags = {
        licence = pf.licence or (chance(C.SUSPENDED) and "suspended" or "valid"),
        bac = prof and (tonumber(pf.bac) or 0) or (chance(isNight() and C.ALCOHOL_NIGHT or C.ALCOHOL) and (floor((0.2 + random() * 1.4) * 100) / 100) or 0),
        drug = chance(C.DRUG),
        drugType = prof and pf.drugType or nil,
    }
    if prof then flags.drug = pf.drug == true end
    if pf.flee ~= nil then
        flags.flee = pf.flee == true
    else
        flags.flee = chance((warrant or (prof and prof.warrants and #prof.warrants > 0)) and C.FLEE_WARRANT or C.FLEE)
    end
    local row = { kind = "npc", name = name, gender = gender, birth_date = birth, skin = skin, flags = POL.db.json(flags),
                  generated = 1, created_at = now, last_seen = now, ext_key = prof and prof.key or nil }
    POL.db.create("pol_citizens", row, function(id)
        if not id then return cb(false) end
        row.id = id
        fillPast(id, prof, warrant)
        POL.records.cacheCitizen(row)
        cb(row)
    end)
end

-- the citizen row of an NPC ped (made now if needed): cb(row | false). A scene ped (element data "pol.profile" of
-- v_scenemanager) gets its profile; one with profile.key is the same person at every spawn (pol_citizens.ext_key),
-- its warrants are only issued again when it has no active one.
function H.npc(ped, cb)
    if not isElement(ped) or getElementType(ped) ~= "ped" then return cb(false) end
    local cid = getElementData(ped, "pol.cid")
    if cid then return POL.records.citizen(cid, cb) end
    if waiting[ped] then table.insert(waiting[ped], cb); return end
    waiting[ped] = { cb }

    local prof = getElementData(ped, "pol.profile")
    if type(prof) ~= "table" then prof = nil end
    local skin = getElementModel(ped)
    local function done(row)
        if row and isElement(ped) then setElementData(ped, "pol.cid", row.id, false) end
        finish(ped, row or false)
    end
    if prof and type(prof.key) == "string" and prof.key ~= "" then
        POL.db.query(function(rows)
            local r = type(rows) == "table" and rows[1]
            if not r then return makeCitizen(skin, prof, done) end
            POL.records.cacheCitizen(r)
            POL.db.exec("UPDATE pol_citizens SET last_seen = ? WHERE id = ?", POL.now(), r.id)
            if prof.warrants and #prof.warrants > 0 then
                POL.warrants.activeFor(r.id, function(active)
                    if not active or #active == 0 then
                        for _, w in ipairs(prof.warrants) do
                            local text, lang = warrantText(w.description)
                            POL.warrants.create(r.id, w.reasons or {}, text, lang, nil, false)
                        end
                    end
                    done(r)
                end)
            else
                done(r)
            end
        end, "SELECT * FROM pol_citizens WHERE ext_key = ? AND is_pool = 0 LIMIT 1", prof.key)
        return
    end
    makeCitizen(skin, prof, done)
end

-- export (v_scenemanager, profile.announce): the citizen row of a scene ped is made now (MDC search, warrants listed)
function registerNPC(ped)
    if not isElement(ped) or getElementType(ped) ~= "ped" then return false end
    H.npc(ped, function() end)
    return true
end

-- the vehicle row of an NPC (traffic) vehicle, with its driver as the owner: cb(row | false)
function H.npcVehicle(veh, cb)
    if not isElement(veh) or getElementType(veh) ~= "vehicle" then return cb(false) end
    local vid = getElementData(veh, "pol.vid")
    if vid then return POL.records.vehicle(vid, cb) end
    if waiting[veh] then table.insert(waiting[veh], cb); return end
    waiting[veh] = { cb }
    -- a scene vehicle (v_scenemanager "pol.vprofile"): stolen / inspection fixed; owner = a scene ped, "random"
    -- (a generated person who is not on the scene) or "none"
    local vp = getElementData(veh, "pol.vprofile")
    if type(vp) ~= "table" then vp = nil end
    local function make(owner)
        local now = POL.now()
        local r, g, b = getVehicleColor(veh, true)
        local expired
        if vp then expired = vp.inspection == "expired" else expired = chance(C.EXPIRED_INSPECTION) end
        local flags = {
            registration = "valid",
            inspection = expired and ("expired " .. dateOf(now - random(10, 300) * 86400):sub(1, 7))
                or ("valid " .. dateOf(now + random(60, 700) * 86400):sub(1, 7)),
            stolen = vp and vp.stolen == true or (not vp and chance(C.STOLEN)),
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
    if vp then
        if vp.owner == "none" then return make(nil) end
        if isElement(vp.owner) and getElementType(vp.owner) == "ped" then return H.npc(vp.owner, make) end
        -- someone who is not on the scene (a stolen car's real owner)
        return makeCitizen(pick(OWNER_SKINS), nil, make)
    end
    local driver = getVehicleController(veh)
    if driver and getElementType(driver) == "ped" then H.npc(driver, make) else make(nil) end
end
