if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ============================================================
--  v_admin / server/pages/mail.lua
--  Mail page (was the /mail panel of v_mail). Everything goes through the
--  v_mail mailAdmin* exports, which answer later (REMOTE.call):
--
--  recipients {}                           -> { names, configured }
--  send       { mode, names, texts }       -> mode = all | selected | test
--  history    { page }                     -> { groups, more, page }
--  group      { key }                      -> { key, mails }
--  mail       { id }                       -> { mail }
--  status     {}                           -> queue + weekly update state
--  updatetest { lang }                     the weekly update mail to the admin's own email
--
--  A finished circular (onMailCircularDone) is told to the admin if online.
-- ============================================================

local function remote(fn, reply, ...)
    REMOTE.call("v_mail", fn, function(r)
        if type(r) ~= "table" then return reply(false, L.msg("v_admin.page.resource_missing", { name = "v_mail" })) end
        if r.ok == false then return reply(false, r.message) end
        local msg = r.message
        r.message = nil
        reply(r, msg)
    end, ...)
end

PAGES.register("mail", {
    perm = "mail",
    actions = {
        recipients = function(actor, args, reply) remote("mailAdminRecipients", reply) end,

        send = function(actor, args, reply)
            local mode = args.mode
            if mode ~= "all" and mode ~= "selected" and mode ~= "test" then return reply(false) end
            local account = actorAccount(actor)
            remote("mailAdminSend", function(r, msg)
                if r and mode ~= "test" then
                    adminLog(actor, ("mail: sent a circular (%s, %s)"):format(mode,
                        mode == "selected" and (#(type(args.names) == "table" and args.names or {}) .. " recipients") or "all"))
                end
                reply(r, msg)
            end, account, mode, type(args.names) == "table" and args.names or nil, type(args.texts) == "table" and args.texts or {})
        end,

        history = function(actor, args, reply) remote("mailAdminHistory", reply, tonumber(args.page) or 0) end,
        group   = function(actor, args, reply) remote("mailAdminGroup", reply, tostring(args.key or "")) end,
        mail    = function(actor, args, reply) remote("mailAdminMail", reply, tonumber(args.id) or 0) end,
        status  = function(actor, args, reply) remote("mailAdminStatus", reply) end,

        updatetest = function(actor, args, reply)
            local account = actorAccount(actor)
            remote("mailAdminUpdateTest", function(r, msg)
                if r then adminLog(actor, "mail: sent a test weekly update to own e-mail") end
                reply(r, msg)
            end, account, type(args.lang) == "string" and args.lang or nil)
        end,
    },
})

-- a circular finished: tell the admin who sent it (in game; the web page sees it in the history)
addEvent("onMailCircularDone")
addEventHandler("onMailCircularDone", root, function(admin, sent, failed, isTest)
    if not resourceRunning("acc_auth") then return end
    for _, p in ipairs(getElementsByType("player")) do
        if tostring(exports.acc_auth:getName(p) or ""):lower() == tostring(admin):lower() then
            adminAlert(p, L.msg(isTest and "v_mail.server.test_done" or "v_mail.server.done", { sent = sent, failed = failed }),
                failed == 0 and 110 or 255, failed == 0 and 220 or 200, failed == 0 and 130 or 90)
        end
    end
end)
