if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
if not MYSQL then loadstring(exports.v_mysql:importAsync())() end -- v_mysql async lib (PERF-01)
--[[
    ui_phone / server/apps/mail.lua
    Email app: in-game mails in the `phone_mails` table (one row per recipient).

    Sending (other resources, e.g. the government news later):

      exports.ui_phone:sendPhoneMail(recipients, mail) -> true, groupKey | false, error
        recipients  "all" (every existing account) | account name | player
                    | { name | player, ... }
        mail        { sender = "Government", kind = "gov",
                      texts = { en = { subject, body [, sender] }, hu = { ... } } }
                    or one language: { sender, kind, subject, body } (= DEFAULT_LANG)
      exports.ui_phone:deletePhoneMailGroup(groupKey) -> bool   (takes a sent mail back)

    A reader gets its own v_locals language, else its fallback, else English,
    else the first language written (like v_news).

    Delivery: a recipient that is offline gets the mail on the next login
    (delivered_at = 0 until then; a toast tells how many new mails came). Online
    recipients get it at once; a POLL_MS check also delivers the mails sent
    from another server instance.
]]

local TABLE        = "phone_mails"
local DEFAULT_LANG = "en"
local LIST_MAX     = 50       -- newest mails sent to the phone
local SUBJECT_MAX  = 120      -- characters
local BODY_MAX     = 4000
local SENDER_MAX   = 64
local POLL_MS      = 60000

local ready = false

local function now() return getRealTime().timestamp end

local function dbReady()
    local res = getResourceFromName("v_mysql")
    return res and getResourceState(res) == "running" and exports.v_mysql:mysqlIsConnected() == true
end

local function ensureTable()
    if ready or not dbReady() then return end
    exports.v_mysql:mysqlExec([[CREATE TABLE IF NOT EXISTS `]] .. TABLE .. [[` (
        `id`           INT AUTO_INCREMENT PRIMARY KEY,
        `group_key`    VARCHAR(64)  NOT NULL DEFAULT '',
        `account_name` VARCHAR(64)  NOT NULL,
        `kind`         VARCHAR(32)  NOT NULL DEFAULT '',
        `sender`       VARCHAR(64)  NOT NULL DEFAULT '',
        `texts`        MEDIUMTEXT   NOT NULL,
        `created_at`   INT          NOT NULL DEFAULT 0,
        `delivered_at` INT          NOT NULL DEFAULT 0,
        `read_at`      INT          NOT NULL DEFAULT 0,
        `deleted_at`   INT          NOT NULL DEFAULT 0,
        KEY `idx_account` (`account_name`, `deleted_at`, `id`),
        KEY `idx_pending` (`delivered_at`, `account_name`),
        KEY `idx_group` (`group_key`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    ready = true
end

addEventHandler("onResourceStart", resourceRoot, ensureTable)
addEvent("mysql:connected")
addEventHandler("mysql:connected", root, ensureTable)

local function accName(player)
    if not isElement(player) or getElementType(player) ~= "player" then return nil end
    if not exports.v_accounts:isLoggedIn(player) then return nil end
    local n = exports.v_accounts:getName(player)
    return (type(n) == "string" and n ~= "") and n or nil
end

local function playerByAccount(name)
    local needle = tostring(name):lower()
    for _, p in ipairs(getElementsByType("player")) do
        local a = accName(p)
        if a and a:lower() == needle then return p end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Languages (same resolution as v_news)
--------------------------------------------------------------------------------

local function languages()
    local order, fallback = {}, {}
    local ok, list = pcall(function() return exports.v_locals:getLanguages() end)
    for _, l in ipairs(ok and type(list) == "table" and list or {}) do order[#order + 1] = l.value end
    local ok2, info = pcall(function() return exports.v_locals:getLanguageInfo() end)
    for code, l in pairs(ok2 and type(info) == "table" and info or {}) do
        if type(l) == "table" and type(l.fallback) == "string" then fallback[code] = l.fallback end
    end
    return { order = order, fallback = fallback }
end

local function resolveLang(texts, lang, langs)
    local seen = {}
    while lang and not seen[lang] do
        if texts[lang] then return lang end
        seen[lang] = true
        lang = langs.fallback[lang]
    end
    if texts[DEFAULT_LANG] then return DEFAULT_LANG end
    for _, code in ipairs(langs.order) do
        if texts[code] then return code end
    end
    local first
    for code in pairs(texts) do
        if not first or code < first then first = code end
    end
    return first
end

--------------------------------------------------------------------------------
-- Sending
--------------------------------------------------------------------------------

local function clean(text, max)
    text = tostring(text or ""):gsub("\r\n", "\n"):gsub("[%z\1-\8\11\12\14-\31]", "")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if utf8.len(text) and utf8.len(text) > max then text = utf8.sub(text, 1, max) end
    return text
end

-- mail -> { kind, sender, texts = { [lang] = { subject, body, sender? } } } | nil, error
local function normalize(mail)
    if type(mail) ~= "table" then return nil, "bad mail" end
    local src = mail.texts
    if type(src) ~= "table" then src = { [DEFAULT_LANG] = { subject = mail.subject, body = mail.body } } end
    local texts, count = {}, 0
    for code, t in pairs(src) do
        if type(code) == "string" and code:match("^%a%a?%a?[%w_-]*$") and #code <= 8 and type(t) == "table" then
            local subject = clean(t.subject or t[1], SUBJECT_MAX)
            local body = clean(t.body or t[2], BODY_MAX)
            if subject ~= "" and body ~= "" then
                local entry = { subject = subject, body = body }
                if t.sender then entry.sender = clean(t.sender, SENDER_MAX) end
                texts[code] = entry
                count = count + 1
            end
        end
    end
    if count == 0 then return nil, "no subject / body" end
    return {
        kind = clean(mail.kind, 32),
        sender = clean(mail.sender, SENDER_MAX),
        texts = texts,
    }
end

-- recipients -> "all" | { accountName, ... } | nil, error
local function recipientList(recipients)
    if recipients == "all" or recipients == "*" then return "all" end
    if type(recipients) ~= "table" or isElement(recipients) then recipients = { recipients } end
    local names, seen = {}, {}
    for _, r in ipairs(recipients) do
        local name = isElement(r) and accName(r) or (type(r) == "string" and r ~= "" and r or nil)
        if name and not seen[name:lower()] then
            seen[name:lower()] = true
            names[#names + 1] = name
        end
    end
    if #names == 0 then return nil, "no recipient" end
    return names
end

local deliver   -- forward: deliver(player)
local groupSeq = 0

function sendPhoneMail(recipients, mail)
    ensureTable()
    if not ready then return false, "database not connected" end
    local m, err = normalize(mail)
    if not m then return false, err end
    local names, err2 = recipientList(recipients)
    if not names then return false, err2 end

    groupSeq = groupSeq + 1
    local ts = now()
    local group = ("%s:%d:%d"):format(m.kind ~= "" and m.kind or "mail", ts, groupSeq):sub(1, 64)
    -- INSERT ... SELECT from `accounts`: only existing accounts get a row, with
    -- their stored spelling; "all" = every account that exists right now
    local sql = "INSERT INTO `" .. TABLE .. "` (group_key, account_name, kind, sender, texts, created_at) "
        .. "SELECT ?, a.account_name, ?, ?, ?, ? FROM `accounts` a"
    local args = { group, m.kind, m.sender, toJSON(m.texts, true), ts }
    if names ~= "all" then
        sql = sql .. " WHERE a.account_name IN (" .. ("?, "):rep(#names):sub(1, -3) .. ")"
        for _, n in ipairs(names) do args[#args + 1] = n end
    end

    MYSQL.insert(function(id, e)
        if not id then
            outputDebugString("[phone] sendPhoneMail failed: " .. tostring(e), 2)
            return
        end
        if names == "all" then
            for _, p in ipairs(getElementsByType("player")) do deliver(p) end
        else
            for _, n in ipairs(names) do
                local p = playerByAccount(n)
                if p then deliver(p) end
            end
        end
    end, sql, unpack(args))
    return true, group
end

function deletePhoneMailGroup(groupKey)
    if type(groupKey) ~= "string" or groupKey == "" or not dbReady() then return false end
    exports.v_mysql:mysqlExec("UPDATE `" .. TABLE .. "` SET deleted_at = ? WHERE group_key = ? AND deleted_at = 0", now(), groupKey)
    setTimer(function()
        for _, p in ipairs(getElementsByType("player")) do deliver(p) end
    end, 1000, 1)
    return true
end

--------------------------------------------------------------------------------
-- Delivery + the client list
--------------------------------------------------------------------------------

local announced = {}   -- [player] = { [id] = true } new mails already toasted

-- Pushes the player's newest mails and marks the undelivered ones delivered.
deliver = function(player)
    local name = accName(player)
    if not name or not ready then return end
    MYSQL.query(function(rows)
        if not isElement(player) or type(rows) ~= "table" then return end
        local lang = L.lang(player)
        local langs = languages()
        local list, fresh = {}, 0
        announced[player] = announced[player] or {}
        for _, row in ipairs(rows) do
            local texts = fromJSON(tostring(row.texts or "")) or {}
            local code = resolveLang(texts, lang, langs)
            local t = code and texts[code]
            if type(t) == "table" then
                list[#list + 1] = {
                    id = tonumber(row.id), time = tonumber(row.created_at) or 0,
                    sender = (t.sender and t.sender ~= "") and t.sender or tostring(row.sender or ""),
                    subject = tostring(t.subject or ""), body = tostring(t.body or ""),
                    read = (tonumber(row.read_at) or 0) > 0,
                }
            end
            local id = tonumber(row.id)
            if (tonumber(row.delivered_at) or 0) == 0 and id and not announced[player][id] then
                announced[player][id] = true
                fresh = fresh + 1
            end
        end
        if fresh > 0 then
            exports.v_mysql:mysqlExec("UPDATE `" .. TABLE .. "` SET delivered_at = ? WHERE account_name = ? AND delivered_at = 0",
                now(), name)
            PhoneServer.toast(player, L.forPlayer(player, "ui_phone.mail.new_mails", { count = fresh }))
        end
        PhoneServer.push(player, "mail:list", list)
    end, "SELECT id, sender, texts, created_at, delivered_at, read_at FROM `" .. TABLE
        .. "` WHERE account_name = ? AND deleted_at = 0 ORDER BY id DESC LIMIT ?", name, LIST_MAX)
end

-- runs on login (onPlayerLoaded) and whenever the phone opens
PhoneServer.onPull(deliver)

addEventHandler("onPlayerQuit", root, function() announced[source] = nil end)

PhoneServer.on("mail:read", function(player, id)
    local name = accName(player)
    id = tonumber(id)
    if not name or not id or not ready then return end
    exports.v_mysql:mysqlExec("UPDATE `" .. TABLE .. "` SET read_at = ? WHERE id = ? AND account_name = ? AND read_at = 0",
        now(), id, name)
end)

PhoneServer.on("mail:delete", function(player, id)
    local name = accName(player)
    id = tonumber(id)
    if not name or not id or not ready then return end
    exports.v_mysql:mysqlExec("UPDATE `" .. TABLE .. "` SET deleted_at = ? WHERE id = ? AND account_name = ?",
        now(), id, name)
end)

-- mails written by another server instance (same database) reach online players here
setTimer(function()
    if not ready then return end
    local byName, names = {}, {}
    for _, p in ipairs(getElementsByType("player")) do
        local n = accName(p)
        if n then byName[n:lower()] = p; names[#names + 1] = n end
    end
    if #names == 0 then return end
    MYSQL.query(function(rows)
        if type(rows) ~= "table" then return end
        for _, row in ipairs(rows) do
            local p = byName[tostring(row.account_name):lower()]
            if isElement(p) then deliver(p) end
        end
    end, "SELECT DISTINCT account_name FROM `" .. TABLE .. "` WHERE delivered_at = 0 AND deleted_at = 0 AND account_name IN ("
        .. ("?, "):rep(#names):sub(1, -3) .. ")", unpack(names))
end, POLL_MS, 0)

--------------------------------------------------------------------------------
-- /phonemail <account|all> <subject> | <text>   (admin_level >= 5, for testing;
-- one language: the admin's own)
--------------------------------------------------------------------------------

addCommandHandler("phonemail", function(player, _, target, ...)
    if (tonumber(exports.v_mysql:getAccData(player, "admin_level")) or 0) < 5 then return end
    local subject, body = table.concat({ ... }, " "):match("^(.-)%s*|%s*(.+)$")
    if not target or not subject or subject == "" then
        return PhoneServer.toast(player, L.forPlayer(player, "ui_phone.mail.cmd_usage"))
    end
    local lang = L.lang(player) or DEFAULT_LANG
    local ok, groupOrErr = sendPhoneMail(target:lower() == "all" and "all" or target, {
        kind = "admin", sender = accName(player) or "Admin",
        texts = { [lang] = { subject = subject, body = body:gsub("\\n", "\n") } },
    })
    PhoneServer.toast(player, ok and L.forPlayer(player, "ui_phone.mail.cmd_sent", { group = groupOrErr })
        or L.forPlayer(player, "ui_phone.mail.cmd_failed", { error = tostring(groupOrErr) }))
end)
