-- mg_ecg: 12-lead ECG electrode placement (HK-E01). Drag the ten electrodes from the tray onto the
-- patient: RA / LA / RL / LL on the limbs, V1-V2 in the 4th intercostal space at the two edges of the
-- sternum, V4 in the 5th intercostal space on the mid-clavicular line, V3 between V2 and V4, V5 / V6
-- laterally at the level of V4 (anterior / mid axillary line). The preview on the right draws the
-- curves live: swapped RA / LA gives a negative lead I, a misplaced V electrode a broken R progression.
-- Record with the button (or ENTER) once all ten are on.

ECG = {
    ELECTRODES = { "RA", "LA", "RL", "LL", "V1", "V2", "V3", "V4", "V5", "V6" },
    COLORS = { RA = { 240, 240, 240 }, LA = { 30, 30, 30 }, RL = { 47, 158, 90 }, LL = { 211, 51, 51 },
               V1 = { 211, 51, 51 }, V2 = { 230, 190, 40 }, V3 = { 47, 158, 90 }, V4 = { 56, 120, 230 },
               V5 = { 229, 130, 42 }, V6 = { 142, 91, 198 } },
    LIMB_TOL = 52,             -- design px around a limb target
    V_TOL = 22,                -- design px around a chest target (the body is 1.2x bigger since 2026-11-06)
    R_TRAY = 22,               -- electrode radius in the tray / while dragged (design px)
    R_PLACED = 16,             -- electrode radius on the patient
    KEY_RECORD = "enter",
}

MGDEF = {
    res = "mg_ecg", serverEvent = "onEcgGameFinish", clientEvent = "onClientEcgGameFinish",
    testCommand = "ecgtest",
    details = { correct = "number", swapRALA = "boolean", wrongLimb = "number", wrongV = "number", placed = "number" },
}

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

-- options: { time = 60, passPercent = 80, stand = nil, guide = false }
-- guide = true (hospital Nurse / Resident): the target spots are labelled, the spot of the electrode
-- in hand is highlighted
function MGDEF.normalize(o)
    o = type(o) == "table" and o or {}
    return {
        time = clamp(tonumber(o.time) or 60, 20, 150),
        passPercent = clamp(tonumber(o.passPercent) or 80, 0, 100),
        stand = (o.stand == true or o.stand == false) and o.stand or nil,
        guide = o.guide == true,
    }
end

function MGDEF.minDuration(o) return 5 end

function MGDEF.pass(percent, details, o) return percent >= o.passPercent and details.swapRALA ~= true end
