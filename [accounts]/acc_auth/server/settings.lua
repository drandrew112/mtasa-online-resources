if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Password change of the logged-in account (social panel > Account).
-- The current password is always required. The answer goes to the client as
-- acc_auth:onClientSettings (kind, ok, text).

local busy = {}      -- [player] = true while a change is in flight
local seq, byId = 0, {}

local function reply(player, ok, key, params)
    if isElement(player) then
        triggerClientEvent(player, "acc_auth:onClientSettings", player, "password", ok, L.msg(key, params))
    end
end

addEvent("acc_auth:changePassword", true)
addEventHandler("acc_auth:changePassword", root, function(currentPassword, newPassword)
    local player = client
    local name = nameOf(player)
    if not name or busy[player] then return end
    if type(currentPassword) ~= "string" or type(newPassword) ~= "string"
        or #currentPassword > 128 or #newPassword > 128 then return end

    local wait = lockRemaining(player)
    if wait > 0 then return reply(player, false, "acc_auth.server.too_many_login_attempts", { seconds = wait }) end
    if currentPassword == "" then return reply(player, false, "acc_auth.server.wrong_password") end
    if #newPassword < AUTH.PASSWORD_MIN then return reply(player, false, "acc_auth.server.password_too_short") end

    seq = seq + 1
    byId[seq] = { player = player, current = currentPassword, new = newPassword }
    busy[player] = true
    if not fetchAccountRowAsync(name, "acc_auth:passwordRow", seq) then
        byId[seq], busy[player] = nil, nil
        reply(player, false, "acc_auth.server.database_query_error")
    end
end)

addEvent("acc_auth:passwordRow")
addEventHandler("acc_auth:passwordRow", resourceRoot, function(id, rows)
    local req = byId[id]
    byId[id] = nil
    if not req then return end
    local player = req.player
    local row = type(rows) == "table" and rows[1] or nil
    if not isElement(player) then return end
    if not row then
        busy[player] = nil
        return reply(player, false, "acc_auth.server.database_query_error")
    end
    passwordVerify(req.current, tostring(row.password), {}, function(ok)
        if not ok then
            busy[player] = nil
            if isElement(player) then recordLoginFail(player) end
            return reply(player, false, "acc_auth.server.wrong_password")
        end
        passwordHash(req.new, "bcrypt", {}, function(hashed)
            busy[player] = nil
            if type(hashed) ~= "string" or not setAccountHash(row.account_name, hashed) then
                return reply(player, false, "acc_auth.server.database_query_error")
            end
            outputServerLog(("[acc_auth] password of '%s' changed by the player"):format(row.account_name))
            reply(player, true, "acc_auth.server.password_changed")
        end)
    end)
end)

addEventHandler("onPlayerQuit", root, function() busy[source] = nil end)
