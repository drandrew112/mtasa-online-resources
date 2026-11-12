-- police_system / modules/callouts/server/callouts.lua
-- CalloutManager: every call (bejelentés) of the police lives here. Kinds:
--   phone   citizens ring the police on the phone's emergency contact (ui_phone "pd" line -> export createPoliceCall);
--           the text is what the caller typed (no translation)
--   scene   v_scenemanager (export createSceneCall): English title / description + locales = { hu = {...} }
--   agency  an EMS crew asks for the police on the ERM tablet (med_erm -> export createAgencyCall), texts in every language
-- Scene and agency texts follow the reader's language like med_erm tasks (CO.textFor = Tasks.textFor): English is the
-- base, a missing language or field falls back to it.
--
-- Offers: a new call is offered to the Available units within OFFER_RADIUS (the popup next to the speedometer, Y
-- accept / N decline, OFFER_TIME seconds). One offer per unit at a time, the others wait in the unit's queue; a unit
-- that becomes Available again gets the nearest open (unassigned) call it has not declined. Accepting is the same as
-- Respond on the MDC Calls page.
-- Respond: status Responding + route objective on v_radar (this module owns the objectives, the backup route too).
-- One call per unit: responding to another one leaves the old call (it is open again when no unit is left on it).
-- Arrival (a member within ARRIVE_RADIUS): the objective goes, a Responding unit becomes Busy ("On scene"). From then
-- on Available is never automatic: the officers set it (F5 / Code 4) when the job is done.
--
-- Every call has a text channel ("call": the units on it); a call linked to an ERM task (scene / agency) has the
-- inter-agency channel too ("agency": the units + the EMS crews of the task, med_erm postAgencyMessage).
-- Safe scene (v_scenemanager setCallSafety): while "unsafe" the call cannot be closed, the MDC shows the mandatory
-- block; "Report scene safe" fires onPoliceSceneSafeReported (v_scenemanager decides).
--
-- Events (resource root): onPoliceCallResponded (id, callsign, accounts), onPoliceCallClosed (id, reason, by | false),
-- onPoliceSceneSafeReported (id, callsign, player)

local CO = POL.module("callouts", { calls = {}, seq = 0, objectives = {}, msgSeq = 0, offers = {}, queue = {} })
local C = POLICE.CALLOUTS

local MAX_MESSAGES = 80
local DEFAULT_LANG = "en"

addEvent("onPoliceCallResponded")
addEvent("onPoliceCallClosed")
addEvent("onPoliceSceneSafeReported")

local function cut(s, max)
    s = tostring(s or ""):gsub("%c", " ")
    if utf8 and utf8.len(s) and utf8.len(s) > max then return utf8.sub(s, 1, max) end
    return s:sub(1, max)
end

------------------------------------------------------------------------ objectives (v_radar)

local function setPlayerObjective(p, x, y, z, labelKey)
    if not POL.running("v_radar") then return end
    local old = CO.objectives[p]
    if old then pcall(function() exports.v_radar:removeObjective(p, old) end) end
    local ok, id = pcall(function() return exports.v_radar:addObjective(p, x, y, z, L.forPlayer(p, labelKey)) end)
    CO.objectives[p] = ok and id or nil
end

function CO.setObjective(unit, x, y, z, labelKey)
    for _, p in ipairs(POL.units.members(unit)) do setPlayerObjective(p, x, y, z, labelKey) end
end

local function clearPlayerObjective(p)
    local id = CO.objectives[p]
    if id and POL.running("v_radar") then pcall(function() exports.v_radar:removeObjective(p, id) end) end
    CO.objectives[p] = nil
end

function CO.clearObjective(unit)
    for _, p in ipairs(POL.units.members(unit)) do clearPlayerObjective(p) end
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
function CO.textFor(c, who)
    local loc = c.locales
    if type(loc) ~= "table" then return c.title, c.description end
    local code = type(who) == "string" and who or (isElement(who) and POL.lang(who)) or DEFAULT_LANG
    local e = loc[code]
    if type(e) ~= "table" then return c.title, c.description end
    return (e.title ~= "" and e.title or c.title), (e.description ~= "" and e.description or c.description)
end

------------------------------------------------------------------------ helpers

-- the call a unit is on (not closed) -> c, entry { arrived }
function CO.callOf(unit)
    if not unit then return nil end
    for _, c in pairs(CO.calls) do
        local e = c.status ~= "closed" and c.units[unit.callsign]
        if e then return c, e end
    end
    return nil
end

-- the nearest member of a unit to a point (2D) -> distance | nil
local function unitDist(unit, x, y)
    local best
    for _, p in ipairs(POL.units.members(unit)) do
        if getElementInterior(p) == 0 then
            local d = POL.dist2D(p, x, y)
            if not best or d < best then best = d end
        end
    end
    return best
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

------------------------------------------------------------------------ offers (popup)

-- the popup content for one player (texts in their language)
local function offerFor(p, c, offer)
    local title, description = CO.textFor(c, p)
    local px, py = getElementPosition(p)
    return { id = c.id, kind = c.kind, priority = c.priority, title = title, description = description, zone = c.zone,
             distance = math.floor(math.sqrt((px - c.x) ^ 2 + (py - c.y) ^ 2)),
             left = math.max(1, math.ceil((offer.expires - getTickCount()) / 1000)), total = C.OFFER_TIME }
end

local function sendOffer(unit, p)
    local o = CO.offers[unit.id]
    local c = o and CO.calls[o.call]
    POL.send(p, "callout:offer", c and offerFor(p, c, o) or false)
end

local function pushOffer(unit)
    for _, p in ipairs(POL.units.members(unit)) do sendOffer(unit, p) end
end

-- a unit with a prisoner transport offer on its screen (transport.lua) gets no call offer meanwhile (one Y / N at a
-- time); it gets the nearest open call when that offer ends (CO.unitFree)
local function offerable(unit, c)
    return c and c.status ~= "closed" and not c.units[unit.callsign] and not c.declined[unit.callsign]
        and unit.status == "available" and POL.units.list[unit.id] == unit
        and not (POL.transport and POL.transport.offerOf and POL.transport.offerOf(unit))
end

local nextOffer

-- the offer of a unit ends (answered, expired, withdrawn); the next one of its queue comes up
local function endOffer(unit, silent)
    if not CO.offers[unit.id] then return end
    CO.offers[unit.id] = nil
    if not silent then pushOffer(unit) end
    nextOffer(unit)
end

function nextOffer(unit)
    if CO.offers[unit.id] or unit.status ~= "available" then return end
    local q = CO.queue[unit.id]
    while q and #q > 0 do
        local c = CO.calls[table.remove(q, 1)]
        if offerable(unit, c) then
            CO.offers[unit.id] = { call = c.id, expires = getTickCount() + C.OFFER_TIME * 1000 }
            pushOffer(unit)
            POL.emit("callout.offered", unit, c)
            return
        end
    end
    CO.queue[unit.id] = nil
end

-- offers a call to a unit (now, or after its current offer)
local function offer(unit, c)
    if not offerable(unit, c) then return false end
    local cur = CO.offers[unit.id]
    if cur then
        if cur.call == c.id then return true end
        local q = CO.queue[unit.id] or {}
        CO.queue[unit.id] = q
        for _, id in ipairs(q) do if id == c.id then return true end end
        q[#q + 1] = c.id
        return true
    end
    CO.offers[unit.id] = { call = c.id, expires = getTickCount() + C.OFFER_TIME * 1000 }
    pushOffer(unit)
    POL.emit("callout.offered", unit, c)
    return true
end

-- withdraws a call from every popup and queue (closed / assigned elsewhere does not withdraw: more units may go)
local function withdraw(c)
    for uid, q in pairs(CO.queue) do
        for i = #q, 1, -1 do if q[i] == c.id then table.remove(q, i) end end
    end
    for uid, o in pairs(CO.offers) do
        local unit = POL.units.list[uid]
        if o.call == c.id then
            if unit then endOffer(unit) else CO.offers[uid] = nil end
        end
    end
end

local function dropUnit(unit)
    CO.queue[unit.id] = nil
    if CO.offers[unit.id] then
        CO.offers[unit.id] = nil
        pushOffer(unit)
    end
end

-- a new call goes to the Available units near it; everybody else on duty gets the usual notification
local function announce(c)
    local offered = {}
    for _, u in pairs(POL.units.list) do
        if u.status == "available" then
            local d = unitDist(u, c.x, c.y)
            if d and d <= C.OFFER_RADIUS and offer(u, c) then
                for _, p in ipairs(POL.units.members(u)) do offered[p] = true end
            end
        end
    end
    for _, p in ipairs(POL.units.onDuty()) do
        if not offered[p] then
            POL.notify(p, "police_system.callouts.new_call", { id = c.id, title = (CO.textFor(c, p)), zone = c.zone })
        end
    end
    POL.emit("callout.announced", c, next(offered) ~= nil)
end

-- a unit Available again: the nearest open call around it that it has not declined
local function offerNearestOpen(unit)
    local best, bd
    for _, c in pairs(CO.calls) do
        if c.status == "open" and offerable(unit, c) then
            local d = unitDist(unit, c.x, c.y)
            if d and d <= C.OFFER_RADIUS and (not bd or d < bd) then best, bd = c, d end
        end
    end
    if best then offer(unit, best) end
end

function CO.unitFree(unit)
    if unit and POL.units.list[unit.id] == unit and unit.status == "available" and not CO.offers[unit.id] then offerNearestOpen(unit) end
end

-- Y / N on the popup (any member of the unit answers for it)
function CO.answer(player, id, accept)
    local unit = POL.units.of(player)
    local o = unit and CO.offers[unit.id]
    if not o or o.call ~= tonumber(id) then
        POL.send(player, "callout:offer", false)
        return false
    end
    local c = CO.calls[o.call]
    if accept then
        CO.offers[unit.id] = nil
        CO.queue[unit.id] = nil
        pushOffer(unit)
        if not CO.respond(player, o.call) then POL.notify(player, "police_system.callouts.err_gone") end
        return true
    end
    if c then
        c.declined[unit.callsign] = true
        POL.events.log(unit, player, "call_declined", { call = c.id })
        local others = {}
        for _, p in ipairs(POL.units.members(unit)) do if p ~= player then others[#others + 1] = p end end
        POL.notify(others, "police_system.callouts.declined", { id = c.id, name = POL.nameOf(player) })
    end
    endOffer(unit)
    return true
end

POL.net("callout:answer", function(player, id, accept) CO.answer(player, id, accept == true) end)

------------------------------------------------------------------------ calls

local function newCall(fields)
    CO.seq = CO.seq + 1
    local c = {
        id = CO.seq, kind = fields.kind or "phone", caller = fields.caller, name = fields.name or "?",
        title = cut(fields.title, 80), description = cut(fields.description, 500), locales = cleanLocales(fields.locales),
        lang = fields.lang, x = fields.x, y = fields.y, z = fields.z, zone = getZoneName(fields.x, fields.y, fields.z),
        at = POL.now(), status = "open", units = {}, declined = {}, priority = tonumber(fields.priority) or 2,
        source = fields.source or "", meta = fields.meta or {}, ermTask = fields.ermTask or false,
        safety = fields.safety or false, messages = {},
    }
    if c.title == "" then c.title = L.msg("police_system.callouts.default_title") end
    CO.calls[c.id] = c
    POL.db.stat("calls", 1)
    announce(c)
    POL.emit("calls.changed")
    return c
end

-- export: a call from a player's phone. -> id | false, reason
function createPoliceCall(caller, title, description)
    if not isElement(caller) or getElementType(caller) ~= "player" then return false, "bad_caller" end
    if #POL.units.onDuty() == 0 then return false, "no_units" end
    for _, c in pairs(CO.calls) do
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
    if (opts.note or "") ~= "" then CO.post(c, "agency", "ems", "EMS " .. cut(opts.unit or "?", 20), cut(opts.note, 300)) end
    return c.id
end

-- the row of the Calls list for a player (texts in their language)
local function row(c, player)
    local units = {}
    for cs in pairs(c.units) do units[#units + 1] = cs end
    table.sort(units)
    local title, description = CO.textFor(c, player)
    return { id = c.id, kind = c.kind, name = c.name, title = title, description = description, zone = c.zone,
             at = c.at, status = c.status, units = units, priority = c.priority, ermTask = c.ermTask,
             safety = c.safety and c.safety.state or false, unread = 0 }
end

function CO.list(player)
    local out = {}
    for _, c in pairs(CO.calls) do
        if c.status ~= "closed" or POL.now() - (c.closedAt or 0) < 900 then out[#out + 1] = row(c, player) end
    end
    table.sort(out, function(a, b) return a.id > b.id end)
    return out
end

-- the detail panel of one call for a player
function CO.detail(player, id)
    local c = CO.calls[tonumber(id)]
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
            from = m.key and L.forPlayer(player, "police_system.callouts.system") or m.from,
            text = m.key and L.forPlayer(player, m.key, m.params) or m.text,
        }
    end
    local unit = POL.units.of(player)
    r.mine = unit and c.units[unit.callsign] and true or false
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
                POL.notify(p, "police_system.callouts.unsafe_reopened", { id = c.id, title = (CO.textFor(c, p)), zone = c.zone })
            end
        end
    end
    POL.events.log(unit, nil, "call_left", { call = c.id, why = why })
end

-- a unit takes a call (MDC Respond, popup Y)
function CO.respond(player, id)
    local unit = POL.units.of(player)
    local c = CO.calls[tonumber(id)]
    if not unit or not c or c.status == "closed" then return false end
    for _, other in pairs(CO.calls) do
        if other ~= c and other.status ~= "closed" then leave(other, unit, "other_call") end
    end
    if CO.offers[unit.id] and CO.offers[unit.id].call == c.id then dropUnit(unit) end
    c.units[unit.callsign] = c.units[unit.callsign] or { arrived = false, at = POL.now() }
    c.status = "assigned"
    POL.units.setStatus(unit, "responding", player)
    if c.units[unit.callsign].arrived then
        CO.clearObjective(unit)
    else
        CO.setObjective(unit, c.x, c.y, c.z, "police_system.callouts.call_objective")
    end
    POL.events.log(unit, player, "call_respond", { call = c.id })
    if isElement(c.caller) then POL.notify(c.caller, "police_system.callouts.call_taken", { callsign = unit.callsign }) end
    if c.safety and c.safety.state == "unsafe" then
        POL.notify(POL.units.members(unit), "police_system.callouts.unsafe_required", { id = c.id })
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
        if u then CO.clearObjective(u) end
    end
    withdraw(c)
    triggerEvent("onPoliceCallClosed", resourceRoot, c.id, c.closeReason, by or false)
    refresh(c)
end

function CO.closeCall(player, id)
    local unit = POL.units.of(player)
    local c = CO.calls[tonumber(id)]
    if not unit or not c or c.status == "closed" then return false end
    if c.safety and c.safety.state == "unsafe" then return false, "scene_unsafe" end
    POL.events.log(unit, player, "call_closed", { call = c.id })
    CO.clearObjective(unit)
    close(c, "closed by " .. unit.callsign, unit.callsign)
    return true
end

-- export (v_scenemanager): closes a scene call (no safety check: the script knows) -> bool
function closeSceneCall(id, reason)
    local c = CO.calls[tonumber(id)]
    if not c or c.status == "closed" then return false end
    close(c, reason or "closed by script", false)
    return true
end

-- export: { id, kind, status, units = { callsign }, officers = { { player, callsign } }, safety, ermTask, x, y, z } | false
function getCall(id)
    local c = CO.calls[tonumber(id)]
    if not c then return false end
    local units = {}
    for cs in pairs(c.units) do units[#units + 1] = cs end
    return { id = c.id, kind = c.kind, status = c.status, units = units, officers = officersOf(c), safety = c.safety,
             ermTask = c.ermTask, x = c.x, y = c.y, z = c.z, closeReason = c.closeReason or "" }
end

-- export (v_scenemanager): the safe scene info { state, since, by, auto, threats, activeNear, emsWaitingSince, radius }
function setCallSafety(id, info)
    local c = CO.calls[tonumber(id)]
    if not c or type(info) ~= "table" then return false end
    local old = c.safety and c.safety.state
    c.safety = info
    if old and old ~= info.state and c.status ~= "closed" then
        local key = info.state == "safe" and "police_system.callouts.scene_safe" or "police_system.callouts.scene_unsafe_again"
        POL.notify(membersOf(c), key, { id = c.id, callsign = info.by or "-" })
    end
    refresh(c)
    return true
end

-- export: links a call to an ERM task (inter-agency channel)
function setCallLink(id, ermTask)
    local c = CO.calls[tonumber(id)]
    if not c then return false end
    c.ermTask = tonumber(ermTask) or false
    refresh(c)
    return true
end

------------------------------------------------------------------------ channels

-- kind: "pd" | "ems" | "sys"; key + params = a system line (resolved per reader), else from + text
function CO.post(c, channel, kind, from, text, key, params)
    CO.msgSeq = CO.msgSeq + 1
    local m = { id = CO.msgSeq, at = POL.now(), channel = channel == "agency" and "agency" or "call", kind = kind,
                from = cut(from, 60), text = cut(text, 300), key = key, params = params }
    c.messages[#c.messages + 1] = m
    while #c.messages > MAX_MESSAGES do table.remove(c.messages, 1) end
    POL.send(membersOf(c), "mdc:refresh", "calls")
    if kind ~= "pd" then
        POL.notify(membersOf(c), key and "police_system.callouts.call_system" or "police_system.callouts.call_message",
            { id = c.id, from = m.from })
    end
    return m.id
end

-- export (v_scenemanager system lines, med_erm crews): postCallMessage(id, channel, from, text [, key, params])
function postCallMessage(id, channel, from, text, key, params)
    local c = CO.calls[tonumber(id)]
    if not c then return false end
    if key then return CO.post(c, channel, "sys", "", "", tostring(key), type(params) == "table" and params or {}) end
    if tostring(text or ""):gsub("%s", "") == "" then return false end
    return CO.post(c, channel, "ems", from or "EMS", text)
end

-- an officer writes on the MDC -> ok, err
function CO.message(player, id, channel, text)
    local c = CO.calls[tonumber(id)]
    local unit = POL.units.of(player)
    if not c or not unit then return false, "not_found" end
    text = cut(text, 300):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return false, "empty" end
    if channel == "agency" and not c.ermTask then return false, "no_link" end
    local from = unit.callsign .. " · " .. POL.nameOf(player)
    CO.post(c, channel, "pd", from, text)
    if channel == "agency" and POL.running("med_erm") then
        pcall(function() exports.med_erm:postAgencyMessage(c.ermTask, from, text) end)
    end
    return true
end

-- MDC "Report scene safe": the officer is near and no active threat is near -> v_scenemanager decides
function CO.reportSafe(player, id)
    local c = CO.calls[tonumber(id)]
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

------------------------------------------------------------------------ arrival + offer timeouts

local function arrive(c, unit, e, player)
    e.arrived = true
    CO.clearObjective(unit)
    if unit.status == "responding" then
        POL.units.setStatus(unit, "busy", player)
        POL.units.setSub(unit, "callout")
    end
    POL.events.log(unit, player, "call_arrived", { call = c.id })
    POL.notify(POL.units.members(unit), "police_system.callouts.arrived", { id = c.id })
    refresh(c)
end

local function tick()
    for _, c in pairs(CO.calls) do
        if c.status ~= "closed" then
            for cs, e in pairs(c.units) do
                local unit = not e.arrived and POL.units.get(cs)
                if unit then
                    for _, p in ipairs(POL.units.members(unit)) do
                        if getElementInterior(p) == 0 and POL.dist2D(p, c.x, c.y) <= C.ARRIVE_RADIUS then
                            arrive(c, unit, e, p)
                            break
                        end
                    end
                end
            end
        end
    end
    local now = getTickCount()
    for uid, o in pairs(CO.offers) do
        local unit = POL.units.list[uid]
        if not unit then
            CO.offers[uid], CO.queue[uid] = nil, nil
        elseif now >= o.expires then
            endOffer(unit)
        end
    end
end

function CO.start() setTimer(tick, C.TICK, 0) end

------------------------------------------------------------------------ unit changes

POL.on("unit.status", function(unit, status)
    if status == "available" then
        offerNearestOpen(unit)
    else
        dropUnit(unit)
    end
end)

POL.on("unit.signedIn", offerNearestOpen)

POL.on("units.member", function(unit, player, joined)
    if not joined then
        clearPlayerObjective(player)
        if isElement(player) then POL.send(player, "callout:offer", false) end
        return
    end
    -- a new member: the route of the unit's call and its popup
    local c, e = CO.callOf(unit)
    if c and not e.arrived then setPlayerObjective(player, c.x, c.y, c.z, "police_system.callouts.call_objective") end
    if CO.offers[unit.id] then sendOffer(unit, player) end
end)

POL.on("unit.signedOff", function(unit)
    CO.offers[unit.id], CO.queue[unit.id] = nil, nil
    for _, p in ipairs(POL.units.members(unit)) do POL.send(p, "callout:offer", false) end
    for _, c in pairs(CO.calls) do
        if c.status ~= "closed" then leave(c, unit, "signed_off") end
    end
    refresh()
end)

addEventHandler("onPlayerQuit", root, function()
    for _, c in pairs(CO.calls) do if c.caller == source then c.caller = nil end end
    CO.objectives[source] = nil
end)
