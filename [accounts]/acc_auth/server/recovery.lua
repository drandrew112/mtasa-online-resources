if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Forgotten password.
--
--   1. acc_auth:resetRequest (email)   "sending" at once, then account by
--      email -> limits -> new code (only its hash is stored, RECOVERY.TABLE) ->
--      Brevo transactional email API (RECOVERY.BREVO_URL) sends it. The
--      "code" step comes only when the mail went out; a failed send answers
--      "failed" and the panel stays on the email step. An unknown email gets
--      the same "code" step after a short random delay (the panel must not
--      reveal who has which email).
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

local function codeStep(player, email)
    if isElement(player) and pendingEmail[player] == email then
        resetState(player, "code", { email = maskEmail(email), wait = RECOVERY.SERIAL_INTERVAL })
    end
end

-- "code" for a request that sends no mail, about as late as a real send would be
local function fakeCodeStep(player, email)
    setTimer(codeStep, math.random(800, 2000), 1, player, email)
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

-- creates RECOVERY.TABLE once per run: on start, on a later mysql:connected,
-- or right before the first use (whichever has a connection first)
local tableReady = false
local function ensureTable()
    if tableReady or not dbReady() then return tableReady end
    tableReady = exports.v_mysql:mysqlExec([[CREATE TABLE IF NOT EXISTS `]] .. RECOVERY.TABLE .. [[` (
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
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]) == true
    if tableReady then outputServerLog("[acc_auth] `" .. RECOVERY.TABLE .. "` table checked/created") end
    return tableReady
end

addEvent("mysql:connected")
addEventHandler("mysql:connected", root, ensureTable)

addEventHandler("onResourceStart", resourceRoot, function()
    if not ensureTable() then
        outputServerLog("[acc_auth] v_mysql not connected yet, `" .. RECOVERY.TABLE .. "` will be created on mysql:connected")
    end
    if RECOVERY.BREVO_API_KEY:find("^CHANGE_ME") then
        outputServerLog("[acc_auth] RECOVERY.BREVO_API_KEY in config.lua is not set: password reset emails cannot be sent")
    end
end)

--------------------------------------------------------------------------------
-- step 1: request a code
--------------------------------------------------------------------------------

local MAIL_TEXT = {
    en = {
        subject = "Your FreeV password reset code",
        hello   = "Hi %s,",
        line1   = "Someone asked to reset the password of your FreeV account. Enter this code in the game:",
        line2   = "The code is valid for %d minutes. If you did not ask for it, ignore this email: your password stays the same.",
        sign    = "FreeV MTA:SA",
    },
    hu = {
        subject = "FreeV jelszó-visszaállító kód",
        hello   = "Szia %s!",
        line1   = "Valaki a FreeV fiókod jelszavának visszaállítását kérte. Ezt a kódot írd be a játékban:",
        line2   = "A kód %d percig érvényes. Ha nem te kérted, hagyd figyelmen kívül ezt a levelet: a jelszavad nem változik.",
        sign    = "FreeV MTA:SA",
    },
}

local function htmlEscape(text)
    return (tostring(text):gsub("[&<>\"']", { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&#39;" }))
end

-- { subject, textContent, htmlContent } of the reset mail
local function mailContent(lang, accountName, code)
    local t = MAIL_TEXT[lang] or MAIL_TEXT.en
    local minutes = math.floor(RECOVERY.CODE_TTL / 60)
    local hello, line2 = t.hello:format(accountName), t.line2:format(minutes)
    local text = hello .. "\n\n" .. t.line1 .. "\n\n    " .. code .. "\n\n" .. line2 .. "\n\n" .. t.sign .. "\n"
    local html = '<!doctype html><html><body style="margin:0;padding:24px;background:#101318;font-family:Arial,sans-serif;color:#e4e9ee">'
        .. '<div style="max-width:520px;margin:0 auto;background:#181d24;padding:28px;border-left:4px solid #409cb4">'
        .. '<p style="margin:0 0 14px;font-size:16px">' .. htmlEscape(hello) .. '</p>'
        .. '<p style="margin:0 0 18px;font-size:15px;line-height:1.5">' .. htmlEscape(t.line1) .. '</p>'
        .. '<p style="margin:0 0 18px;font-size:32px;font-weight:bold;letter-spacing:8px;color:#ffffff">' .. htmlEscape(code) .. '</p>'
        .. '<p style="margin:0 0 18px;font-size:13px;line-height:1.5;color:#929eaa">' .. htmlEscape(line2) .. '</p>'
        .. '<p style="margin:0;font-size:13px;color:#929eaa">' .. htmlEscape(t.sign) .. '</p>'
        .. '</div></body></html>'
    return t.subject, text, html
end

local function sendMail(player, accountName, email, code, rowId)
    local lang = (resourceRunning("v_locals") and exports.v_locals:getPlayerLanguage(player)) or "en"
    local subject, text, html = mailContent(lang, accountName, code)
    local body = toJSON({
        sender = { name = RECOVERY.SENDER_NAME, email = RECOVERY.SENDER_EMAIL },
        to = { { email = email, name = accountName } },
        subject = subject,
        textContent = text,
        htmlContent = html,
    }, true):gsub("^%[(.*)%]$", "%1")
    local ok = fetchRemote(RECOVERY.BREVO_URL, {
        method = "POST",
        postData = body,
        headers = {
            ["Content-Type"] = "application/json",
            ["Accept"] = "application/json",
            ["api-key"] = RECOVERY.BREVO_API_KEY,
        },
        connectTimeout = RECOVERY.HTTP_TIMEOUT,
        connectionAttempts = 2,
    }, function(response, info)
        -- Brevo answers 201 {"messageId": "..."} when the mail is accepted
        local status = type(info) == "table" and tonumber(info.statusCode) or 0
        local good = type(info) == "table" and info.success == true and status >= 200 and status < 300
            and tostring(response):find('"messageId"', 1, true) ~= nil
        if good then return codeStep(player, email) end
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
    if not row or type(row.account_name) ~= "string" then return fakeCodeStep(player, req.email) end -- unknown email: nothing is sent
    local account = row.account_name
    local player = req.player

    local accLog = recent(accountLog, account:lower())
    if #accLog >= RECOVERY.ACCOUNT_PER_HOUR then
        outputServerLog(("[acc_auth] password reset for '%s' skipped: hourly limit"):format(account))
        return fakeCodeStep(player, req.email)
    end
    accLog[#accLog + 1] = now()

    ensureTable()
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

    if not dbReady() then return resetState(player, "failed", L.msg("acc_auth.server.database_query_error")) end
    pendingEmail[player] = mail
    resetState(player, "sending")
    seq = seq + 1
    byId[seq] = { player = player, email = mail, serial = serial, ip = getPlayerIP(player) }
    if not fetchAccountByEmailAsync(mail, "acc_auth:resetAccount", seq) then
        byId[seq] = nil
        resetState(player, "failed", L.msg("acc_auth.server.database_query_error"))
    end
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
    ensureTable()

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
