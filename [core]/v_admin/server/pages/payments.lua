if not MYSQL then loadstring(exports.v_mysql:importAsync())() end -- v_mysql async lib
-- ============================================================
--  v_admin / server/pages/payments.lua
--  Payments page: SynHosting payments. The rows of ADMIN.payments.source
--  (`__syn_payments`, written by SynHosting, only read here) are copied into
--  ADMIN.payments.table with the approval columns:
--    status (pending | approved | rejected), suggested (account named in the
--    comment, '' = none found), account (credited), multiplier, bank_money,
--    reviewed_by, reviewed_at, reject_reason
--  An approval books amount (points) * multiplier bank money to the personal
--  v_bank account (key payment.topup); a rejection gives nobody anything.
--  Pending rows carry eventMultiplier: the ui_help donate event multiplier at
--  payment time, the default of the multiplier field.
--
--  list    { status, text, page }               -> { rows, more, counts, minMultiplier, maxMultiplier }
--  approve { id, account, multiplier }          edit
--  reject  { id, reason }                       edit
-- ============================================================

local CFG = ADMIN.payments
local TABLE, SOURCE = CFG.table, CFG.source
local ready = false
local sourceWarned = false

local function now() return getRealTime().timestamp end

local function ensure()
    if ready then return true end
    if not resourceRunning("v_mysql") or exports.v_mysql:mysqlIsConnected() ~= true then return false end
    exports.v_mysql:mysqlExec([[CREATE TABLE IF NOT EXISTS `]] .. TABLE .. [[` (
        `id`            INT          NOT NULL PRIMARY KEY,
        `paymethodid`   INT          NOT NULL DEFAULT 0,
        `amount`        INT          NOT NULL DEFAULT 0,
        `comment`       TEXT         NULL,
        `smsid`         TEXT         NULL,
        `smssendernum`  TEXT         NULL,
        `created`       TIMESTAMP    NULL DEFAULT NULL,
        `copied_at`     INT          NOT NULL DEFAULT 0,
        `status`        VARCHAR(10)  NOT NULL DEFAULT 'pending',
        `suggested`     VARCHAR(64)  NULL DEFAULT NULL,
        `account`       VARCHAR(64)  NULL DEFAULT NULL,
        `multiplier`    INT          NOT NULL DEFAULT ]] .. CFG.minMultiplier .. [[,
        `bank_money`    BIGINT       NOT NULL DEFAULT 0,
        `reviewed_by`   VARCHAR(64)  NULL DEFAULT NULL,
        `reviewed_at`   INT          NOT NULL DEFAULT 0,
        `reject_reason` VARCHAR(255) NULL DEFAULT NULL,
        KEY `idx_status` (`status`),
        KEY `idx_account` (`account`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    ready = true
    return true
end

local function cut(s, n)
    s = tostring(s or "")
    return utf8.sub(s, 1, n) or s:sub(1, n)
end

--------------------------------------------------------------------------------
-- copy + account suggestion
--------------------------------------------------------------------------------

--- the first word of a comment that is an account name ('' = none)
local function suggest(done)
    MYSQL.query(function(rows)
        if not rows or #rows == 0 then return done() end
        local want, per, names = {}, {}, {}
        for _, r in ipairs(rows) do
            local list = {}
            for tok in tostring(r.comment or ""):gmatch("[%w_%-%.]+") do
                tok = tok:lower()
                if #tok >= 3 and #tok <= 32 and #list < 20 then
                    list[#list + 1] = tok
                    if not want[tok] then want[tok] = true; names[#names + 1] = tok end
                end
            end
            per[#per + 1] = { id = tonumber(r.id), tokens = list }
        end
        local function finish(found)
            for _, p in ipairs(per) do
                local hit = ""
                for _, t in ipairs(p.tokens) do
                    if found[t] then hit = found[t]; break end
                end
                MYSQL.query(nil, "UPDATE `" .. TABLE .. "` SET suggested = ? WHERE id = ? AND suggested IS NULL", hit, p.id)
            end
            done()
        end
        if #names == 0 then return finish({}) end
        MYSQL.query(function(acc)
            if not acc then return done() end   -- asked again on the next copy
            local found = {}
            for _, a in ipairs(acc) do found[tostring(a.account_name):lower()] = tostring(a.account_name) end
            finish(found)
        end, "SELECT account_name FROM accounts WHERE LOWER(account_name) IN (" .. ("?,"):rep(#names):sub(1, -2) .. ")",
            unpack(names))
    end, "SELECT id, comment FROM `" .. TABLE .. "` WHERE status = 'pending' AND suggested IS NULL LIMIT 200")
end

--- copies the new source rows (idempotent: every server instance may run it). cb(ok)
local function sync(cb)
    cb = cb or function() end
    if not ensure() then return cb(false) end
    MYSQL.query(function(rows, info)
        if not rows then
            if not sourceWarned then
                sourceWarned = true
                outputDebugString(("[v_admin] payments: cannot read %s: %s"):format(SOURCE, tostring(info)), 2)
            end
            return cb(false)
        end
        sourceWarned = false
        suggest(function() cb(true) end)
    end, "INSERT IGNORE INTO `" .. TABLE .. "` (id, paymethodid, amount, comment, smsid, smssendernum, created, copied_at) "
        .. "SELECT s.id, s.paymethodid, s.amount, s.comment, s.smsid, s.smssendernum, s.created, ? FROM `" .. SOURCE .. "` s "
        .. "LEFT JOIN `" .. TABLE .. "` p ON p.id = s.id WHERE p.id IS NULL", now())
end

setTimer(sync, 5000, 1)
setTimer(sync, CFG.syncEvery * 1000, 0)

--------------------------------------------------------------------------------
-- page
--------------------------------------------------------------------------------

local STATUS = { pending = true, approved = true, rejected = true }

--- multiplier of the ui_help donate event running when the payment was made (min without one)
local function eventMultiplier(ts)
    if not resourceRunning("ui_help") then return CFG.minMultiplier end
    local m = math.floor(tonumber(exports.ui_help:getDonateMultiplier(ts)) or 0)
    return math.max(CFG.minMultiplier, math.min(CFG.maxMultiplier, m))
end

local function rowOut(r)
    local pending = tostring(r.status) == "pending"
    return {
        id = tonumber(r.id), method = tonumber(r.paymethodid) or 0, amount = tonumber(r.amount) or 0,
        comment = tostring(r.comment or ""), smsId = tostring(r.smsid or ""), sender = tostring(r.smssendernum or ""),
        created = tonumber(r.created_ts) or 0, status = tostring(r.status),
        suggested = tostring(r.suggested or ""), account = tostring(r.account or ""),
        multiplier = tonumber(r.multiplier) or CFG.minMultiplier, bankMoney = tonumber(r.bank_money) or 0,
        reviewedBy = tostring(r.reviewed_by or ""), reviewedAt = tonumber(r.reviewed_at) or 0,
        rejectReason = tostring(r.reject_reason or ""),
        eventMultiplier = pending and eventMultiplier(tonumber(r.created_ts) or tonumber(r.copied_at)) or nil,
    }
end

local function dbError(reply) return reply(false, L.msg("v_admin.page.database_error")) end

PAGES.register("payments", {
    perm = "payments",
    actions = {
        list = function(actor, args, reply)
            if not ensure() then return dbError(reply) end
            sync(function()
                local status = STATUS[args.status] and args.status or nil
                local text = argText(args.text)
                local page = math.max(0, math.floor(tonumber(args.page) or 0))
                local where, params = {}, {}
                if status then where[#where + 1] = "status = ?"; params[#params + 1] = status end
                if text ~= "" then
                    local like = likeText(text)
                    where[#where + 1] = "(comment LIKE ? OR account LIKE ? OR suggested LIKE ? OR smssendernum LIKE ? OR smsid LIKE ? OR id = ?)"
                    for _ = 1, 5 do params[#params + 1] = like end
                    params[#params + 1] = tonumber(text) or -1
                end
                params[#params + 1] = CFG.pageSize + 1
                params[#params + 1] = page * CFG.pageSize
                MYSQL.query(function(rows)
                    if not rows then return dbError(reply) end
                    local out = {}
                    for i = 1, math.min(#rows, CFG.pageSize) do out[i] = rowOut(rows[i]) end
                    MYSQL.query(function(c)
                        local counts = { pending = 0, approved = 0, rejected = 0 }
                        for _, r in ipairs(c or {}) do counts[tostring(r.status)] = tonumber(r.n) or 0 end
                        reply({ rows = out, more = #rows > CFG.pageSize, page = page, counts = counts,
                                minMultiplier = CFG.minMultiplier, maxMultiplier = CFG.maxMultiplier })
                    end, "SELECT status, COUNT(*) AS n FROM `" .. TABLE .. "` GROUP BY status")
                end, "SELECT *, UNIX_TIMESTAMP(created) AS created_ts FROM `" .. TABLE .. "`"
                    .. (#where > 0 and (" WHERE " .. table.concat(where, " AND ")) or "")
                    .. " ORDER BY id DESC LIMIT ? OFFSET ?", unpack(params))
            end)
        end,

        approve = function(actor, args, reply)
            if not ensure() then return dbError(reply) end
            local id = math.floor(tonumber(args.id) or 0)
            local name = argText(args.account)
            local mult = math.floor(tonumber(args.multiplier) or 0)
            if mult < CFG.minMultiplier or mult > CFG.maxMultiplier then
                return reply(false, L.msg("v_admin.payments.bad_multiplier", { min = CFG.minMultiplier, max = CFG.maxMultiplier }))
            end
            if name == "" then return reply(false, L.msg("v_admin.payments.need_account")) end
            if not resourceRunning("v_bank") then
                return reply(false, L.msg("v_admin.page.resource_missing", { name = "v_bank" }))
            end
            MYSQL.query(function(rows)
                if not rows then return dbError(reply) end
                local p = rows[1]
                if not p then return reply(false, L.msg("v_admin.payments.not_found")) end
                if p.status ~= "pending" then return reply(false, L.msg("v_admin.payments.already_reviewed")) end
                local points = tonumber(p.amount) or 0
                local money = points * mult
                if money <= 0 then return reply(false, L.msg("v_admin.page.bad_number")) end
                MYSQL.query(function(acc)
                    if not acc then return dbError(reply) end
                    local a = acc[1]
                    if not a then return reply(false, L.msg("v_admin.payments.no_account", { account = name })) end
                    local accName, bankId = tostring(a.account_name), tonumber(a.bank_id)
                    if not bankId then return reply(false, L.msg("v_admin.payments.no_bank_account", { account = accName })) end
                    local admin = actorAccount(actor) or "admin"
                    -- claim the row first: two admins cannot both book it
                    MYSQL.query(function(res, affected)
                        if not res then return dbError(reply) end
                        if tonumber(affected) ~= 1 then return reply(false, L.msg("v_admin.payments.already_reviewed")) end
                        local ok, err = exports.v_bank:credit(bankId, money, "payment.topup",
                            { payment = id, points = points, multiplier = mult, admin = admin }, admin)
                        -- a v_bank started before payment.topup existed: book it as an admin credit
                        if ok ~= true and err == "bad_key" then
                            ok, err = exports.v_bank:credit(bankId, money, "admin.credit",
                                { note = ("Payment #%d (%d points x%d)"):format(id, points, mult), admin = admin }, admin)
                        end
                        if ok ~= true then
                            outputDebugString(("[v_admin] payment #%d: v_bank credit of %d to account %s (bank #%d) failed: %s")
                                :format(id, money, accName, bankId, tostring(err)), 2)
                            MYSQL.query(nil, "UPDATE `" .. TABLE .. "` SET status = 'pending', account = NULL, bank_money = 0, "
                                .. "reviewed_by = NULL, reviewed_at = 0 WHERE id = ? AND status = 'approved'", id)
                            return reply(false, L.msg("v_admin.payments.credit_failed", { error = tostring(err or "?") }))
                        end
                        adminLog(actor, ("payment #%d approved: %d points x%d = %d bank money"):format(id, points, mult, money), accName)
                        reply({ id = id }, L.msg("v_admin.payments.approved_msg", { money = money, account = accName }))
                    end, "UPDATE `" .. TABLE .. "` SET status = 'approved', account = ?, multiplier = ?, bank_money = ?, "
                        .. "reviewed_by = ?, reviewed_at = ? WHERE id = ? AND status = 'pending'",
                        accName, mult, money, cut(admin, 64), now(), id)
                end, "SELECT a.account_name, b.id AS bank_id FROM accounts a LEFT JOIN bank_accounts b "
                    .. "ON b.kind = 'personal' AND b.owner_ref = LOWER(a.account_name) WHERE LOWER(a.account_name) = ? LIMIT 1",
                    name:lower())
            end, "SELECT id, amount, status FROM `" .. TABLE .. "` WHERE id = ?", id)
        end,

        reject = function(actor, args, reply)
            if not ensure() then return dbError(reply) end
            local id = math.floor(tonumber(args.id) or 0)
            local reason = argText(args.reason)
            if reason == "" then return reply(false, L.msg("v_admin.payments.need_reason")) end
            local admin = actorAccount(actor) or "admin"
            MYSQL.query(function(res, affected)
                if not res then return dbError(reply) end
                if tonumber(affected) ~= 1 then return reply(false, L.msg("v_admin.payments.already_reviewed")) end
                adminLog(actor, ("payment #%d rejected: %s"):format(id, reason):sub(1, 250))
                reply({ id = id }, L.msg("v_admin.payments.rejected_msg"))
            end, "UPDATE `" .. TABLE .. "` SET status = 'rejected', reject_reason = ?, reviewed_by = ?, reviewed_at = ? "
                .. "WHERE id = ? AND status = 'pending'", cut(reason, 255), cut(admin, 64), now(), id)
        end,
    },
})
