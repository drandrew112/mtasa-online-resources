-- Dispatcher <-> unit messaging. Kept in memory only.
--
-- Channels:
--   broadcast        -> every signed-in unit
--   unit  (target=id) -> one unit (dispatcher <-> crew thread)
--   task  (target=id) -> every unit currently assigned to the task
--
-- Each message remembers its recipient unit ids at send time, so a tablet's
-- history is simply "messages addressed to my unit".

Chat = {
    messages = {},
    nextId   = 1,
}

local function deliver(msg)
    for _, unitId in ipairs(msg.units) do
        local u = Units.get(unitId)
        if u then
            for _, p in ipairs(u.members) do
                triggerClientEvent(p, "erm:message", resourceRoot, msg)
            end
        end
    end
end

-- from: display name, fromDispatch: true when sent from the web console.
function Chat.post(channel, target, from, fromDispatch, text)
    text = cleanText(text, 300)
    if text == "" then return false, "Empty message" end

    local recipients, label = {}, ""
    if channel == "broadcast" then
        for id in pairs(Units.list) do recipients[#recipients + 1] = id end
        label = "Broadcast"
        target = 0
    elseif channel == "unit" then
        local u = Units.get(target)
        if not u then return false, "Unit not found" end
        recipients = { u.id }
        label = u.callsign
        target = u.id
    elseif channel == "task" then
        local t = Tasks.get(target)
        if not t then return false, "Task not found" end
        if #t.units == 0 then return false, "No units assigned to this task" end
        recipients = { unpack(t.units) }
        label = string.format("Case #%d", t.id)
        target = t.id
    else
        return false, "Unknown channel"
    end

    local ts = now()
    local msg = {
        id           = Chat.nextId,
        ts           = ts,
        time         = formatTime(ts),
        channel      = channel,
        target       = target,
        label        = label,
        from         = cleanText(from, 40),
        fromDispatch = fromDispatch and true or false,
        text         = text,
        units        = recipients,
    }
    Chat.nextId = Chat.nextId + 1

    Chat.messages[#Chat.messages + 1] = msg
    while #Chat.messages > Config.MAX_MESSAGES do table.remove(Chat.messages, 1) end

    deliver(msg)
    Events.fire("onErmMessage", msg.id, msg.channel, msg.target, msg.from, msg.fromDispatch, msg.text)
    return msg.id
end

function Chat.forUnit(unitId)
    local out = {}
    for _, m in ipairs(Chat.messages) do
        if hasValue(m.units, unitId) then out[#out + 1] = m end
    end
    while #out > 100 do table.remove(out, 1) end
    return out
end

-- Messages newer than lastId (the web page polls incrementally).
function Chat.since(lastId)
    local out = {}
    for _, m in ipairs(Chat.messages) do
        if m.id > lastId then
            out[#out + 1] = {
                id = m.id, ts = m.ts, time = m.time, channel = m.channel, target = m.target,
                label = m.label, from = m.from, fromDispatch = m.fromDispatch, text = m.text,
            }
        end
    end
    return out
end
