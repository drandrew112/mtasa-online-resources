if not MYSQL then loadstring(exports.v_mysql:importAsync())() end -- v_mysql async lib
-- The `mails` table: one row per mail the server sent, or still has to send
-- (update mails over the daily limit wait here as "pending"). Mails that belong
-- together (one circular, one weekly update) share a group_key; a single mail
-- (password reset) has none. No email address is ever stored: account_name only.
--
-- status: pending (waits for its turn) | sending | sent | failed | skipped
-- body = the plain text as sent (a template `code` is masked);
-- template = the layout JSON of a pending mail, cleared once it is sent.

MAILDB = {}

local ready = false

local function now() return getRealTime().timestamp end

local function dbReady()
    local res = getResourceFromName("v_mysql")
    return res and getResourceState(res) == "running" and exports.v_mysql:mysqlIsConnected() == true
end

function MAILDB.serverId()
    local res = getResourceFromName("v_main")
    if not res or getResourceState(res) ~= "running" then return 0 end
    local ok, id = pcall(function() return exports.v_main:getServerInstanceId() end)
    return ok and tonumber(id) or 0
end

function MAILDB.isReady() return ready end

local function ensure()
    if ready or not dbReady() then return ready end
    exports.v_mysql:mysqlExec([[CREATE TABLE IF NOT EXISTS `]] .. MAILER.TABLE .. [[` (
        `id`           INT AUTO_INCREMENT PRIMARY KEY,
        `group_key`    VARCHAR(64)  NULL DEFAULT NULL,
        `kind`         VARCHAR(32)  NOT NULL DEFAULT '',
        `sender`       VARCHAR(64)  NOT NULL DEFAULT '',
        `server_id`    INT          NOT NULL DEFAULT 0,
        `account_name` VARCHAR(64)  NULL DEFAULT NULL,
        `language`     VARCHAR(8)   NOT NULL DEFAULT '',
        `subject`      VARCHAR(255) NOT NULL DEFAULT '',
        `body`         MEDIUMTEXT   NULL,
        `template`     MEDIUMTEXT   NULL,
        `status`       VARCHAR(16)  NOT NULL DEFAULT 'sent',
        `message_id`   VARCHAR(128) NULL DEFAULT NULL,
        `error`        VARCHAR(255) NULL DEFAULT NULL,
        `created_at`   INT          NOT NULL DEFAULT 0,
        `sent_at`      INT          NOT NULL DEFAULT 0,
        KEY `idx_group` (`group_key`),
        KEY `idx_kind_status` (`kind`, `status`),
        KEY `idx_created` (`created_at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    ready = true
    triggerEvent("v_mail:dbReady", resourceRoot)
    return true
end

-- Brevo errors may quote the address: never store or show it
local function cleanError(text)
    if text == nil then return nil end
    return (tostring(text):gsub("[^%s@\"'<>,;:]+@[^%s@\"'<>,;:]+", "<address>"):sub(1, 255))
end

local function cut(text, max)
    return type(text) == "string" and (utf8.sub(text, 1, max) or text:sub(1, max)) or nil
end

-- a mail that went through queueMail without a row of its own
-- row = { group, kind, sender, account, language, subject, body }
function MAILDB.record(row, ok, info)
    if not ensure() then return end
    local t = now()
    MYSQL.insert(function(id, err)
        if not id then outputServerLog("[v_mail] could not store a mail in `" .. MAILER.TABLE .. "`: " .. tostring(err)) end
    end, "INSERT INTO `" .. MAILER.TABLE .. "` (group_key, kind, sender, server_id, account_name, language, subject, body, "
        .. "status, message_id, error, created_at, sent_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
        cut(row.group, 64), cut(row.kind or "", 32), cut(row.sender or "", 64), MAILDB.serverId(),
        cut(row.account, 64), cut(row.language or "", 8), cut(row.subject or "", 255), row.body or "",
        ok and "sent" or "failed", ok and cut(tostring(info), 128) or nil, (not ok) and cleanError(info) or nil, t, t)
end

-- the answer for a row that already exists (a pending update mail)
function MAILDB.finish(id, status, info)
    if not ensure() then return end
    local sent = status == "sent"
    MYSQL.query(nil, "UPDATE `" .. MAILER.TABLE .. "` SET status = ?, message_id = ?, error = ?, sent_at = ?, template = NULL WHERE id = ?",
        status, sent and cut(tostring(info), 128) or nil, (not sent and info) and cleanError(info) or nil, now(), id)
end

--------------------------------------------------------------------------------
-- history (/mail panel); cb(result | nil)
--------------------------------------------------------------------------------

-- a single mail is a group of its own: "#<id>"
local GKEY = "COALESCE(group_key, CONCAT('#', id))"

-- -> { { key, kind, sender, subject, created, total, sent, failed, waiting, skipped }, ... }, hasMore
function MAILDB.groups(page, cb)
    if not ensure() then return cb(nil) end
    local size = MAILER.HISTORY_PAGE
    MYSQL.query(function(rows)
        if not rows then return cb(nil) end
        local out = {}
        for i = 1, math.min(#rows, size) do
            local r = rows[i]
            out[i] = {
                key = tostring(r.gkey), kind = r.kind, sender = r.sender, subject = r.subject,
                created = tonumber(r.created) or 0, total = tonumber(r.total) or 0,
                sent = tonumber(r.sent) or 0, failed = tonumber(r.failed) or 0,
                waiting = tonumber(r.waiting) or 0, skipped = tonumber(r.skipped) or 0,
            }
        end
        cb(out, #rows > size)
    end, "SELECT " .. GKEY .. " AS gkey, MIN(kind) AS kind, MIN(sender) AS sender, MIN(subject) AS subject, "
        .. "MIN(created_at) AS created, COUNT(*) AS total, SUM(status = 'sent') AS sent, SUM(status = 'failed') AS failed, "
        .. "SUM(status = 'pending' OR status = 'sending') AS waiting, SUM(status = 'skipped') AS skipped "
        .. "FROM `" .. MAILER.TABLE .. "` GROUP BY gkey ORDER BY created DESC, gkey DESC LIMIT ? OFFSET ?",
        size + 1, math.max(0, math.floor(tonumber(page) or 0)) * size)
end

-- -> { { id, account, language, status, created, sent }, ... }
function MAILDB.group(key, cb)
    if not ensure() or type(key) ~= "string" then return cb(nil) end
    local where, arg = "group_key = ?", key
    local single = key:match("^#(%d+)$")
    if single then where, arg = "id = ?", tonumber(single) end
    MYSQL.query(function(rows)
        if not rows then return cb(nil) end
        local out = {}
        for i, r in ipairs(rows) do
            out[i] = { id = tonumber(r.id), account = r.account_name or "", language = r.language or "",
                       status = r.status, created = tonumber(r.created_at) or 0, sent = tonumber(r.sent_at) or 0 }
        end
        cb(out)
    end, "SELECT id, account_name, language, status, created_at, sent_at FROM `" .. MAILER.TABLE .. "` WHERE "
        .. where .. " ORDER BY account_name, id LIMIT ?", arg, MAILER.HISTORY_MAILS)
end

-- -> { id, subject, body, error, status } | nil
function MAILDB.mail(id, cb)
    if not ensure() or not tonumber(id) then return cb(nil) end
    MYSQL.query(function(rows)
        local r = rows and rows[1]
        if not r then return cb(nil) end
        cb({ id = tonumber(r.id), subject = r.subject or "", body = r.body or "", error = r.error, status = r.status })
    end, "SELECT id, subject, body, error, status FROM `" .. MAILER.TABLE .. "` WHERE id = ?", tonumber(id))
end

--------------------------------------------------------------------------------

addEvent("v_mail:dbReady")
addEvent("mysql:connected")

addEventHandler("onResourceStart", resourceRoot, function()
    if not ensure() then
        outputServerLog("[v_mail] v_mysql not connected yet, `" .. MAILER.TABLE .. "` waits for mysql:connected")
    end
end)

addEventHandler("mysql:connected", root, function()
    ensure()
end)
