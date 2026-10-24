-- v_gov / server/works.lua
-- Everything about a work's pay (DESIGN.md 5): payer, pay + XP parameters, multiplier, income tax
-- rate key. Settings: work.<id>.payer | work.<id>.multiplier | work.<id>.taxKey | work.<id>.p.<param>
--
-- A work resource registers its parameters (current config values = defaults) with
--   exports.v_gov:registerWage(workId, { { key = "base", label = "Base pay", default = 600 }, ... })
-- on its start and on v_gov's start, and reads a value with exports.v_gov:getWage(workId, key)
-- (nil = no override, use the default). Without v_gov it simply pays its defaults.

WAGES = {}   -- [workId] = { params = { {key, label, default, kind}, ... }, byKey = {} }

local function workKey(workId, field) return ("work.%s.%s"):format(workId, field) end

function registerWage(workId, params)
    if type(workId) ~= "string" or workId == "" or type(params) ~= "table" then return false end
    local w = { params = {}, byKey = {} }
    for _, p in ipairs(params) do
        if type(p) == "table" and type(p.key) == "string" and tonumber(p.default) then
            local e = { key = p.key, label = tostring(p.label or p.key), default = tonumber(p.default),
                        kind = p.kind == "xp" and "xp" or "pay" }
            w.params[#w.params + 1] = e
            w.byKey[p.key] = e
        end
    end
    WAGES[workId] = w
    return true
end

--- the /gov override of a pay / XP parameter, or nil (= use the default)
function getWage(workId, key)
    local v = SETTINGS[workKey(workId, "p." .. tostring(key))]
    return tonumber(v)
end

--- the stored payer spec: "system" | "state:<code>" | "company:<id>"
function GOV.payerSpec(workId)
    local v = SETTINGS[workKey(workId, "payer")]
    if type(v) == "string" then return v end
    local d = GOV_WORK_DEFAULTS[workId]
    return d and d.payer or "system"
end

--- v_bank account id of a payer / receiver spec ("system" | "state:<code>" | "company:<id>"):
--- the id, "system", or false (the account does not exist / is closed)
function GOV.specAccount(spec)
    local bank = GOV.bank()
    if spec == "system" or not bank then return "system" end
    local kind, ref = tostring(spec):match("^(%a+):(.+)$")
    local id
    if kind == "state" then id = bank:getStateAccount(ref)
    elseif kind == "company" then id = bank:getCompanyAccount(ref) end
    local info = id and bank:getAccountInfo(id)
    if not info or info.status == "closed" then return false end
    return id
end

--- v_bank account id of the payer, or "system"
function getWorkPayer(workId)
    local spec = GOV.payerSpec(workId)
    local id = GOV.specAccount(spec)
    if not id then
        outputDebugString(("[v_gov] payer %s of work %s does not exist, paid from system"):format(spec, tostring(workId)), 2)
        return "system"
    end
    return id
end

function getWorkMultiplier(workId)
    local v = tonumber(SETTINGS[workKey(workId, "multiplier")])
    return v or 1
end

--- rate, key of the work's income tax rate key
function getIncomeTaxRate(workId)
    local key = SETTINGS[workKey(workId, "taxKey")]
    if type(key) ~= "string" then
        local d = GOV_WORK_DEFAULTS[workId]
        key = d and d.taxKey or "standard"
    end
    local keys = GOV.get("tax.income_keys") or {}
    local rate = tonumber(keys[key])
    if not rate then key, rate = "standard", tonumber(keys.standard) or 0 end
    return rate, key
end

function getCompanyTaxRate()
    return tonumber(GOV.get("tax.company")) or 0
end

--- where the money of a tax / fee goes: setting "tax.targets" / "fee.targets" = { key -> state
--- account code }; the stored code, or nil = the money disappears
function GOV.targetCode(setting, key)
    local code = (GOV.get(setting) or {})[tostring(key)]
    return type(code) == "string" and code ~= "" and code or nil
end

--- v_bank account id of a target, or nil (none set, or the account is gone / not active)
function GOV.targetAccount(setting, key)
    local code = GOV.targetCode(setting, key)
    local bank = GOV.bank()
    if not code or not bank then return nil end
    local id = bank:getStateAccount(code)
    local info = id and bank:getAccountInfo(id)
    if not info or info.status ~= "active" then return nil end
    return id
end

--- the account a tax (GOV_TAXES) goes to, or nil = it disappears
function getTaxTarget(tax) return GOV.targetAccount("tax.targets", tax) end

--- the account a fee (GOV.FEES) goes to, or nil = it disappears
function getFeeTarget(fee) return GOV.targetAccount("fee.targets", fee) end

function getFee(key)
    return tonumber(GOV.get("fee." .. tostring(key))) or 0
end

function getSetting(key)
    return GOV.get(key)
end

--- a private company that is sold / closed while it pays a work: back to system (checked with
--- every settings re-read)
function GOV.checkPayers()
    local bank = GOV.bank()
    if not bank or not bank:isBankReady() then return end
    local function closed(spec)
        if type(spec) ~= "string" or not spec:match("^company:") then return false end
        local id = bank:getCompanyAccount(spec:match("^company:(.+)$"))
        local info = id and bank:getAccountInfo(id)
        return info and info.status == "closed"
    end
    for key, v in pairs(SETTINGS) do
        local workId = key:match("^work%.([^%.]+)%.payer$")
        if workId and closed(v) then GOV.set(key, "system", "system") end
    end
    -- healthcare: a closed company payer / receiver goes back to the default
    local hospitals, changed = GOV.get("health.hospitals") or {}, false
    for _, row in pairs(hospitals) do
        if type(row) == "table" then
            if closed(row.payer) then row.payer, changed = nil, true end
            if closed(row.receiver) then row.receiver, changed = nil, true end
        end
    end
    if changed then GOV.set("health.hospitals", hospitals, "system") end
end
