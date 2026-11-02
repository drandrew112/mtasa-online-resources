-- police_system / modules/events/server/dispatch.lua
-- Calls and backup. Calls:
--   phone   citizens ring the police on the phone's emergency contact (ui_phone "pd" line -> export createPoliceCall);
--           the text is what the caller typed (no translation)
--   scene   v_scenemanager (export createSceneCall): English title / description + locales = { hu = {...} }
--   agency  an EMS crew asks for the police on the ERM tablet (med_erm -> export createAgencyCall), texts in every language
-- Scene and agency texts follow the reader's language like med_erm tasks (D.textFor = Tasks.textFor): English is the
-- base, a missing language or field falls back to it. The MDC Calls page lists them; a unit responds (route objective
-- on v_radar, status Responding) and closes them. One call per unit: responding to another one leaves the old call
-- (it is open again when no unit is left on it).
-- Every call has a text channel ("call": the units on it); a call linked to an ERM task (scene / agency) has the
-- inter-agency channel too ("agency": the units + the EMS crews of the task, med_erm postAgencyMessage).
-- Safe scene (v_scenemanager setCallSafety): while "unsafe" the call cannot be closed, the MDC shows the mandatory
-- block; "Report scene safe" fires onPoliceSceneSafeReported (v_scenemanager decides).
-- Backup (REQUEST_BACKUP): only when another unit is on duty; the nearest available one gets it (MDC message,
-- route objective, Responding) and a "backup" incident, paid when it arrived there (within 40 m).
--
-- Events (resource root): onPoliceCallResponded (id, callsign, accounts), onPoliceCallClosed (id, reason, by | false),
-- onPoliceSceneSafeReported (id, callsign, player)

local D = POL.module("dispatch", { calls = {}, seq = 0, objectives = {}, msgSeq = 0 })

local MAX_MESSAGES = 80
local DEFAULT_LANG = "en"

addEvent("onPoliceCallResponded")
addEvent("onPoliceCallClosed")
addEvent("onPoliceSceneSafeReported")

local function setObjective(unit, x, y, z, labelKey)
    for _, p in ipairs(POL.units.members(unit)) do
        if POL.running("v_radar") then
            local old = D.objectives[p]
            if old then pcall(function() exports.v_radar:removeObjective(p, old) end) end
            local ok, id = pcall(function() return exports.v_radar:addObjective(p, x, y, z, L.forPlayer(p, labelKey)) end)
            D.objectives[p] = ok and id or nil
        end
    end
end

function D.clearObjective(unit)
    for _, p in ipairs(POL.units.members(unit)) do
        local id = D.objectives[p]
        if id and POL.running("v_radar") then pcall(function() exports.v_radar:removeObjective(p, id) end) end
        D.objectives[p] = nil
    end
end

local function cut(s, max)
    s = tostring(s or ""):gsub("%c", " ")
    if utf8 and utf8.len(s) and utf8.len(s) > max then return utf8.sub(s, 1, max) end
    return s:sub(1, max)
end

------------------------------------------------------------------------ texts

local function cleanLocales(locales)
    if type(locales) ~= "table" then return nil end
    local out = {}
    for code, e in pairs(locales) do
        if type(code) == "string" and code:match("^%l%l$") and type(e) == "table" then
            local t, d = cut(e.title, 80), cut(e.description, 500)
            if t ~= "" or d ~= "" then out[code] = { title = t, description = d } end
        end
    end
    return next(out) and out or nil
end

-- title, description of a call for a player (or a language code); English (the base fields) where missing
function D.textFor(c, who)
    local loc = c.locales
    if type(loc) ~= "table" then return c.title, c.description end
    local code = type(who) == "string" and who or (isElement(who) and POL.lang(who)) or DEFAULT_LANG
    local e = loc[code]
    if type(e) ~= "table" then return c.title, c.description end
    return (e.title ~= "" and e.title or c.title), (e.description ~= "" and e.description or c.description)
end

-- every officer on duty told about a new call, each in their own language
local function announce(c)
    for _, p in ipairs(POL.units.onDuty()) do
        POL.notify(p, "police_system.dispatch.new_call", { id = c.id, title = (D.textFor(c, p)), zone = c.zone })
    end
end

------------------------------------------------------------------------ calls

local function newCall(fields)
    D.seq = D.seq + 1
    local c = {
        id = D.seq, kind = fields.kind or "phone", caller = fields.caller, name = fields.name or "?",
        title = cut(fields.title, 80), description = cut(fields.description, 500), locales = cleanLocales(fields.locales),
        lang = fields.lang, x = fields.x, y = fields.y, z = fields.z, zone = getZoneName(fields.x, fields.y, fields.z),
        at = POL.now(), status = "open", units = {}, priority = tonumber(fields.priority) or 2,
        source = fields.source or "", meta = fields.meta or {}, ermTask = fields.ermTask or false,
        safety = fields.safety or false, messages = {},
    }
    if c.title == "" then c.title = L.msg("police_system.dispatch.default_title") end
    D.calls[c.id] = c
    POL.db.stat("calls", 1)
    announce(c)
    POL.emit("calls.changed")
    return c
end

-- export: a call from a player's phone. -> id | false, reason
function createPoliceCall(caller, title, description)
    if not isElement(caller) or getElementType(caller) ~= "player" then return false, "bad_caller" end
    if #POL.units.onDuty() == 0 then return false, "no_units" end
    for _, c in pairs(D.calls) do
        if c.caller == caller and c.status ~= "closed" then return false, "open_call" end
    end
    local x, y, z = getElementPosition(caller)
    local c = newCall({ kind = "phone", caller = caller, name = POL.nameOf(caller), title = cut(title, 60),
                        description = cut(description, 300), lang = POL.lang(caller), x = x, y = y, z = z })
    return c.id
end

-- export (v_scenemanager): { title, description, locales, x, y, z, priority, caller, source, meta = { scene, instance,
-- ermTask }, safety } -> id | false, reason
function createSceneCall(opts)
    if type(opts) ~= "table" or not tonumber(opts.x) or not tonumber(opts.y) then return false, "bad_args" end
    local meta = type(opts.meta) == "table" and opts.meta or {}
    local c = newCall({ kind = "scene", name = cut(opts.caller or "Dispatch", 40), title = opts.title,
                        description = opts.description, locales = opts.locales, x = tonumber(opts.x), y = tonumber(opts.y),
                        z = tonumber(opts.z) or 0, priority = opts.priority,
                        source = sourceResource and getResourceName(sourceResource) or tostring(opts.source or ""),
                        meta = meta, ermTask = tonumber(meta.ermTask) or false,
                        safety = type(opts.safety) == "table" and opts.safety or false })
    return c.id
end

-- export (med_erm "Request agency"): { reason, note, ermTask, unit = EMS callsign, locales = { en = {...}, hu = {...} },
-- x, y, z } -> id | false, reason ("no_units")
function createAgencyCall(opts)
    if type(opts) ~= "table" or not tonumber(opts.x) or not tonumber(opts.y) then return false, "bad_args" end
    if #POL.units.onDuty() == 0 then return false, "no_units" end
    local loc = cleanLocales(opts.locales) or {}
    local en = loc.en or { title = "", description = "" }
    loc.en = nil
    local c = newCall({ kind = "agency", name = "EMS " .. cut(opts.unit or "?", 20), title = en.title,
                        description = en.description, locales = loc, x = tonumber(opts.x), y = tonumber(opts.y),
                        z = tonumber(opts.z) or 0, priority = 2, source = "med_erm",
                        meta = { reason = opts.reason, note = cut(opts.note, 200) }, ermTask = tonumber(opts.ermTask) or false })
    if (opts.note or "") ~= "" then D.post(c, "agency", "ems", "EMS " .. cut(opts.unit or "?", 20), cut(opts.note, 300)) end
    return c.id
end

local function officersOf(c)
    local out = {}
    for cs in pairs(c.units) do
        local u = POL.units.get(cs)
        if u then
            for _, p in ipairs(POL.units.members(u)) do out[#out + 1] = { player = p, callsign = cs } end
        end
    end
    return out
end

local function membersOf(c)
    local out = {}
    for _, o in ipairs(officersOf(c)) do out[#out + 1] = o.player end
    return out
end

local function refresh(c)
    POL.emit("calls.changed", c and c.id)
    POL.send(POL.units.onDuty(), "mdc:refresh", "calls")
end

-- the row of the Calls list for a player (texts in their language)
local function row(c, player)
    local units = {}
    for cs in pairs(c.units) do units[#units + 1] = cs end
    table.sort(units)
    local title, description = D.textFor(c, player)
    return { id = c.id, kind = c.kind, name = c.name, title = title, description = description, zone = c.zone,
             at = c.at, status = c.status, units = units, priority = c.priority, ermTask = c.ermTask,
             safety = c.safety and c.safety.state or false, unread = 0 }
end

function D.list(player)
    local out = {}
    for _, c in pairs(D.calls) do
        if c.status ~= "closed" or POL.now() - (c.closedAt or 0) < 900 then out[#out + 1] = row(c, player) end
    end
    table.sort(out, function(a, b) return a.id > b.id end)
    return out
end

-- the detail panel of one call for a player
function D.detail(player, id)
    local c = D.calls[tonumber(id)]
    if not c then return false end
    local r = row(c, player)
    r.x, r.y, r.z = c.x, c.y, c.z
    r.source = c.source
    r.meta = { scene = c.meta.scene, reason = c.meta.reason }
    r.safetyInfo = c.safety or false
    r.messages = {}
    for _, m in ipairs(c.messages) do
        r.messages[#r.messages + 1] = {
            id = m.id, at = m.at, channel = m.channel, kind = m.kind,
            from = m.key and L.forPlayer(player, "police_system.dispatch.system") or m.from,
            text = m.key and L.forPlayer(player, m.key, m.params) or m.text,
        }
    end
    local unit = POL.units.of(player)
    r.mine = unit and c.units[unit.callsign] or false
    if isElement(player) then
        local px, py = getElementPosition(player)
        r.distance = math.floor(math.sqrt((px - c.x) ^ 2 + (py - c.y) ^ 2))
    end
    return r
end

-- a unit leaves a call (another call, sign off): with nobody left the call is open again
local function leave(c, unit, why)
    if not c.units[unit.callsign] then return end
    c.units[unit.callsign] = nil
    if c.status == "assigned" and not next(c.units) then
        c.status = "open"
        if c.safety and c.safety.state == "unsafe" then
            for _, p in ipairs(POL.units.onDuty()) do
                POL.notify(p, "police_system.dispatch.unsafe_reopened", { id = c.id, title = (D.textFor(c, p)), zone = c.zone })
            end
        end
    end
    POL.events.log(unit, nil, "call_left", { call = c.id, why = why })
end

function D.respond(player, id)
    local unit = POL.units.of(player)
    local c = D.calls[tonumber(id)]
    if not unit or not c or c.status == "closed" then return false end
    for _, other in pairs(D.calls) do
        if other ~= c and other.status ~= "closed" then leave(other, unit, "other_call") end
    end
    c.units[unit.callsign] = true
    c.status = "assigned"
    POL.units.setStatus(unit, "responding", player)
    setObjective(unit, c.x, c.y, c.z, "police_system.dispatch.call_objective")
    POL.events.log(unit, player, "call_respond", { call = c.id })
    if isElement(c.caller) then POL.notify(c.caller, "police_system.dispatch.call_taken", { callsign = unit.callsign }) end
    if c.safety and c.safety.state == "unsafe" then
        POL.notify(POL.units.members(unit), "police_system.dispatch.unsafe_required", { id = c.id })
    end
    local accounts = {}
    for _, p in ipairs(POL.units.members(unit)) do accounts[#accounts + 1] = POL.accountOf(p) or "" end
    triggerEvent("onPoliceCallResponded", resourceRoot, c.id, unit.callsign, accounts)
    refresh(c)
    return true
end

local function close(c, reason, by)
    c.status, c.closedAt, c.closeReason = "closed", POL.now(), cut(reason, 120)
    for cs in pairs(c.units) do
        local u = POL.units.get(cs)
        if u then D.clearObjective(u) end
    end
    triggerEvent("onPoliceCallClosed", resourceRoot, c.id, c.closeReason, by or false)
    refresh(c)
end

function D.closeCall(player, id)
    local unit = POL.units.of(player)
    local c = D.calls[tonumber(id)]
    if not unit or not c or c.status == "closed" then return false end
    if c.safety and c.safety.state == "unsafe" then return false, "scene_unsafe" end
    POL.events.log(unit, player, "call_closed", { call = c.id })
    D.clearObjective(unit)
    close(c, "closed by " .. unit.callsign, unit.callsign)
    return true
end

-- export (v_scenemanager): closes a scene call (no safety check: the script knows) -> bool
function closeSceneCall(id, reason)
    local c = D.calls[tonumber(id)]
    if not c or c.status == "closed" then return false end
    close(c, reason or "closed by script", false)
    return true
end

-- export: { id, kind, status, units = { callsign }, officers = { { player, callsign } }, safety, ermTask, x, y, z } | false
function getCall(id)
    local c = D.calls[tonumber(id)]
    if not c then return false end
    local units = {}
    for cs in pairs(c.units) do units[#units + 1] = cs end
    return { id = c.id, kind = c.kind, status = c.status, units = units, officers = officersOf(c), safety = c.safety,
             ermTask = c.ermTask, x = c.x, y = c.y, z = c.z, closeReason = c.closeReason or "" }
end

-- export (v_scenemanager): the safe scene info { state, since, by, auto, threats, activeNear, emsWaitingSince, radius }
function setCallSafety(id, info)
    local c = D.calls[tonumber(id)]
    if not c or type(info) ~= "table" then return false end
    local old = c.safety and c.safety.state
    c.safety = info
    if old and old ~= info.state and c.status ~= "closed" then
        local key = info.state == "safe" and "police_system.dispatch.scene_safe" or "police_system.dispatch.scene_unsafe_again"
        POL.notify(membersOf(c), key, { id = c.id, callsign = info.by or "-" })
    end
    refresh(c)
    return true
end

-- export: links a call to an ERM task (inter-agency channel)
function setCallLink(id, ermTask)
    local c = D.calls[tonumber(id)]
    if not c then return false end
    c.ermTask = tonumber(ermTask) or false
    refresh(c)
    return true
end

------------------------------------------------------------------------ channels

-- kind: "pd" | "ems" | "sys"; key + params = a system line (resolved per reader), else from + text
function D.post(c, channel, kind, from, text, key, params)
    D.msgSeq = D.msgSeq + 1
    local m = { id = D.msgSeq, at = POL.now(), channel = channel == "agency" and "agency" or "call", kind = kind,
                from = cut(from, 60), text = cut(text, 300), key = key, params = params }
    c.messages[#c.messages + 1] = m
    while #c.messages > MAX_MESSAGES do table.remove(c.messages, 1) end
    POL.send(membersOf(c), "mdc:refresh", "calls")
    if kind ~= "pd" then
        POL.notify(membersOf(c), key and "police_system.dispatch.call_system" or "police_system.dispatch.call_message",
            { id = c.id, from = m.from })
    end
    return m.id
end

-- export (v_scenemanager system lines, med_erm crews): postCallMessage(id, channel, from, text [, key, params])
function postCallMessage(id, channel, from, text, key, params)
    local c = D.calls[tonumber(id)]
    if not c then return false end
    if key then return D.post(c, channel, "sys", "", "", tostring(key), type(params) == "table" and params or {}) end
    if tostring(text or ""):gsub("%s", "") == "" then return false end
    return D.post(c, channel, "ems", from or "EMS", text)
end

-- an officer writes on the MDC -> ok, err
function D.message(player, id, channel, text)
    local c = D.calls[tonumber(id)]
    local unit = POL.units.of(player)
    if not c or not unit then return false, "not_found" end
    text = cut(text, 300):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return false, "empty" end
    if channel == "agency" and not c.ermTask then return false, "no_link" end
    local from = unit.callsign .. " · " .. POL.nameOf(player)
    D.post(c, channel, "pd", from, text)
    if channel == "agency" and POL.running("med_erm") then
        pcall(function() exports.med_erm:postAgencyMessage(c.ermTask, from, text) end)
    end
    return true
end

-- MDC "Report scene safe": the officer is near and no active threat is near -> v_scenemanager decides
function D.reportSafe(player, id)
    local c = D.calls[tonumber(id)]
    local unit = POL.units.of(player)
    if not c or not unit then return false, "not_found" end
    local s = c.safety
    if not s or s.state ~= "unsafe" then return false, "not_unsafe" end
    local px, py = getElementPosition(player)
    if math.sqrt((px - c.x) ^ 2 + (py - c.y) ^ 2) > (tonumber(s.radius) or 40) then return false, "not_on_scene" end
    if s.activeNear then return false, "active_threat" end
    triggerEvent("onPoliceSceneSafeReported", resourceRoot, c.id, unit.callsign, player)
    return true
end

addEventHandler("onPlayerQuit", root, function()
    for _, c in pairs(D.calls) do if c.caller == source then c.caller = nil end end
    D.objectives[source] = nil
end)

POL.on("unit.signedOff", function(unit)
    for _, c in pairs(D.calls) do
        if c.status ~= "closed" then leave(c, unit, "signed_off") end
    end
    refresh()
end)

------------------------------------------------------------------------ free units (export)

-- export (v_scenemanager): units that can take a call now -> { { id, callsign, x, y, z, interior, accounts } }
function getFreeUnits()
    local out = {}
    for cs, u in pairs(POL.units.list) do
        if u.status == "available" then
            local members = POL.units.members(u)
            local lead = isElement(u.leader) and u.leader or members[1]
            if lead then
                local x, y, z = POL.pos(lead)
                local accounts = {}
                for _, p in ipairs(members) do accounts[#accounts + 1] = POL.accountOf(p) or "" end
                out[#out + 1] = { id = u.callsign or cs, callsign = u.callsign or cs, x = x, y = y, z = z,
                                  interior = getElementInterior(lead), accounts = accounts }
            end
        end
    end
    return out
end

function isOfficerOnDuty(player)
    return isElement(player) and POL.units.isOnDuty(player) or false
end

-- on-duty officers are in the ai_peds group "police" (the AI cops too): scene NPCs hostile only to the police
-- (v_scenemanager) attack them and nobody else
local function setAIGroup(player, on)
    if not isElement(player) or not POL.running("ai_peds") then return end
    pcall(function() exports.ai_peds:setPlayerAIGroup(player, on and "police" or false) end)
end

POL.on("units.member", function(unit, player, joined) setAIGroup(player, joined) end)
POL.on("unit.signedOff", function(unit)
    for _, p in ipairs(POL.units.members(unit)) do setAIGroup(p, false) end
end)

addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) ~= "ai_peds" then return end
    setTimer(function()
        for _, p in ipairs(POL.units.onDuty()) do setAIGroup(p, true) end
    end, 1000, 1)
end)

------------------------------------------------------------------------ backup

function D.requestBackup(player)
    local unit = POL.units.of(player)
    if not unit then return false, "not_in_unit" end
    local x, y, z = getElementPosition(player)
    local best, bd
    for _, u in pairs(POL.units.list) do
        if u ~= unit and u.status == "available" then
            for _, p in ipairs(POL.units.members(u)) do
                local d = POL.dist2D(p, x, y)
                if not bd or d < bd then best, bd = u, d end
            end
        end
    end
    local others = 0
    for _, u in pairs(POL.units.list) do if u ~= unit then others = others + 1 end end
    if others == 0 then return false, "no_units" end
    if not best then return false, "none_available" end
    POL.units.setStatus(best, "responding", nil)
    setObjective(best, x, y, z, "police_system.dispatch.backup_objective")
    local inc = POL.events.open(best, "backup", nil)
    inc.backupFor, inc.bx, inc.by, inc.bz = unit.callsign, x, y, z
    POL.notify(POL.units.members(best), "police_system.dispatch.backup_assigned", { callsign = unit.callsign, zone = getZoneName(x, y, z) })
    POL.notify(POL.units.members(unit), "police_system.dispatch.backup_coming", { callsign = best.callsign })
    POL.events.log(unit, player, "backup_requested", { to = best.callsign })
    POL.db.stat("backups", 1)
    return true
end

-- a backup unit that got there counts as arrived (paid at Code 4)
local function backupTick()
    for _, u in pairs(POL.units.list) do
        for inc in pairs(u.incidents) do
            if inc.type == "backup" and not inc.arrived then
                for _, p in ipairs(POL.units.members(u)) do
                    if POL.dist2D(p, inc.bx, inc.by) < 40 then
                        inc.arrived = true
                        POL.events.log(u, p, "backup_arrived", { for_unit = inc.backupFor }, inc)
                        D.clearObjective(u)
                        break
                    end
                end
            end
        end
    end
end

function D.start() setTimer(backupTick, 2000, 0) end
