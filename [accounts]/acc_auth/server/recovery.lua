if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Forgotten password.
--
--   1. acc_auth:resetRequest (email)   the player is answered at once with the
--      same "code" step whether or not an account uses that email (the panel
--      must not reveal who has which email). In the background: account by
--      email -> limits -> new code (only its hash is stored, RECOVERY.TABLE) ->
--      POST to RECOVERY.API_URL, which emails it (web/forgotpasswd.php).
--   2. acc_auth:resetConfirm (code, newPassword)   the code of the email given in
--      step 1 (kept here per player), max RECOVERY.MAX_ATTEMPTS tries, then a
--      new bcrypt hash. Remember-me tokens die with the old hash.

local pendingEmail = {}  -- [player] = normalized email of step 1
local serialLog    = {}  -- [serial] = { timestamps }
local accountLog   = {}  -- [lower account] = { timestamps }
local confirmBusy  = {}  -- [player] = true
local seq, byId    = 0, {}
local codeCounter  = 0

local function now() return getRealTime().timestamp end

local function dbReady()
    return resourceRunning("v_mysql") and exports.v_mysql:mysqlIsConnected() == true
end

local function resetState(player, step, info)
    if isElement(player) then
        triggerClientEvent(player, "acc_auth:onClientResetState", player, step, info)
    end
end

-- keeps the timestamps of the last hour, returns the list
local function recent(log, key)
    local t, keep = now(), {}
    for _, ts in ipairs(log[key] or {}) do
        if t - ts < 3600 then keep[#keep + 1] = ts end
    end
    log[key] = keep
    return keep
end

local function newCode(salt)
    codeCounter = codeCounter + 1
    local seed = table.concat({ tostring(math.random()), getTickCount(), now(), codeCounter, tostring(salt), tostring(math.random(1, 2 ^ 30)) }, "|")
    local hex = hash("sha256", seed)
    local chars, out = RECOVERY.CODE_CHARS, {}
    for i = 1, RECOVERY.CODE_LENGTH do
        local byte = tonumber(hex:sub(i * 2 - 1, i * 2), 16)
        local idx = byte % #chars + 1
        out[i] = chars:sub(idx, idx)
    end
    return table.concat(out)
end

local function codeHash(code, accountName)
    return hash("sha256", tostring(code):upper() .. "|" .. tostring(accountName):lower()):lower()
end

addEventHandler("onResourceStart", resourceRoot, function()
    if not dbReady() then return end
    exports.v_mysql:mysqlExec([[CREATE TABLE IF NOT EXISTS `]] .. RECOVERY.TABLE .. [[` (
        `id`           INT AUTO_INCREMENT PRIMARY KEY,
        `account_name` VARCHAR(50)  NOT NULL,
        `code_hash`    CHAR(64)     NOT NULL,
        `expires_at`   INT          NOT NULL DEFAULT 0,
        `attempts`     INT          NOT NULL DEFAULT 0,
        `serial`       VARCHAR(32)  DEFAULT NULL,
        `ip`           VARCHAR(45)  DEFAULT NULL,
        `created_at`   INT          NOT NULL DEFAULT 0,
        `used_at`      INT          NOT NULL DEFAULT 0,
        KEY `idx_account` (`account_name`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    if RECOVERY.API_KEY:find("^CHANGE_ME") then
        outputServerLog("[acc_auth] RECOVERY.API_KEY in config.lua is not set: password reset emails will be refused by the PHP")
    end
end)

--------------------------------------------------------------------------------
-- step 1: request a code
--------------------------------------------------------------------------------

local function sendMail(player, accountName, email, code, rowId)
    local body = toJSON({
        email = email, account = accountName, code = code,
        expires_minutes = math.floor(RECOVERY.CODE_TTL / 60),
        lang = (resourceRunning("v_locals") and exports.v_locals:getPlayerLanguage(player)) or "en",
    }, true):gsub("^%[(.*)%]$", "%1")
    local ok = fetchRemote(RECOVERY.API_URL, {
        method = "POST",
        postData = body,
        headers = { ["Content-Type"] = "application/json", ["Authorization"] = "Bearer " .. RECOVERY.API_KEY },
        connectTimeout = RECOVERY.HTTP_TIMEOUT,
        connectionAttempts = 2,
    }, function(response, info)
        local good = type(info) == "table" and info.success == true and tostring(response):find('"ok"%s*:%s*true') ~= nil
        if good then return end
        outputServerLog(("[acc_auth] password reset mail for '%s' failed: HTTP %s %s"):format(accountName,
            tostring(type(info) == "table" and info.statusCode or "?"), tostring(response):sub(1, 200)))
        exports.v_mysql:mysqlExec("UPDATE `" .. RECOVERY.TABLE .. "` SET used_at = ? WHERE id = ?", now(), rowId)
        if isElement(player) and pendingEmail[player] == email then
            resetState(player, "failed", L.msg("acc_auth.server.reset_mail_failed"))
        end
    end)
    if not ok then
        outputServerLog("[acc_auth] fetchRemote refused the password reset request (ACL / URL?)")
        exports.v_mysql:mysqlExec("UPDATE `" .. RECOVERY.TABLE .. "` SET used_at = ? WHERE id = ?", now(), rowId)
        resetState(player, "failed", L.msg("acc_auth.server.reset_mail_failed"))
    end
end

addEvent("acc_auth:resetAccount")
addEventHandler("acc_auth:resetAccount", resourceRoot, function(id, rows)
    local req = byId[id]
    byId[id] = nil
    if not req then return end
    local row = type(rows) == "table" and rows[1] or nil
    if not row or type(row.account_name) ~= "string" then return end -- unknown email: nothing is sent
    local account = row.account_name
    local player = req.player

    local accLog = recent(accountLog, account:lower())
    if #accLog >= RECOVERY.ACCOUNT_PER_HOUR then
        outputServerLog(("[acc_auth] password reset for '%s' skipped: hourly limit"):format(account))
        return
    end
    accLog[#accLog + 1] = now()

    local code = newCode(account .. tostring(req.serial))
    local t = now()
    -- one live code per account: older ones die
    exports.v_mysql:mysqlExec("UPDATE `" .. RECOVERY.TABLE .. "` SET used_at = ? WHERE account_name = ? AND used_at = 0", t, account)
    local rowId = exports.v_mysql:mysqlInsert("INSERT INTO `" .. RECOVERY.TABLE
        .. "` (account_name, code_hash, expires_at, serial, ip, created_at) VALUES (?, ?, ?, ?, ?, ?)",
        account, codeHash(code, account), t + RECOVERY.CODE_TTL, req.serial, req.ip, t)
    if type(rowId) ~= "number" then
        outputServerLog(("[acc_auth] password reset for '%s': could not store the code"):format(account))
        return resetState(player, "failed", L.msg("acc_auth.server.database_query_error"))
    end
    sendMail(player, account, req.email, code, rowId)
end)

addEvent("acc_auth:resetRequest", true)
addEventHandler("acc_auth:resetRequest", root, function(email)
    local player = client
    if not isElement(player) or nameOf(player) or getElementData(player, "banned") == true then return end

    local mail = normalizeEmail(email)
    if not mail then return authError(player, "acc_auth.server.invalid_email") end

    local serial = getPlayerSerial(player)
    local log = recent(serialLog, serial)
    local last = log[#log]
    if last and now() - last < RECOVERY.SERIAL_INTERVAL then
        return authError(player, "acc_auth.server.reset_wait", { seconds = RECOVERY.SERIAL_INTERVAL - (now() - last) })
    end
    if #log >= RECOVERY.SERIAL_PER_HOUR then
        return authError(player, "acc_auth.server.reset_too_many")
    end
    log[#log + 1] = now()

    pendingEmail[player] = mail
    -- the same answer for every email
    resetState(player, "code", { email = maskEmail(mail), wait = RECOVERY.SERIAL_INTERVAL })

    if not dbReady() then return end
    seq = seq + 1
    byId[seq] = { player = player, email = mail, serial = serial, ip = getPlayerIP(player) }
    fetchAccountByEmailAsync(mail, "acc_auth:resetAccount", seq)
end)

--------------------------------------------------------------------------------
-- step 2: code + new password
--------------------------------------------------------------------------------

addEvent("acc_auth:resetCode")
addEventHandler("acc_auth:resetCode", resourceRoot, function(id, rows)
    local req = byId[id]
    byId[id] = nil
    if not req then return end
    local player = req.player
    confirmBusy[player] = nil
    if not isElement(player) then return end

    local row = type(rows) == "table" and rows[1] or nil
    if not row then
        recordLoginFail(player)
        return authError(player, "acc_auth.server.reset_code_wrong")
    end
    local account, rowId = row.account_name, tonumber(row.id)
    if codeHash(req.code, account) ~= tostring(row.code_hash):lower() then
        recordLoginFail(player)
        local attempts = (tonumber(row.attempts) or 0) + 1
        if attempts >= RECOVERY.MAX_ATTEMPTS then
            exports.v_mysql:mysqlExec("UPDATE `" .. RECOVERY.TABLE .. "` SET attempts = ?, used_at = ? WHERE id = ?", attempts, now(), rowId)
            return authError(player, "acc_auth.server.reset_code_dead")
        end
        exports.v_mysql:mysqlExec("UPDATE `" .. RECOVERY.TABLE .. "` SET attempts = ? WHERE id = ?", attempts, rowId)
        return authError(player, "acc_auth.server.reset_code_wrong")
    end

    -- right code: it is used up now, whatever happens next
    exports.v_mysql:mysqlExec("UPDATE `" .. RECOVERY.TABLE .. "` SET used_at = ? WHERE id = ?", now(), rowId)
    confirmBusy[player] = true
    passwordHash(req.password, "bcrypt", {}, function(hashed)
        confirmBusy[player] = nil
        if type(hashed) ~= "string" or not setAccountHash(account, hashed) then
            if isElement(player) then authError(player, "acc_auth.server.database_query_error") end
            return
        end
        outputServerLog(("[acc_auth] password of '%s' reset by email code"):format(account))
        pendingEmail[player] = nil
        resetState(player, "done", account)
    end)
end)

addEvent("acc_auth:resetConfirm", true)
addEventHandler("acc_auth:resetConfirm", root, function(code, newPassword)
    local player = client
    if not isElement(player) or nameOf(player) or confirmBusy[player] then return end
    local mail = pendingEmail[player]
    if not mail then return authError(player, "acc_auth.server.reset_code_wrong") end

    local wait = lockRemaining(player)
    if wait > 0 then return authError(player, "acc_auth.server.too_many_login_attempts", { seconds = wait }) end

    code = tostring(code or ""):upper():gsub("%s", "")
    if #code ~= RECOVERY.CODE_LENGTH or code:find("[^" .. RECOVERY.CODE_CHARS .. "]") then
        return authError(player, "acc_auth.server.reset_code_wrong")
    end
    if type(newPassword) ~= "string" or #newPassword > 128 then return end
    if #newPassword < AUTH.PASSWORD_MIN then return authError(player, "acc_auth.server.password_too_short") end
    if not dbReady() then return authError(player, "acc_auth.server.database_query_error") end

    seq = seq + 1
    byId[seq] = { player = player, code = code, password = newPassword }
    confirmBusy[player] = true
    -- the live code of the account behind the email of step 1
    if not exports.v_mysql:mysqlQueryAsync("acc_auth:resetCode", seq,
        "SELECT r.id, r.account_name, r.code_hash, r.attempts FROM `" .. RECOVERY.TABLE .. "` r "
        .. "JOIN `accounts` a ON a.account_name = r.account_name "
        .. "WHERE a.email = ? AND r.used_at = 0 AND r.expires_at > ? ORDER BY r.id DESC LIMIT 1",
        mail, now()) then
        byId[seq] = nil
        confirmBusy[player] = nil
        authError(player, "acc_auth.server.database_query_error")
    end
end)

addEventHandler("onPlayerQuit", root, function()
    pendingEmail[source] = nil
    confirmBusy[source] = nil
end)
