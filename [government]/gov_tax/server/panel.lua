-- gov_tax / server/panel.lua
-- Fees, the Taxes + Fees pages of /gov, the public part of gov_web and the registration with
-- gov_core. Rights (gov_perms): tax.* per tax, fees.<fee>.edit / .target per fee, fines.<fine>.*
-- per fine (GOV.FINES, Justice); the Fees page shows the fees with fees.view, the fines with
-- fines.view.

local A = GOV.A

local function clamp(v, r) return math.max(r[1], math.min(r[2], v)) end

--------------------------------------------------------------------------------
-- fees
--------------------------------------------------------------------------------

function getFee(key)
    return tonumber(GOV.get("fee." .. tostring(key))) or 0
end

--- the account a fee (GOV.FEES) goes to, or nil = it disappears
function getFeeTarget(fee) return GOV.targetAccount("fee.targets", fee) end

--------------------------------------------------------------------------------
-- tax / fee targets
--------------------------------------------------------------------------------

--- where each key of a target setting goes: { {key, code (nil = disappears), missing = the set
--- account is gone}, ... }
local function targetsOf(setting, keys)
    local list = {}
    for i, key in ipairs(keys) do
        local code = GOV.targetCode(setting, key)
        list[i] = { key = key, code = code, missing = code ~= nil and GOV.targetAccount(setting, key) == nil }
    end
    return list
end

--- stores the target of one key: { key, code } (code "" / nil = the money disappears)
local function setTarget(setting, keys, args, reply, actor)
    local key = tostring(args.key or "")
    local known = false
    for _, x in ipairs(keys) do if x == key then known = true end end
    if not known then return reply(false, "bad_key") end
    local code = tostring(args.code or ""):lower()
    if code ~= "" then
        local bank = GOV.bank()
        if not bank then return reply(false, "v_bank.error.unavailable") end
        if code ~= "treasury" and not GOV.companyByCode(code) then return reply(false, "bad_company") end
        local id = bank:getStateAccount(code)
        local info = id and bank:getAccountInfo(id)
        if not info or info.status ~= "active" then return reply(false, "bad_company") end
    end
    local targets = GOV.get(setting) or {}
    targets[key] = code ~= "" and code or nil
    GOV.set(setting, targets, actor)
    reply(true)
end

--- the works of every income tax key (gov_works): { [key] = { work name, ... } }, or nil when
--- gov_works does not run
local function worksByTaxKey()
    if not isResourceRunning("gov_works") then return nil end
    local ok, used = pcall(function() return exports.gov_works:getWorkTaxKeys() end)
    return ok and type(used) == "table" and used or nil
end

--------------------------------------------------------------------------------
-- pages
--------------------------------------------------------------------------------

function A.taxes(p, args, reply)
    local vat = {}
    for i, g in ipairs(GOV_VAT_GROUPS) do vat[i] = { group = g, rate = getVatRate(g), default = GOV_DEFAULTS["tax.vat"][g] or 0 } end
    reply({ company = getCompanyTaxRate(), keys = GOV.get("tax.income_keys") or {}, used = worksByTaxKey() or {},
        runs = getTaxRuns(48, GOV.historySince()), vat = vat, property = getPropertyTaxRate(),
        propertyDefault = GOV_DEFAULTS["tax.property"], targets = targetsOf("tax.targets", GOV_TAXES),
        targetOptions = GOV.targetOptions() })
end

--- the right of a fee key: "fees.<id>.<what>" or, for a fine, "fines.<id>.<what>"
local function feePerm(key, what)
    return (GOV.FINES[key] and "fines." or "fees.") .. GOV.feeTarget(key) .. "." .. what
end

function A.fees(p, args, reply)
    local fees, fines = GOV.has(p, "fees.view"), GOV.has(p, "fines.view")
    if not fees and not fines then return reply(false, "no_right") end
    local list = {}
    for _, k in ipairs(GOV.FEES) do
        local fine = GOV.FINES[k] == true
        if (fine and fines) or (not fine and fees) then
            list[#list + 1] = { key = k, value = getFee(k), default = GOV_DEFAULTS["fee." .. k], fine = fine,
                perm = (fine and "fines." or "fees.") .. GOV.feeTarget(k) }
        end
    end
    reply({ fees = list, targets = targetsOf("fee.targets", GOV.FEES), targetOptions = GOV.targetOptions() })
end

--- { group, value (%) } (value nil = default)
function A.setVat(p, args, reply, actor)
    local g = tostring(args.group or "")
    local known = false
    for _, x in ipairs(GOV_VAT_GROUPS) do if x == g then known = true end end
    if not known then return reply(false, "bad_key") end
    local v = tonumber(args.value)
    if args.value ~= nil and not v then return reply(false, "bad_number") end
    local rates = GOV.get("tax.vat") or {}
    rates[g] = v and clamp(v / 100, GOV_RANGE.vat) or GOV_DEFAULTS["tax.vat"][g]
    GOV.set("tax.vat", rates, actor)
    reply(true)
end

function A.setPropertyTax(p, args, reply, actor)
    local v = tonumber(args.value)
    if args.value ~= nil and not v then return reply(false, "bad_number") end
    GOV.set("tax.property", v and clamp(v / 100, GOV_RANGE.propertyTax) or nil, actor)
    reply(true)
end

--- the state account a tax / fee goes to: { key, code } (code "" = the money disappears)
function A.setTaxTarget(p, args, reply, actor) setTarget("tax.targets", GOV_TAXES, args, reply, actor) end
function A.setFeeTarget(p, args, reply, actor)
    if not GOV.has(p, feePerm(tostring(args.key or ""), "target")) then return reply(false, "no_right") end
    setTarget("fee.targets", GOV.FEES, args, reply, actor)
end

function A.setCompanyTax(p, args, reply, actor)
    local v = tonumber(args.value)
    if not v then return reply(false, "bad_number") end
    GOV.set("tax.company", clamp(v / 100, GOV_RANGE.tax), actor)
    reply(true)
end

--- add / change an income tax rate key: { key, value (%) }
function A.setTaxKey(p, args, reply, actor)
    local key = tostring(args.key or ""):lower()
    local v = tonumber(args.value)
    if not key:match("^[a-z0-9_]+$") or #key > 24 then return reply(false, "bad_key") end
    if not v then return reply(false, "bad_number") end
    local keys = GOV.get("tax.income_keys") or {}
    keys[key] = clamp(v / 100, GOV_RANGE.tax)
    GOV.set("tax.income_keys", keys, actor)
    reply(true)
end

--- a key a work uses cannot be deleted; without gov_works this cannot be checked, so it is refused
function A.deleteTaxKey(p, args, reply, actor)
    local key = tostring(args.key or "")
    if key == "standard" then return reply(false, "key_protected") end
    local used = worksByTaxKey()
    if not used then return reply(false, "works_offline") end
    if used[key] and #used[key] > 0 then return reply(false, "key_in_use") end
    local keys = GOV.get("tax.income_keys") or {}
    keys[key] = nil
    GOV.set("tax.income_keys", keys, actor)
    reply(true)
end

function A.setFee(p, args, reply, actor)
    local key = tostring(args.key or "")
    if not GOV.has(p, feePerm(key, "edit")) then return reply(false, "no_right") end
    local known = false
    for _, k in ipairs(GOV.FEES) do if k == key then known = true end end
    if not known then return reply(false, "bad_key") end
    local v = tonumber(args.value)
    if args.value ~= nil and not v then return reply(false, "bad_number") end
    GOV.set("fee." .. key, v and math.floor(clamp(v, GOV_RANGE.fee)) or nil, actor)
    reply(true)
end

--------------------------------------------------------------------------------
-- gov_web
--------------------------------------------------------------------------------

--- { fees = { {key, value}, ... }, taxes = { company, income, vat = { {group, rate}, ... }, property, runs = { count, total } } }
function getPublicTaxes()
    local fees = {}
    for i, k in ipairs(GOV.FEES) do fees[i] = { key = k, value = getFee(k) } end
    local vat = {}
    for i, g in ipairs(GOV_VAT_GROUPS) do vat[i] = { group = g, rate = getVatRate(g) } end
    return { fees = fees, taxes = { company = getCompanyTaxRate(), income = GOV.get("tax.income_keys") or {}, vat = vat,
        property = getPropertyTaxRate(), runs = RUNS_30D } }
end

--------------------------------------------------------------------------------
-- registration
--------------------------------------------------------------------------------

GOV.module({
    settings = { prefixes = { "tax.", "fee." }, defaults = GOV_DEFAULTS },
    perms = {
        { "tax.view",          "revenue", 0 },
        { "tax.company.edit",  "revenue", 1 },
        { "tax.income.edit",   "revenue", 1 },
        { "tax.vat.edit",      "revenue", 1 },
        { "tax.property.edit", "revenue", 1 },
        { "tax.targets.edit",  "revenue", 2 },
        { "fees.view",         "revenue", 0 },
        { "fines.view",        "revenue", 0 },
    },
    -- targets: the fees / the fines of GOV.FEES (setTargets below)
    families = {
        { "fees.*.edit",    "revenue", 1 },
        { "fees.*.target",  "revenue", 2 },
        { "fines.*.edit",   "revenue", 1 },
        { "fines.*.target", "revenue", 2 },
    },
    actions = {
        taxes = "tax.view", fees = "panel",
        setCompanyTax = "tax.company.edit", setTaxKey = "tax.income.edit", deleteTaxKey = "tax.income.edit", setVat = "tax.vat.edit",
        setPropertyTax = "tax.property.edit", setTaxTarget = "tax.targets.edit", setFee = "panel", setFeeTarget = "panel",
    },
    pages = {
        { id = "taxes", category = "revenue", order = 10, script = "web/js/pages.js", need = "tax.view" },
        { id = "fees",  category = "revenue", order = 20, script = "web/js/pages.js", need = { "fees.view", "fines.view" } },
    },
})

-- the targets of the fees.* / fines.* rights
do
    local fees, fines = {}, {}
    for _, k in ipairs(GOV.FEES) do
        local name = L.has("gov_tax.fee." .. k) and L.text("gov_tax.fee." .. k) or k
        local list = GOV.FINES[k] and fines or fees
        list[#list + 1] = { id = GOV.feeTarget(k), name = name }
    end
    GOV.setTargets("fees", fees)
    GOV.setTargets("fines", fines)
end
