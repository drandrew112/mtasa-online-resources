-- eco_loan / server/exports.lua
-- Server exports (README.md). Synchronous getters read the open-loan cache; the history (closed
-- loans, payments) goes through loanCall, which answers later like v_bank's bankCall:
--   loanCall(requestId, action, args, actor) -> true | false
--   answer: triggerEvent("<caller resource>:remoteResult", <caller root>, requestId, result)

local int = DB.int

function isLoanReady()
    return DB.ready and LOANS.loaded and LOAN.bank() ~= nil
end

--- the settings of every kind (copies)
function getLoanConfig()
    local out = {}
    for name, k in pairs(LOAN.KINDS) do
        local c = {}
        for key, v in pairs(k) do c[key] = v end
        out[name] = c
    end
    return out
end

--- { principal, interest, total, rate, installments, installment, interval } | false, err
function quoteLoan(kind, amount, options)
    local q, err = CALC.quote(kind, amount, options)
    if not q then return false, err end
    return q
end

--- creates and pays out a loan -> true, quote | false, err
--- the loan id arrives with the event onLoanCreated(loanId, kind, borrowerRef, principal, tag)
--- (or onLoanFailed(kind, borrowerRef, err, tag)); options.tag is handed back in both
---   kind = "personal" | "company" | "state"
---   borrower = player element / account name (online) | company id | state account code
---   options = { rate, installments, interval, lender = bank account id, note, tag }
function createLoan(kind, borrower, amount, options, actor)
    local q, err = CALC.quote(kind, amount, options)
    if not q then return false, err end
    if not isLoanReady() then return false, "unavailable" end
    local b, berr = LOANS.resolveBorrower(kind, borrower)
    if not b then return false, berr end
    LOANS.create(kind, borrower, amount, options, actor)
    return true, q
end

function getLoan(id)
    return LOANS.public(OPEN[int(id)])
end

--- open loans, filter = { kind, borrower } (both optional)
function getLoans(filter)
    filter = type(filter) == "table" and filter or {}
    local ref = filter.borrower ~= nil and tostring(filter.borrower):lower() or nil
    local out = {}
    for _, l in pairs(OPEN) do
        if (not filter.kind or l.kind == filter.kind) and (not ref or l.borrower:lower() == ref) then
            out[#out + 1] = LOANS.public(l)
        end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

function getPlayerLoans(player)
    local name = isElement(player) and LOAN.accountOf(player) or (type(player) == "string" and player:lower())
    if not name then return {} end
    return getLoans({ kind = "personal", borrower = name })
end

function getCompanyLoans(companyId)
    return getLoans({ kind = "company", borrower = tostring(int(companyId)) })
end

function getStateLoans(code)
    return getLoans({ kind = "state", borrower = tostring(code or "") })
end

--- the remaining debt of a borrower (open loans)
function getDebt(kind, borrower)
    local ref = kind == "personal" and isElement(borrower) and LOAN.accountOf(borrower) or borrower
    local sum = 0
    for _, l in ipairs(LOANS.ofBorrower(kind, ref)) do sum = sum + l.remaining end
    return sum
end

--- extra repayment from the borrower's account -> true, paidAmount | false, err
function repayLoan(id, amount, actor)
    return LOANS.repay(id, amount, actor)
end

--- pays the whole remaining debt -> true, paidAmount | false, err
function payOffLoan(id, actor)
    return LOANS.repay(id, nil, actor)
end

--- cancels the remaining debt -> true | false, err
function forgiveLoan(id, actor)
    return LOANS.forgive(id, actor)
end

--------------------------------------------------------------------------------
-- loanCall (website / gov_* / admin)
--------------------------------------------------------------------------------

local A = {}

-- { kind, borrower, status ("open" | "closed" | a status | nil = all), beforeId, limit } -> { ok, loans }
function A.history(args, done)
    local where, params = {}, {}
    if LOAN.KINDS[args.kind] then where[#where + 1] = "kind = ?"; params[#params + 1] = args.kind end
    if args.borrower ~= nil then where[#where + 1] = "borrower_ref = ?"; params[#params + 1] = tostring(args.borrower):lower() end
    if args.status == "open" then where[#where + 1] = "status IN ('pending', 'active')"
    elseif args.status == "closed" then where[#where + 1] = "status IN ('paid', 'forgiven', 'failed')"
    elseif LOAN_STATUS[args.status] then where[#where + 1] = "status = ?"; params[#params + 1] = args.status end
    if int(args.beforeId) > 0 then where[#where + 1] = "id < ?"; params[#params + 1] = int(args.beforeId) end
    local limit = math.max(1, math.min(LOAN.HISTORY_MAX, int(args.limit) > 0 and int(args.limit) or LOAN.HISTORY_PAGE))
    local sql = "SELECT * FROM eco_loans" .. (#where > 0 and (" WHERE " .. table.concat(where, " AND ")) or "")
        .. " ORDER BY id DESC LIMIT " .. limit
    DB.query(function(rows)
        if rows == false then return done({ ok = false, error = "unavailable" }) end
        local list = {}
        for i, r in ipairs(rows) do list[i] = LOANS.public(LOANS.rowLoan(r)) end
        done({ ok = true, loans = list })
    end, sql, unpack(params))
end

-- { id } -> { ok, loan, payments }
function A.payments(args, done)
    local id = int(args.id)
    DB.query(function(rows)
        local r = rows and rows[1]
        if not r then return done({ ok = false, error = "no_loan" }) end
        local loan = LOANS.public(LOANS.rowLoan(r))
        DB.query(function(prows)
            local list = {}
            for i, p in ipairs(prows or {}) do
                list[i] = { id = int(p.id), ts = int(p.ts), kind = tostring(p.kind), amount = int(p.amount),
                    remaining = int(p.remaining_after), info = tostring(p.info), actor = tostring(p.actor) }
            end
            done({ ok = true, loan = loan, payments = list })
        end, "SELECT * FROM eco_loan_payments WHERE loan_id = ? ORDER BY id DESC LIMIT " .. LOAN.HISTORY_MAX, id)
    end, "SELECT * FROM eco_loans WHERE id = ? LIMIT 1", id)
end

-- { kind, borrower, amount, options } -> { ok, id } | { ok = false, error }
function A.create(args, done, actor)
    LOANS.create(args.kind, args.borrower, args.amount, args.options, actor, function(ok, v)
        if ok then done({ ok = true, id = v }) else done({ ok = false, error = v }) end
    end)
end

-- { id, amount (nil = all) } -> { ok, paid }
function A.repay(args, done, actor)
    local ok, v = LOANS.repay(args.id, args.amount, actor)
    done(ok and { ok = true, paid = v } or { ok = false, error = v })
end

-- { id } -> { ok }
function A.forgive(args, done, actor)
    local ok, err = LOANS.forgive(args.id, actor)
    done(ok and { ok = true } or { ok = false, error = err })
end

-- { kind, amount, options } -> { ok, quote }
function A.quote(args, done)
    local q, err = CALC.quote(args.kind, args.amount, args.options)
    done(q and { ok = true, quote = q } or { ok = false, error = err })
end

function loanCall(requestId, action, args, actor)
    local caller = sourceResource
    local root = caller and getResourceRootElement(caller)
    local event = caller and (getResourceName(caller) .. ":remoteResult")
    local fn = A[tostring(action)]
    if not fn or not DB.ready or not root then return false end
    args = type(args) == "table" and args or {}
    local function done(result)
        if isElement(root) then triggerEvent(event, root, requestId, result) end
    end
    local ok, err = pcall(fn, args, done, tostring(actor or "system"))
    if not ok then
        outputDebugString("[eco_loan] loanCall " .. tostring(action) .. ": " .. tostring(err), 1)
        done({ ok = false, error = "failed" })
    end
    return true
end
