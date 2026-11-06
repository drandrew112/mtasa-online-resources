-- Transfusion (plan: Transzfúzió): blood from the hospital's bt_stock stock (ls_allsaints) by unit
-- (rbc, ffp, platelets; 8 groups) and the emergency 0 Rh- RBC / AB plasma of the shock room fridge.
--   * the blood group is known after the "group" / "full" lab, a crossmatch (lab.crossmatch, 60 s) after that
--   * until then only the emergency units; incompatible blood -> acute haemolytic reaction (T8030)
--   * a unit runs 5 min (2 min with the pressure bag in a massive transfusion): blood volume, Hb, clotting
--   * 4+ units in 10 min = massive transfusion protocol (Orvos); too much / too fast -> fluid overload
--   * Ú6: fridge and bank out of 0 Rh- for 10 min -> an emergency NPC shipment (2 RBC 0- + 2 FFP AB)

local UNIT_TIME, PRESSURE_TIME = 300, 120
local GROUPS = { "0-", "0+", "A-", "A+", "B-", "B+", "AB-", "AB+" }

local function ms() return ER.running("medsys") and exports.medsys or nil end
local function bt() return ER.running("bt_stock") and exports.bt_stock or nil end

-- red cells: the donor's ABO antigens must be in the recipient, Rh+ only for Rh+ recipients
local function rbcOk(recipient, donor)
    local ra, rr = recipient:sub(1, -2), recipient:sub(-1)
    local da, dr = donor:sub(1, -2), donor:sub(-1)
    if dr == "+" and rr == "-" then return false end
    if da == "0" then return true end
    if da == "AB" then return ra == "AB" end
    return ra == da or ra == "AB"
end
-- plasma: the reverse (AB plasma for everyone, 0 plasma only for 0)
local function ffpOk(recipient, donor)
    local ra, da = recipient:sub(1, -2), donor:sub(1, -2)
    if da == "AB" then return true end
    if ra == "0" then return true end
    return ra == da
end
function ER.bloodCompatible(product, recipient, donor)
    if product == "rbc" then return rbcOk(recipient, donor) end
    if product == "ffp" then return ffpOk(recipient, donor) end
    return true   -- platelets: any (best ABO identical)
end

local function stockOf(hid)
    local b = bt()
    local s = b and b:getStock(hid) or false
    return type(s) == "table" and s or {}
end

function ER.transfusionView(c)
    local known = c.bloodGroup and c.groupKnown and c.bloodGroup or nil
    local s = stockOf(c.hospital)
    local units = {}
    local function add(product, group, compatible, extra)
        local n = (s[product] and tonumber(s[product][group]) or 0) + (extra or 0)
        units[#units + 1] = { product = product, group = group, stock = n, compatible = compatible }
    end
    if not known then
        add("rbc", "0-", true, ER.stockLeft(c.hospital, "shock", "rbc_0neg"))
        add("ffp", "AB+", true, ER.stockLeft(c.hospital, "shock", "ffp_ab"))
    else
        for _, product in ipairs({ "rbc", "ffp", "platelets" }) do
            for _, g in ipairs(GROUPS) do
                local ok = ER.bloodCompatible(product, known, g)
                if ok then add(product, g, c.crossmatched or (product == "rbc" and g == "0-") or product ~= "rbc",
                    (product == "rbc" and g == "0-") and ER.stockLeft(c.hospital, "shock", "rbc_0neg") or ((product == "ffp" and g:find("^AB")) and ER.stockLeft(c.hospital, "shock", "ffp_ab") or 0)) end
            end
        end
    end
    local running = {}
    local t = getRealTime().timestamp
    for _, r in ipairs(c.transfusions or {}) do if r.ends > t then running[#running + 1] = { product = r.product, group = r.group, left = r.ends - t } end end
    return { group = known or false, crossmatched = c.crossmatched or false, units = units, running = running }
end

local function takeUnit(c, product, group)
    -- the shock room fridge first for the emergency units, then the hospital's bank stock
    if product == "rbc" and group == "0-" and ER.fridgeTake(c.hospital, "rbc_0neg") then return true end
    if product == "ffp" and group:find("^AB") and ER.fridgeTake(c.hospital, "ffp_ab") then return true end
    local b = bt()
    return b and b:consume(c.hospital, product, group, 1, "er_transfusion") == true
end

function ER.transfuse(c, player, product, group)
    if product ~= "rbc" and product ~= "ffp" and product ~= "platelets" then return false end
    if not tostring(c.location or ""):find("^shock") and not tostring(c.location or ""):find("^icu") and c.location ~= "or" then
        return ER.notify(player, L.forPlayer(player, "med_hospitals.proc.shock_only"), true)
    end
    local px, py, pz = getElementPosition(player)
    local x, y, z = getElementPosition(c.ped)
    if getDistanceBetweenPoints3D(px, py, pz, x, y, z) > 3.2 then return ER.notify(player, L.forPlayer(player, "med_hospitals.exam.too_far"), true) end
    local t = getRealTime().timestamp
    c.transfusions = c.transfusions or {}
    -- massive transfusion: the 4th unit within 10 minutes needs a physician (C06)
    local recent = 0
    for _, r in ipairs(c.transfusions) do if t - r.at < 600 then recent = recent + 1 end end
    local mtp = recent >= 3
    if mtp and not ER.canDo(player, "er.mtp") then return false end
    if not takeUnit(c, product, group) then
        return ER.notify(player, L.forPlayer(player, "med_hospitals.transfusion.no_stock", { what = L.forPlayer(player, "med_hospitals.transfusion.product_" .. product) .. " " .. group }), true)
    end
    local actual = ms() and ms():getBloodGroup(c.ped) or "0+"
    local compatible = ER.bloodCompatible(product, actual, group)
    local dur = mtp and PRESSURE_TIME or UNIT_TIME
    local run = { product = product, group = group, at = t, ends = t + dur, by = getPlayerName(player) }
    c.transfusions[#c.transfusions + 1] = run
    ER.award(player, c, "HK-C05", 5, "med_docs.code.hk_c05")
    if mtp and not c.mtpDone then c.mtpDone = true ER.award(player, c, "HK-C06", 12, "med_docs.code.hk_c06") end
    ER.log(c, "transfusion", product .. " " .. group, player)
    ER.syncCase(c)
    setTimer(function()
        if not ER.cases[c.ped] or not ms() then return end
        local snap = ms():getMedicalState(c.ped) or {}
        if not compatible then
            -- acute haemolytic transfusion reaction
            ms():setMedicalState(c.ped, "systolic", math.max(50, (snap.systolic or 110) - 40))
            ms():setMedicalState(c.ped, "heartRate", math.min(170, (snap.heartRate or 90) + 35))
            c.findings = c.findings or {}
            c.findings[#c.findings + 1] = { id = "transfusion_reaction", injuryId = "tr" .. run.at, treated = false }
            ER.log(c, "complication", "haemolytic_reaction", player)
            ER.notifyStaff(c.hospital, function(p) return L.forPlayer(p, "med_hospitals.transfusion.reaction", { name = c.name or "?" }) end, true)
        elseif product == "rbc" then
            ms():setMedicalState(c.ped, "bloodVolume", math.min(5000, (snap.bloodVolume or 4000) + 450))
        elseif product == "ffp" then
            ms():setMedicalState(c.ped, "bloodVolume", math.min(5000, (snap.bloodVolume or 4000) + 250))
            ms():setMedicalState(c.ped, "anticoagulant", false)
            if (snap.bleeding or 0) > 0 then ms():setMedicalState(c.ped, "bleeding", snap.bleeding - 1) end
        else
            if (snap.bleeding or 0) > 0 then ms():setMedicalState(c.ped, "bleeding", snap.bleeding - 1) end
        end
        -- volume overload: many units fast in a small blood loss
        if (snap.bloodVolume or 4500) > 4800 and product ~= "platelets" then
            ms():setMedicalState(c.ped, "spo2", math.max(80, (snap.spo2 or 96) - 6))
            ER.log(c, "complication", "volume_overload", player)
        end
        ER.syncCase(c)
    end, dur * 1000, 1)
    return true
end

-- the group lab makes the group known; the crossmatch order (60 s) frees the matching units
addEvent("onERLabResult")
function ER.onLabResult(c, panel)
    if panel == "group" or panel == "full" then
        c.groupKnown = true
        c.bloodGroup = ms() and ms():getBloodGroup(c.ped) or c.bloodGroup
    end
    if panel == "crossmatch" then
        if c.groupKnown then c.crossmatched = true end
    end
end

-- Ú6: no 0 Rh- in the fridge and the bank for 10 min -> an emergency NPC shipment
local emptySince = {}
setTimer(function()
    for hid in pairs(ER.byHospital) do
        local s = stockOf(hid)
        local bank = s.rbc and tonumber(s.rbc["0-"]) or 0
        if ER.stockLeft(hid, "shock", "rbc_0neg") <= 0 and bank <= 0 then
            emptySince[hid] = emptySince[hid] or getTickCount()
            if getTickCount() - emptySince[hid] >= 600000 then
                emptySince[hid] = nil
                ER.fridgeAdd(hid, "rbc_0neg", 2)
                ER.fridgeAdd(hid, "ffp_ab", 2)
                ER.notifyStaff(hid, function(p) return L.forPlayer(p, "med_hospitals.transfusion.emergency_shipment") end)
            end
        else
            emptySince[hid] = nil
        end
    end
end, 30000, 0)
