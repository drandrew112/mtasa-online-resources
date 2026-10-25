-- gov_health / server/panel.lua
-- The Healthcare page of /gov, the public part of gov_web and the registration with gov_core.
-- Rights (gov_perms): health.view, health.prices.edit (on / off, HP and injury prices: the state
-- only, never a city), health.<hospital>.billing (payer / receiver of one hospital).

local A = GOV.A

local function clamp(v, r) return math.max(r[1], math.min(r[2], v)) end

--- payer / receiver of every med_hospitals hospital (+ rows of hospitals no longer in hospitals.json)
local function hospitalList()
    local list, seen = {}, {}
    if isResourceRunning("med_hospitals") then
        for _, h in ipairs(exports.med_hospitals:getHospitals() or {}) do
            local pay = GOV.hospitalPayment(h.id)
            list[#list + 1] = { id = h.id, name = h.name, payer = pay.payer, receiver = pay.receiver, heal = h.heal }
            seen[h.id] = true
        end
    end
    for id in pairs(GOV.get("health.hospitals") or {}) do
        if not seen[id] then
            local pay = GOV.hospitalPayment(id)
            list[#list + 1] = { id = id, name = id, payer = pay.payer, receiver = pay.receiver, missing = true }
        end
    end
    return list
end

function A.health(p, args, reply)
    local hospitals = hospitalList()
    local ids, seen = {}, {}
    for _, h in ipairs(hospitals) do
        for _, spec in ipairs({ h.payer, h.receiver }) do
            local id = tonumber(spec:match("^company:(%d+)$"))
            if id and not seen[id] then seen[id] = true; ids[#ids + 1] = id end
        end
    end
    GOV.companyNames(ids, function(names)
        reply({ enabled = GOV.get("health.enabled") ~= false, hpPrice = tonumber(GOV.get("health.hp_price")) or 0,
            injuries = GOV.get("health.injuries") or {}, hospitals = hospitals, payers = GOV.payerOptions(), companies = names,
            hospitalsRunning = isResourceRunning("med_hospitals") })
    end)
end

--- { field = enabled | hp_price | injury | remove_injury | hospital, type, severity, value }
function A.setHealth(p, args, reply, actor)
    if args.field == "hospital" then
        if not GOV.has(p, "health." .. tostring(args.id or "") .. ".billing") then return reply(false, "no_right") end
    elseif not GOV.has(p, "health.prices.edit") then
        return reply(false, "no_right")
    end
    if args.field == "enabled" then
        GOV.set("health.enabled", args.value == true, actor)
    elseif args.field == "hp_price" then
        local v = tonumber(args.value)
        if not v then return reply(false, "bad_number") end
        GOV.set("health.hp_price", math.floor(clamp(v, GOV_RANGE.hpPrice)), actor)
    elseif args.field == "injury" then
        local t, sev, v = tostring(args.type or ""), tonumber(args.severity), tonumber(args.value)
        if not t:match("^[a-z_]+$") then return reply(false, "bad_key") end
        if not v or not sev or sev < 1 or sev > 3 then return reply(false, "bad_number") end
        local list = GOV.get("health.injuries") or {}
        local prices = list[t] or { 0, 0, 0 }
        prices[math.floor(sev)] = math.floor(clamp(v, GOV_RANGE.injuryPrice))
        list[t] = prices
        GOV.set("health.injuries", list, actor)
    elseif args.field == "hospital" then
        -- { id, side = payer | receiver | all, value = spec } (value nil = back to the default)
        local id, side, spec = tostring(args.id or ""), args.side, args.value
        if id == "" or #id > 48 then return reply(false, "bad_key") end
        if side == "all" then
            local list = GOV.get("health.hospitals") or {}
            list[id] = nil
            GOV.set("health.hospitals", list, actor)
            return reply(true)
        end
        if side ~= "payer" and side ~= "receiver" then return reply(false, "bad_field") end
        local function store(value)
            local list = GOV.get("health.hospitals") or {}
            local row = type(list[id]) == "table" and list[id] or {}
            row[side] = value
            list[id] = next(row) and row or nil
            GOV.set("health.hospitals", list, actor)
            reply(true)
        end
        if spec == nil then return store(nil) end
        GOV.checkSpec(spec, side == "payer", function(ok, err)
            if not ok then return reply(false, err) end
            store(ok)
        end)
        return
    elseif args.field == "remove_injury" then
        local t = tostring(args.type or "")
        if t == "default" then return reply(false, "key_protected") end
        local list = GOV.get("health.injuries") or {}
        list[t] = nil
        GOV.set("health.injuries", list, actor)
    else
        return reply(false, "bad_field")
    end
    reply(true)
end

--- gov_web: { enabled, hpPrice, injuries }
function getPublicHealth()
    return { enabled = GOV.get("health.enabled") ~= false, hpPrice = tonumber(GOV.get("health.hp_price")) or 0,
        injuries = GOV.get("health.injuries") or {} }
end

GOV.module({
    settings = { prefixes = { "health." }, defaults = GOV_DEFAULTS },
    perms = {
        { "health.view",        "services", 0 },
        { "health.prices.edit", "services", 1 },
    },
    -- targets: the hospitals of med_hospitals (publishHospitals)
    families = {
        { "health.*.billing", "services", 2 },
    },
    actions = { health = "health.view", setHealth = "panel" },
    pages = {
        { id = "health", category = "services", order = 10, script = "web/js/pages.js", need = "health.view" },
    },
})

--- the targets of health.*.billing: every hospital (+ the ones only in the setting)
local function publishHospitals()
    local list, seen = {}, {}
    if isResourceRunning("med_hospitals") then
        for _, h in ipairs(exports.med_hospitals:getHospitals() or {}) do
            local id = tostring(h.id)
            if id:match("^[%w_]+$") then list[#list + 1] = { id = id, name = tostring(h.name or id) }; seen[id] = true end
        end
    end
    for id in pairs(GOV.get("health.hospitals") or {}) do
        id = tostring(id)
        if not seen[id] and id:match("^[%w_]+$") then list[#list + 1] = { id = id, name = id } end
    end
    GOV.setTargets("health", list)
end
publishHospitals()
addEventHandler("onGovSettingsSynced", root, publishHospitals)
addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) == "med_hospitals" then setTimer(publishHospitals, 2000, 1) end
end)
