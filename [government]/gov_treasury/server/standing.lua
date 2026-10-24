-- gov_treasury / server/standing.lua
-- Standing orders (recurring transfers): the same three kinds as the Transfers page
--   state:   state account -> state account            (gov.transfer)
--   pay:     state account -> private company          (gov.company_payment, needs the money)
--   collect: private company -> state account          (gov.collection, forced)
-- Table gov_standing_orders. Every order has an interval (s) and next_run; a due order is claimed
-- with an UPDATE on its next_run (the other instance may see it at the same time), then booked.
-- An order that cannot be booked (not enough money ...) waits for the next interval.

loadstring(exports.gov_core:importLib())()

GOV.STANDING_CHECK_MS = 30000   -- due standing orders are booked this often
GOV.PUBLIC_REFRESH_MS = 60000   -- the budget for gov_web (getPublicFinance) is rebuilt this often

GOV_RANGE = {
    standingAmount = { 1, 100000000 },
    standingInterval = { 600, 365 * 86400 },   -- s between two bookings
}

local SCHEMA = {
    -- from_ref / to_ref = v_bank state account id, or biz_core company id on the private side
    -- (kind pay: to, collect: from)
    [[CREATE TABLE IF NOT EXISTS gov_standing_orders (
        id INT UNSIGNED NOT NULL AUTO_INCREMENT,
        kind VARCHAR(16) NOT NULL,
        from_ref INT UNSIGNED NOT NULL,
        to_ref INT UNSIGNED NOT NULL,
        amount BIGINT NOT NULL,
        interval_sec INT UNSIGNED NOT NULL,
        next_run INT UNSIGNED NOT NULL,
        last_run INT UNSIGNED NOT NULL DEFAULT 0,
        last_status VARCHAR(32) NOT NULL DEFAULT '',
        runs INT UNSIGNED NOT NULL DEFAULT 0,
        enabled TINYINT NOT NULL DEFAULT 1,
        note VARCHAR(48) NOT NULL DEFAULT '',
        created_by VARCHAR(64) NOT NULL DEFAULT '',
        created_at INT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (id),
        KEY idx_due (enabled, next_run)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

local function int(v) return DB.int(v) end

local KIND_KEY = { state = "gov.transfer", pay = "gov.company_payment", collect = "gov.collection" }

--- display name of a state bank account
local function stateName(id)
    local bank = GOV.bank()
    for _, c in ipairs(GOV.companyList()) do
        if c.accountId == id then return c.name end
    end
    local info = bank and bank:getAccountInfo(id)
    return info and info.name or ("#" .. tostring(id))
end

--- cb(name) of a biz_core company
local function bizName(id, cb)
    DB.query(function(rows)
        local r = rows and rows[1]
        cb(r and (tostring(r.name) .. " #" .. int(r.id)) or ("#" .. tostring(id)))
    end, "SELECT id, name FROM biz_companies WHERE id = ? LIMIT 1", id)
end

local function rowOrder(r)
    return { id = int(r.id), kind = tostring(r.kind), from = int(r.from_ref), to = int(r.to_ref), amount = int(r.amount),
        interval = int(r.interval_sec), nextRun = int(r.next_run), lastRun = int(r.last_run), lastStatus = tostring(r.last_status),
        runs = int(r.runs), enabled = int(r.enabled) == 1, note = tostring(r.note), createdBy = tostring(r.created_by),
        createdAt = int(r.created_at) }
end

--- cb(list): every order with fromName / toName
function GOV.standingList(cb)
    DB.query(function(rows)
        local list, pending, filled = {}, 0, false
        local function finish()
            if filled and pending == 0 then cb(list) end
        end
        for i, r in ipairs(rows or {}) do
            local o = rowOrder(r)
            list[i] = o
            local function name(ref, isCompany, field)
                if isCompany then
                    pending = pending + 1
                    bizName(ref, function(n) o[field] = n; pending = pending - 1; finish() end)
                else
                    o[field] = stateName(ref)
                end
            end
            name(o.from, o.kind == "collect", "fromName")
            name(o.to, o.kind == "pay", "toName")
        end
        filled = true
        finish()
    end, "SELECT * FROM gov_standing_orders ORDER BY id")
end

--- { kind, from, to, fromName, toName, amount, interval (s), note } -> cb(ok, errKey)
function GOV.standingCreate(d, actor, cb)
    local interval = int(d.interval)
    local amount = int(d.amount)
    if not KIND_KEY[d.kind] then return cb(false, "bad_field") end
    if amount < GOV_RANGE.standingAmount[1] or amount > GOV_RANGE.standingAmount[2] then return cb(false, "bad_number") end
    if interval < GOV_RANGE.standingInterval[1] or interval > GOV_RANGE.standingInterval[2] then return cb(false, "bad_number") end
    local now = GOV.now()
    DB.query(function(res)
        if res == false then return cb(false, "unknown") end
        GOV.log(actor, "standing.create", { kind = d.kind, from = d.fromName, to = d.toName, amount = amount, every = interval })
        cb(true)
    end, "INSERT INTO gov_standing_orders (kind, from_ref, to_ref, amount, interval_sec, next_run, note, created_by, created_at) "
        .. "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", d.kind, int(d.from), int(d.to), amount, interval, now + interval,
        DB.clip(d.note, 48), DB.clip(actor, 64), now)
end

function GOV.standingSetEnabled(id, enabled, actor, cb)
    local now = GOV.now()
    DB.query(function(res, affected)
        if res == false or tonumber(affected) == 0 then return cb(false, "bad_field") end
        GOV.log(actor, "standing.toggle", { id = int(id), enabled = enabled })
        cb(true)
    end, "UPDATE gov_standing_orders SET enabled = ?, next_run = GREATEST(next_run, ?) WHERE id = ?", enabled and 1 or 0, now, int(id))
end

function GOV.standingDelete(id, actor, cb)
    DB.query(function(res, affected)
        if res == false or tonumber(affected) == 0 then return cb(false, "bad_field") end
        GOV.log(actor, "standing.delete", { id = int(id) })
        cb(true)
    end, "DELETE FROM gov_standing_orders WHERE id = ?", int(id))
end

--------------------------------------------------------------------------------
-- the runner
--------------------------------------------------------------------------------

local function status(id, text, ok)
    DB.exec("UPDATE gov_standing_orders SET last_status = ?, last_run = ?, runs = runs + ? WHERE id = ?",
        DB.clip(text, 32), GOV.now(), ok and 1 or 0, id)
end

local function book(o, fromId, toId, fromName, toName)
    local bank = GOV.bank()
    local ok, err = bank:transfer(fromId, toId, o.amount, KIND_KEY[o.kind], { note = o.note }, "standing#" .. o.id)
    if not ok then return status(o.id, "failed: " .. tostring(err), false) end
    status(o.id, "ok", true)
    GOV.log("standing#" .. o.id, "transfer." .. o.kind, { from = fromName, to = toName, amount = o.amount, note = DB.clip(o.note, 48) })
end

local function execute(o)
    local bank = GOV.bank()
    if not bank or not bank:isBankReady() then return end
    local function company(ref, cb)
        DB.query(function(rows)
            local r = rows and rows[1]
            local acc = r and bank:getCompanyAccount(int(r.id))
            if not acc then return status(o.id, "failed: no_company", false) end
            cb(acc, tostring(r.name) .. " #" .. int(r.id))
        end, "SELECT id, name FROM biz_companies WHERE id = ? AND status = 'active' LIMIT 1", ref)
    end
    if o.kind == "state" then
        book(o, o.from, o.to, stateName(o.from), stateName(o.to))
    elseif o.kind == "pay" then
        company(o.to, function(acc, name) book(o, o.from, acc, stateName(o.from), name) end)
    else
        company(o.from, function(acc, name) book(o, acc, o.to, name, stateName(o.to)) end)
    end
end

local function runDue()
    if not DB.ready or not GOV.coreReady() then return end
    local now = GOV.now()
    DB.query(function(rows)
        for _, r in ipairs(rows or {}) do
            local o = rowOrder(r)
            o.interval = math.max(60, o.interval)
            -- missed intervals (server down) are skipped: one booking, then the next future slot
            local nextRun = o.nextRun + o.interval * (math.floor((now - o.nextRun) / o.interval) + 1)
            DB.query(function(res, affected)
                if res ~= false and tonumber(affected) == 1 then execute(o) end
            end, "UPDATE gov_standing_orders SET next_run = ? WHERE id = ? AND next_run = ? AND enabled = 1", nextRun, o.id, o.nextRun)
        end
    end, "SELECT * FROM gov_standing_orders WHERE enabled = 1 AND next_run <= ? ORDER BY next_run LIMIT 50", now)
end

addEventHandler("onResourceStart", resourceRoot, function()
    DB.start(SCHEMA, function()
        setTimer(runDue, GOV.STANDING_CHECK_MS, 0)
    end)
end)
