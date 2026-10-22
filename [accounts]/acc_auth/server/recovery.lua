if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Forgotten password.
--
--   1. acc_auth:resetRequest (email)   "sending" at once, then account by
--      email -> limits -> new code (only its hash is stored, RECOVERY.TABLE) ->
--      v_mail (Brevo transactional email API) sends it. The
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
    if not resourceRunning("v_mail") or exports.v_mail:isMailConfigured() ~= true then
        outputServerLog("[acc_auth] v_mail is not running / not configured: password reset emails cannot be sent")
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

-- the reset mail in v_mail's house layout (server/template.lua there)
local function mailContent(lang, accountName, code)
    local t = MAIL_TEXT[lang] or MAIL_TEXT.en
    return t.subject, {
        greeting = t.hello:format(accountName),
        paragraphs = { t.line1 },
        code = code,
        note = t.line2:format(math.floor(RECOVERY.CODE_TTL / 60)),
        signature = t.sign,
    }
end

local mailReq = {} -- [requestId] = { player, accountName, email, rowId } while v_mail sends

local function mailFailed(req)
    exports.v_mysql:mysqlExec("UPDATE `" .. RECOVERY.TABLE .. "` SET used_at = ? WHERE id = ?", now(), req.rowId)
    if isElement(req.player) and pendingEmail[req.player] == req.email then
        resetState(req.player, "failed", L.msg("acc_auth.server.reset_mail_failed"))
    end
end

local function sendMail(player, accountName, email, code, rowId)
    local lang = (resourceRunning("v_locals") and exports.v_locals:getPlayerLanguage(player)) or "en"
    local subject, template = mailContent(lang, accountName, code)
    seq = seq + 1
    local req = { player = player, accountName = accountName, email = email, rowId = rowId }
    mailReq[seq] = req
    local ok, err = false, "v_mail is not running"
    if resourceRunning("v_mail") then
        ok, err = exports.v_mail:sendMail({ to = email, toName = accountName, subject = subject, template = template,
            log = { kind = "password_reset", language = lang } }, "acc_auth:resetMailSent", seq)
    end
    if not ok then
        mailReq[seq] = nil
        outputServerLog(("[acc_auth] password reset mail for '%s' not sent: %s"):format(accountName, tostring(err)))
        mailFailed(req)
    end
end

-- answer of v_mail: the "code" step comes only when the mail went out
addEvent("acc_auth:resetMailSent")
addEventHandler("acc_auth:resetMailSent", resourceRoot, function(id, ok)
    local req = mailReq[id]
    mailReq[id] = nil
    if not req then return end
    if ok then return codeStep(req.player, req.email) end
    mailFailed(req) -- v_mail logged the reason
end)

addEvent("acc_auth:resetAccount")
addEventHandler("acc_auth:resetAccount", resourceRoot, function(id, rows)
    local req = byId[id]
    byId[id] = nil
    if not req then return end
    local row = type(rows) == "table" and rows[1] or nil
    if not row or type(row.account_name) ~= "string" then return fakeCodeStep(req.player, req.email) end -- unknown email: nothing is sent
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

--------------------------------------------------------------------------------
-- a code the player got some other way (sent by an admin): step 2 without a new mail
--------------------------------------------------------------------------------

-- The panel's "I already have a code": the email is only remembered for step 2,
-- nothing is looked up or sent, so it reveals nothing about the address.
addEvent("acc_auth:resetHaveCode", true)
addEventHandler("acc_auth:resetHaveCode", root, function(email)
    local player = client
    if not isElement(player) or nameOf(player) or getElementData(player, "banned") == true then return end
    local mail = normalizeEmail(email)
    if not mail then return authError(player, "acc_auth.server.invalid_email") end
    pendingEmail[player] = mail
    resetState(player, "code", { email = maskEmail(mail), wait = 0, haveCode = true })
end)

--------------------------------------------------------------------------------
-- admin exports (v_admin Accounts page; v_admin checks the admin level)
--------------------------------------------------------------------------------

local ADMIN_MAIL_TEXT = {
    en = {
        subject = "FreeV password reset",
        hello   = "Hi %s,",
        line1   = "An admin started a password reset for your FreeV account. In the game click \"Forgot password\", then \"I already have a code\", enter this email address and the code below:",
        line2   = "The code is valid for %d hours. If you did not ask for it, you can ignore this email: your password stays the same.",
    },
    hu = {
        subject = "FreeV jelszó-visszaállítás",
        hello   = "Szia %s!",
        line1   = "Egy admin jelszó-visszaállítást indított a FreeV fiókodhoz. A játékban kattints az \"Elfelejtett jelszó\", majd a \"Már van kódom\" gombra, add meg ezt az e-mail címet és az alábbi kódot:",
        line2   = "A kód %d óráig érvényes. Ha nem te kérted, hagyd figyelmen kívül ezt a levelet: a jelszavad nem változik.",
    },
}

local function accountRow(accountName)
    local rows = exports.v_mysql:mysqlQuerySync(
        "SELECT account_name, email, SUBSTRING(account_data, LOCATE('\"locale.language\"', account_data), 120) AS loc "
        .. "FROM `accounts` WHERE account_name = ? LIMIT 1", accountName)
    return type(rows) == "table" and rows[1] or nil
end

--- Mails a password reset code to the account's own email (valid RECOVERY.ADMIN_CODE_TTL).
--- -> true | false, errorKey (acc_auth.server.*)
function adminSendPasswordReset(accountName, adminName)
    if type(accountName) ~= "string" or accountName == "" then return false, "acc_auth.server.account_not_found" end
    if not dbReady() then return false, "acc_auth.server.database_query_error" end
    if not resourceRunning("v_mail") or exports.v_mail:isMailConfigured() ~= true then return false, "acc_auth.server.reset_mail_failed" end
    local row = accountRow(accountName)
    if not row then return false, "acc_auth.server.account_not_found" end
    local email = type(row.email) == "string" and row.email ~= "" and row.email or nil
    if not email then return false, "acc_auth.server.account_has_no_email" end
    local account = row.account_name

    ensureTable()
    local ttl = tonumber(RECOVERY.ADMIN_CODE_TTL) or 24 * 3600
    local code = newCode(account .. tostring(adminName))
    local t = now()
    exports.v_mysql:mysqlExec("UPDATE `" .. RECOVERY.TABLE .. "` SET used_at = ? WHERE account_name = ? AND used_at = 0", t, account)
    local rowId = exports.v_mysql:mysqlInsert("INSERT INTO `" .. RECOVERY.TABLE
        .. "` (account_name, code_hash, expires_at, serial, ip, created_at) VALUES (?, ?, ?, ?, ?, ?)",
        account, codeHash(code, account), t + ttl, "admin", tostring(adminName or "admin"):sub(1, 45), t)
    if type(rowId) ~= "number" then return false, "acc_auth.server.database_query_error" end

    local lang = type(row.loc) == "string" and row.loc:match('^"locale%.language"%s*:%s*%[?%s*{[^}]-"v"%s*:%s*"([%w_%-]+)"') or "en"
    local text = ADMIN_MAIL_TEXT[lang] or ADMIN_MAIL_TEXT.en
    local ok, err = exports.v_mail:sendMail({
        to = email, toName = account, subject = text.subject,
        template = {
            greeting = text.hello:format(account),
            paragraphs = { text.line1 },
            code = code,
            note = text.line2:format(math.floor(ttl / 3600)),
            signature = "FreeV MTA:SA",
        },
        log = { kind = "password_reset", language = lang, sender = tostring(adminName or "admin") },
    })
    if not ok then
        exports.v_mysql:mysqlExec("UPDATE `" .. RECOVERY.TABLE .. "` SET used_at = ? WHERE id = ?", now(), rowId)
        outputServerLog(("[acc_auth] admin password reset mail for '%s' not sent: %s"):format(account, tostring(err)))
        return false, "acc_auth.server.reset_mail_failed"
    end
    outputServerLog(("[acc_auth] password reset code for '%s' mailed by admin %s"):format(account, tostring(adminName)))
    return true
end

--- Sets (or with "" removes) the email of an account; an address another account has is refused.
--- -> true | false, errorKey (acc_auth.server.*)
function adminSetAccountEmail(accountName, email)
    if type(accountName) ~= "string" or accountName == "" then return false, "acc_auth.server.account_not_found" end
    if not dbReady() then return false, "acc_auth.server.database_query_error" end
    local mail = normalizeEmail(email)
    if mail == false then return false, "acc_auth.server.invalid_email" end
    local row = accountRow(accountName)
    if not row then return false, "acc_auth.server.account_not_found" end
    if mail then
        local other = exports.v_mysql:mysqlQuerySync("SELECT account_name FROM `accounts` WHERE email = ? AND account_name <> ? LIMIT 1",
            mail, row.account_name)
        if type(other) ~= "table" then return false, "acc_auth.server.database_query_error" end
        if other[1] then return false, "acc_auth.server.email_in_use" end
    end
    -- through v_mysql so its account cache stays right (email is a promoted UNIQUE column; nil = NULL)
    if not exports.v_mysql:setAccData(row.account_name, "email", mail) then return false, "acc_auth.server.database_query_error" end
    -- a logged in player sees the new (masked) address in the account menu
    for _, p in ipairs(getElementsByType("player")) do
        local n = nameOf(p)
        if n and n:lower() == row.account_name:lower() then
            triggerClientEvent(p, "acc_auth:onClientEmail", p, maskEmail(mail), mail ~= nil)
        end
    end
    return true
end
