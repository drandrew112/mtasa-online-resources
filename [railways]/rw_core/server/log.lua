-- Railway event log: every event of the network in one place - trains (spawn / removal /
-- composition / driver / crossing between lines), services (start, stops, delays, completion,
-- cancellation), hold-ups (standing at a red signal, behind a train, without a route, stuck),
-- switches (thrown, trailed, repaired), signal aspects, SPADs, ATP overruns, crashes, Sifa.
--
-- Most of it comes from the events of rw_core / rw_customtracks / rw_signals / rw_timetable /
-- rw_loco; the rest is written by those resources through the railLog export.
-- Storage: the newest RW.LOG.KEEP entries in memory (/rwlog, getRailLog) and a daily file
-- logs/rail_YYYY-MM-DD.log (buffered, written every FLUSH_EVERY ms).

local L = RW.LOG
local LEVELS = { debug = 1, info = 2, warn = 3, error = 4 }
local ASPECTS = { [0] = "red", [1] = "yellow", [2] = "green" }

local entries = {}          -- ring buffer
local head, size, seq = 0, 0, 0
local pending = {}          -- file lines waiting for the flush: { day, line }

local function running(name)
    local r = getResourceFromName(name)
    return r and getResourceState(r) == "running"
end

local function call(res, fn, ...)
    if not running(res) then return nil end
    local ok, a = pcall(function(...) return exports[res][fn](exports[res], ...) end, ...)
    if ok then return a end
end

local function clean(name) return (tostring(name or "")):gsub("#%x%x%x%x%x%x", "") end
local function playerName(p) return isElement(p) and clean(getPlayerName(p)) or nil end

-- "BR 232 1112 / SL1 1015" (running number + the trip it runs)
function railTrainTag(id)
    local c = Consists[id]
    if not c then return "train #" .. tostring(id) end
    local def = RW.VEHICLES[c.types[1]]
    local tag = ("%s %d"):format(def and def.name or tostring(c.types[1]), c.number or 0)
    local svc = isElement(c.lead) and getElementData(c.lead, "rw.service")
    if type(svc) == "table" and svc.trip and svc.status == "running" then tag = tag .. " / " .. tostring(svc.trip) end
    return tag
end
local tagOf = railTrainTag

local function stamp(ts)
    local t = getRealTime(ts)
    return ("%04d-%02d-%02d"):format(t.year + 1900, t.month + 1, t.monthday), ("%02d:%02d:%02d"):format(t.hour, t.minute, t.second)
end

--[[ Writes one entry.
    category: train | service | delay | stop | hold | stuck | switch | signal | spad | safety | auto | loco
    level:    debug | info | warn | error
    text:     the event, in English
    train:    consist id it is about (optional) - the entry gets its running number / trip
    data:     extra fields kept with the entry (optional table) ]]
function railLog(category, level, text, train, data)
    category = tostring(category or "misc")
    if L.CATEGORIES[category] == false then return false end
    if not LEVELS[level] then level = "info" end
    seq = seq + 1
    local ts = getRealTime().timestamp
    local day, time = stamp(ts)
    local e = { seq = seq, ts = ts, time = time, level = level, cat = category, text = tostring(text),
        train = train, tag = train and tagOf(train) or nil, data = data }
    head = head % L.KEEP + 1
    entries[head] = e
    size = math.min(size + 1, L.KEEP)

    local line = ("%s %s %-5s %-7s %s%s"):format(day, time, level:upper(), category,
        e.tag and ("[" .. e.tag .. "] ") or "", e.text)
    if L.FILE then pending[#pending + 1] = { day, line } end
    if LEVELS[level] >= LEVELS[L.DEBUG_LEVEL] then
        outputDebugString("[rw_log] " .. line:sub(12), level == "error" and 1 or 2)
    end
    return seq
end

--[[ Entries, oldest first. opts = { category = "hold" | { hold = true, ... }, level = "warn" (minimum),
    train = consist id, match = text in the tag / text, since = seq, limit = n (newest n) } ]]
function getRailLog(opts)
    opts = opts or {}
    local cats = opts.category
    if type(cats) == "string" then cats = { [cats] = true } end
    local minLevel = LEVELS[opts.level] or 1
    local match = opts.match and tostring(opts.match):lower()
    local out = {}
    for k = 0, size - 1 do
        local e = entries[(head - k - 1) % L.KEEP + 1]
        if e and (not opts.since or e.seq > opts.since) and LEVELS[e.level] >= minLevel
            and (not cats or cats[e.cat]) and (not opts.train or e.train == opts.train)
            and (not match or (e.tag or ""):lower():find(match, 1, true) or e.text:lower():find(match, 1, true)) then
            out[#out + 1] = e
            if opts.limit and #out >= opts.limit then break end
        end
    end
    -- newest first above -> oldest first
    for i = 1, math.floor(#out / 2) do out[i], out[#out - i + 1] = out[#out - i + 1], out[i] end
    return out
end

------------------------------------------------------------------ file

local function flush()
    if #pending == 0 then return end
    local byDay, order = {}, {}
    for _, p in ipairs(pending) do
        if not byDay[p[1]] then byDay[p[1]] = {} order[#order + 1] = p[1] end
        local t = byDay[p[1]]
        t[#t + 1] = p[2]
    end
    pending = {}
    for _, day in ipairs(order) do
        local path = L.FILE_DIR .. "rail_" .. day .. ".log"
        local f = fileExists(path) and fileOpen(path) or fileCreate(path)
        if f then
            fileSetPos(f, fileGetSize(f))
            fileWrite(f, table.concat(byDay[day], "\n") .. "\n")
            fileClose(f)
        end
    end
end
setTimer(flush, L.FLUSH_EVERY, 0)

------------------------------------------------------------------ helpers

local function signalName(id)
    local s = call("rw_signals", "getSignal", tonumber(id) or id)
    return s and s.name or ("signal " .. tostring(id))
end

local function switchName(group)
    for _, s in ipairs(call("rw_customtracks", "getNetSwitches") or {}) do
        if s.id == group then return s.name and s.name ~= "" and s.name ~= group and (group .. " (" .. s.name .. ")") or group end
    end
    return tostring(group)
end

-- "train:5" / "train 5" -> running number
local function readableOwner(text)
    return (tostring(text):gsub("train[: ](%d+)", function(id) return tagOf(tonumber(id)) end))
end

-- an authority end the train is held by, in words (nil = not a hold-up)
local IGNORED = { destination = true, line = true, ["end of track"] = true }
local function holdReason(reason)
    reason = tostring(reason)
    local sig = reason:match("^signal (.+)$")
    if sig then return "red signal " .. signalName(sig), "signal" end
    local tr = reason:match("^train (%d+)$")
    if tr then return "train ahead (" .. tagOf(tonumber(tr)) .. ")", "train" end
    if reason == "no route" then return "no route can be set", "route" end
    if reason == "horizon" then return "route ahead not set", "route" end
    return readableOwner(reason), "route"
end

local function minutes(sec)
    sec = math.floor(sec + 0.5)
    if sec < 60 then return sec .. " s" end
    return ("%d min %02d s"):format(math.floor(sec / 60), sec % 60)
end

------------------------------------------------------------------ trains

addEventHandler("onRailConsistSpawn", root, function(id)
    local c = Consists[id]
    if not c then return end
    local types = {}
    for i = 2, #c.types do types[#types + 1] = RW.VEHICLES[c.types[i]] and RW.VEHICLES[c.types[i]].name or c.types[i] end
    local where = c.track and (RW.TRACK_NAMES[c.track] or ("line " .. c.track)) or "off the lines"
    railLog("train", "info", ("spawned%s on %s, %d carriage(s)%s"):format(c.auto and " (automatic)" or "",
        where, #c.cars, c.owner and (", by " .. playerName(c.owner)) or ""), id, { cars = types })
end)

addEventHandler("onRailConsistDestroy", root, function(id, reason)
    railLog("train", "info", "removed: " .. tostring(reason or "removed"), id)
end)

addEventHandler("onRailConsistChange", root, function(id)
    local c = Consists[id]
    railLog("train", "info", ("composition changed: %d carriage(s)"):format(c and #c.cars or 0), id)
end)

-- per train, from the simulation states: driver, lines, emergency brake, hold-ups
local watch = {}        -- [id] = { driver, line, emergency, hold = { since, reason, kind, logged, stuck }, idle = { since, warned } }

addEvent("onNetTrainStates", false)
addEventHandler("onNetTrainStates", root, function(list)
    local tick = getTickCount()
    local seen = {}
    for _, st in ipairs(list) do
        local id = st.id
        seen[id] = true
        local w = watch[id]
        local c = Consists[id]
        if not w then
            w = { driver = st.driver, line = c and c.track, emergency = st.emergency }
            watch[id] = w
        end

        -- driver
        local drv = isElement(st.driver) and st.driver or nil
        if drv ~= w.driver then
            if drv then railLog("train", "info", playerName(drv) .. " took the cab", id)
            elseif not st.auto then railLog("train", "info", (playerName(w.driver) or "the driver") .. " left the cab", id) end
            w.driver = drv
        end

        -- line changes (crossovers); trains between lines have no line for a moment
        local line = c and c.track
        if line and line ~= w.line then
            if w.line then
                railLog("train", "debug", ("crossed from %s to %s"):format(RW.TRACK_NAMES[w.line] or w.line, RW.TRACK_NAMES[line] or line), id)
            end
            w.line = line
        end

        -- emergency brake
        if st.emergency ~= w.emergency then
            if st.emergency then railLog("safety", "warn", ("emergency brake at %.0f km/h"):format(math.abs(st.speed) * 3.6), id) end
            w.emergency = st.emergency
        end

        -- hold-ups: standing close to the end of the movement authority
        local standing = math.abs(st.speed) < 0.1
        local A = st.authority
        local reason = standing and A and A.reason and (A.remaining or 0) <= L.BLOCK_DIST and not IGNORED[A.reason] and A.reason or nil
        local h = w.hold
        if reason then
            if not h then
                h = { since = tick, reason = reason }
                w.hold = h
            end
            if h.reason ~= reason then
                if h.logged then
                    local text = holdReason(reason)
                    railLog("hold", "info", "still standing, now held by " .. text, id)
                end
                h.reason = reason
            end
            local held = (tick - h.since) / 1000
            if not h.logged and held >= L.HOLD_MIN then
                h.logged = true
                local text, kind = holdReason(reason)
                railLog("hold", "info", "stopped: " .. text, id, { reason = reason, kind = kind })
            end
            if not h.stuck and held >= L.STUCK_AFTER then
                h.stuck = true
                railLog("stuck", "warn", ("stuck for %s: %s"):format(minutes(held), (holdReason(reason))), id, { reason = reason })
            end
        elseif h then
            local held = (tick - h.since) / 1000
            if h.stuck then
                railLog("stuck", "info", ("cleared after %s (%s)"):format(minutes(held), (holdReason(h.reason))), id)
            elseif h.logged then
                railLog("hold", "info", ("cleared after %s (%s)"):format(minutes(held), (holdReason(h.reason))), id)
            end
            w.hold = nil
        end

        -- automatic trains standing without any restriction (not at a platform)
        if st.auto and standing and not reason and not st.arrived then
            local i = w.idle
            if not i then i = { since = tick } w.idle = i end
            local idle = (tick - i.since) / 1000
            if not i.warned and idle >= L.STUCK_AFTER and not call("rw_timetable", "isConsistAtStation", id) then
                i.warned = true
                railLog("stuck", "warn", ("automatic train standing for %s outside a station (authority: %s)"):format(
                    minutes(idle), A and tostring(A.reason) or "none"), id)
            end
        elseif w.idle then
            if w.idle.warned then
                railLog("stuck", "info", ("automatic train moving again after %s"):format(minutes((tick - w.idle.since) / 1000)), id)
            end
            w.idle = nil
        end
    end
    for id in pairs(watch) do if not seen[id] then watch[id] = nil end end
end)

addEvent("onNetTrainCrash", false)
addEventHandler("onNetTrainCrash", root, function(id, hit, speed)
    local what = hit == "end" and "the buffer stop / end of track" or ("train " .. tagOf(tonumber(hit) or hit))
    railLog("safety", "error", ("collided with %s at %.0f km/h"):format(what, (speed or 0) * 3.6), id)
end)

addEvent("onNetTrainOverrun", false)
addEventHandler("onNetTrainOverrun", root, function(id, reason, speed)
    railLog("safety", "warn", ("overran its authority end (%s) at %.0f km/h - ATP stopped it"):format(
        (holdReason(reason)), (speed or 0) * 3.6), id)
end)

------------------------------------------------------------------ switches

addEvent("onNetSwitchChange", false)
addEventHandler("onNetSwitchChange", root, function(group, state, reason, owner)
    local why = reason == "route" and ("route of " .. readableOwner(owner or "?")) or tostring(reason)
    local trainId = owner and tonumber(tostring(owner):match("^train:(%d+)$"))
    railLog("switch", reason == "trailed" and "warn" or "info", ("%s -> %s (%s)"):format(switchName(group), tostring(state), why),
        trainId, { switch = group, state = state, reason = reason })
end)

addEvent("onNetTrainTrailedSwitch", false)
addEventHandler("onNetTrainTrailedSwitch", root, function(id, node)
    railLog("switch", "warn", ("trailed a switch set against it (node %s) - the switch is damaged"):format(tostring(node)), id)
end)

addEvent("onNetSwitchRepaired", false)
addEventHandler("onNetSwitchRepaired", root, function(group)
    railLog("switch", "info", switchName(group) .. " repaired")
end)

------------------------------------------------------------------ signals

addEvent("onRailSignalChange")
addEventHandler("onRailSignalChange", root, function(sigId, aspect, prev, name)
    if prev == nil then return end          -- initial aspects at start
    railLog("signal", "debug", ("%s: %s -> %s"):format(tostring(name or sigId), ASPECTS[prev] or tostring(prev), ASPECTS[aspect] or tostring(aspect)),
        nil, { signal = sigId, aspect = aspect })
end)

addEvent("onRailSignalPassedAtDanger")
addEventHandler("onRailSignalPassedAtDanger", root, function(id, sigId, name)
    railLog("spad", "error", "passed signal " .. tostring(name or sigId) .. " at danger (SPAD)", id, { signal = sigId })
end)

------------------------------------------------------------------ services (rw_timetable)

local function tripLabel(tripId)
    local plan = call("rw_timetable", "getTripPlan", tripId)
    if type(plan) == "table" and plan.number then
        return ("%s (%s -> %s)"):format(tostring(plan.number), tostring(plan.from), tostring(plan.to))
    end
    return tostring(tripId)
end

addEvent("onRailServiceStart")
addEventHandler("onRailServiceStart", root, function(id, tripId, player)
    railLog("service", "info", ("service %s started%s"):format(tripLabel(tripId),
        isElement(player) and (" by " .. playerName(player)) or (isConsistAuto(id) and " (automatic)" or "")), id, { trip = tripId })
end)

addEvent("onRailServiceComplete")
addEventHandler("onRailServiceComplete", root, function(id, tripId, player, sum)
    sum = type(sum) == "table" and sum or {}
    local d = sum.arrivalDelay or 0
    railLog("service", "info", ("service %s completed: arrival %s, %d stop(s) served, %d skipped, %d early departure(s), max delay %s"):format(
        tostring(sum.number or tripId), d >= 60 and ("+" .. math.floor(d / 60) .. " min") or "on time",
        sum.served or 0, sum.skipped or 0, sum.earlyDepartures or 0, minutes(sum.maxDelay or 0)), id, { trip = tripId, summary = sum })
end)

addEvent("onRailServiceCancel")
addEventHandler("onRailServiceCancel", root, function(id, tripId, reason)
    railLog("service", "warn", ("service %s cancelled: %s"):format(tostring(tripId), tostring(reason)), Consists[id] and id or nil, { trip = tripId })
end)

------------------------------------------------------------------ locomotives (rw_loco)

addEvent("onRailSifaBrake")
addEventHandler("onRailSifaBrake", root, function(id, player)
    railLog("safety", "warn", "Sifa (driver vigilance) brake" .. (isElement(player) and (" - driver " .. playerName(player)) or ""), id)
end)

addEvent("onRailEngineChange")
addEventHandler("onRailEngineChange", root, function(id, eng)
    railLog("loco", "debug", "engine " .. tostring(eng), id)
end)

addEventHandler("onElementDataChange", root, function(key, old, new)
    if key ~= "rw.doors" or old == new then return end
    local id = getVehicleConsist(source)
    if not id then return end
    railLog("loco", "debug", new == "closed" and "doors closed" or ("doors released: " .. tostring(new)), id)
end)

------------------------------------------------------------------ /rwlog

local COLORS = { debug = { 150, 150, 150 }, info = { 200, 220, 255 }, warn = { 255, 200, 90 }, error = { 255, 90, 90 } }

-- /rwlog                 last entries (no signal aspect changes)
-- /rwlog warn            warnings and errors
-- /rwlog <category>      e.g. hold, stuck, delay, switch, signal, service, spad
-- /rwlog <text>          a running number / trip number / station / switch ("1112", "SL3", "W19")
-- /rwlog ... <count>
addCommandHandler(L.CMD, function(player, _, a, b)
    if not isRailwayAdmin(player) then
        outputChatBox("[" .. RW.COMPANY_SHORT .. "] Nincs jogod ehhez.", player, 255, 80, 80)
        return
    end
    -- a lone small number is the count; running numbers (1001+) are filters
    local filter, count = a, tonumber(b)
    if a and not b and tonumber(a) and tonumber(a) <= 100 then filter, count = nil, tonumber(a) end
    count = count or L.CMD_LINES
    local opts = { limit = math.min(count, 100) }
    if not filter then
        local cats = {}
        for k, on in pairs(L.CATEGORIES) do if on and k ~= "signal" then cats[k] = true end end
        opts.category, opts.level = cats, "info"
    elseif filter == "all" then
    elseif LEVELS[filter] then opts.level = filter
    elseif L.CATEGORIES[filter] ~= nil then opts.category = filter
    else opts.match = filter end
    local list = getRailLog(opts)
    outputChatBox(("[%s] Vasúti napló (%s) - %d bejegyzés:"):format(RW.COMPANY_SHORT, filter or "minden", #list), player, 120, 200, 255)
    for _, e in ipairs(list) do
        local col = COLORS[e.level] or COLORS.info
        outputChatBox(("%s %s %s%s"):format(e.time, e.cat, e.tag and ("[" .. e.tag .. "] ") or "", e.text), player, col[1], col[2], col[3])
    end
end)

addEventHandler("onResourceStart", resourceRoot, function()
    railLog("train", "info", "rw_core started - railway log running")
end)

addEventHandler("onResourceStop", resourceRoot, function()
    railLog("train", "info", "rw_core stopped")
    flush()
end)
