-- police_system / modules/units/server/pay.lua
-- Pay at the end of a unit, by the submitted reports (type -> money / work XP per participant) + duty time
-- (POLICE.PAY.duty_10min per full 10 active minutes, AFK minutes do not count). Hourly cap (HOUR_CAP). Paid with
-- work_core payWork (income tax, weekly multiplier), XP with giveWorkXp. The amounts are gov_works wage
-- parameters (the /gov Works page sets them; the payer is the treasury by default).
-- Paid at once when the duty ends: the unit ends (everybody still in it) or a member leaves / quits (that member).
-- A report submitted after that (a draft left by a forced end: leader quit, right lost, restart) pays its own share
-- when it is submitted. Offline accounts (quit) get it at their next login.
-- pol_shifts.pay = { callsign, startedAt, endedAt, paid = { [acc] = { ["r<report id>"] = true } },
--                    paidTotal = { [acc] = money }, left = { [acc] = entry } }; pay_pending = 2 while `left` has rows.

local PAY = POL.module("pay", {})
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

-- per account: { counts, sums, xp, total, ids } from the submitted reports of a shift
-- reports: { { id, pay_type, level, members = { acc, ... }, subjects, at } }; active: { [acc] = minutes }
-- paid: { [acc] = { ["r<id>"] = true } } reports already paid (skipped); paidTotal: { [acc] = money } (the cap)
function PAY.compute(reports, active, accounts, startedAt, endedAt, paid, paidTotal)
    paid, paidTotal = paid or {}, paidTotal or {}
    local out = {}
    local function entry(acc)
        local e = out[acc]
        if not e then e = { xp = 0, total = 0, counts = {}, sums = {}, ids = {} }; out[acc] = e end
        return e
    end
    local warned = {}   -- [acc .. subject] = last time (traffic warning once per 10 min per subject)
    for _, r in ipairs(reports) do
        local t = r.pay_type
        local key = "r" .. tostring(r.id)
        local members = {}
        for _, acc in ipairs(r.members or {}) do
            if accounts[acc] and not (paid[acc] and paid[acc][key]) then
                members[#members + 1] = acc
                local e = entry(acc)
                e.ids[#e.ids + 1] = key
            end
        end
        if t and default[t] then
            local amount = PAY.wage(t)
            if t == "arrest_player" then
                amount = math.floor(amount * (P.LEVEL_MULT[math.max(1, math.min(6, tonumber(r.level) or 1))] or 1) + 0.5)
            end
            local xp = PAY.wage("xp_" .. t)
            for _, acc in ipairs(members) do
                local ok = true
                if t == "traffic_warning" then
                    for _, s in ipairs(r.subjects or {}) do
                        local k = acc .. "|" .. tostring(s)
                        if warned[k] and (r.at or 0) - warned[k] < P.WARNING_REPEAT then ok = false end
                        warned[k] = r.at or 0
                    end
                end
                if ok then
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
    local fullCap = math.floor(PAY.wage("hour_cap") * hours)
    for acc in pairs(accounts) do
        local e = entry(acc)
        local cap = math.max(0, fullCap - (tonumber(paidTotal[acc]) or 0))
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

-- a left entry merged into another (two payouts both waiting for the next login)
local function merge(a, b)
    if not a then return b end
    for t, n in pairs(b.counts or {}) do a.counts[t] = (a.counts[t] or 0) + n end
    for t, v in pairs(b.sums or {}) do a.sums[t] = (a.sums[t] or 0) + v end
    a.total = (a.total or 0) + (b.total or 0)
    a.xp = (a.xp or 0) + (b.xp or 0)
    a.capped = a.capped or b.capped
    return a
end

local function newRecord(callsign, startedAt)
    return { callsign = callsign, startedAt = startedAt, paid = {}, paidTotal = {}, left = {} }
end

local function saveRecord(shiftId, rec)
    POL.db.exec("UPDATE pol_shifts SET pay = ?, pay_pending = ? WHERE id = ?", POL.db.json(rec),
        next(rec.left) and 2 or 0, shiftId)
end

-- pays `accounts` ({ [acc] = name }) from the submitted reports of the shift (`reportId`: only that report) not paid
-- yet + `active` duty minutes. Online accounts now, the rest (and `offline` ones) at the next login.
local function payout(shiftId, rec, accounts, active, endedAt, opts)
    opts = opts or {}
    local sql = "SELECT id, pay_type, level, members, subjects, submitted_at FROM pol_reports WHERE shift_id = ? AND status = 'submitted' AND is_pool = 0"
    local args = { shiftId }
    if opts.reportId then sql = sql .. " AND id = ?"; args[2] = opts.reportId end
    POL.db.query(function(rows)
        local reports = {}
        for _, r in ipairs(type(rows) == "table" and rows or {}) do
            reports[#reports + 1] = { id = r.id, pay_type = r.pay_type, level = r.level, members = POL.db.unjson(r.members),
                subjects = POL.db.unjson(r.subjects), at = tonumber(r.submitted_at) or 0 }
        end
        local result = PAY.compute(reports, active, accounts, rec.startedAt, endedAt, rec.paid, rec.paidTotal)
        for acc, e in pairs(result) do
            local again = rec.paidTotal[acc] ~= nil
            rec.paid[acc] = rec.paid[acc] or {}
            for _, k in ipairs(e.ids) do rec.paid[acc][k] = true end
            e.ids = nil
            -- already paid once and nothing new: no empty pay slip
            if not (again and e.total <= 0 and e.xp <= 0) then
                rec.paidTotal[acc] = (tonumber(rec.paidTotal[acc]) or 0) + e.total
                local p = not (opts.offline and opts.offline[acc]) and POL.playerByAccount(acc)
                if not (p and payPlayer(p, e, rec.callsign)) then rec.left[acc] = merge(rec.left[acc], e) end
            end
        end
        saveRecord(shiftId, rec)
    end, sql, unpack(args))
end

local function record(unit)
    unit.payRec = unit.payRec or newRecord(unit.callsign, unit.startedAt)
    return unit.payRec
end

-- the unit ended: everybody who served in it, at once (drafts left are paid when submitted: PAY.report)
function PAY.settle(unit)
    if not unit.shiftId then return end
    local rec = record(unit)
    rec.endedAt = POL.now()
    payout(unit.shiftId, rec, unit.accounts, unit.active, rec.endedAt)
end

-- a member's duty ended (left the unit, quit, lost the right): that member at once; quit = at the next login
function PAY.member(unit, player, acc, quit)
    if not unit.shiftId or not acc then return end
    local minutes = unit.active[acc] or 0
    unit.active[acc] = minutes % 10   -- the started 10 minutes stay for a later rejoin
    payout(unit.shiftId, record(unit), { [acc] = unit.accounts[acc] or POL.nameOf(player) }, { [acc] = minutes },
        POL.now(), { offline = quit and { [acc] = true } or nil })
end

-- reports.lua: a report of an ended shift was submitted: its share is paid now
function PAY.report(shiftId, reportId)
    POL.db.query(function(rows)
        local s = type(rows) == "table" and rows[1]
        if not s then return end
        local rec = POL.db.unjson(s.pay)
        if not rec.paid then rec = newRecord(s.callsign, tonumber(s.started_at)) end
        rec.paidTotal, rec.left = rec.paidTotal or {}, rec.left or {}
        rec.startedAt = rec.startedAt or tonumber(s.started_at)
        rec.endedAt = rec.endedAt or tonumber(s.ended_at) or POL.now()
        POL.db.query(function(r)
            local row = type(r) == "table" and r[1]
            if not row then return end
            local accounts = {}
            for _, acc in ipairs(POL.db.unjson(row.members)) do accounts[acc] = true end
            payout(shiftId, rec, accounts, {}, rec.endedAt, { reportId = reportId })
        end, "SELECT members FROM pol_reports WHERE id = ?", reportId)
    end, "SELECT callsign, started_at, ended_at, pay FROM pol_shifts WHERE id = ?", shiftId)
end

-- login: what was left for this account (pay_pending = 2)
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
