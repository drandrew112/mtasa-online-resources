-- police_system / modules/units/server/pay.lua
-- Pay at the end of a unit, by the submitted reports (type -> money / work XP per participant) + duty time
-- (POLICE.PAY.duty_10min per full 10 active minutes, AFK minutes do not count). Hourly cap (HOUR_CAP). Paid with
-- work_core payWork (income tax, weekly multiplier), XP with giveWorkXp. The amounts are gov_works wage
-- parameters (the /gov Works page sets them; the payer is the treasury by default).
-- A unit that ended with drafts left: pay_pending; paid once the last draft of that shift is submitted (offline
-- members at their next login).

local PAY = POL.module("pay", { kept = {} })
local P = POLICE.PAY

local WAGE_PARAMS = {
    { key = "traffic_warning", label = "Traffic / ped stop with a warning", default = P.traffic_warning },
    { key = "traffic_fine", label = "Traffic / ped stop with a fine", default = P.traffic_fine },
    { key = "arrest_npc", label = "Arrest (NPC)", default = P.arrest_npc },
    { key = "arrest_player", label = "Arrest (player, x wanted level)", default = P.arrest_player },
    { key = "pursuit_caught", label = "Pursuit with arrest", default = P.pursuit_caught },
    { key = "backup", label = "Backup / support", default = P.backup },
    { key = "duty_10min", label = "Duty time (per 10 minutes)", default = P.duty_10min },
    { key = "hour_cap", label = "Hourly cap", default = P.HOUR_CAP },
    { key = "xp_traffic_warning", label = "XP: stop with a warning", default = P.xp_traffic_warning, kind = "xp" },
    { key = "xp_traffic_fine", label = "XP: stop with a fine", default = P.xp_traffic_fine, kind = "xp" },
    { key = "xp_arrest_npc", label = "XP: arrest (NPC)", default = P.xp_arrest_npc, kind = "xp" },
    { key = "xp_arrest_player", label = "XP: arrest (player)", default = P.xp_arrest_player, kind = "xp" },
    { key = "xp_pursuit_caught", label = "XP: pursuit with arrest", default = P.xp_pursuit_caught, kind = "xp" },
    { key = "xp_backup", label = "XP: backup", default = P.xp_backup, kind = "xp" },
    { key = "xp_duty_10min", label = "XP: duty time (per 10 minutes)", default = P.xp_duty_10min, kind = "xp" },
}
local default = {}
for _, p in ipairs(WAGE_PARAMS) do default[p.key] = p.default end

function PAY.wage(key)
    if POL.running("gov_works") then
        local ok, v = pcall(function() return exports.gov_works:getWage(POLICE.WORK_ID, key) end)
        if ok and tonumber(v) then return tonumber(v) end
    end
    return default[key] or 0
end

function PAY.register()
    if POL.running("gov_works") then
        pcall(function() exports.gov_works:registerWage(POLICE.WORK_ID, WAGE_PARAMS) end)
    end
end

addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) == "gov_works" then PAY.register() end
end)

-- per account: { items = { {label, amount} }, xp, total } from the submitted reports of a shift
-- reports: { { pay_type, level, members = { acc, ... }, subjects, at } }; active: { [acc] = minutes }
function PAY.compute(reports, active, accounts, startedAt, endedAt)
    local out = {}
    local function entry(acc)
        local e = out[acc]
        if not e then e = { xp = 0, total = 0, counts = {}, sums = {} }; out[acc] = e end
        return e
    end
    local warned = {}   -- [acc .. subject] = last time (traffic warning once per 10 min per subject)
    for _, r in ipairs(reports) do
        local t = r.pay_type
        if t and default[t] then
            local amount = PAY.wage(t)
            if t == "arrest_player" then
                amount = math.floor(amount * (P.LEVEL_MULT[math.max(1, math.min(6, tonumber(r.level) or 1))] or 1) + 0.5)
            end
            local xp = PAY.wage("xp_" .. t)
            for _, acc in ipairs(r.members or {}) do
                local ok = true
                if t == "traffic_warning" then
                    for _, s in ipairs(r.subjects or {}) do
                        local k = acc .. "|" .. tostring(s)
                        if warned[k] and (r.at or 0) - warned[k] < P.WARNING_REPEAT then ok = false end
                        warned[k] = r.at or 0
                    end
                end
                if ok and accounts[acc] then
                    local e = entry(acc)
                    e.counts[t] = (e.counts[t] or 0) + 1
                    e.sums[t] = (e.sums[t] or 0) + amount
                    e.total = e.total + amount
                    e.xp = e.xp + xp
                end
            end
        end
    end
    -- duty time + the hourly cap
    local hours = math.max(1, ((endedAt or POL.now()) - (startedAt or POL.now())) / 3600)
    local cap = math.floor(PAY.wage("hour_cap") * hours)
    for acc in pairs(accounts) do
        local e = entry(acc)
        local blocks = math.floor((active[acc] or 0) / 10)
        if blocks > 0 then
            e.counts.duty_10min = blocks
            e.sums.duty_10min = blocks * PAY.wage("duty_10min")
            e.total = e.total + e.sums.duty_10min
            e.xp = e.xp + blocks * PAY.wage("xp_duty_10min")
        end
        if e.total > cap then e.capped = e.total - cap; e.total = cap end
    end
    return out
end

local LABELS = {
    traffic_warning = "police_system.pay.traffic_warning", traffic_fine = "police_system.pay.traffic_fine",
    arrest_npc = "police_system.pay.arrest_npc", arrest_player = "police_system.pay.arrest_player",
    pursuit_caught = "police_system.pay.pursuit_caught", backup = "police_system.pay.backup",
    duty_10min = "police_system.pay.duty_10min",
}

local function payPlayer(player, e, callsign)
    if not isElement(player) or not POL.running("work_core") then return false end
    local items = {}
    local full = 0
    for _, v in pairs(e.sums) do full = full + v end
    -- over the hourly cap every line is scaled down
    local scale = full > 0 and math.min(1, e.total / full) or 1
    for t, n in pairs(e.counts) do
        local amount = math.floor((e.sums[t] or 0) * scale)
        if amount > 0 then items[#items + 1] = { label = L.msg(LABELS[t], { count = n }), amount = amount } end
    end
    if e.capped then items[#items + 1] = { label = L.msg("police_system.pay.hour_cap"), amount = 0 } end
    if #items == 0 then items[1] = { label = L.msg("police_system.pay.nothing"), amount = 0 } end
    exports.work_core:payWork(player, POLICE.WORK_ID, items, L.msg("police_system.pay.reason", { callsign = callsign }))
    if e.xp > 0 then exports.work_core:giveWorkXp(player, POLICE.WORK_ID, e.xp) end
    return true
end

-- pays a finished shift from the database (its submitted reports), online accounts now, the rest stays pending
local function settleShift(shiftId, callsign, accounts, active, startedAt, endedAt)
    POL.db.query(function(rows)
        local reports = {}
        for _, r in ipairs(type(rows) == "table" and rows or {}) do
            reports[#reports + 1] = { pay_type = r.pay_type, level = r.level, members = POL.db.unjson(r.members),
                subjects = POL.db.unjson(r.subjects), at = tonumber(r.submitted_at) or 0 }
        end
        local result = PAY.compute(reports, active, accounts, startedAt, endedAt)
        local left = {}
        for acc, e in pairs(result) do
            local p = POL.playerByAccount(acc)
            if not (p and payPlayer(p, e, callsign)) then left[acc] = e end
        end
        POL.db.exec("UPDATE pol_shifts SET pay = ?, pay_pending = ? WHERE id = ?",
            POL.db.json({ callsign = callsign, left = left }), next(left) and 2 or 0, shiftId)
    end, "SELECT pay_type, level, members, subjects, submitted_at FROM pol_reports WHERE shift_id = ? AND status = 'submitted' AND is_pool = 0", shiftId)
end

function PAY.settle(unit)
    if not unit.shiftId then return end
    settleShift(unit.shiftId, unit.callsign, unit.accounts, unit.active, unit.startedAt, POL.now())
end

-- ended with drafts: what the pay needs is kept until the last draft is submitted
function PAY.keep(unit)
    if not unit.shiftId then return end
    PAY.kept[unit.shiftId] = { callsign = unit.callsign, accounts = unit.accounts, active = unit.active,
        startedAt = unit.startedAt, endedAt = POL.now() }
    POL.db.exec("UPDATE pol_shifts SET pay = ?, pay_pending = 1 WHERE id = ?", POL.db.json(PAY.kept[unit.shiftId]), unit.shiftId)
end

-- reports.lua: no draft left in a finished shift
function PAY.shiftComplete(shiftId)
    local k = PAY.kept[shiftId]
    if k then
        PAY.kept[shiftId] = nil
        return settleShift(shiftId, k.callsign, k.accounts, k.active, k.startedAt, k.endedAt)
    end
    POL.db.query(function(rows)
        local r = type(rows) == "table" and rows[1]
        if not r or tonumber(r.pay_pending) ~= 1 then return end
        local d = POL.db.unjson(r.pay)
        if d.accounts then settleShift(shiftId, d.callsign, d.accounts, d.active or {}, d.startedAt, d.endedAt) end
    end, "SELECT pay, pay_pending FROM pol_shifts WHERE id = ?", shiftId)
end

-- login: what was left for this account in settled shifts (pay_pending = 2)
addEvent("onPlayerAccountLogin")
addEventHandler("onPlayerAccountLogin", root, function(acc)
    local player = source
    if not POL.db.ready or not acc then return end
    POL.db.query(function(rows)
        for _, r in ipairs(type(rows) == "table" and rows or {}) do
            local d = POL.db.unjson(r.pay)
            local e = d.left and d.left[acc]
            if e and isElement(player) and payPlayer(player, e, d.callsign or "") then
                d.left[acc] = nil
                POL.db.exec("UPDATE pol_shifts SET pay = ?, pay_pending = ? WHERE id = ?", POL.db.json(d), next(d.left) and 2 or 0, r.id)
            end
        end
    end, "SELECT id, pay FROM pol_shifts WHERE pay_pending = 2 AND is_pool = 0 AND pay LIKE ?", '%"' .. acc .. '"%')
end)

function PAY.start() PAY.register() end
