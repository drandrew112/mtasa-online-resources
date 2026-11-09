-- ER documents through med_docs: Ambuláns lap (at the outcome), Labor / CT / Röntgen / UH / EKG
-- lelet (every result), Műtéti leírás and Halottvizsgálati bizonyítvány. Stored structured (codes);
-- the language is the author's (the treating / performing staff member). The numbers of the documents
-- made for a case come back (onMedicalDocumentCreated) and go into "Kapcsolódó dokumentumok".

local function docs() return ER.running("med_docs") and exports.med_docs or nil end
local function now() return getRealTime().timestamp end

local function caseRef(c) return "er:" .. c.hospital .. ":" .. c.id .. ":" .. (c.created or 0) end

local function baseMeta(c, author)
    return { author = author or c.treating or c.treatingName or "", hospital = c.hospital, caseRef = caseRef(c),
             patient = c.name or "", citizenId = c.citizenId }
end

local function patientBlock(c)
    return { name = c.name or false, age = c.age or false, gender = c.gender or false, birth = c.birth or false, cid = c.citizenId or false }
end

local function hospitalName(c) local h = Hospitals.byId[c.hospital] return h and h.name or c.hospital end

-- related documents: the numbers of the result documents of the case
addEvent("onMedicalDocumentCreated")
addEventHandler("onMedicalDocumentCreated", root, function(id, no, dtype, ref)
    if type(ref) ~= "string" or not ref:find("^er:") then return end
    for _, c in pairs(ER.cases) do
        if caseRef(c) == ref then
            c.docNos = c.docNos or {}
            if dtype ~= "amb" then c.docNos[#c.docNos + 1] = { type = dtype, no = no } end
            return
        end
    end
end)

function ER.writeResultDoc(c, r, author)
    local d = docs()
    if not d then return end
    local kind = r.kind == "lab" and "lab" or r.kind
    local body = { patient = patientBlock(c), order = r.key, at = r.at, issued = now(), findings = r.findings, positive = r.positive,
                   values = r.values, images = r.images, image = r.image, rhythm = r.rhythm, spec = r.spec, side = r.side,
                   windows = r.windows, control = r.control, hospitalName = hospitalName(c),
                   performer = isElement(author) and (getElementData(author, "displayName") or getPlayerName(author)) or false, auto = r.kind == "lab" }
    d:createDocument(kind, baseMeta(c, author), body)
end

function ER.writeAmbulatory(c, outcome, author)
    local d = docs()
    if not d then return end
    local snap = ER.running("medsys") and exports.medsys:getMedicalState(c.ped) or {}
    -- interventions: code, count, paid points (the code table * ERC.POINT_MULT; the per-case limit counts)
    local items = {}
    for code, n in pairs(c.done or {}) do
        local def = ERC.CODES and ERC.CODES[code]
        local counted = def and math.min(n, def.limit or n) or n
        items[#items + 1] = { code = code, n = n, points = def and def.points * counted * (ERC.POINT_MULT or 1) or 0 }
    end
    table.sort(items, function(a, b) return a.code < b.code end)
    local care = {}
    for _, e in ipairs(c.events or {}) do
        if e.kind == "medsys" or e.kind == "treat" or e.kind == "procedure" then care[#care + 1] = { at = e.at, what = e.text, by = e.by } end
    end
    local diagnoses = {}
    for _, code in ipairs(c.diagnoses or {}) do diagnoses[#diagnoses + 1] = { code = code, at = c.diagnosisAt and c.diagnosisAt[code] or now() } end
    local p = c.pending or {}
    local body = {
        hospitalName = hospitalName(c),
        patient = patientBlock(c),
        arrival = c.arrival, arrivedAt = c.created, anamnesis = c.anamnesis or (c.arrival and c.arrival.text) or "",
        statusText = c.statusText or "",
        status = { hr = snap.heartRate, bp = snap.bloodPressure, spo2 = snap.spo2, consciousness = snap.consciousness, pain = snap.pain,
                   gcs = c.gcs, temperature = c.temperature, nrs = c.nrs },
        triage = c.triage, treating = c.treatingName or false,
        interventions = items, care = care, diagnoses = diagnoses, epicrisis = c.epicrisis or "",
        results = (function() local out = {} for _, r in ipairs(c.results or {}) do out[#out + 1] = { key = r.key, at = r.at, findings = r.findings } end return out end)(),
        related = c.docNos or {},
        outcome = outcome, department = p.department or false, place = c.location or "", risky = c.riskyDischarge or false,
        surgeries = c.surgeries or {}, closedAt = now(), reopened = c.reopened or 0,
    }
    d:createDocument("amb", baseMeta(c, author), body)
end

function ER.writeDeathCertificate(c, author)
    local d = docs()
    if not d then return end
    d:createDocument("death", baseMeta(c, author or c.deathBy), {
        hospitalName = hospitalName(c), patient = patientBlock(c), at = c.deathAt or now(),
        by = c.deathBy or "", diagnoses = c.diagnoses or {}, place = c.location or "",
        cause = c.deathCause or false, circumstances = c.deathCircumstances or "", collectedBy = c.collectedBy or false,
        arrivedDead = c.doa or false, arrival = c.created, surgeries = c.surgeries or {},
    })
end

-- result: "success" | "complication" | "death"
function ER.writeOpNote(c, surgery, result, startedAt, bloodLoss)
    local d = docs()
    if not d then return end
    d:createDocument("op", baseMeta(c, "NPC"), {
        hospitalName = hospitalName(c), patient = patientBlock(c), surgery = surgery, result = result,
        success = result ~= "death", code = ERC.SURGERIES[surgery] and ERC.SURGERIES[surgery].code or false,
        started = startedAt, finished = now(), diagnoses = c.diagnoses or {}, bloodLoss = bloodLoss or 0,
        surgeon = "NPC", transfusions = #(c.transfusions or {}),
    })
end
