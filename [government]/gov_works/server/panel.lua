-- gov_works / server/panel.lua
-- The Works page of /gov and the registration with gov_core.

local A = GOV.A

local function int(v) return DB.int(v) end

local function clamp(v, r) return math.max(r[1], math.min(r[2], v)) end

function A.works(p, args, reply)
    local list = GOV.workList()
    local ids, seen = {}, {}
    for _, w in ipairs(list) do
        local id = tonumber(w.payer:match("^company:(%d+)$"))
        if id and not seen[id] then seen[id] = true; ids[#ids + 1] = id end
    end
    GOV.companyNames(ids, function(names)
        reply({ works = list, payers = GOV.payerOptions(), taxKeys = GOV.get("tax.income_keys") or {}, companies = names })
    end)
end

--- { work, field = payer | multiplier | taxKey | param, key, value } (value nil = default)
function A.setWork(p, args, reply, actor)
    local workId = tostring(args.work or "")
    if not workId:match("^[%w_]+$") then return reply(false, "bad_work") end
    local field = args.field
    if field == "payer" then
        local spec = tostring(args.value or "system")
        if spec == "system" or spec:match("^state:[a-z0-9_]+$") then
            GOV.set("work." .. workId .. ".payer", spec, actor)
            return reply(true)
        end
        -- a private company (the picker sends its id)
        local id = tonumber(spec:match("^company:(%d+)$"))
        if not id then return reply(false, "bad_payer") end
        DB.query(function(rows)
            local r = rows and rows[1]
            if not r then return reply(false, "no_company") end
            GOV.set("work." .. workId .. ".payer", "company:" .. int(r.id), actor)
            reply(true)
        end, "SELECT id FROM biz_companies WHERE id = ? AND status = 'active' LIMIT 1", id)
        return
    elseif field == "multiplier" then
        local v = tonumber(args.value)
        if args.value ~= nil and not v then return reply(false, "bad_number") end
        GOV.set("work." .. workId .. ".multiplier", v and clamp(v, GOV_RANGE.multiplier) or nil, actor)
    elseif field == "taxKey" then
        local keys = GOV.get("tax.income_keys") or {}
        if args.value ~= nil and keys[args.value] == nil then return reply(false, "bad_key") end
        GOV.set("work." .. workId .. ".taxKey", args.value, actor)
    elseif field == "param" then
        local w = WAGES[workId]
        local prm = w and w.byKey[tostring(args.key)]
        if not prm then return reply(false, "bad_param") end
        local v = tonumber(args.value)
        if args.value ~= nil then
            if not v then return reply(false, "bad_number") end
            local limit = math.max(math.abs(prm.default) * GOV_RANGE.wageFactor, 1000000)
            if math.abs(v) > limit then return reply(false, "out_of_range") end
        end
        GOV.set("work." .. workId .. ".p." .. prm.key, v, actor)
    else
        return reply(false, "bad_field")
    end
    reply(true)
end

GOV.module({
    settings = { prefixes = { "work." }, defaults = {} },
    actions = { works = "viewer", setWork = "minister" },
    pages = {
        { id = "works", category = "employment", order = 10, script = "web/js/pages.js" },
    },
})
