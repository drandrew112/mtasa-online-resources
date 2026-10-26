if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- The account's email (account menu Profile > Account). The full address never
-- goes to the client, only a masked one ("dr****@gmail.com").
-- Adding the first email needs no password; changing or removing an existing
-- one needs the current password (an unattended PC must not give the account away).

local busy = {}      -- [player] = true while a request is in flight
local lastChange = {}
local seq, byId = 0, {}

function maskEmail(email)
    if type(email) ~= "string" or email == "" then return false end
    local localPart, domain = email:match("^([^@]+)@(.+)$")
    if not localPart then return "****" end
    return utf8.sub(localPart, 1, 2) .. "****@" .. domain
end

local function reply(player, email, noticeKey)
    if not isElement(player) then return end
    local has = type(email) == "string" and email ~= ""
    triggerClientEvent(player, "v_accounts:onClientEmail", player, maskEmail(email), has,
        noticeKey and L.msg(noticeKey) or nil)
end

local function newRequest(player, data)
    seq = seq + 1
    data.player = player
    byId[seq] = data
    busy[player] = true
    return seq
end

local function take(id)
    local data = byId[id]
    byId[id] = nil
    if data then busy[data.player] = nil end
    if data and isElement(data.player) and nameOf(data.player) then return data end
    return nil
end

-- the client asks for its (masked) email
addEvent("v_accounts:requestEmail", true)
addEventHandler("v_accounts:requestEmail", root, function()
    local player = client
    local name = nameOf(player)
    if not name or busy[player] then return end
    local id = newRequest(player, { kind = "get" })
    if not fetchAccountRowAsync(name, "v_accounts:emailRow", id) then
        take(id)
        authError(player, "v_accounts.auth.server.database_query_error")
    end
end)

-- the client sets / changes / removes (email = "") its email
addEvent("v_accounts:setEmail", true)
addEventHandler("v_accounts:setEmail", root, function(email, currentPassword)
    local player = client
    local name = nameOf(player)
    if not name or busy[player] then return end
    local tick = getTickCount()
    if lastChange[player] and tick - lastChange[player] < AUTH.EMAIL_MIN_INTERVAL then return end
    lastChange[player] = tick

    local mail = normalizeEmail(email)
    if mail == false then return authError(player, "v_accounts.auth.server.invalid_email") end
    if lockRemaining(player) > 0 then
        return authError(player, "v_accounts.auth.server.too_many_login_attempts", { seconds = lockRemaining(player) })
    end
    local id = newRequest(player, { kind = "set", email = mail,
        password = type(currentPassword) == "string" and #currentPassword <= 128 and currentPassword or "" })
    if not fetchAccountRowAsync(name, "v_accounts:emailRow", id) then
        take(id)
        authError(player, "v_accounts.auth.server.database_query_error")
    end
end)

local function write(data, name)
    -- mysqlInsertAsync is v_mysql's write with an answer: a duplicate email is reported back
    local id = newRequest(data.player, data)
    if not exports.v_mysql:mysqlInsertAsync("v_accounts:emailSaved", id,
        "UPDATE `accounts` SET email = ?, updated_at = ? WHERE account_name = ?",
        data.email, getRealTime().timestamp, name) then
        local d = take(id)
        if d then authError(d.player, "v_accounts.auth.server.database_query_error") end
    end
end

addEvent("v_accounts:emailRow")
addEventHandler("v_accounts:emailRow", resourceRoot, function(id, rows)
    local data = take(id)
    if not data then return end
    local player = data.player
    local row = type(rows) == "table" and rows[1] or nil
    if not row then return authError(player, "v_accounts.auth.server.database_query_error") end
    local current = (type(row.email) == "string" and row.email ~= "") and row.email or nil

    if data.kind == "get" then return reply(player, current) end

    if data.email == current then return reply(player, current) end
    if not current then
        if not data.email then return reply(player, nil) end
        return write(data, row.account_name)
    end

    -- changing / removing an existing email: the password decides
    if data.password == "" then return authError(player, "v_accounts.auth.server.password_needed_for_email") end
    busy[player] = true
    passwordVerify(data.password, tostring(row.password), {}, function(ok)
        busy[player] = nil
        if not isElement(player) or not nameOf(player) then return end
        if not ok then
            recordLoginFail(player)
            return authError(player, "v_accounts.auth.server.wrong_password")
        end
        write(data, row.account_name)
    end)
end)

addEvent("v_accounts:emailSaved")
addEventHandler("v_accounts:emailSaved", resourceRoot, function(id, result, err)
    local data = take(id)
    if not data then return end
    if result == false then
        if tostring(err):lower():find("duplicate", 1, true) then
            return authError(data.player, "v_accounts.auth.server.email_in_use")
        end
        return authError(data.player, "v_accounts.auth.server.database_query_error")
    end
    reply(data.player, data.email, data.email and "v_accounts.auth.server.email_saved" or "v_accounts.auth.server.email_removed")
end)

addEventHandler("onPlayerQuit", root, function()
    busy[source] = nil
    lastChange[source] = nil
end)
