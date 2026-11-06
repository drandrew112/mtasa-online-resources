-- ER rooms (plan: Helyiségek, Sokktalanító, Sebkezelő, Gipszelő):
--   * the room procedures of the patient panel ("Beavatkozások" tab): rank, room, consumable, why not
--   * the room rule of the medsys procedures (RSI only in the shock room; CPR / defib anywhere)
--   * the shock room's wall monitor connects by itself (no portable monitor needed)
--   * a triage suggestion from the measured values (for beginners; the decision is the player's)

local function ms() return ER.running("medsys") and exports.medsys or nil end
local function snapOf(c) return ms() and ms():getMedicalState(c.ped) or {} end
local function hasFinding(c, id, untreated)
    for _, f in ipairs(ER.findings(c)) do if f.id == id and (not untreated or not f.treated) then return f end end
end
local function inRoom(c, room) return tostring(c.location or ""):find("^" .. room) ~= nil end

-- id = { code, need (er.* activity), rooms = { room = true } | nil (anywhere), stock, time, cond(c) -> true | false, reasonKey, apply(c, player) }
ER.PROCEDURES = {
    { id = "needle_decompression", code = "HK-R07", need = "er.drain", rooms = { shock = true }, stock = "decompression_needle", time = 6,
      cond = function(c) return hasFinding(c, "ptx", true) and true or false, "proc_no_ptx" end,
      apply = function(c) local s = snapOf(c) if ms() then ms():setMedicalState(c.ped, "spo2", math.min(99, (s.spo2 or 85) + 10)) end end },
    { id = "pelvic_binder", code = "HK-C07", rooms = { shock = true }, stock = "pelvic_binder", time = 8,
      cond = function(c) return hasFinding(c, "pelvis_fx", true) and not c.binder and true or false, "proc_no_pelvis" end,
      apply = function(c) c.binder = true if ms() then local s = snapOf(c) ms():setMedicalState(c.ped, "bleeding", math.max(0, (s.bleeding or 1) - 1)) end end },
    { id = "ventilator", code = "HK-R06", need = "er.icu", rooms = { shock = true, icu = true }, time = 6,
      cond = function(c) return snapOf(c).intubated and not c.ventilator and true or false, "proc_not_intubated" end,
      apply = function(c) c.ventilator = { mode = "VC", fio2 = 60, peep = 5, rr = 14, vt = 450 } end },
    { id = "abg", code = "HK-L06", rooms = { shock = true, icu = true }, stock = "abg_syringe", time = 5,
      cond = function() return true end,
      apply = function(c, player)
          -- the arterial sample goes to the blood gas analyser of the shock room (30 s)
          local o = ER.order(c, player, "lab.abg")
          if not o then return end
          o.status, o.drawErrors, o.ends = "running", {}, getRealTime().timestamp + 30
          setTimer(function() ER.finishOrder(c, o, player) end, 30000, 1)
      end },
    { id = "cpap", code = "HK-R11", need = "er.order", rooms = { shock = true, icu = true }, time = 6,
      cond = function(c) local s = snapOf(c) return (s.spo2 or 99) < 92 and not s.intubated and not c.cpap, "proc_no_hypoxia" end,
      apply = function(c) c.cpap = true if ms() then local s = snapOf(c) ms():setMedicalState(c.ped, "spo2", math.min(97, (s.spo2 or 88) + 6)) end end },
    { id = "local_anaesthesia", code = "HK-S03", need = "er.suture", rooms = { wound = true, cast = true }, stock = "lidocaine", time = 5,
      cond = function(c) return not c.localAnaesthesia, "proc_done" end,
      apply = function(c) c.localAnaesthesia = true end },
    { id = "disinfection", code = "HK-S02", rooms = { wound = true }, stock = "povidone", time = 4,
      cond = function(c) return not c.disinfected, "proc_done" end, apply = function(c) c.disinfected = true end },
    { id = "final_dressing", code = "HK-S06", rooms = { wound = true }, stock = "sterile_dressing", time = 5,
      cond = function(c)
          for _, f in ipairs(ER.findings(c)) do local d = ERC.FINDINGS[f.id] if d and d.suture and f.treated and not f.dressed then return true end end
          return false, "proc_no_sutured"
      end,
      apply = function(c) for _, f in ipairs(ER.findings(c)) do local d = ERC.FINDINGS[f.id] if d and d.suture and f.treated then f.dressed = true end end end },
    { id = "sling", code = "HK-S13", rooms = { cast = true }, stock = "sling", time = 4,
      cond = function(c) local f = hasFinding(c, "radius_fx") or hasFinding(c, "humerus_fx") return f and f.treated and not c.sling and true or false, "proc_no_arm_cast" end,
      apply = function(c) c.sling = true end },
    { id = "urinary_catheter", code = "HK-T04", time = 8, cond = function(c) return not c.catheter, "proc_done" end, apply = function(c) c.catheter = true end },
    { id = "ng_tube", code = "HK-T05", time = 8, cond = function(c) return not c.ngTube, "proc_done" end, apply = function(c) c.ngTube = true end },
    { id = "observation", code = "HK-V15", time = 4,
      cond = function(c) return (getRealTime().timestamp - (c.lastObservation or 0)) > 300, "proc_too_soon" end,
      apply = function(c) c.lastObservation = getRealTime().timestamp end },
    { id = "consult", code = "HK-A13", need = "er.order", time = 3, cond = function() return true end,
      apply = function(c, player) if ER.requestConsult then ER.requestConsult(c, player) end end },
}
local BY_ID = {}
for _, p in ipairs(ER.PROCEDURES) do BY_ID[p.id] = p end

local function rankOf(p)
    if not p.need then return "nurse" end
    local acts = HOSPW_ACTIVITY_RANK and HOSPW_ACTIVITY_RANK[p.need]
    return acts or ({ ["er.drain"] = "physician", ["er.icu"] = "physician", ["er.order"] = "resident", ["er.suture"] = "resident" })[p.need] or "resident"
end

-- -> true | reason text (in the viewer's language)
local function availability(c, p, viewer)
    if p.rooms then
        local ok = false
        for room in pairs(p.rooms) do if inRoom(c, room) then ok = true end end
        if not ok then
            local names = {}
            for room in pairs(p.rooms) do names[#names + 1] = L.forPlayer(viewer, "med_hospitals.his.pool_" .. room) end
            return L.forPlayer(viewer, "med_hospitals.proc.needs_room", { room = table.concat(names, " / ") })
        end
    end
    if p.need then
        local ok, needName = ER.can(viewer, p.need)
        if not ok then return L.forPlayer(viewer, "med_hospitals.er.rank_needed", { rank = needName or "?" }) end
    end
    local ok, why = p.cond(c)
    if not ok then return L.forPlayer(viewer, "med_hospitals.proc." .. tostring(why or "proc_not_needed")) end
    if p.stock and ER.stockLeft and ER.stockLeft(c.hospital, ERC.stockPool(c.location), p.stock) <= 0 and ER.stockLeft(c.hospital, "nurse", p.stock) <= 0 then
        return L.forPlayer(viewer, "med_hospitals.stock.out_of", { what = L.forPlayer(viewer, "med_hospitals.stock.item_" .. p.stock) })
    end
    return true
end

function ER.procedureList(c, viewer)
    local out = {}
    for _, p in ipairs(ER.PROCEDURES) do
        out[#out + 1] = { id = p.id, available = availability(c, p, viewer), rank = rankOf(p), code = p.code, stock = p.stock }
    end
    return out
end

function ER.doProcedure(c, player, id)
    local p = BY_ID[id]
    if not p then return false end
    local ok = availability(c, p, player)
    if ok ~= true then return ER.notify(player, tostring(ok), true) end
    local px, py, pz = getElementPosition(player)
    local x, y, z = getElementPosition(c.ped)
    if getDistanceBetweenPoints3D(px, py, pz, x, y, z) > 3.2 then return ER.notify(player, L.forPlayer(player, "med_hospitals.exam.too_far"), true) end
    if p.stock and not ER.useStock(c, p.stock, 1) then return false end
    ER.notify(player, L.forPlayer(player, "med_hospitals.erc.started", { what = L.forPlayer(player, "med_hospitals.proc." .. id), s = p.time }))
    setPedAnimation(player, "MEDIC", "CPR", p.time * 1000, false, false, false, false)
    setTimer(function()
        if not ER.cases[c.ped] then return end
        if isElement(player) then setPedAnimation(player) end
        p.apply(c, player)
        if isElement(player) then ER.award(player, c, p.code, 0, "med_docs.code." .. p.code:lower():gsub("%-", "_")) end
        ER.log(c, "procedure", id, player)
        ER.syncCase(c)
    end, p.time * 1000, 1)
    return true
end

-- NPC consultant: reads the confirmed findings and says what the patient needs
function ER.requestConsult(c, player)
    local shown = {}
    for _, r in ipairs(c.results or {}) do for _, fid in ipairs(r.findings or {}) do shown[fid] = true end end
    local key, p = "consult_none", {}
    for _, f in ipairs(ER.findings(c)) do
        local d = ERC.FINDINGS[f.id]
        if d and shown[f.id] and not f.treated then
            if d.surgery then key, p = "consult_surgery", { what = L.forPlayer(player, "med_hospitals.erc.surgery_" .. d.surgery) } break end
            if d.lysis then key = "consult_neuro" break end
            if d.icu then key = "consult_icu" break end
        end
    end
    ER.log(c, "consult", key, player)
    ER.notify(player, L.forPlayer(player, "med_hospitals.proc." .. key, p))
end

---------------------------------------------------------------- room rule of the medsys procedures

local SHOCK_ONLY = { airway = true }
local SHOCK_DRUGS = { ketamine = true, rocuronium = true, propofol = true, noradrenaline = true, alteplase = true }

function ER.roomRule(c, medic, action, option)
    if inRoom(c, "shock") or inRoom(c, "icu") then return true end
    local s = snapOf(c)
    if s.clinicalDeath or s.dead then return true end   -- resuscitation goes on anywhere
    if action == "airway" and s.consciousness == "unconscious" then return true end   -- airway rescue of a comatose patient (K10)
    if SHOCK_ONLY[action] then return false, L.forPlayer(medic, "med_hospitals.proc.shock_only") end
    if action == "medication" and SHOCK_DRUGS[tostring(option)] then return false, L.forPlayer(medic, "med_hospitals.proc.shock_only") end
    return true
end

---------------------------------------------------------------- shock room: the wall monitor connects by itself

setTimer(function()
    if not ms() then return end
    for ped, c in pairs(ER.cases) do
        if isElement(ped) and inRoom(c, "shock") and not c.dead then
            local s = snapOf(c)
            if not s.monitor and not s.dead then
                ms():setMedicalState(ped, "monitor", true)
                ER.log(c, "monitor", "wall")
            end
        end
    end
end, 3000, 0)

---------------------------------------------------------------- triage suggestion

-- from the values measured so far (monitor or the vital signs exam), the consciousness and the findings
function ER.triageSuggest(c)
    local s = snapOf(c)
    local m = c.measured or {}
    local hr = s.monitor and s.heartRate or m.hr
    local spo2 = s.monitor and s.spo2 or m.spo2
    local sys = s.monitor and s.systolic or (m.bp and tonumber(tostring(m.bp):match("^(%d+)")))
    if s.clinicalDeath or s.consciousness == "unconscious" then return 1 end
    if (spo2 and spo2 < 88) or (sys and sys < 85) or (hr and (hr > 140 or hr < 40)) then return 1 end
    for _, f in ipairs(ER.findings(c)) do local d = ERC.FINDINGS[f.id] if d and d.critical and (c.results and #c.results > 0) then return 1 end end
    if s.consciousness == "dazed" or s.consciousness == "confused" then return 2 end
    if (spo2 and spo2 < 93) or (sys and sys < 100) or (hr and hr > 120) or (s.pain or 0) >= 70 then return 2 end
    if not (hr or spo2 or sys) then return nil end   -- nothing measured yet
    if (s.pain or 0) >= 40 then return 3 end
    for _, inj in ipairs(s.injuries or {}) do if (inj.severity or 1) >= 2 then return 3 end end
    return 4
end
