if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ============================================================
--  v_admin / server/pages/organizations.lua
--  Organizations page: the companies of biz_core. Everything goes through
--  biz_core:adminCall (answers later, REMOTE.call); edits are logged.
--
--  list      { query, status = active | sold | all }  -> { rows }
--  detail    { id }                                   -> { company, units, ledger }
--  catalog   {}                                       -> { list }  (properties an admin can give)
--  rename    { id, name }            edit
--  adjust    { id, amount, dirty, reason }            edit
--  transfer  { id, account }         edit (founder offline only)
--  forcesell { id }                  edit (online founder: normal sale; offline: closed without payout)
--  removeunit { id, unitId }         edit
--  giveunit  { id, propertyId }      edit
--  kick      { id, player }          edit (an associate)
-- ============================================================

local ERRORS = {
    not_found = "v_admin.org.err_not_found", bad_id = "v_admin.org.err_not_found",
    name_taken = "v_admin.org.err_name_taken", name_short = "v_admin.org.err_name", name_long = "v_admin.org.err_name",
    name_invalid = "v_admin.org.err_name", bad_amount = "v_admin.org.err_amount", reason_required = "v_admin.org.err_reason",
    not_enough_money = "v_admin.org.err_money", founder_online = "v_admin.org.err_founder_online",
    no_account = "v_admin.org.err_no_account", target_online = "v_admin.org.err_target_online",
    target_has_company = "v_admin.org.err_target_has_company", cannot_sell_hq = "v_admin.org.err_hq",
    unknown_property = "v_admin.org.err_property", already_owned = "v_admin.org.err_owned",
    founder_offline = "v_admin.org.err_founder_offline", not_member = "v_admin.org.err_not_member",
    activity_offline = "v_admin.org.err_activity",
}

local function call(actor, action, args, reply, logText)
    if not resourceRunning("biz_core") then
        return reply(false, L.msg("v_admin.page.resource_missing", { name = "biz_core" }))
    end
    REMOTE.call("biz_core", "adminCall", function(r)
        if type(r) ~= "table" then return reply(false, L.msg("v_admin.page.request_failed")) end
        if r.ok == false then return reply(false, L.msg(ERRORS[r.error] or "v_admin.page.failed_reason", { reason = tostring(r.error) })) end
        if logText then adminLog(actor, logText:sub(1, 250)) end
        reply(r, logText and L.msg("v_admin.page.saved") or nil)
    end, action, args, actorAccount(actor) or "admin")
end

PAGES.register("organizations", {
    perm = "organizations",
    perms = {
        rename = "organizationsEdit", adjust = "organizationsEdit", transfer = "organizationsEdit",
        forcesell = "organizationsEdit", removeunit = "organizationsEdit", giveunit = "organizationsEdit",
        kick = "organizationsEdit",
    },
    actions = {
        list = function(actor, args, reply)
            call(actor, "list", { query = argText(args.query), status = argText(args.status) }, reply)
        end,
        detail = function(actor, args, reply)
            call(actor, "detail", { id = tonumber(args.id) }, reply)
        end,
        catalog = function(actor, args, reply)
            if not resourceRunning("biz_core") then return reply({ list = {} }) end
            local list = {}
            for _, p in ipairs(exports.biz_core:getCatalog() or {}) do
                if p.kind ~= "office" then list[#list + 1] = { id = p.id, name = p.name, kind = p.kind, price = p.price } end
            end
            reply({ list = list })
        end,
        rename = function(actor, args, reply)
            local name = argText(args.name)
            call(actor, "rename", { id = tonumber(args.id), name = name }, reply,
                ("organizations: renamed #%s to %s"):format(tostring(args.id), name))
        end,
        adjust = function(actor, args, reply)
            local amount = math.floor(tonumber(args.amount) or 0)
            call(actor, "adjust", { id = tonumber(args.id), amount = amount, dirty = args.dirty and true or false, reason = argText(args.reason) }, reply,
                ("organizations: balance of #%s %+d%s (%s)"):format(tostring(args.id), amount, args.dirty and " dirty" or "", argText(args.reason)))
        end,
        transfer = function(actor, args, reply)
            local acc = argText(args.account)
            call(actor, "transfer", { id = tonumber(args.id), account = acc }, reply,
                ("organizations: founder of #%s -> %s"):format(tostring(args.id), acc))
        end,
        forcesell = function(actor, args, reply)
            call(actor, "forcesell", { id = tonumber(args.id) }, reply,
                ("organizations: force sold / closed #%s"):format(tostring(args.id)))
        end,
        removeunit = function(actor, args, reply)
            call(actor, "removeunit", { id = tonumber(args.id), unitId = tonumber(args.unitId) }, reply,
                ("organizations: removed unit %s of #%s"):format(tostring(args.unitId), tostring(args.id)))
        end,
        giveunit = function(actor, args, reply)
            local pid = argText(args.propertyId)
            call(actor, "giveunit", { id = tonumber(args.id), propertyId = pid }, reply,
                ("organizations: gave %s to #%s"):format(pid, tostring(args.id)))
        end,
        kick = function(actor, args, reply)
            local who = argText(args.player)
            call(actor, "kick", { id = tonumber(args.id), player = who }, reply,
                ("organizations: removed associate %s of #%s"):format(who, tostring(args.id)))
        end,
    },
})
