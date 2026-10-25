-- gov_perms / server/bank.lua
-- The bank access of the state accounts (the State Treasury + every state company) IS the rights
-- (DESIGN.md 8): gov.<target>.bank.manage -> v_bank "owner", .pay -> "manager", .view -> "viewer",
-- none -> no access row. Synced after every change of rights / appointments (2 s later) and every
-- BANK_SYNC_MS; an access row no right explains is removed. Private company accounts are not
-- touched. Admins keep their own admin view (no access row).

local timer

--- the state accounts: { [bank account id] = target }
local function stateAccounts()
    local out = {}
    local tid = GOV.treasuryId()
    if tid then out[tid] = "treasury" end
    for _, c in ipairs(GOV.companyList()) do
        if c.accountId then out[c.accountId] = tostring(c.id) end
    end
    return out
end

--- the v_bank role an account should have on a target, or nil
local function roleOf(account, target)
    for _, r in ipairs(PERMS.BANK_ROLES) do
        if PERMS.has(account, "gov." .. target .. ".bank." .. r.perm) then return r.role end
    end
end

function PERMS.syncBank()
    local bank = GOV.bank()
    if not PERMS.ready or not bank or bank:isBankReady() ~= true then return end
    local accounts = stateAccounts()
    local ids = {}
    for id in pairs(accounts) do ids[#ids + 1] = id end
    if #ids == 0 then return end
    -- who should have what: every appointed account x every state account
    local want = {}   -- [bank id] = { [account] = role }
    local officials = {}
    for _, m in pairs(MEMBERS) do officials[m.account] = true end
    for id, target in pairs(accounts) do
        local w = {}
        for acc in pairs(officials) do w[acc] = roleOf(acc, target) end
        want[id] = w
    end
    local marks = {}
    for i = 1, #ids do marks[i] = "?" end
    DB.query(function(rows)
        if not rows then return end
        local have = {}
        for _, r in ipairs(rows) do
            local id = DB.int(r.account_id)
            have[id] = have[id] or {}
            have[id][tostring(r.account_name):lower()] = tostring(r.role)
        end
        for id in pairs(accounts) do
            local h, w = have[id] or {}, want[id] or {}
            for acc, role in pairs(w) do
                if h[acc] ~= role then bank:setAccess(id, acc, role, "gov_perms") end
            end
            for acc in pairs(h) do
                if not w[acc] then bank:setAccess(id, acc, nil, "gov_perms") end
            end
        end
    end, "SELECT account_id, account_name, role FROM bank_account_access WHERE account_id IN (" .. table.concat(marks, ",") .. ")", unpack(ids))
end

function PERMS.scheduleBankSync()
    if isTimer(timer) then killTimer(timer) end
    timer = setTimer(PERMS.syncBank, 2000, 1)
end
