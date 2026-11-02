if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Other agencies (police_system) on a task:
--   meta.police = { call, status, units }   the linked police call (v_scenemanager scene call or "Request agency")
--   meta.safety = { state, since, by, auto, staging }   safe scene (v_scenemanager); the tablet shows it, warns the
--                 crew on approach and routes it to the staging point while it is "unsafe"
--   inter-agency chat: Chat channel "agency" (target = task id) <-> the police call's "agency" channel
-- Request agency (Active Case): the crew asks for the police with a reason (Config.AGENCY_REASONS); the call text is
-- made from v_locals templates in every language, so every officer reads it in their own.

Agency = {}

local POLICE = "police_system"
local lastRequest = {}   -- [unit id] = getTickCount()

addEvent("onPoliceCallResponded")
addEvent("onPoliceCallClosed")

local function policeRunning()
    local res = getResourceFromName(POLICE)
    return res and getResourceState(res) == "running"
end

local function reasonOf(id)
    for _, r in ipairs(Config.AGENCY_REASONS) do
        if r.id == id then return r end
    end
end

-- the task linked to a police call | nil
local function taskOfCall(callId)
    callId = tonumber(callId)
    for _, t in pairs(Tasks.list) do
        local p = type(t.meta) == "table" and t.meta.police
        if type(p) == "table" and tonumber(p.call) == callId then return t end
    end
end

-- one meta field changes, the crews see it at once (no onErmTaskUpdated spam for a field)
function Agency.setMeta(t, key, value)
    t.meta = type(t.meta) == "table" and t.meta or {}
    t.meta[key] = value
    Tasks.save(t)
    Tasks.syncUnits(t)
end

function Agency.system(t, key, params)
    if #t.units == 0 then return end
    Chat.post("agency", t.id, "", true, "", nil, { key = key, params = params })
end

-- -> true | false, error
function Agency.request(u, agency, reasonId, note)
    if agency ~= "pd" then return false, L.msg("med_erm.agency.not_available") end
    local t = u.task and Tasks.get(u.task)
    if not t then return false, L.msg("med_erm.tablet.no_active_case") end
    local reason = reasonOf(reasonId)
    if not reason then return false, L.msg("med_erm.agency.select_reason") end
    local p = type(t.meta) == "table" and t.meta.police
    if type(p) == "table" and p.status ~= "closed" then return false, L.msg("med_erm.agency.already_linked", { id = p.call }) end
    if not policeRunning() then return false, L.msg("med_erm.agency.no_police") end
    local last = lastRequest[u.id]
    if last and getTickCount() - last < Config.AGENCY_COOLDOWN then
        return false, L.msg("med_erm.backup.wait", { seconds = math.ceil((Config.AGENCY_COOLDOWN - (getTickCount() - last)) / 1000) })
    end
    note = cleanText(note, 200)
    if reason.note and #note < 3 then return false, L.msg("med_erm.agency.note_required") end

    local locales = {}
    for _, lang in ipairs(Config.AGENCY_LANGS) do
        local title = L.forLang(lang, "med_erm.agency.call_title", { reason = L.forLang(lang, reason.label) })
        local caseTitle = Tasks.textFor(t, lang)
        locales[lang] = {
            title = tostring(title),
            description = tostring(L.forLang(lang, "med_erm.agency.call_description",
                { id = t.id, title = caseTitle, unit = u.callsign, zone = t.zone })),
        }
    end
    local ok, id, err = pcall(function()
        return exports[POLICE]:createAgencyCall({ reason = reason.id, note = note, ermTask = t.id, unit = u.callsign,
            locales = locales, x = t.x, y = t.y, z = t.z })
    end)
    if not ok or not id then
        if err == "no_units" then return false, L.msg("med_erm.agency.no_officers") end
        return false, L.msg("med_erm.agency.failed")
    end
    lastRequest[u.id] = getTickCount()
    Agency.setMeta(t, "police", { call = id, status = "open", units = {} })
    Agency.system(t, "med_erm.agency.sys_requested", { callsign = u.callsign, reason = L.msg(reason.label), call = id })
    Events.fire("onErmAgencyRequested", t.id, u.id, "pd", reason.id, id)
    return true
end

-- a police unit took the linked call / it closed
addEventHandler("onPoliceCallResponded", root, function(callId, callsign)
    local t = taskOfCall(callId)
    if not t then return end
    local p = t.meta.police
    local units = type(p.units) == "table" and p.units or {}
    local known = false
    for _, cs in ipairs(units) do if cs == callsign then known = true end end
    if not known then units[#units + 1] = callsign end
    Agency.setMeta(t, "police", { call = p.call, status = "assigned", units = units })
    Agency.system(t, "med_erm.agency.sys_responding", { callsign = callsign, call = p.call })
end)

addEventHandler("onPoliceCallClosed", root, function(callId)
    local t = taskOfCall(callId)
    if not t then return end
    local p = t.meta.police
    Agency.setMeta(t, "police", { call = p.call, status = "closed", units = p.units or {} })
    Agency.system(t, "med_erm.agency.sys_closed", { call = p.call })
end)

-- a crew member writes in the inter-agency channel: the police call gets it too
function Agency.post(u, player, text)
    local t = u.task and Tasks.get(u.task)
    if not t then return false, L.msg("med_erm.tablet.no_active_case") end
    local p = type(t.meta) == "table" and t.meta.police
    if type(p) ~= "table" then return false, L.msg("med_erm.agency.not_linked") end
    local from = u.callsign .. " · " .. (getElementData(player, "displayName") or getPlayerName(player))
    from = tostring(from):gsub("#%x%x%x%x%x%x", "")
    local id, err = Chat.post("agency", t.id, from, false, text, u.id)
    if not id then return false, err end
    if policeRunning() and p.status ~= "closed" then
        pcall(function() exports[POLICE]:postCallMessage(p.call, "agency", from, cleanText(text, 300)) end)
    end
    return true
end
