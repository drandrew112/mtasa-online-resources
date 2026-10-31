-- police_system / modules/units/server/units.lua
-- Units: signing in only in a police vehicle, on the MDC. Adam (A-) = 2-4 officers (never alone), Lincoln (L-) =
-- exactly 1. Number 1-99; the number is taken whatever the type (A-10 and L-10 never at once), across every server
-- instance (open pol_shifts rows). One unit per player. Officers can be added on the way (invite + accept).
-- The leader quits: the unit ends. A member quits: the unit stays. Signing off only when every report of the closed
-- incidents is submitted; then the pay (pay.lua).
--
-- unit = { id, callsign, type, number, leader, members = { [player] = true }, order = { player, ... }, vehicle,
--          status, sub, shiftId, startedAt, incidents = { [incident] = true }, incSeq, tail = { log lines },
--          accounts = { [account] = name } (everybody who served in it), active = { [account] = minutes }, idle = {} }

local U = POL.module("units", { list = {}, byPlayer = {}, forms = {}, invites = {} })
local C = POLICE.UNITS
local nextId = 1

local function callsignOf(kind, number) return (kind == "adam" and "A-" or "L-") .. tostring(number) end

function U.of(player) return U.byPlayer[player] end

function U.members(unit)
    local out = {}
    if unit then for _, p in ipairs(unit.order) do if isElement(p) then out[#out + 1] = p end end end
    return out
end

function U.get(callsign)
    for _, u in pairs(U.list) do if u.callsign == callsign then return u end end
    return nil
end

-- every player signed in to a unit (on duty)
function U.onDuty()
    local out = {}
    for p in pairs(U.byPlayer) do if isElement(p) then out[#out + 1] = p end end
    return out
end

function U.isOnDuty(player) return U.byPlayer[player] ~= nil end

-- public state for the HUD / MDC
function U.state(unit)
    if not unit then return false end
    local names = {}
    for _, p in ipairs(U.members(unit)) do names[#names + 1] = POL.nameOf(p) end
    return { id = unit.id, callsign = unit.callsign, type = unit.type, status = unit.status, sub = unit.sub or false,
             members = names, leader = POL.nameOf(unit.leader), since = unit.startedAt }
end

function U.push(unit)
    POL.send(U.members(unit), "unit:state", U.state(unit))
    POL.emit("units.changed", unit)
end

-- pol.unit (callsign) on the unit vehicles, subscribed by every officer on duty
function U.refreshVehicleData()
    local duty = U.onDuty()
    for _, u in pairs(U.list) do
        local v = u.vehicle
        if isElement(v) then
            if getElementData(v, "pol.unit") ~= u.callsign then setElementData(v, "pol.unit", u.callsign, "subscribe") end
            for _, p in ipairs(duty) do
                if not hasElementDataSubscriber(v, "pol.unit", p) then addElementDataSubscriber(v, "pol.unit", p) end
            end
        end
    end
end

------------------------------------------------------------------------ sign-in form (MDC sign-in window)

local function form(player)
    local f = U.forms[player]
    if not f then f = { type = "lincoln", number = 1, invited = {} }; U.forms[player] = f end
    return f
end

-- is the number free here and on the other instances? cb(bool)
function U.numberFree(number, cb)
    number = tonumber(number)
    if not number or number < C.NUMBER_MIN or number > C.NUMBER_MAX then return cb(false) end
    for _, u in pairs(U.list) do if u.number == number then return cb(false) end end
    if not POL.db.ready then return cb(true) end
    POL.db.query(function(rows)
        cb(not (type(rows) == "table" and rows[1]))
    end, "SELECT id FROM pol_shifts WHERE ended_at IS NULL AND is_pool = 0 AND callsign IN (?, ?) LIMIT 1",
        callsignOf("adam", number), callsignOf("lincoln", number))
end

-- officers who could be invited: with the right, not in a unit, near
function U.candidates(player)
    local out = {}
    local x, y, z = getElementPosition(player)
    for _, p in ipairs(getElementsWithinRange(x, y, z, C.INVITE_DIST, "player")) do
        if p ~= player and not U.byPlayer[p] and POL.rights.has(p) then out[#out + 1] = p end
    end
    return out
end

function U.formState(player, cb)
    local f = form(player)
    local inv = {}
    for p, st in pairs(f.invited) do
        if isElement(p) then inv[#inv + 1] = { name = POL.nameOf(p), state = st, el = p } else f.invited[p] = nil end
    end
    local cand = {}
    for _, p in ipairs(U.candidates(player)) do
        if not f.invited[p] then cand[#cand + 1] = { name = POL.nameOf(p), el = p } end
    end
    U.numberFree(f.number, function(free)
        cb({ type = f.type, number = f.number, free = free, invited = inv, candidates = cand, leader = POL.nameOf(player),
             inVehicle = isPoliceVehicle(getPedOccupiedVehicle(player)) })
    end)
end

function U.setForm(player, kind, number)
    local f = form(player)
    if kind == "adam" or kind == "lincoln" then f.type = kind end
    number = math.floor(tonumber(number) or f.number)
    if number >= C.NUMBER_MIN and number <= C.NUMBER_MAX then f.number = number end
    if f.type == "lincoln" then f.invited = {} end
end

-- invite an officer: into the sign-in form, or into the running Adam unit of the leader
function U.invite(player, target)
    if not isElement(target) or target == player or U.byPlayer[target] or not POL.rights.has(target) then return false, "bad_target" end
    if POL.dist(player, target) > C.INVITE_DIST then return false, "too_far" end
    local unit = U.byPlayer[player]
    local callsign
    if unit then
        if unit.leader ~= player then return false, "not_leader" end
        if unit.type ~= "adam" then return false, "lincoln_alone" end
        if #U.members(unit) >= C.ADAM_MAX then return false, "full" end
        callsign = unit.callsign
    else
        local f = form(player)
        if f.type ~= "adam" then return false, "lincoln_alone" end
        local n = 1
        for _, st in pairs(f.invited) do if st ~= "declined" then n = n + 1 end end
        if n >= C.ADAM_MAX then return false, "full" end
        f.invited[target] = "pending"
        callsign = callsignOf(f.type, f.number)
    end
    U.invites[target] = { from = player, at = getTickCount() }
    POL.send(target, "unit:invite", POL.nameOf(player), callsign)
    return true
end

function U.answer(target, accept)
    local inv = U.invites[target]
    U.invites[target] = nil
    if not inv or not isElement(inv.from) or getTickCount() - inv.at > C.INVITE_TIMEOUT then return false end
    local leader = inv.from
    local unit = U.byPlayer[leader]
    if unit then
        if not accept then POL.notify(leader, "police_system.units.invite_declined", { name = POL.nameOf(target) }) return true end
        if U.byPlayer[target] or #U.members(unit) >= C.ADAM_MAX then return false end
        U.addMember(unit, target)
        return true
    end
    local f = U.forms[leader]
    if f and f.invited[target] then
        f.invited[target] = accept and "accepted" or "declined"
        POL.notify(leader, accept and "police_system.units.invite_accepted" or "police_system.units.invite_declined",
            { name = POL.nameOf(target) })
        POL.send(leader, "mdc:refresh", "signin")
    end
    return true
end

------------------------------------------------------------------------ lifecycle

function U.addMember(unit, player)
    if U.byPlayer[player] then return false end
    unit.members[player] = true
    unit.order[#unit.order + 1] = player
    U.byPlayer[player] = unit
    local acc = POL.accountOf(player) or getPlayerName(player)
    unit.accounts[acc] = POL.nameOf(player)
    unit.active[acc] = unit.active[acc] or 0
    if unit.shiftId then
        POL.db.appendLine("pol_shifts", "members", unit.shiftId, { acc = acc, at = POL.now(), joined = true })
    end
    POL.events.log(unit, player, "member_joined", {})
    U.push(unit)
    U.refreshVehicleData()
    POL.emit("units.member", unit, player, true)
    return true
end

function U.removeMember(unit, player, reason)
    if not unit.members[player] then return end
    unit.members[player] = nil
    for i, p in ipairs(unit.order) do if p == player then table.remove(unit.order, i) break end end
    U.byPlayer[player] = nil
    if unit.shiftId then
        POL.db.appendLine("pol_shifts", "members", unit.shiftId, { acc = POL.accountOf(player), at = POL.now(), left = reason or true })
    end
    POL.events.log(unit, player, "member_left", { reason = reason })
    if isElement(player) then POL.send(player, "unit:state", false) end
    U.push(unit)
    POL.emit("units.member", unit, player, false)
end

-- cb(true | false, err)
function U.signIn(player, cb)
    if U.byPlayer[player] then return cb(false, "already") end
    if not POL.rights.has(player) then return cb(false, "no_right") end
    local veh = getPedOccupiedVehicle(player)
    if not isPoliceVehicle(veh) then return cb(false, "vehicle") end
    local f = form(player)
    local accepted = {}
    for p, st in pairs(f.invited) do
        if st == "accepted" and isElement(p) and not U.byPlayer[p] and POL.rights.has(p) then accepted[#accepted + 1] = p end
    end
    if f.type == "adam" and (#accepted + 1 < C.ADAM_MIN or #accepted + 1 > C.ADAM_MAX) then return cb(false, "adam_size") end
    if f.type == "lincoln" then accepted = {} end
    U.numberFree(f.number, function(free)
        if not free then return cb(false, "number_taken") end
        if U.byPlayer[player] or not isElement(player) then return cb(false, "already") end
        local callsign = callsignOf(f.type, f.number)
        local unit = { id = nextId, callsign = callsign, type = f.type, number = f.number, leader = player, members = {},
            order = {}, vehicle = veh, status = "available", startedAt = POL.now(), incidents = {}, incSeq = 0, tail = {},
            accounts = {}, active = {}, idle = {} }
        nextId = nextId + 1
        U.list[unit.id] = unit
        U.forms[player] = nil
        POL.db.create("pol_shifts", { callsign = callsign, unit_type = f.type, leader = POL.accountOf(player) or "",
            members = "", started_at = unit.startedAt, events = "", pay = "", pay_pending = 0 }, function(id)
            unit.shiftId = id
            -- the shift row exists now: the member lines of the officers that already joined
            for _, p in ipairs(unit.order) do
                POL.db.appendLine("pol_shifts", "members", id, { acc = POL.accountOf(p), at = unit.startedAt, joined = true })
            end
            -- ended_at must be NULL for an open shift (pool rows have 0)
            POL.db.exec("UPDATE pol_shifts SET ended_at = NULL WHERE id = ?", id)
        end)
        U.addMember(unit, player)
        for _, p in ipairs(accepted) do U.addMember(unit, p) end
        POL.events.log(unit, player, "signed_in", { vehicle = getVehiclePlateText(veh) })
        POL.notify(U.members(unit), "police_system.units.signed_in", { callsign = callsign })
        POL.db.stat("shifts", 1)
        POL.emit("unit.signedIn", unit)
        cb(true)
    end)
end

-- the unit ends (sign off, leader quit, script). Open incidents are closed (their reports become drafts).
function U.finish(unit, reason)
    if not U.list[unit.id] then return end
    for inc in pairs(unit.incidents) do POL.events.close(inc, "unit_end") end
    POL.events.log(unit, unit.leader, "signed_off", { reason = reason })
    POL.events.flush(unit.shiftId)
    U.list[unit.id] = nil
    local members = U.members(unit)
    for _, p in ipairs(members) do U.byPlayer[p] = nil; POL.send(p, "unit:state", false) end
    if isElement(unit.vehicle) then removeElementData(unit.vehicle, "pol.unit") end
    local pending = POL.reports.pendingCount(unit)
    if unit.shiftId then
        local accs = {}
        for acc, name in pairs(unit.accounts) do accs[#accs + 1] = acc end
        POL.db.exec("UPDATE pol_shifts SET ended_at = ?, pay_pending = ? WHERE id = ?", POL.now(), pending > 0 and 1 or 0, unit.shiftId)
    end
    if pending == 0 then
        POL.pay.settle(unit)
    else
        POL.pay.keep(unit)
        POL.notify(members, "police_system.units.pay_pending", { count = pending })
    end
    POL.emit("unit.signedOff", unit, reason)
    POL.emit("units.changed", unit)
end

function U.signOff(player, cb)
    local unit = U.byPlayer[player]
    if not unit then return cb(false, "not_in_unit") end
    if unit.leader ~= player then
        U.removeMember(unit, player, "left")
        return cb(true)
    end
    local pending = POL.reports.pendingCount(unit)
    if pending > 0 then return cb(false, "reports", pending) end
    U.finish(unit, "sign_off")
    cb(true)
end

function U.setStatus(unit, status, by)
    if not unit or not UNIT_STATUS[status] or unit.status == status then return false end
    unit.status = status
    if status ~= "busy" then unit.sub = nil end
    POL.events.log(unit, by, "status", { status = status })
    U.push(unit)
    POL.emit("unit.status", unit, status, by)
    return true
end

-- the Busy sub label ("traffic_stop", ...): set automatically, does not change the status
function U.setSub(unit, sub)
    if not unit or unit.sub == sub then return end
    unit.sub = sub
    U.push(unit)
end

------------------------------------------------------------------------ activity (duty time pay, AFK)

local function activityTick()
    for _, unit in pairs(U.list) do
        for _, p in ipairs(U.members(unit)) do
            local acc = POL.accountOf(p) or getPlayerName(p)
            local x, y, z = getElementPosition(p)
            local last = unit.idle[acc]
            local moved = not last or (last.x - x) ^ 2 + (last.y - y) ^ 2 > 9
            if moved then
                unit.idle[acc] = { x = x, y = y, n = 0 }
            else
                last.n = last.n + 1
            end
            if (unit.idle[acc].n or 0) < POLICE.PAY.AFK_MINUTES then
                unit.active[acc] = (unit.active[acc] or 0) + 1
            end
        end
    end
end

function U.start()
    setTimer(activityTick, 60000, 0)
    -- open shifts of this instance left by a crash / restart: closed (their reports stay drafts)
    POL.on("db.ready", function()
        POL.db.exec("UPDATE pol_shifts SET ended_at = ? WHERE ended_at IS NULL AND is_pool = 0 AND server = ?",
            POL.now(), POL.db.instance())
    end)
end

function U.stop()
    for _, unit in pairs(U.list) do U.finish(unit, "shutdown") end
end

POL.net("unit:answer", function(player, accept) U.answer(player, accept == true) end)

addEventHandler("onPlayerQuit", root, function()
    local unit = U.byPlayer[source]
    U.forms[source] = nil
    U.invites[source] = nil
    for _, f in pairs(U.forms) do f.invited[source] = nil end
    if not unit then return end
    if unit.leader == source then
        U.removeMember(unit, source, "quit")
        U.finish(unit, "leader_quit")
    else
        U.removeMember(unit, source, "quit")
    end
end)

-- the last police vehicle a member drives is the unit vehicle
addEventHandler("onVehicleEnter", root, function(player, seat)
    local unit = U.byPlayer[player]
    if unit and seat == 0 and isPoliceVehicle(source) and unit.vehicle ~= source then
        if isElement(unit.vehicle) then removeElementData(unit.vehicle, "pol.unit") end
        unit.vehicle = source
        U.refreshVehicleData()
    end
end)

POL.on("rights.changed", function(player, on)
    if not on then
        local unit = U.byPlayer[player]
        if unit then
            if unit.leader == player then U.finish(unit, "right_lost") else U.removeMember(unit, player, "right_lost") end
        end
    end
end)
