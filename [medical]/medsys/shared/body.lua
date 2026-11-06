L.config(function()  -- texts are refreshed once the player is loaded (v_locals L.config)
-- Body parts of the injuries (core record: injury.part, injury.side, injury.cause).
-- The hospital (med_hospitals er/) builds its hidden findings, imaging and body map on them;
-- v_scenemanager stores them per injury in the scene files; the events module passes the GTA hit part.
--
-- part: head, face, neck, chest, abdomen, pelvis, spine_c, spine_t, spine_l, arm, leg, skin
-- side: "left" | "right" for the paired / sided parts, nil otherwise

MEDIC_PARTS = {
    head    = { label = L.text("medsys.body.head"), sided = true },     -- side = the side of the lesion (EDH, SDH ...)
    face    = { label = L.text("medsys.body.face") },
    neck    = { label = L.text("medsys.body.neck") },
    chest   = { label = L.text("medsys.body.chest"), sided = true },
    abdomen = { label = L.text("medsys.body.abdomen"), sided = true },  -- left: spleen, right: liver
    pelvis  = { label = L.text("medsys.body.pelvis"), sided = true },   -- hip / femoral neck side
    spine_c = { label = L.text("medsys.body.spine_c") },
    spine_t = { label = L.text("medsys.body.spine_t") },
    spine_l = { label = L.text("medsys.body.spine_l") },
    arm     = { label = L.text("medsys.body.arm"), sided = true },
    leg     = { label = L.text("medsys.body.leg"), sided = true },
    skin    = { label = L.text("medsys.body.skin") },                   -- burns: the body surface
}
MEDIC_SIDE_LABELS = { left = L.text("medsys.body.left"), right = L.text("medsys.body.right") }

-- Where an injury type lands when no part is given: { part, weight }. A type without a list is
-- systemic (no body part: overdose, intoxication, asthma attack ...).
MEDIC_PART_WEIGHTS = {
    fracture = { { "leg", 35 }, { "arm", 30 }, { "chest", 12 }, { "pelvis", 8 }, { "spine_l", 5 }, { "spine_t", 3 }, { "spine_c", 2 }, { "head", 5 } },
    gunshot = { { "chest", 30 }, { "abdomen", 20 }, { "arm", 18 }, { "leg", 22 }, { "head", 6 }, { "neck", 2 }, { "pelvis", 2 } },
    burn = { { "skin", 1 } },
    head_injury = { { "head", 1 } },
    stroke = { { "head", 1 } },
    suffocation = { { "neck", 1 } },
    asthma = { { "chest", 1 } },
    copd = { { "chest", 1 } },
    pulmonary_edema = { { "chest", 1 } },
}
-- the cause changes the odds (falls hurt legs, pelvis and spine; a car hits legs, pelvis, head)
MEDIC_PART_WEIGHTS_BY_CAUSE = {
    fall = { fracture = { { "leg", 35 }, { "pelvis", 15 }, { "spine_l", 15 }, { "spine_t", 5 }, { "arm", 15 }, { "head", 8 }, { "chest", 7 } } },
    vehicle_hit = { fracture = { { "leg", 35 }, { "pelvis", 20 }, { "head", 15 }, { "chest", 15 }, { "arm", 15 } } },
    crash = { fracture = { { "chest", 25 }, { "leg", 25 }, { "arm", 20 }, { "pelvis", 10 }, { "spine_c", 8 }, { "head", 12 } } },
    fist = { fracture = { { "face", 40 }, { "arm", 30 }, { "chest", 30 } } },
}

-- other part names accepted on input (events module GTA parts, editor shortcuts)
local ALIASES = {
    left_arm = { "arm", "left" }, right_arm = { "arm", "right" }, left_leg = { "leg", "left" }, right_leg = { "leg", "right" },
    spine = { "spine_l" }, back = { "spine_t" }, thorax = { "chest" }, belly = { "abdomen" }, hip = { "pelvis" },
}

local function pick(list, rnd)
    local total = 0
    for _, e in ipairs(list) do total = total + e[2] end
    local r = rnd() * total
    for _, e in ipairs(list) do
        r = r - e[2]
        if r < 0 then return e[1] end
    end
    return list[#list][1]
end

-- -> part, side (part nil = systemic). rnd: optional function returning [0, 1) (a seeded one for
-- reproducible scene injuries), math.random by default.
function medicResolvePart(injuryType, part, side, cause, rnd)
    rnd = rnd or math.random
    if type(part) == "string" then
        local alias = ALIASES[part]
        if alias then part, side = alias[1], side or alias[2] end
        if part == "torso" then
            -- GTA torso: chest or belly 60 / 40; a fall can break the spine
            if cause == "fall" and injuryType == "fracture" and rnd() < 0.25 then part = "spine_l"
            else part = rnd() < 0.6 and "chest" or "abdomen" end
        end
        if not MEDIC_PARTS[part] then part = nil end
    else
        part = nil
    end
    if not part then
        local byCause = cause and MEDIC_PART_WEIGHTS_BY_CAUSE[cause]
        local list = (byCause and byCause[injuryType]) or MEDIC_PART_WEIGHTS[injuryType]
        if not list then return nil, nil end
        part = pick(list, rnd)
    end
    if MEDIC_PARTS[part].sided then
        if side ~= "left" and side ~= "right" then side = rnd() < 0.5 and "left" or "right" end
    else
        side = nil
    end
    return part, side
end

-- Clinical time: 1 game hour = 10 real minutes (the S2 transfer "3 h = 30 min"). Every clinical time
-- window (STEMI door-to-balloon, stroke lysis 4.5 h, symptom onset) is counted with these.
MEDIC_CLINICAL_SCALE = 6
function medicClinicalHours(realSeconds) return (realSeconds or 0) * MEDIC_CLINICAL_SCALE / 3600 end
function medicRealSeconds(clinicalHours) return (clinicalHours or 0) * 3600 / MEDIC_CLINICAL_SCALE end

-- "Bal alkar" style label of a part + side (the viewer's language on the client)
function medicPartLabel(part, side)
    local p = MEDIC_PARTS[part]
    if not p then return nil end
    if side and MEDIC_SIDE_LABELS[side] then return MEDIC_SIDE_LABELS[side] .. " " .. L.lower(p.label) end
    return p.label
end
end)
