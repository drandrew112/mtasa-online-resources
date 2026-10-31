-- Medical status (medsys, optional at runtime): every AI ped is a persistent medsys patient, so a medic can always
-- examine it, and the medsys events module injures it (a hit that would kill puts it down instead of killing it).
-- While medsys keeps it dazed / unconscious / in clinical death the ped has the "downed" behaviour (medsys plays
-- the animation); once it is up again it goes back to what it was doing. medsys' biological death kills the ped
-- (then the usual "dead" behaviour).

AIPedsMedical = {}

local T = AIPEDS
local DOWN = { dazed = true, unconscious = true, clinical_death = true }
-- behaviour after getting up (the args they had are gone: civilian keeps its task, the others wait for their owner)
local RESUME = { civilian = "civilian", scared = "civilian", enemy = "enemy", police = "police", patient = "patient",
    detained = "detained", cuffed = "cuffed" }
local NO_DOWN = { dead = true, downed = true, exiting = true, seated = true }

local function medsys()
    local res = getResourceFromName("medsys")
    return res and getResourceState(res) == "running" and exports.medsys or nil
end

-- called for every new / adopted ped (Peds register)
function AIPedsMedical.register(el, kind)
    if not T.MEDICAL or not T.MEDICAL_KINDS[kind] then return end
    if T.MEDICAL_SAVE_KINDS[kind] then setElementData(el, DATA_SAVE_LETHAL, true) end
    local ms = medsys()
    if ms then pcall(function() ms:setPatientPersistent(el, true) end) end
end

local function down(p)
    if p.dead or p.removed or NO_DOWN[p.behaviour] or p.vt or getPedOccupiedVehicle(p.el) then return end
    Peds.setBehaviour(p, "downed", { resume = RESUME[p.behaviour] or "civilian" })
end

local function up(p)
    if p.behaviour ~= "downed" or p.removed then return end
    Peds.setBehaviour(p, p.b.resume or "civilian", {})
end

local function check(p)
    if not isElement(p.el) then return end
    local status = getElementData(p.el, MEDICAL_STATUS)
    if DOWN[status] then down(p) else up(p) end
end

-- Behaviour "downed": lies / sits where it fell, does nothing (threats are ignored, no cull while a player is near)
Behaviours.downed = {
    enter = function(p, args)
        p.b.resume = args.resume
        Peds.idle(p)
    end,
    update = function() end,
}

addEvent("onMedicalStateChange")
addEventHandler("onMedicalStateChange", root, function()
    local p = Peds.get(source)
    if p then check(p) end
end)

-- catches what the event cannot: a ped that got out of a vehicle down, a script that changed the behaviour
setTimer(function()
    if not T.MEDICAL then return end
    for _, p in pairs(Peds.list) do
        if not p.dead then check(p) end
    end
end, T.MEDICAL_CHECK, 0)

-- medsys (re)started after ai_peds: every ped gets its status again
addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) ~= "medsys" then return end
    setTimer(function()
        for el, p in pairs(Peds.list) do
            if isElement(el) and not p.dead then AIPedsMedical.register(el, p.kind) end
        end
    end, 500, 1)
end)
