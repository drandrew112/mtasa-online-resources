if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ============================================================
--  v_admin / server/pages/bank.lua
--  Bank page: every v_bank account (personal, company, state). Everything goes
--  through v_bank:bankCall (answers later, REMOTE.call); edits are logged.
--
--  search    { text, kind, negative }          -> { accounts }
--  account   { id }                            -> { account (+ access) }
--  ledger    { id, before, group }             -> { rows, more }
--  adjust    { id, amount, note }              edit (signed amount: admin.credit / admin.debit)
--  transfer  { id, to (account number), amount, note }   edit (admin.transfer)
--  status    { id, status = active | frozen }  edit
--  overdraft { id, allow }                     edit (the overdraft list)
--  access    { id, account, role | "none" }    edit
-- ============================================================

local function call(actor, action, args, reply, logText)
    if not resourceRunning("v_bank") then
        return reply(false, L.msg("v_admin.page.resource_missing", { name = "v_bank" }))
    end
    REMOTE.call("v_bank", "bankCall", function(r)
        if type(r) ~= "table" then return reply(false, L.msg("v_admin.page.request_failed")) end
        if r.ok == false then
            return reply(false, L.msg("v_bank.error." .. tostring(r.error or "failed")))
        end
        if logText then adminLog(actor, logText:sub(1, 250)) end
        reply(r, logText and L.msg("v_admin.page.saved") or nil)
    end, action, args, actorAccount(actor) or "admin")
end

PAGES.register("bank", {
    perm = "bank",
    perms = { adjust = "bankEdit", transfer = "bankEdit", status = "bankEdit", overdraft = "bankEdit", access = "bankEdit" },
    actions = {
        search = function(actor, args, reply)
            call(actor, "search", { text = argText(args.text), kind = argText(args.kind), negative = args.negative == true, limit = 100 }, reply)
        end,
        account = function(actor, args, reply)
            call(actor, "account", { id = tonumber(args.id) }, reply)
        end,
        ledger = function(actor, args, reply)
            call(actor, "ledger", { id = tonumber(args.id), before = tonumber(args.before), group = argText(args.group), limit = 50 }, reply)
        end,
        adjust = function(actor, args, reply)
            local amount = math.floor(tonumber(args.amount) or 0)
            call(actor, "adjust", { id = tonumber(args.id), amount = amount, note = argText(args.note) }, reply,
                ("bank: account #%s %+d (%s)"):format(tostring(args.id), amount, argText(args.note)))
        end,
        transfer = function(actor, args, reply)
            local amount = math.floor(tonumber(args.amount) or 0)
            local to, note = argText(args.to), argText(args.note)
            call(actor, "byNumber", { number = to }, function(r)
                if not r or not r.account then return reply(false, L.msg("v_bank.error.no_such_account")) end
                call(actor, "transfer", { from = tonumber(args.id), to = r.account.id, amount = amount, note = note }, reply,
                    ("bank: transfer %d from #%s to %s (%s)"):format(amount, tostring(args.id), to, note))
            end)
        end,
        status = function(actor, args, reply)
            local status = args.status == "frozen" and "frozen" or "active"
            call(actor, "status", { id = tonumber(args.id), status = status }, reply,
                ("bank: account #%s %s"):format(tostring(args.id), status))
        end,
        overdraft = function(actor, args, reply)
            call(actor, "overdraft", { id = tonumber(args.id), allow = args.allow == true }, reply,
                ("bank: account #%s overdraft %s"):format(tostring(args.id), args.allow == true and "on" or "off"))
        end,
        access = function(actor, args, reply)
            local acc, role = argText(args.account), argText(args.role)
            call(actor, "access", { id = tonumber(args.id), account = acc, role = role }, reply,
                ("bank: access of %s on account #%s: %s"):format(acc, tostring(args.id), role))
        end,
    },
})
