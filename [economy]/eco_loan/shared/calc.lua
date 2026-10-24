-- eco_loan / shared/calc.lua
-- Pure loan arithmetic (no MTA calls, unit tested). Simple flat interest:
--   total = principal + principal * rate / 100, split into n equal installments (rounded up);
--   the last installment is whatever is left.

CALC = {}

local function int(v) return math.floor(tonumber(v) or 0) end

--- the settings of a kind with the options filled in -> rate, installments, interval | nil, err
function CALC.terms(kind, options)
    local k = LOAN.KINDS[kind]
    if not k then return nil, "bad_kind" end
    options = type(options) == "table" and options or {}
    local rate = tonumber(options.rate) or k.rate
    local n = int(options.installments ~= nil and options.installments or k.installments)
    local interval = int(options.interval ~= nil and options.interval or k.interval)
    if rate < 0 or rate > k.maxRate then return nil, "bad_rate" end
    if n < 1 or n > k.maxInstallments then return nil, "bad_installments" end
    if interval < 60 then return nil, "bad_interval" end
    return rate, n, interval
end

--- { principal, interest, total, installment, installments, interval, rate } | nil, err
function CALC.quote(kind, amount, options)
    local k = LOAN.KINDS[kind]
    if not k then return nil, "bad_kind" end
    amount = int(amount)
    if amount < k.minAmount or amount > k.maxAmount then return nil, "bad_amount" end
    local rate, n, interval = CALC.terms(kind, options)
    if not rate then return nil, n end
    local interest = math.floor(amount * rate / 100 + 0.5)
    local total = amount + interest
    return {
        principal = amount, interest = interest, total = total, rate = rate,
        installments = n, installment = math.ceil(total / n), interval = interval,
    }
end

--- the amount of the next installment
function CALC.due(installment, remaining)
    return math.max(0, math.min(int(installment), int(remaining)))
end

--- the penalty of a missed installment
function CALC.penalty(kind, installment)
    local k = LOAN.KINDS[kind]
    if not k or k.penaltyRate <= 0 then return 0 end
    return math.ceil(int(installment) * k.penaltyRate / 100)
end

--- is this installment taken by force (the payer may go into debt)?
function CALC.forced(kind, missedStreak)
    local k = LOAN.KINDS[kind]
    if not k then return false end
    return k.forceAfterMissed == 0 or int(missedStreak) >= k.forceAfterMissed
end
