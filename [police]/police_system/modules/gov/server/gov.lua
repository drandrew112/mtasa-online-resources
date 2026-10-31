-- police_system / modules/gov/server/gov.lua
-- The /gov module of the police: page "Police · Fines" in Public services. Every penal code amount can be edited and
-- reset to its default (the btk.json value stays); the fine income goes to the chosen state account (default the
-- treasury). Rights (gov_perms): police.fines.view, police.fines.edit, police.fines.target. The pay of the officers is
-- on gov_works' Works page (registerWage in units/server/pay.lua).
-- gov_core is optional: without it the defaults apply and this module stays off.

local G = POL.module("gov", { ok = false })

local ok = pcall(function() loadstring(exports.gov_core:importLib())() end)
G.ok = ok and GOV ~= nil
if not G.ok then
    outputDebugString("[police_system] gov_core not running: the /gov page of the police is off (defaults apply)", 3)
    return
end

local A = GOV.A
local MAX_FACTOR = 10

local function overrides()
    local v = GOV.get("police.btk")
    return type(v) == "table" and v or {}
end

function A.policeFines(p, args, reply)
    local list = POL.btk.list()
    for _, c in ipairs(list) do
        c.name = L.forPlayer(p, btkCategoryKey(c.id))
        for _, it in ipairs(c.items) do it.name = L.forPlayer(p, btkKey(it.id)) end
    end
    reply({ categories = list, target = GOV.get("police.fine_target") or "treasury", targets = GOV.targetOptions(),
            canEdit = GOV.has(p, "police.fines.edit"), canTarget = GOV.has(p, "police.fines.target") })
end

function A.setPoliceFine(p, args, reply, actor)
    local e = POL.btk.get(tostring(args.id or ""))
    if not e or e.warning then return reply(false, "bad_item") end
    local amount = math.floor(tonumber(args.amount) or -1)
    if amount < 0 or amount > math.max(1, e.default) * MAX_FACTOR then return reply(false, "bad_amount") end
    local o = overrides()
    o[e.id] = amount
    GOV.set("police.btk", o, actor)
    GOV.log(actor, "police.fine", { item = e.id, amount = amount, default = e.default })
    reply(true)
end

function A.resetPoliceFine(p, args, reply, actor)
    local e = POL.btk.get(tostring(args.id or ""))
    if not e then return reply(false, "bad_item") end
    local o = overrides()
    o[e.id] = nil
    GOV.set("police.btk", o, actor)
    GOV.log(actor, "police.fine_reset", { item = e.id })
    reply(true)
end

function A.setPoliceFineTarget(p, args, reply, actor)
    local code = tostring(args.code or "")
    if code ~= "treasury" and not GOV.companyByCode(code) then return reply(false, "bad_company") end
    GOV.set("police.fine_target", code, actor)
    GOV.log(actor, "police.fine_target", { code = code })
    reply(true)
end

GOV.module({
    settings = { prefixes = { "police." }, defaults = { ["police.btk"] = {}, ["police.fine_target"] = "treasury" } },
    perms = {
        { "police.fines.view", "services", 0 },
        { "police.fines.edit", "services", 2 },
        { "police.fines.target", "services", 3 },
    },
    actions = { policeFines = "police.fines.view", setPoliceFine = "police.fines.edit",
                resetPoliceFine = "police.fines.edit", setPoliceFineTarget = "police.fines.target" },
    pages = { { id = "police_fines", category = "services", order = 40, script = "modules/gov/web/js/police.js", need = "police.fines.view" } },
})

-- texts of the page (police.js), listed for the v_locals build
POLICE_GOV_KEYS = {
    "police_system.page.police_fines", "police_system.ui.hint", "police_system.ui.item", "police_system.ui.default",
    "police_system.ui.current", "police_system.ui.reset", "police_system.ui.save", "police_system.ui.target",
    "police_system.ui.target_hint", "police_system.ui.changed", "police_system.ui.warnings_free",
    "police_system.err.bad_item", "police_system.err.bad_amount", "police_system.menu.police",
}
