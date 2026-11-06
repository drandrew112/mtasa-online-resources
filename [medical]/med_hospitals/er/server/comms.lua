-- ER communication (plan: Kommunikáció):
--   * EMS unit <-> hospital: one thread per unit (opens with its first message or parameter card, closes
--     when the unit's ERM task ends); the hospital tablet / PC shows each on its own tab
--   * Belső (internal): every staff member of the hospital on duty
--   * the hospital status for the ERM tablets (staff on duty, free corridor places)
--   * parameter cards (one button on the EMS tablet: pulse, SpO2, BP by default ...)
-- exports: getHospitalStatus, receiveParams, sendHospitalMessage, getHospitalThreads; event onHospitalMessage
--
-- thread = { key, kind = "unit" | "internal", unit, taskId, msgs = { { at, from, text, card, mine = side } }, at }

local cards = {}     -- [hospitalId] = { { at, unit, medic, items } } (last 12)
local threads = {}   -- [hospitalId] = { [key] = thread }
local MAX_MSGS = 60

addEvent("onHospitalMessage")   -- (hospitalId, threadKey, msg) source = resourceRoot

local function threadsOf(hid)
    local t = threads[hid]
    if not t then
        t = { internal = { key = "internal", kind = "internal", msgs = {}, at = 0 } }
        threads[hid] = t
    end
    return t
end

local function unitThread(hid, unit, taskId)
    local key = "unit:" .. tostring(unit)
    local t = threadsOf(hid)
    local th = t[key]
    if not th then
        th = { key = key, kind = "unit", unit = tostring(unit), taskId = taskId, msgs = {}, at = 0 }
        t[key] = th
    elseif taskId then
        th.taskId = taskId
    end
    return th
end

local function push(hid, th, msg)
    msg.at = msg.at or getRealTime().timestamp
    th.msgs[#th.msgs + 1] = msg
    while #th.msgs > MAX_MSGS do table.remove(th.msgs, 1) end
    th.at = msg.at
    triggerEvent("onHospitalMessage", resourceRoot, hid, th.key, msg)
    if ER.markDirty then ER.markDirty(hid) end
end

-- export: every hospital with its ER state (ERM tablet)
function getHospitalStatus()
    local out = {}
    for _, h in ipairs(Hospitals.list) do
        local e = ER.byHospital[h.id]
        out[#out + 1] = { id = h.id, name = h.name, x = h.x, y = h.y, er = e ~= nil,
                          staff = e and #ER.staff(h.id) or 0, free = e and ER.freeCorridorCount(h.id) or 0,
                          total = e and #(e.cfg.corridor or {}) or 0 }
    end
    return out
end

-- export: an EMS crew sent parameters. card = { unit, medic, taskId, items = { { key, value } } }
function receiveParams(hospitalId, card)
    if type(card) ~= "table" or not Hospitals.byId[hospitalId] then return false end
    local list = cards[hospitalId] or {}
    cards[hospitalId] = list
    local entry = { at = getRealTime().timestamp, unit = tostring(card.unit or "?"), medic = card.medic, items = card.items or {} }
    table.insert(list, 1, entry)
    while #list > 12 do table.remove(list) end
    if ER.byHospital[hospitalId] then
        push(hospitalId, unitThread(hospitalId, entry.unit, card.taskId), { from = card.medic or entry.unit, side = "ems", card = entry.items })
        ER.notifyStaff(hospitalId, function(p)
            local parts = {}
            for _, it in ipairs(card.items or {}) do parts[#parts + 1] = L.forPlayer(p, "med_hospitals.comms.p_" .. it.key) .. " " .. tostring(it.value) end
            return L.forPlayer(p, "med_hospitals.comms.card", { unit = card.unit or "?", text = table.concat(parts, " · ") })
        end, true)
    end
    return true
end

function ER.cards(hospitalId) return cards[hospitalId] or {} end

-- export: an EMS crew writes to the hospital. from = { unit = callsign, taskId, name }
function sendHospitalMessage(hospitalId, from, text)
    if not ER.byHospital[hospitalId] or type(from) ~= "table" or type(text) ~= "string" then return false end
    text = text:gsub("[%c]", " "):sub(1, 300)
    if text == "" then return false end
    local th = unitThread(hospitalId, from.unit or "?", from.taskId)
    push(hospitalId, th, { from = tostring(from.name or from.unit or "?"), side = "ems", text = text })
    ER.notifyStaff(hospitalId, function(p) return L.forPlayer(p, "med_hospitals.comms.new_message", { unit = th.unit, text = text }) end, false)
    return true
end

-- export: the thread of a unit with this hospital (EMS tablet "Kórház" tab), or every unit thread of the
-- hospital when unit is nil
function getHospitalThreads(hospitalId, unit)
    local t = threadsOf(hospitalId)
    if unit then return t["unit:" .. tostring(unit)] or false end
    local out = {}
    for _, th in pairs(t) do if th.kind == "unit" then out[#out + 1] = th end end
    return out
end

-- a staff member writes into a thread (internal or to a unit)
function ER.staffMessage(hid, player, key, text)
    if type(text) ~= "string" then return false end
    text = text:gsub("[%c]", " "):sub(1, 300)
    if text == "" then return false end
    local th = threadsOf(hid)[key]
    if not th then return false end
    local name = getElementData(player, "displayName") or getPlayerName(player)
    push(hid, th, { from = name, side = "hospital", text = text })
    if th.kind == "internal" then
        ER.notifyStaff(hid, function(p) return L.forPlayer(p, "med_hospitals.comms.internal_message", { name = name, text = text }) end, false, player)
    end
    return true
end

-- the HIS (tablet / PC) list of threads: internal first, then the units by their last message
function ER.threadList(hid, viewer)
    local list = {}
    for _, th in pairs(threadsOf(hid)) do list[#list + 1] = th end
    table.sort(list, function(a, b)
        if a.kind ~= b.kind then return a.kind == "internal" end
        return (a.at or 0) > (b.at or 0)
    end)
    return list
end

-- unit threads close when their ERM task ended (or after 30 min without a task)
setTimer(function()
    local erm = ER.running("med_erm") and exports.med_erm or nil
    local now = getRealTime().timestamp
    for hid, t in pairs(threads) do
        for key, th in pairs(t) do
            if th.kind == "unit" then
                local open = true
                if th.taskId and erm then
                    local ok, task = pcall(function() return erm:getTask(th.taskId) end)
                    open = ok and type(task) == "table" and task.status ~= "closed" and task.status ~= "done"
                elseif now - (th.at or now) > 1800 then
                    open = false
                end
                if not open then t[key] = nil if ER.markDirty then ER.markDirty(hid) end end
            end
        end
    end
end, 30000, 0)

addEvent("his:message", true)
addEventHandler("his:message", resourceRoot, function(key, text)
    local hid = getElementData(client, "hosp.staff")
    if not hid or not ER.isStaff(client, hid) then return end
    ER.staffMessage(hid, client, tostring(key), text)
end)

---------------------------------------------------------------- notifications page (Értesítések)

local notes = {}   -- [player] = { { at, text, alert } } (last 30)

local baseNotify = ER.notify
function ER.notify(player, text, alert)
    if isElement(player) and getElementType(player) == "player" and getElementData(player, "hosp.staff") then
        local list = notes[player] or {}
        notes[player] = list
        table.insert(list, 1, { at = getRealTime().timestamp, text = text, alert = alert == true })
        while #list > 30 do table.remove(list) end
    end
    return baseNotify(player, text, alert)
end

function ER.notesOf(player) return notes[player] or {} end
addEventHandler("onPlayerQuit", root, function() notes[source] = nil end)
