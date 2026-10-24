-- v_bank / server/queries.lua
-- Reads that need the database (statements, search, account lookup by number) and the
-- requests of the bank website.
--
-- Website (ui_browser server calls these; the answer is a client event to the player):
--   requestBankAccounts(player)                          -> "v_bank:accounts"  (list)
--   requestLedger(player, accountId, beforeId, group)    -> "v_bank:ledger"    (accountId, rows, hasMore, beforeId)
--   requestTransfer(player, fromId, number, amount, note, confirm)
--                                                        -> "v_bank:transfer"  (stage, data)
--
-- Admin / v_gov (answers later, like v_admin REMOTE.call):
--   bankCall(requestId, action, args, actorAccount) -> true | false
--   answer: triggerEvent("<caller resource>:remoteResult", <caller root>, requestId, result)

local function int(v) return DB.int(v) end

--- cb(map): lower-case account name -> display name, for the website only (the
--- tables keep the account name). Online players come from element data, the rest
--- from one query; an account without a display name is left out of the map.
local function displayNames(refs, cb)
    local map, need, seen = {}, {}, {}
    for _, ref in ipairs(refs) do
        local key = tostring(ref):lower()
        if key ~= "" and not seen[key] then
            seen[key] = true
            local online = exports.acc_auth:playerOnAccount(key)
            local d = online and getElementData(online, "displayName")
            if type(d) == "string" and d ~= "" then map[key] = d
            elseif not online then need[#need + 1] = key end
        end
    end
    if #need == 0 then return cb(map) end
    local marks = string.rep("?,", #need):sub(1, -2)
    DB.query(function(rows)
        for _, r in ipairs(rows or {}) do
            if type(r.display_name) == "string" and r.display_name ~= "" then map[tostring(r.k):lower()] = r.display_name end
        end
        cb(map)
    end, "SELECT LOWER(account_name) AS k, display_name FROM accounts WHERE LOWER(account_name) IN (" .. marks .. ")", unpack(need))
end

--- a ledger row for the UI
local function ledgerRow(r)
    local params = {}
    local p = r.params and r.params ~= "" and fromJSON(tostring(r.params))
    if type(p) == "table" then params = p end
    return {
        id = int(r.id), ts = int(r.ts), amount = int(r.amount),
        balance = r.balance_after ~= nil and r.balance_after ~= false and tonumber(r.balance_after) or false,
        key = tostring(r.tx_key), params = params, actor = tostring(r.actor or ""),
        counter = r.counter_number and { number = tostring(r.counter_number), name = tostring(r.counter_name or ""),
            kind = tostring(r.counter_kind or "") } or false,
    }
end

--- cb(rows, hasMore) of one account, newest first
local function queryLedger(id, beforeId, group, limit, cb, since, display)
    limit = math.max(1, math.min(BANK.LEDGER_MAX, math.floor(tonumber(limit) or BANK.LEDGER_PAGE)))
    local sql = "SELECT l.id, l.ts, l.amount, l.balance_after, l.tx_key, l.params, l.actor, "
        .. "c.number AS counter_number, c.name AS counter_name, c.kind AS counter_kind, c.owner_ref AS counter_owner "
        .. "FROM bank_ledger l LEFT JOIN bank_accounts c ON c.id = l.counter_id WHERE l.account_id = ?"
    local args = { tonumber(id) or 0 }
    if tonumber(beforeId) then
        sql = sql .. " AND l.id < ?"
        args[#args + 1] = math.floor(tonumber(beforeId))
    end
    if tonumber(since) then
        sql = sql .. " AND l.ts >= ?"
        args[#args + 1] = math.floor(tonumber(since))
    end
    if type(group) == "string" and group:match("^[%w_]+$") then
        sql = sql .. " AND l.tx_key LIKE ?"
        args[#args + 1] = group .. ".%"
    end
    sql = sql .. " ORDER BY l.id DESC LIMIT " .. (limit + 1)
    DB.query(function(rows)
        if not rows then return cb(false) end
        local out, refs = {}, {}
        for i = 1, math.min(#rows, limit) do
            out[i] = ledgerRow(rows[i])
            if out[i].counter and out[i].counter.kind == "personal" then refs[#refs + 1] = tostring(rows[i].counter_owner or "") end
        end
        if not display then return cb(out, #rows > limit) end
        -- the website shows display names of personal counter accounts
        displayNames(refs, function(map)
            for i, row in ipairs(out) do
                local c = row.counter
                if c and c.kind == "personal" then c.name = map[tostring(rows[i].counter_owner or ""):lower()] or c.name end
            end
            cb(out, #rows > limit)
        end)
    end, sql, unpack(args))
end

local function infoOfRow(r)
    local a = getAcc(r.id)
    return {
        id = int(r.id), number = tostring(r.number or ""), kind = tostring(r.kind), ownerRef = tostring(r.owner_ref),
        name = tostring(r.name or ""), balance = a and a.balance or int(r.balance),
        status = tostring(r.status or "active"), allowNegative = int(r.allow_negative) == 1, online = a ~= nil,
    }
end

local ACC_COLS = "id, number, kind, owner_ref, name, balance, allow_negative, status"

--- cb(info | false) of an account number (cache first)
local function findByNumber(number, cb)
    number = tostring(number or ""):upper():gsub("%s", "")
    if number == "" then return cb(false) end
    for _, a in pairs(ACC) do
        if a.number == number then return cb(getAccountInfo(a.id)) end
    end
    DB.query(function(rows)
        local r = rows and rows[1]
        cb(r and infoOfRow(r) or false)
    end, "SELECT " .. ACC_COLS .. " FROM bank_accounts WHERE number = ?", number)
end

--------------------------------------------------------------------------------
-- website
--------------------------------------------------------------------------------

local function toClient(player, event, ...)
    if isElement(player) then triggerClientEvent(player, event, resourceRoot, ...) end
end

--- the accounts the player can see: own personal + every access row
function requestBankAccounts(player)
    if not isElement(player) or not PLAYER_ACC[player] then return false end
    loadAccess(player, function(map)
        if not isElement(player) then return end
        local list = {}
        local own = getAccountInfo(PLAYER_ACC[player])
        if own then own.role = "owner"; list[1] = own end
        for id, role in pairs(map or {}) do
            local info = getAccountInfo(id)
            if info and info.status ~= "closed" and id ~= PLAYER_ACC[player] then
                info.role = role
                list[#list + 1] = info
            end
        end
        local refs = {}
        for _, info in ipairs(list) do
            if info.kind == "personal" then refs[#refs + 1] = info.ownerRef end
        end
        displayNames(refs, function(map)
            for _, info in ipairs(list) do
                if info.kind == "personal" then info.name = map[info.ownerRef:lower()] or info.name end
            end
            toClient(player, "v_bank:accounts", list)
        end)
    end)
    return true
end

function requestLedger(player, id, beforeId, group)
    id = tonumber(id)
    if not isElement(player) or not id or not hasAccessRole(player, id, "view") then return false end
    queryLedger(id, beforeId, group, BANK.LEDGER_PAGE, function(rows, more)
        toClient(player, "v_bank:ledger", id, rows or {}, more == true, tonumber(beforeId) or false)
    end, nil, true)
    return true
end

local function cleanNote(note)
    note = tostring(note or ""):gsub("#%x%x%x%x%x%x", ""):gsub("[%c]", " "):gsub("%s+", " ")
    note = note:gsub("^ ", ""):gsub(" $", "")
    if utf8 and utf8.len(note) and utf8.len(note) > BANK.NOTE_MAX then
        note = utf8.sub(note, 1, BANK.NOTE_MAX)
    elseif #note > BANK.NOTE_MAX * 2 then
        note = note:sub(1, BANK.NOTE_MAX * 2)
    end
    return note
end

--- stage "preview" (data = recipient + amount, nothing booked) or "done" / "error" (data.error)
function requestTransfer(player, fromId, number, amount, note, confirm)
    fromId = tonumber(fromId)
    if not isElement(player) or not fromId then return false end
    local function fail(code) toClient(player, "v_bank:transfer", "error", { error = code }) end
    if not hasAccessRole(player, fromId, "use") then fail("no_access") return true end
    amount = BOOK.amountOf(amount)
    if not amount then fail("bad_amount") return true end
    note = cleanNote(note)
    findByNumber(number, function(to)
        if not isElement(player) then return end
        if not to then return fail("no_such_account") end
        if to.id == fromId then return fail("same_account") end
        if to.status ~= "active" then return fail("account_closed") end
        local from = getAcc(fromId)
        if not from then return fail("unavailable") end
        local data = { from = from.number, to = to.number, toName = to.name, toKind = to.kind, amount = amount, note = note }
        local function show()
            if not confirm then
                return toClient(player, "v_bank:transfer", "preview", data)
            end
            local ok, err = BOOK.move(fromId, to.id, amount, "transfer.account", { note = note }, BANK.accountOf(player) or "")
            if not ok then return fail(err) end
            toClient(player, "v_bank:transfer", "done", data)
        end
        if to.kind ~= "personal" then return show() end
        -- the recipient is shown by display name (never booked: the ledger keeps the account)
        displayNames({ to.ownerRef }, function(map)
            if not isElement(player) then return end
            data.toName = map[to.ownerRef:lower()] or data.toName
            show()
        end)
    end)
    return true
end

--------------------------------------------------------------------------------
-- admin panel / v_gov
--------------------------------------------------------------------------------

local A = {}

function A.search(args, done)
    local text = tostring(args.text or ""):gsub("[%%_]", "")
    local sql = "SELECT " .. ACC_COLS .. " FROM bank_accounts WHERE 1 = 1"
    local p = {}
    if text ~= "" then
        sql = sql .. " AND (number LIKE ? OR name LIKE ? OR owner_ref LIKE ?)"
        local like = "%" .. text .. "%"
        p[#p + 1], p[#p + 2], p[#p + 3] = like, like, like
    end
    if args.kind == "personal" or args.kind == "company" or args.kind == "state" then
        sql = sql .. " AND kind = ?"
        p[#p + 1] = args.kind
    end
    if args.negative then sql = sql .. " AND allow_negative = 1" end
    sql = sql .. " ORDER BY FIELD(kind, 'state', 'company', 'personal'), id LIMIT " .. math.max(1, math.min(200, tonumber(args.limit) or 50))
    DB.query(function(rows)
        if not rows then return done({ ok = false, error = "db" }) end
        local list = {}
        for i, r in ipairs(rows) do list[i] = infoOfRow(r) end
        done({ ok = true, accounts = list })
    end, sql, unpack(p))
end

function A.account(args, done)
    local id = tonumber(args.id)
    DB.query(function(rows)
        local r = rows and rows[1]
        if not r then return done({ ok = false, error = "unknown" }) end
        local info = infoOfRow(r)
        DB.query(function(acc)
            info.access = {}
            for i, x in ipairs(acc or {}) do
                info.access[i] = { account = tostring(x.account_name), role = tostring(x.role),
                    by = tostring(x.granted_by or ""), at = int(x.granted_at) }
            end
            done({ ok = true, account = info })
        end, "SELECT account_name, role, granted_by, granted_at FROM bank_account_access WHERE account_id = ? ORDER BY account_name", info.id)
    end, "SELECT " .. ACC_COLS .. " FROM bank_accounts WHERE id = ?", id or 0)
end

function A.ledger(args, done)
    queryLedger(args.id, args.before, args.group, args.limit or BANK.LEDGER_PAGE, function(rows, more)
        if not rows then return done({ ok = false, error = "db" }) end
        done({ ok = true, rows = rows, more = more == true })
    end, args.since)
end

--- sums by key since a timestamp: { [key] = { inSum, outSum, n } }
function A.stats(args, done)
    DB.query(function(rows)
        if not rows then return done({ ok = false, error = "db" }) end
        local out = {}
        for _, r in ipairs(rows) do
            out[tostring(r.tx_key)] = { inSum = int(r.in_sum), outSum = int(r.out_sum), n = int(r.n) }
        end
        done({ ok = true, stats = out })
    end, "SELECT tx_key, SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END) AS in_sum, "
        .. "SUM(CASE WHEN amount < 0 THEN -amount ELSE 0 END) AS out_sum, COUNT(*) AS n "
        .. "FROM bank_ledger WHERE account_id = ? AND ts >= ? GROUP BY tx_key", tonumber(args.id) or 0, tonumber(args.since) or 0)
end

function A.byNumber(args, done)
    findByNumber(args.number, function(info) done({ ok = info ~= false, account = info or nil, error = not info and "unknown" or nil }) end)
end

--- signed amount: + admin.credit, - admin.debit (works on offline accounts too)
function A.adjust(args, done, actor)
    local amount = math.floor(tonumber(args.amount) or 0)
    local note = cleanNote(args.note)
    if amount == 0 then return done({ ok = false, error = "bad_amount" }) end
    if note == "" then return done({ ok = false, error = "note_required" }) end
    local id = tonumber(args.id)
    local params = { note = note, admin = actor }
    local ok, err
    if amount > 0 then ok, err = BOOK.move(nil, id, amount, "admin.credit", params, actor)
    else ok, err = BOOK.move(id, nil, -amount, "admin.debit", params, actor) end
    done({ ok = ok == true, error = err })
end

function A.transfer(args, done, actor)
    local note = cleanNote(args.note)
    if note == "" then return done({ ok = false, error = "note_required" }) end
    local key = args.key == "gov.transfer" and "gov.transfer" or "admin.transfer"
    local ok, err = BOOK.move(tonumber(args.from), tonumber(args.to), args.amount, key, { note = note, admin = actor }, actor)
    done({ ok = ok == true, error = err })
end

function A.status(args, done)
    done({ ok = setAccountStatus(args.id, args.status) == true })
end

function A.overdraft(args, done)
    done({ ok = setAllowNegative(args.id, args.allow == true) == true })
end

function A.access(args, done, actor)
    local role = args.role
    if role == "" or role == "none" then role = nil end
    done({ ok = setAccess(args.id, args.account, role, actor) == true })
end

function A.rename(args, done)
    done({ ok = renameAccount(args.id, args.name) == true })
end

function A.close(args, done)
    local ok, err = closeAccount(args.id)
    done({ ok = ok == true, error = err })
end

function A.createState(args, done, actor)
    local code = tostring(args.code or ""):lower()
    if not code:match("^[a-z0-9_]+$") or #code < 3 or #code > 24 then return done({ ok = false, error = "bad_code" }) end
    if findAcc("state", code) then return done({ ok = false, error = "code_taken" }) end
    local name = tostring(args.name or "")
    if name == "" then return done({ ok = false, error = "bad_name" }) end
    createAccount("state", code, name, args.allowNegative == true, actor, function(a)
        if not a then return done({ ok = false, error = "db" }) end
        for _, m in ipairs(type(args.members) == "table" and args.members or {}) do
            if type(m) == "table" then setAccess(a.id, m.account, m.role, actor) end
        end
        done({ ok = true, account = getAccountInfo(a.id) })
    end)
end

function bankCall(requestId, action, args, actorAccount)
    local caller = sourceResource
    local root = caller and getResourceRootElement(caller)
    local event = caller and (getResourceName(caller) .. ":remoteResult")
    local fn = A[tostring(action)]
    if not fn or not BANK.started or not root then return false end
    args = type(args) == "table" and args or {}
    local function done(result)
        if isElement(root) then triggerEvent(event, root, requestId, result) end
    end
    local ok, err = pcall(fn, args, done, tostring(actorAccount or "admin"))
    if not ok then
        outputDebugString("[v_bank] bankCall " .. tostring(action) .. ": " .. tostring(err), 1)
        done({ ok = false, error = "failed" })
    end
    return true
end
