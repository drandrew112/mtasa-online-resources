if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- biz_core / server/notify.lua
-- Every business event reaches the players as a ui_core notification (no
-- e-mail). Texts are v_locals messages, resolved in each receiver's language.
--
--   exports.biz_core:notifyPlayer(player, msg [, title])
--   exports.biz_core:notifyCompany(companyId, scope, msg [, title])
--       scope: "founder" | "associates" | "all"

NOTIFY = {}

function NOTIFY.player(player, msg, title)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    triggerClientEvent(player, "biz_core:notify", resourceRoot, title or L.msg("biz_core.notify.title"), msg)
    return true
end

function NOTIFY.company(c, scope, msg, title)
    if not c then return false end
    scope = scope or "all"
    if scope ~= "associates" and isElement(c.founder) then NOTIFY.player(c.founder, msg, title) end
    if scope ~= "founder" then
        for p in pairs(MEM.membersOf(c.id)) do NOTIFY.player(p, msg, title) end
    end
    return true
end

function notifyPlayer(player, msg, title)
    return NOTIFY.player(player, msg, title)
end

function notifyCompany(companyId, scope, msg, title)
    return NOTIFY.company(CO.byId[tonumber(companyId)], scope, msg, title)
end
