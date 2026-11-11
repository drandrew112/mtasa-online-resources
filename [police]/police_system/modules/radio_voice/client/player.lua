-- police_system / modules/radio_voice/client/player.lua
-- The dispatcher voice on the client: the server sends "rv:say" (phrase id + args), the builder turns it into sound
-- items, the queue plays one message at a time.
--   queue: by trigger priority (0-4), a message older than its ttl is dropped, max db.settings.maxQueue waiting,
--          one "coalesce" group keeps only its newest message (pursuit updates), priority 4 (code 99) interrupts
--   play:  frame intro -> items one after the other on timers (trimmed lengths, gaps / overlaps) -> outro, static
--          noise underneath; the English sentence is a subtitle above the bottom HUD
-- Only for officers on duty (POL.unit). Volume: ui_pause Online > Dispatcher voice (setDispatchVolume export).

local RV = POL.module("voice", { queue = {}, cur = nil, last = {} })
local V = POLICE.VOICE
local DB

local volume = V.DEFAULT_VOLUME / 100
local sub = { text = "", untilTick = 0 }
local rendering = false

local function vol()
    local v = volume * (tonumber(DB and DB.settings.voiceVolume) or 1)
    if not isPedInVehicle(localPlayer) then v = v * V.ON_FOOT end
    return math.max(0, math.min(1, v))
end

------------------------------------------------------------------------ subtitle (drawn only while needed)

local function drawSubtitle()
    local now = getTickCount()
    if not RV.cur and now > sub.untilTick then
        removeEventHandler("onClientRender", root, drawSubtitle)
        rendering = false
        return
    end
    if sub.text == "" then return end
    local fade = RV.cur and 1 or math.min(1, (sub.untilTick - now) / 600)
    local s = POL.scale
    local w = POL.sw * 0.5
    local x, y = (POL.sw - w) / 2, POL.sh - POL.px(210)
    sub.label = sub.label or (L("police_system.voice.dispatch") .. ": ")
    local label = sub.label
    local a = math.floor(255 * fade)
    dxDrawText(label .. sub.text, x + 1, y + 1, x + w + 1, y + POL.px(60) + 1, tocolor(0, 0, 0, math.floor(a * 0.8)),
        1.1 * s, "default-bold", "center", "bottom", false, true)
    dxDrawText(label .. sub.text, x, y, x + w, y + POL.px(60), tocolor(170, 205, 255, a), 1.1 * s, "default-bold",
        "center", "bottom", false, true)
end

local function showSubtitle()
    if not rendering then
        rendering = true
        addEventHandler("onClientRender", root, drawSubtitle)
    end
end

------------------------------------------------------------------------ playback

local pump

local function killSound(s) if isElement(s) then stopSound(s) end end

-- ends the current message; interrupted = cut off by a higher priority one
local function finish(interrupted)
    local m = RV.cur
    if not m then return end
    if m.timer and isTimer(m.timer) then killTimer(m.timer) end
    if interrupted then for _, s in ipairs(m.sounds) do killSound(s) end end
    killSound(m.noise)
    RV.cur = nil
    sub.untilTick = getTickCount() + (interrupted and 0 or V.SUBTITLE_HOLD)
    if RV.wait and isTimer(RV.wait) then killTimer(RV.wait) end
    RV.wait = setTimer(function() RV.wait = nil; pump() end, interrupted and 50 or V.GAP_MESSAGES, 1)
end

local function step()
    local m = RV.cur
    if not m then return end
    m.i = m.i + 1
    local it = m.items[m.i]
    if not it then return finish(false) end
    local wait
    if it.pause then
        wait = it.pause
    else
        local s = playSound(it.file, false)
        if s then
            setSoundVolume(s, vol())
            m.sounds[#m.sounds + 1] = s
        end
        if not it.fx and it.text ~= "" then sub.text = sub.text == "" and it.text or (sub.text .. " " .. it.text) end
        wait = it.len
    end
    local nxt = m.items[m.i + 1]
    if nxt then wait = wait + (nxt.gap or 0) end
    m.timer = setTimer(step, math.max(50, wait), 1)
end

local function play(m)
    local items = VOICE.Builder.build(m.pid, m.args)
    if not items then return false end
    m.items, m.i, m.sounds = items, 0, {}
    RV.cur = m
    local frame = DB.frames[DB.triggers[m.pid].frame]
    if frame and frame.noise then
        local t = DB.tokens["FX.NOISE"]
        local c = t and DB.clips[t.clips[1]]
        if c and c.file then
            m.noise = playSound(c.file, true)
            if m.noise then setSoundVolume(m.noise, vol() * (tonumber(DB.settings.noiseVolume) or 0.18)) end
        end
    end
    sub.text = ""
    showSubtitle()
    step()
    return true
end

function pump()
    if RV.cur or RV.wait then return end
    local now = getTickCount()
    while #RV.queue > 0 do
        local m = table.remove(RV.queue, 1)
        if m.exp > now and play(m) then return end
    end
end

-- puts a message in the queue -> true | false (no voice / unknown phrase / cooldown)
function RV.say(pid, args, local_)
    DB = DB or VOICE.load()
    if not DB or volume <= 0 or not POL.onDuty() then return false end
    local t = DB.triggers[pid]
    if not t or not DB.phrases[pid] then return false end
    local now = getTickCount()
    if local_ and t.cooldown then
        if RV.last[pid] and now - RV.last[pid] < t.cooldown then return false end
        RV.last[pid] = now
    end
    local m = { pid = pid, args = type(args) == "table" and args or {}, pri = tonumber(t.priority) or 1,
                exp = now + (tonumber(t.ttl) or 10000), co = t.coalesce }
    local q = RV.queue
    if m.co then
        for i = #q, 1, -1 do if q[i].co == m.co then table.remove(q, i) end end
    end
    local pos = #q + 1
    for i, o in ipairs(q) do if m.pri > o.pri then pos = i break end end
    table.insert(q, pos, m)
    while #q > (tonumber(DB.settings.maxQueue) or 4) do table.remove(q) end
    if RV.cur and m.pri >= 4 and RV.cur.pri < 4 then finish(true) end
    pump()
    return true
end

function RV.stopAll()
    RV.queue = {}
    finish(true)
    sub.text, sub.untilTick = "", 0
end

POL.handle("rv:say", function(pid, args) RV.say(pid, args) end)

-- signed off: silence
POL.on("unit", function(unit) if not unit then RV.stopAll() end end)

------------------------------------------------------------------------ volume (ui_pause) + test command

-- exported: 0-100 (0 = off)
function setDispatchVolume(v)
    v = tonumber(v)
    if not v then return false end
    volume = math.max(0, math.min(100, v)) / 100
    if volume <= 0 then RV.stopAll() end
    return true
end

function getDispatchVolume() return math.floor(volume * 100 + 0.5) end

-- /dispatchtest [phrase]: a sample of every (or one) phrase, for officers on duty
local SAMPLE = { callsign = "A-12", plate = "4GTR218", color = "28,47,110", model = 560, heading = 0, area = "Idlewood",
                 crime = "robbery", priority = 1, stolen = true, warrant = true, caution = true, vehicle = true,
                 direction = true, shots = true }

addCommandHandler("dispatchtest", function(_, pid)
    DB = DB or VOICE.load()
    if not DB or not POL.hasRight() then return end
    if not POL.onDuty() then return POL.notify(L("police_system.voice.test_duty")) end
    if pid and DB.phrases[pid] then
        RV.say(pid, SAMPLE)
        return
    end
    local ids = {}
    for id in pairs(DB.phrases) do ids[#ids + 1] = id end
    table.sort(ids)
    outputConsole("dispatchtest: " .. table.concat(ids, ", "))
    RV.say(ids[math.random(#ids)], SAMPLE)
end)
