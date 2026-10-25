-- gov_transport / server/panel.lua
-- The Public transport page of /gov and the registration with gov_core. Rights (gov_perms):
-- transport.view, transport.fares.edit (fare per km, minimum, IC supplement),
-- transport.costs.edit (running costs, their payer / receiver, the receiver of the fares).

local FARE_FIELDS = { fare_km = true, fare_min = true, ic_supplement = true }

local A = GOV.A

local function clamp(v, r) return math.max(r[1], math.min(r[2], v)) end

--- every mode with its settings + defaults
function A.transport(p, args, reply)
    local modes, ids, seen = {}, {}, {}
    for i, mode in ipairs(GOV_PT_MODES) do
        local s = GOV.ptSettings(mode)
        modes[i] = { mode = mode, settings = s, defaults = GOV_DEFAULTS["pt." .. mode] }
        for _, f in ipairs(GOV_PT_SPECS) do
            local id = tonumber(tostring(s[f]):match("^company:(%d+)$"))
            if id and not seen[id] then seen[id] = true; ids[#ids + 1] = id end
        end
    end
    GOV.companyNames(ids, function(names)
        reply({ modes = modes, payers = GOV.payerOptions(), companies = names })
    end)
end

--- { mode, field, value }: a number field (value nil = default) or a payer / receiver spec
--- ("system" | "state:<code>" | "company:<id>", nil = default)
function A.setTransport(p, args, reply, actor)
    local mode, field = tostring(args.mode or ""), tostring(args.field or "")
    if not GOV_DEFAULTS["pt." .. mode] then return reply(false, "bad_key") end
    if not GOV.has(p, FARE_FIELDS[field] and "transport.fares.edit" or "transport.costs.edit") then return reply(false, "no_right") end
    local function store(value)
        local cur = GOV.get("pt." .. mode)
        cur = type(cur) == "table" and cur or {}
        cur[field] = value
        GOV.set("pt." .. mode, next(cur) and cur or nil, actor)
        reply(true)
    end
    local isNumber, isSpec = false, false
    for _, f in ipairs(GOV_PT_NUMBERS) do if f == field then isNumber = true end end
    for _, f in ipairs(GOV_PT_SPECS) do if f == field then isSpec = true end end
    if isNumber then
        if args.value == nil then return store(nil) end
        local v = tonumber(args.value)
        if not v then return reply(false, "bad_number") end
        return store(math.floor(clamp(v, GOV_RANGE.ptMoney)))
    end
    if not isSpec then return reply(false, "bad_field") end
    if args.value == nil then return store(nil) end
    GOV.checkSpec(args.value, false, function(spec, err)
        if not spec then return reply(false, err) end
        store(spec)
    end)
end

GOV.module({
    settings = { prefixes = { "pt." }, defaults = GOV_DEFAULTS },
    perms = {
        { "transport.view",       "services", 0 },
        { "transport.fares.edit", "services", 1 },
        { "transport.costs.edit", "services", 2 },
    },
    actions = { transport = "transport.view", setTransport = "panel" },
    pages = {
        { id = "transport", category = "services", order = 20, script = "web/js/pages.js", need = "transport.view" },
    },
})
