-- v_voiceclient_connector / server/codes.lua
-- The radio code database. One entry per supported work (work_core id):
--   resource   the resource that executes the codes (exports.<resource>:radioCommand(player, id, args))
--   codes      radio codes: id = the name id of the target resource, desc + examples = for the AI,
--              args.note = "required" -> the AI must also give a free text note
--   questions  Q_ codes: the message is a radio request of this work but not specific enough;
--              text = v_locals key of the question the player gets as subtitle
-- RAD_ERROR codes (Codes.ERRORS) belong to every work.
--
-- The labels of the codes (success subtitle) come from the target resource (getRadioCodes);
-- a code the target does not know (resource stopped / renamed) is left out of the AI prompt.

Codes = {}

Codes.ERRORS = {
    { id = "RAD_ERROR_NOT_FOUND",
      desc = "The message is a request, but nothing in the radio code list matches it (no such radio code for this work).",
      text = "v_voiceclient_connector.error.not_found" },
    { id = "RAD_ERROR_UNPARSEABLE",
      desc = "The text cannot be interpreted: noise, broken or cut-off speech, gibberish, random words, unrelated chatter.",
      text = "v_voiceclient_connector.error.unparseable" },
    { id = "RAD_ERROR_UNKNOWN",
      desc = "Any other problem that none of the codes above describes.",
      text = "v_voiceclient_connector.error.unknown" },
}

Codes.WORKS = {
    ems = {
        resource = "med_erm",
        label = "v_voiceclient_connector.work.ems",
        intro = "The speaker is an EMS (ambulance) crew member on duty. The radio is used for backup units and for requesting the police (another agency) to the crew's active case.",
        codes = {
            { id = "BACKUP_AMBULANCE",
              desc = "Requests any free transporting ambulance (BLS or ALS, whichever is nearer) - only when the speaker says any ambulance will do or asks an ambulance for transport without a level.",
              examples = { "Kérek egy bármilyen mentőautót", "Szállító mentőt kérek", "Any ambulance for transport please" } },
            { id = "BACKUP_BLS",
              desc = "Requests a BLS (basic life support) ambulance as backup.",
              examples = { "Kérek egy BLS egységet", "Esetkocsi nem kell, egy BLS mentő elég", "Need a BLS unit" } },
            { id = "BACKUP_ALS",
              desc = "Requests an ALS (advanced life support) ambulance as backup.",
              examples = { "ALS egységet kérek", "Kérek egy esetkocsit ALS szinten", "Requesting ALS backup" } },
            { id = "BACKUP_DOC",
              desc = "Requests a doctor car (DOC, physician unit) as backup.",
              examples = { "Orvost kérek a helyszínre", "Kérek egy rohamkocsit orvossal", "Need a doctor car" } },
            { id = "BACKUP_HELI",
              desc = "Requests the air ambulance (helicopter, HELI).",
              examples = { "Kérem a mentőhelikoptert", "Légimentőt kérek", "Requesting air ambulance" } },
            { id = "BACKUP_SOLO",
              desc = "Requests a solo responder unit (SOLO, single paramedic car / motorbike).",
              examples = { "Kérek egy solo egységet", "Need a solo responder" } },
            { id = "AGENCY_POLICE_SECURITY",
              desc = "Requests the police for scene security (securing / protecting the scene).",
              examples = { "Rendőrt kérek a helyszín biztosításához", "Requesting PD for scene security" } },
            { id = "AGENCY_POLICE_TRAFFIC",
              desc = "Requests the police for traffic control (road closure, traffic accident traffic management).",
              examples = { "Rendőrt kérek forgalomirányításhoz", "Need PD for traffic control" } },
            { id = "AGENCY_POLICE_VIOLENT",
              desc = "Requests the police because of an aggressive / violent person on scene.",
              examples = { "Agresszív a beteg, rendőrt kérek", "Violent patient, need police" } },
            { id = "AGENCY_POLICE_CRIME",
              desc = "Requests the police because a crime is suspected (stabbing, shooting, assault, abuse).",
              examples = { "Bűncselekmény gyanúja, kérem a rendőrséget", "Possible crime, requesting PD" } },
            { id = "AGENCY_POLICE_DEATH",
              desc = "Requests the police because of a death on scene.",
              examples = { "Halál a helyszínen, rendőrt kérek", "Deceased on scene, need PD" } },
            { id = "AGENCY_POLICE_OTHER",
              desc = "Requests the police for a reason that is none of the above; the reason itself goes to note.",
              examples = { "Rendőrt kérek, mert elzárták a bejáratot", "Need PD, the patient's dog is blocking the door" },
              args = { note = "required" } },
        },
        questions = {
            { id = "Q_EMS_BACKUP_TYPE",
              desc = "Asks for backup / another unit / an ambulance but does not say which kind of unit (BLS, ALS, doctor car, helicopter, solo, or any ambulance).",
              text = "v_voiceclient_connector.q.ems_backup_type" },
            { id = "Q_EMS_AGENCY_REASON",
              desc = "Asks for the police but gives no reason.",
              text = "v_voiceclient_connector.q.ems_agency_reason" },
            { id = "Q_EMS_AGENCY_NOTE",
              desc = "Asks for the police for an 'other' reason but the reason itself is missing.",
              text = "v_voiceclient_connector.q.ems_agency_note" },
            { id = "Q_EMS_GENERAL",
              desc = "Clearly speaks to dispatch with a request, but it is not clear what is requested.",
              text = "v_voiceclient_connector.q.ems_general" },
        },
    },

    police = {
        resource = "police_system",
        label = "v_voiceclient_connector.work.police",
        intro = "The speaker is a police officer on duty in a unit. The radio is used for unit status, backup / services and lookups (the existing police radio messages).",
        codes = {
            { id = "STATUS_AVAILABLE",
              desc = "Unit status Available: free, back in service, ready for calls (10-8).",
              examples = { "Szabad vagyok", "Egység szabad, hívásra kész", "10-8, available" } },
            { id = "STATUS_RESPONDING",
              desc = "Unit status Responding: en route to a call.",
              examples = { "Vonulunk", "Úton vagyok a helyszínre", "Responding" } },
            { id = "STATUS_BUSY",
              desc = "Unit status Busy: occupied, not available for calls (10-6).",
              examples = { "Foglalt vagyok", "Elfoglalt, nem tudok hívást vállalni", "10-6, busy" } },
            { id = "STATUS_PURSUIT",
              desc = "Starts a pursuit (the unit is chasing a vehicle or person).",
              examples = { "Üldözésbe kezdtem", "Menekül a jármű, üldözöm", "In pursuit" } },
            { id = "CODE_4",
              desc = "Code 4: the situation is under control, no further assistance needed, the current incident / stop ends.",
              examples = { "Code 4", "A helyzet kezelve, nincs szükség segítségre", "Code 4, all clear" } },
            { id = "REQUEST_BACKUP",
              desc = "Requests police backup (more officers) to the unit's location.",
              examples = { "Erősítést kérek", "Kérek még egy egységet", "Requesting backup" } },
            { id = "REQUEST_AMBULANCE",
              desc = "Requests an ambulance (EMS) to the unit's location.",
              examples = { "Mentőt kérek", "Sérült van, kérek egy mentőt", "Need EMS" } },
            { id = "REQUEST_TOW",
              desc = "Requests a tow truck for a vehicle.",
              examples = { "Vontatót kérek", "Kérek egy autómentőt", "Requesting a tow" } },
            { id = "REQUEST_TRANSPORT",
              desc = "Requests prisoner transport for a cuffed suspect.",
              examples = { "Fogolyszállítást kérek", "Kérek egy rabszállítót", "Need prisoner transport" } },
            { id = "QUERY_PERSON",
              desc = "Requests a check of the nearest person (ID / records lookup).",
              examples = { "Kérem a személy ellenőrzését", "Futtasd le ezt a személyt", "Run this person" } },
            { id = "QUERY_VEHICLE",
              desc = "Requests a check of the nearest vehicle (plate / owner lookup).",
              examples = { "Ellenőrizd a rendszámot", "Kérem a jármű lekérdezését", "Run the plate" } },
        },
        questions = {
            { id = "Q_POLICE_STATUS",
              desc = "Wants to change the unit status but it is not clear which (available, responding, busy, pursuit, code 4).",
              text = "v_voiceclient_connector.q.police_status" },
            { id = "Q_POLICE_REQUEST",
              desc = "Requests help / a service but does not say what (backup, ambulance, tow truck or prisoner transport).",
              text = "v_voiceclient_connector.q.police_request" },
            { id = "Q_POLICE_QUERY",
              desc = "Wants a check / lookup but it is not clear whether of a person or a vehicle.",
              text = "v_voiceclient_connector.q.police_query" },
            { id = "Q_POLICE_GENERAL",
              desc = "Clearly speaks to dispatch with a request, but it is not clear what is requested.",
              text = "v_voiceclient_connector.q.police_general" },
        },
    },
}

-- [workId] = { [id] = label key } as reported by the target resource (getRadioCodes)
Codes.available = {}

local function resourceRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

-- asks the target resource which codes it knows (and their labels)
function Codes.refresh(workId)
    local w = Codes.WORKS[workId]
    if not w then return end
    Codes.available[workId] = nil
    if not resourceRunning(w.resource) then return end
    local ok, list = pcall(function() return exports[w.resource]:getRadioCodes() end)
    if not ok or type(list) ~= "table" then
        outputDebugString("[voice] " .. w.resource .. ":getRadioCodes failed", 2)
        return
    end
    local map = {}
    for _, c in ipairs(list) do
        if type(c) == "table" and type(c.id) == "string" then map[c.id] = c.label or c.id end
    end
    for _, c in ipairs(w.codes) do
        if not map[c.id] then
            outputDebugString("[voice] " .. workId .. ": code " .. c.id .. " is not known by " .. w.resource, 2)
        end
    end
    Codes.available[workId] = map
end

function Codes.refreshAll()
    for workId in pairs(Codes.WORKS) do Codes.refresh(workId) end
end

function Codes.isSupported(workId)
    return Codes.WORKS[workId] ~= nil
end

function Codes.isReady(workId)
    return Codes.available[workId] ~= nil
end

-- codes of the work the target can run now
function Codes.activeCodes(workId)
    local w, map, list = Codes.WORKS[workId], Codes.available[workId], {}
    if not w or not map then return list end
    for _, c in ipairs(w.codes) do
        if map[c.id] then list[#list + 1] = c end
    end
    return list
end

-- id -> kind ("code" | "question" | "error"), entry
function Codes.find(workId, id)
    local w = Codes.WORKS[workId]
    if type(id) ~= "string" or not w then return nil end
    for _, e in ipairs(Codes.ERRORS) do if e.id == id then return "error", e end end
    for _, q in ipairs(w.questions) do if q.id == id then return "question", q end end
    local map = Codes.available[workId]
    for _, c in ipairs(w.codes) do
        if c.id == id and map and map[c.id] then return "code", c end
    end
    return nil
end

function Codes.label(workId, id)
    local map = Codes.available[workId]
    return map and map[id] or id
end

-- every id the AI may answer for the work (enum of the response schema)
function Codes.allIds(workId)
    local w, ids = Codes.WORKS[workId], {}
    for _, c in ipairs(Codes.activeCodes(workId)) do ids[#ids + 1] = c.id end
    for _, q in ipairs(w.questions) do ids[#ids + 1] = q.id end
    for _, e in ipairs(Codes.ERRORS) do ids[#ids + 1] = e.id end
    return ids
end

-- the code list as text for the AI
function Codes.describe(workId)
    local w = Codes.WORKS[workId]
    local lines = { w.intro, "", "RADIO CODES (the request is understood and complete):" }
    for _, c in ipairs(Codes.activeCodes(workId)) do
        local line = "- " .. c.id .. ": " .. c.desc
        if c.args and c.args.note == "required" then line = line .. " [needs note]" end
        if c.examples then line = line .. " Examples: \"" .. table.concat(c.examples, "\", \"") .. "\"" end
        lines[#lines + 1] = line
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "QUESTION CODES (a radio request of this work, but not specific enough):"
    for _, q in ipairs(w.questions) do lines[#lines + 1] = "- " .. q.id .. ": " .. q.desc end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "ERROR CODES:"
    for _, e in ipairs(Codes.ERRORS) do lines[#lines + 1] = "- " .. e.id .. ": " .. e.desc end
    return table.concat(lines, "\n")
end

-- a target resource (re)started / stopped -> its code list changes
addEventHandler("onResourceStart", root, function(res)
    local name = getResourceName(res)
    for workId, w in pairs(Codes.WORKS) do
        if w.resource == name then setTimer(function() Codes.refresh(workId) end, 1000, 1) end
    end
end)

addEventHandler("onResourceStop", root, function(res)
    local name = getResourceName(res)
    for workId, w in pairs(Codes.WORKS) do
        if w.resource == name then Codes.available[workId] = nil end
    end
end)
