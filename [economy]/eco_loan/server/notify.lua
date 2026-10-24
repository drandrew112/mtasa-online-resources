if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- eco_loan / server/notify.lua
-- ui_core notifications to the borrower: the player (personal) or the founder (company), when
-- online. State loans notify nobody (gov_* shows them later). Texts are v_locals messages,
-- resolved in the receiver's language on the client.

NOTIFY = {}

function NOTIFY.player(player, key, params)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    triggerClientEvent(player, "eco_loan:notify", resourceRoot, L.msg("eco_loan.notify.title"), L.msg(key, params))
    return true
end

function NOTIFY.borrower(l, key, params)
    if l.kind == "personal" then
        return NOTIFY.player(LOAN.playerOf(l.borrower), key, params)
    elseif l.kind == "company" then
        local biz = LOAN.biz()
        local founder = biz and biz:getCompanyFounder(tonumber(l.borrower))
        return founder and NOTIFY.player(founder, key, params) or false
    end
    return false
end
