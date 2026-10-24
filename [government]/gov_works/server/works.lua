-- gov_works / server/works.lua
-- Everything about a work's pay: payer, pay + XP parameters, multiplier, income tax rate key.
-- Settings (gov_core): work.<id>.payer | work.<id>.multiplier | work.<id>.taxKey | work.<id>.p.<param>
--
-- A work resource registers its parameters (current config values = defaults) with
--   exports.gov_works:registerWage(workId, { { key = "base", label = "Base pay", default = 600 }, ... })
-- on its start and on gov_works' start, and reads a value with exports.gov_works:getWage(workId, key)
-- (nil = no override, use the default). Without gov_works it simply pays its defaults.

loadstring(exports.gov_core:importLib())()

-- per-work defaults (the Works page): anything not listed = system payer, "standard" tax key,
-- multiplier 1
GOV_WORK_DEFAULTS = {
    ems            = { payer = "state:treasury", taxKey = "exempt" },
    bloodtransport = { payer = "state:treasury", taxKey = "exempt" },
}

GOV_RANGE = {
    multiplier = { 0, 5 },
    wageFactor = 10,          -- a wage parameter may be at most this many times its default (abs)
}

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
    return tonumber(GOV.get(workKey(workId, "p." .. tostring(key))))
end

--- the stored payer spec: "system" | "state:<code>" | "company:<id>"
function GOV.payerSpec(workId)
    local v = GOV.get(workKey(workId, "payer"))
    if type(v) == "string" then return v end
    local d = GOV_WORK_DEFAULTS[workId]
    return d and d.payer or "system"
end

--- v_bank account id of the payer, or "system"
function getWorkPayer(workId)
    local spec = GOV.payerSpec(workId)
    local id = GOV.specAccount(spec)
    if not id then
        outputDebugString(("[gov_works] payer %s of work %s does not exist, paid from system"):format(spec, tostring(workId)), 2)
        return "system"
    end
    return id
end

function getWorkMultiplier(workId)
    local v = tonumber(GOV.get(workKey(workId, "multiplier")))
    return v or 1
end

--- rate, key of the work's income tax rate key; nil when the keys are not available (gov_tax /
--- gov_core not running: work_core then uses its own fallback)
function getIncomeTaxRate(workId)
    local key = GOV.get(workKey(workId, "taxKey"))
    if type(key) ~= "string" then
        local d = GOV_WORK_DEFAULTS[workId]
        key = d and d.taxKey or "standard"
    end
    local keys = GOV.get("tax.income_keys")
    if type(keys) ~= "table" or next(keys) == nil then return nil end
    local rate = tonumber(keys[key])
    if not rate then key, rate = "standard", tonumber(keys.standard) or 0 end
    return rate, key
end

--- works of work_core + the registered pay parameters + their settings
function GOV.workList()
    local names = {}
    if isResourceRunning("work_core") then
        for id, w in pairs(exports.work_core:getWorks() or {}) do names[id] = tostring(w.name or id) end
    end
    for id in pairs(WAGES) do names[id] = names[id] or id end
    local list = {}
    for id, name in pairs(names) do
        local w = WAGES[id]
        local params = {}
        for _, prm in ipairs(w and w.params or {}) do
            params[#params + 1] = { key = prm.key, label = prm.label, default = prm.default, kind = prm.kind,
                value = getWage(id, prm.key) }
        end
        local rate, key = getIncomeTaxRate(id)
        if not key then
            key = GOV.get(workKey(id, "taxKey"))
            if type(key) ~= "string" then key = GOV_WORK_DEFAULTS[id] and GOV_WORK_DEFAULTS[id].taxKey or "standard" end
        end
        list[#list + 1] = { id = id, name = name, payer = GOV.payerSpec(id), multiplier = getWorkMultiplier(id),
            taxKey = key, taxRate = rate or 0, params = params }
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

--------------------------------------------------------------------------------
-- answers for the other gov_* resources
--------------------------------------------------------------------------------

function getWorkList() return GOV.workList() end

--- { [income tax key] = { work name, ... } } (gov_tax: "used by", deleting a key)
function getWorkTaxKeys()
    local used = {}
    for _, w in ipairs(GOV.workList()) do
        used[w.taxKey] = used[w.taxKey] or {}
        table.insert(used[w.taxKey], w.name)
    end
    return used
end

--- { [state company code] = { work name, ... } } (gov_core: the Companies page, closing a company)
function getStatePayerWorks()
    local payers = {}
    for _, w in ipairs(GOV.workList()) do
        if w.payer:match("^state:") then
            local code = w.payer:sub(7)
            payers[code] = payers[code] or {}
            table.insert(payers[code], w.name)
        end
    end
    return payers
end

--- gov_web: { {name, payer (display name), payerCode (state code or nil), multiplier, taxKey, taxRate}, ... }
function getPublicWorks()
    local bank = GOV.bank()
    local tid = GOV.treasuryId()
    local tinfo = bank and tid and bank:getAccountInfo(tid)
    local works = {}
    for _, w in ipairs(GOV.workList()) do
        local payer = w.payer == "system" and "System" or w.payer
        local code = w.payer:match("^state:(.+)$")
        if code == "treasury" then payer = tinfo and tinfo.name or "State Treasury"
        elseif code then
            local c = GOV.companyByCode(code)
            payer = c and c.name or code
        elseif w.payer:match("^company:") then payer = "Private company" end
        works[#works + 1] = { name = w.name, payer = payer, payerCode = code, multiplier = w.multiplier, taxKey = w.taxKey, taxRate = w.taxRate }
    end
    return works
end

--------------------------------------------------------------------------------
-- a private company that is sold / closed while it pays a work: back to system (checked after
-- every settings re-read of gov_core)
--------------------------------------------------------------------------------

addEventHandler("onGovSettingsSynced", root, function()
    local bank = GOV.bank()
    local core = GOV.core()
    if not bank or not core or not bank:isBankReady() then return end
    for key, v in pairs(core:getStoredSettings("work.") or {}) do
        if key:match("^work%.([^%.]+)%.payer$") and type(v) == "string" and v:match("^company:") then
            local id = bank:getCompanyAccount(v:match("^company:(.+)$"))
            local info = id and bank:getAccountInfo(id)
            if info and info.status == "closed" then GOV.set(key, "system", "system") end
        end
    end
end)
