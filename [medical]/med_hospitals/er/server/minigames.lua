-- ER minigames ([minigames]/mg_*): the hands-on part of the orders and the room treatments. The result
-- (0-100 % + details) changes the outcome: a bad blood draw spoils the lab values, a FAST window not
-- read is "not evaluable", a too tight cast must be redone, a wrong drain spot bleeds.
--   ER.minigame(kind, player, c, options, done)  done(success, percent, details, reason)
-- Without the minigame resource the step runs on a short timer with an average result.

local GAMES = {
    suture     = { res = "mg_suture",     start = "startSutureGame",     event = "onSutureGameFinish" },
    irrigation = { res = "mg_irrigation", start = "startIrrigationGame", event = "onIrrigationGameFinish" },
    cast       = { res = "mg_cast",       start = "startCastGame",       event = "onCastGameFinish" },
    reduction  = { res = "mg_reduction",  start = "startReductionGame",  event = "onReductionGameFinish" },
    blooddraw  = { res = "mg_blooddraw",  start = "startBloodDrawGame",  event = "onBloodDrawGameFinish" },
    fast       = { res = "mg_fast",       start = "startFastGame",       event = "onFastGameFinish" },
    chestdrain = { res = "mg_chestdrain", start = "startChestDrainGame", event = "onChestDrainGameFinish" },
    ecg        = { res = "mg_ecg",        start = "startEcgGame",        event = "onEcgGameFinish" },
}
local sessions = {}   -- [player] = { kind, case, done, id }

function ER.minigameRunning(player) return sessions[player] ~= nil end

function ER.minigame(kind, player, c, options, done)
    local g = GAMES[kind]
    if not g or sessions[player] then return false end
    triggerClientEvent(player, "his:hide", resourceRoot)
    if ER.running(g.res) then
        local ok, id = pcall(function() return exports[g.res][g.start](exports[g.res], player, c.ped, options or {}) end)
        if ok and id then
            sessions[player] = { kind = kind, case = c, done = done, id = id }
            return true
        end
    end
    -- no minigame: a plain timed step, average result
    sessions[player] = { kind = kind, case = c, done = done, fallback = true }
    setPedAnimation(player, "MEDIC", "CPR", 6000, false, false, false, false)
    setTimer(function()
        local s = sessions[player]
        sessions[player] = nil
        if s and s.done then s.done(true, 70, {}, "fallback") end
    end, 6000, 1)
    return true
end

for kind, g in pairs(GAMES) do
    addEvent(g.event)
    addEventHandler(g.event, root, function(success, percent, reason, sessionId, details)
        local s = sessions[source]
        if not s or s.kind ~= kind or (s.id and sessionId and s.id ~= sessionId) then return end
        sessions[source] = nil
        if reason == "cancelled" or reason == "quit" or reason == "died" or reason == "invalid" then
            ER.notify(source, L.forPlayer(source, "med_hospitals.mg.cancelled"), true)
            if s.done then s.done(false, 0, details or {}, reason) end
            return
        end
        ER.log(s.case, "minigame", kind .. " " .. tostring(math.floor(percent or 0)) .. "%", source)
        if s.done then s.done(success == true, tonumber(percent) or 0, details or {}, reason) end
    end)
end

addEventHandler("onPlayerQuit", root, function() sessions[source] = nil end)

-- 12-lead ECG electrode guide (mg_ecg options.guide): for Nurses and Residents, not from Physician up
function ER.ecgGuide(player)
    if not ER.running("work_core") then return true end
    local ok, has = pcall(function() return exports.work_core:hasCompetency(player, "hospital", "physician") end)
    return not (ok and has == true)
end

-- A badly done minigame (the minigame's own pass rule not met) gives no result: no finding, no points,
-- no document; the order goes back to "ordered" / the treatment stays to do, so it can be retried.
function ER.minigameFailed(player, c, kind)
    ER.log(c, "minigame", tostring(kind) .. " failed", player)
    ER.notify(player, L.forPlayer(player, "med_hospitals.mg.failed_retry", { what = L.forPlayer(player, "med_hospitals.mg.name_" .. tostring(kind)) }), true)
    return false
end

---------------------------------------------------------------- helpers for the callers

-- the patient got a painkiller / sedative (reduction without it hurts: mg_reduction analgesia)
function ER.hasAnalgesia(c)
    local snap = ER.running("medsys") and exports.medsys:getMedicalState(c.ped) or {}
    for _, d in ipairs(snap.drugs or {}) do
        if d.id == "fentanyl" or d.id == "morphine" or d.id == "ketamine" or d.id == "midazolam" or d.id == "propofol"
            or d.id == "metamizole" or d.id == "lidocaine" then return true end
    end
    return false
end

-- blood tubes of a lab panel (mg_blooddraw options.tubes)
local PANEL_TUBES = {
    basic = { "serum", "edta" }, trauma = { "citrate", "serum", "edta" }, cardiac = { "serum" }, coag = { "citrate" },
    abg = { "heparin" }, tox = { "serum", "fluoride" }, group = { "edta" }, crossmatch = { "edta" }, inflam = { "serum", "edta" },
    full = { "citrate", "serum", "heparin", "edta", "fluoride" },
}
function ER.panelTubes(panel) return PANEL_TUBES[panel] or { "serum", "edta" } end

-- FAST windows that show fluid / no lung sliding: { ruq, luq, pelvis, cardiac, lung_r, lung_l }
function ER.fastPositives(c)
    local pos = {}
    for _, f in ipairs(ER.findings(c)) do
        if f.id == "liver" then pos.ruq = true end
        if f.id == "spleen" then pos.luq = true end
        if f.id == "gsw_abdomen" then pos.ruq, pos.pelvis = true, true end
        if f.id == "pelvis_fx" then pos.pelvis = true end
        if f.id == "tamponade" then pos.cardiac = true end
        if f.id == "ptx" or f.id == "htx" then pos[f.side == "left" and "lung_l" or "lung_r"] = true end
    end
    return pos
end
