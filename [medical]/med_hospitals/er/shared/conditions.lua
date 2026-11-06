-- Findings of the medsys hospital conditions (medsys/shared/conditions.lua) for the ER: BNO, which
-- examination shows them (labPanels = lab panels, ecg = the 12-lead ECG, region = imaging, visible = the
-- exam shows it), the definitive care (surgery, lysis) and ERC.CONDITION_FINDINGS[type](injury) -> ids.

local F = ERC.FINDINGS
local function add(id, def) F[id] = def end

add("stemi_anterior", { region = "heart", bno = "I2100", cardiac = true, ecg = true, lysis = true, surgery = "pci", critical = true, labPanels = { cardiac = true, full = true } })
add("stemi_inferior", { region = "heart", bno = "I2110", cardiac = true, ecg = true, lysis = true, surgery = "pci", critical = true, labPanels = { cardiac = true, full = true } })
add("stemi_lateral", { region = "heart", bno = "I2120", cardiac = true, ecg = true, lysis = true, surgery = "pci", critical = true, labPanels = { cardiac = true, full = true } })
add("stemi_lm", { region = "heart", bno = "I2120", cardiac = true, ecg = true, surgery = "pci", critical = true, labPanels = { cardiac = true, full = true } })
add("nstemi", { region = "heart", bno = "I2140", cardiac = true, labPanels = { cardiac = true, full = true } })
add("appendicitis", { region = "abdomen", bno = "K3590", ct = "abd_normal", surgery = "appendectomy", labPanels = { inflam = true, full = true } })
add("renal_colic", { region = "abdomen", bno = "N23H0", ct = "abd_normal" })
add("gi_bleed", { region = "gi", bno = "K9220", labPanels = { basic = true, trauma = true, full = true }, transfer = true })
add("sepsis", { region = "systemic", bno = "A4190", labPanels = { inflam = true, full = true, abg = true }, icu = true })
add("dka", { region = "metabolic", bno = "E1010", labPanels = { abg = true, basic = true, full = true } })
add("pe", { region = "chest", bno = "I2690", ct = "chest_normal_lung", lysis = true, labPanels = { coag = true, full = true } })
add("anaphylaxis", { region = "systemic", bno = "T7820", visible = true })
add("hyperkalemia", { region = "metabolic", bno = "E8750", ecg = true, labPanels = { basic = true, abg = true, full = true } })
add("tamponade", { region = "chest", bno = "I3130", ct = "chest_normal_lung", surgery = "pericardiotomy", critical = true })
add("afib_f", { region = "heart", bno = "I48H0", ecg = true, cardiac = true })
add("avb3_f", { region = "heart", bno = "I4420", ecg = true, cardiac = true })
add("sprain", { region = "leg", bno = "S9340", visible = true, xr = { part = "ankle", img = "ankle_normal", sided = true } })
add("poison_paracetamol", { region = "tox", bno = "T3910", tox = "paracetamol" })
add("poison_tca", { region = "tox", bno = "T4300", tox = "tca", ecg = true })
add("poison_organophosphate", { region = "tox", bno = "T6000", tox = "organophosphate" })
add("poison_co", { region = "tox", bno = "T5801", tox = "carbon_monoxide", labPanels = { abg = true, full = true } })
add("poison_betablocker", { region = "tox", bno = "T4470", tox = "beta_blocker" })
add("poison_digoxin", { region = "tox", bno = "T4600", tox = "digoxin" })
add("poison_methanol", { region = "tox", bno = "T5110", tox = "methanol" })
add("poison_cyanide", { region = "tox", bno = "T6500", tox = "cyanide" })

add("transfusion_reaction", { region = "systemic", bno = "T8030", visible = true })

local WOUND = { arm = "wound_arm", leg = "wound_leg", head = "wound_head", face = "wound_head", neck = "wound_neck" }

ERC.CONDITION_FINDINGS = {
    acs = function(inj) return { inj.severity >= 2 and ("stemi_" .. (inj.territory or "anterior")) or "nstemi" } end,
    appendicitis = function() return { "appendicitis" } end,
    renal_colic = function() return { "renal_colic" } end,
    gi_bleed = function() return { "gi_bleed" } end,
    sepsis = function() return { "sepsis" } end,
    dka = function() return { "dka" } end,
    pe = function() return { "pe" } end,
    anaphylaxis = function() return { "anaphylaxis" } end,
    hyperkalemia = function() return { "hyperkalemia" } end,
    tamponade = function() return { "tamponade" } end,
    afib = function() return { "afib_f" } end,
    avb3 = function() return { "avb3_f" } end,
    sprain = function() return { "sprain" } end,
    laceration = function(inj) return { WOUND[inj.part or "arm"] or "wound_torso" } end,
    poison_paracetamol = function() return { "poison_paracetamol" } end,
    poison_tca = function() return { "poison_tca" } end,
    poison_organophosphate = function() return { "poison_organophosphate" } end,
    poison_co = function() return { "poison_co" } end,
    poison_betablocker = function() return { "poison_betablocker" } end,
    poison_digoxin = function() return { "poison_digoxin" } end,
    poison_methanol = function() return { "poison_methanol" } end,
    poison_cyanide = function() return { "poison_cyanide" } end,
}

-- lab panels reveal the findings that have them in labPanels
function ERC.labReveals(panel)
    local out = {}
    for id, d in pairs(F) do if d.labPanels and d.labPanels[panel] then out[id] = true end end
    return out
end
