if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Circulars from admins. The editor is the Mail page of the v_admin panel
-- (v_admin 3.0, /mail opens it there); v_admin checks the admin level
-- (ADMIN.perms.mail) and calls the mailAdmin* exports below. Email addresses
-- never leave this resource: the panel only gets the names of the accounts that
-- have one, and logs name accounts, not addresses.
--
-- A circular has a subject + text per language (every language enabled in
-- v_locals). Every recipient gets one mail of their own (nobody sees the other
-- addresses) in their account language (accData "locale.language"), else its
-- fallback, else English, else the first language that was filled in.
-- In the text "{name}" becomes the account name; a blank line starts a new paragraph.
--
-- The mailAdmin* exports answer later: their first argument is a request id and
-- the answer is triggerEvent("v_admin:remoteResult", <caller resource root>, id, result).
-- A finished circular fires "onMailCircularDone" (admin account, sent, failed, test) on root.

addEvent("v_mail:rows")
addEvent("onMailCircularDone")

local jobs, seq = {}, 0
local running = nil  -- the circular being sent: { admin, total, sent, failed }

local function dbReady()
    local res = getResourceFromName("v_mysql")
    return res and getResourceState(res) == "running" and exports.v_mysql:mysqlIsConnected() == true
end

-- the caller of the running export answers later through this
function answerer()
    local target = sourceResource and getResourceRootElement(sourceResource)
    return function(id, result)
        if isElement(target) then triggerEvent("v_admin:remoteResult", target, id, result) end
    end
end

function adminMessage(ok, key, params)
    return { ok = ok, message = L.msg(key, params) }
end
local message = adminMessage

-- answer rows come back as "v_mail:rows" (requestId, rows | false, info)
local function query(job, sql, ...)
    seq = seq + 1
    jobs[seq] = job
    if not exports.v_mysql:mysqlQueryAsync("v_mail:rows", seq, sql, ...) then
        jobs[seq] = nil
        return false
    end
    return true
end

addEventHandler("v_mail:rows", resourceRoot, function(id, rows)
    local job = jobs[id]
    jobs[id] = nil
    if job then job.done(type(rows) == "table" and rows or nil) end
end)

--------------------------------------------------------------------------------
-- recipients: the names of the accounts with an email
--------------------------------------------------------------------------------

function mailAdminRecipients(id)
    local answer = answerer()
    if not dbReady() then return false end
    return query({ done = function(rows)
        if not rows then return answer(id, message(false, "v_mail.server.database_error")) end
        local names = {}
        for _, r in ipairs(rows) do
            if type(r.account_name) == "string" then names[#names + 1] = r.account_name end
        end
        answer(id, { ok = true, names = names, configured = isMailConfigured() })
    end }, "SELECT account_name FROM `accounts` WHERE email IS NOT NULL AND email <> '' ORDER BY account_name")
end

--------------------------------------------------------------------------------
-- send
--------------------------------------------------------------------------------

function enabledLanguages()
    local out, info = {}, exports.v_locals:getLanguageInfo() or {}
    for _, choice in ipairs(exports.v_locals:getLanguages() or {}) do
        out[#out + 1] = choice.value
    end
    return out, info
end

local function clean(text, multiline)
    text = tostring(text or "")
    if multiline then
        text = text:gsub("\r\n?", "\n"):gsub("[ \t]+\n", "\n")
    else
        text = text:gsub("[\r\n\t]", " ")
    end
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function ulen(s) return utf8.len(s) or #s end

-- texts = { [lang] = { subject, body } } from the client -> { [lang] = { subject, body } } | nil, key, params
local function checkTexts(texts)
    if type(texts) ~= "table" then return nil, "v_mail.server.text_missing" end
    local langs = enabledLanguages()
    local out, any = {}, false
    for _, lang in ipairs(langs) do
        local t = type(texts[lang]) == "table" and texts[lang] or {}
        local subject, body = clean(t.subject, false), clean(t.body, true)
        if subject ~= "" or body ~= "" then
            if subject == "" or body == "" then return nil, "v_mail.server.language_incomplete", { lang = lang:upper() } end
            if ulen(subject) > MAILER.SUBJECT_MAX then
                return nil, "v_mail.server.subject_too_long", { lang = lang:upper(), max = MAILER.SUBJECT_MAX }
            end
            if ulen(body) > MAILER.BODY_MAX then
                return nil, "v_mail.server.text_too_long", { lang = lang:upper(), max = MAILER.BODY_MAX }
            end
            out[lang] = { subject = subject, body = body }
            any = true
        end
    end
    if not any then return nil, "v_mail.server.text_missing" end
    return out
end

-- the language of the account from a piece of its account_data JSON
function rowLanguage(snippet)
    if type(snippet) ~= "string" then return nil end
    return snippet:match('^"locale%.language"%s*:%s*%[?%s*{[^}]-"v"%s*:%s*"([%w_%-]+)"')
end

function pickLanguage(lang, texts, info)
    local seen = {}
    while lang and not seen[lang] do
        if texts[lang] then return lang end
        seen[lang] = true
        lang = info[lang] and info[lang].fallback
    end
    if texts.en then return "en" end
    for _, l in ipairs((enabledLanguages())) do
        if texts[l] then return l end
    end
end

local function paragraphs(body, account)
    body = body:gsub("{name}", function() return account end)
    local out = {}
    for p in (body .. "\n\n"):gmatch("(.-)\n%s*\n") do
        p = p:gsub("^%s+", ""):gsub("%s+$", "")
        if p ~= "" then out[#out + 1] = p end
    end
    return out
end

local function finish(c)
    outputServerLog(("[v_mail] circular of %s finished: %d sent, %d failed"):format(c.admin, c.sent, c.failed))
    if running == c then running = nil end
    triggerEvent("onMailCircularDone", root, c.admin, c.sent, c.failed, c.test == true)
end

-- -> { ok, message }
local function sendRows(admin, rows, texts, test)
    local _, info = enabledLanguages()
    local c = { admin = admin, total = 0, sent = 0, failed = 0, answered = 0, test = test }
    if not test then running = c end
    local function onDone(ok)
        c.answered = c.answered + 1
        if ok then c.sent = c.sent + 1 else c.failed = c.failed + 1 end
        if c.complete and c.answered == c.total then finish(c) end
    end
    local refused = 0
    -- the mails of one circular share a group in the `mails` table (a test mail stands alone)
    local group = not test and ("circular:%d:%s"):format(getRealTime().timestamp, admin):sub(1, 64) or nil
    for _, r in ipairs(rows) do
        local lang = pickLanguage(rowLanguage(r.loc), texts, info)
        local t = texts[lang]
        if t and type(r.account_name) == "string" and validEmail(r.email) then
            local queued = queueMail({
                to = r.email,
                toName = r.account_name,
                subject = t.subject:gsub("{name}", function() return r.account_name end),
                bulk = not test,
                template = {
                    title = t.subject:gsub("{name}", function() return r.account_name end),
                    paragraphs = paragraphs(t.body, r.account_name),
                    note = exports.v_locals:translate(lang, "v_mail.mail.footer", { account = r.account_name }),
                },
                log = { kind = test and "test" or "circular", group = group, account = r.account_name,
                        language = lang, sender = admin },
            }, onDone, "v_mail /" .. MAILER.COMMAND)
            if queued then c.total = c.total + 1 else refused = refused + 1 end
        end
    end
    outputServerLog(("[v_mail] %s %s: %d mails queued, %d refused"):format(admin,
        test and "sent a test circular" or "sent a circular", c.total, refused))
    if c.total == 0 then
        if running == c then running = nil end
        return message(false, "v_mail.server.nothing_sent")
    end
    c.complete = true -- an answer can only finish the circular once every mail is queued
    if c.answered == c.total then finish(c) end
    return message(true, test and "v_mail.server.test_queued" or "v_mail.server.queued", { count = c.total })
end

-- mode = "all" | "selected" | "test"; names = { accountName, ... } for "selected";
-- admin = the sending admin's account name (the test goes to its email). Answer: { ok, message }
function mailAdminSend(id, admin, mode, names, texts)
    local answer = answerer()
    local function done(ok, key, params) answer(id, message(ok, key, params)) end
    admin = type(admin) == "string" and admin ~= "" and admin or nil
    if not admin then done(false, "v_mail.server.no_own_email") return true end
    if not isMailConfigured() then done(false, "v_mail.server.not_configured") return true end
    if not dbReady() then done(false, "v_mail.server.database_error") return true end
    local checked, key, params = checkTexts(texts)
    if not checked then done(false, key, params) return true end

    local cols = "SELECT account_name, email, SUBSTRING(account_data, LOCATE('\"locale.language\"', account_data), 120) AS loc "
        .. "FROM `accounts` WHERE email IS NOT NULL AND email <> ''"
    if mode == "test" then
        if not query({ done = function(rows)
            if not rows then return done(false, "v_mail.server.database_error") end
            if not rows[1] then return done(false, "v_mail.server.no_own_email") end
            answer(id, sendRows(admin, rows, checked, true))
        end }, cols .. " AND account_name = ? LIMIT 1", admin) then done(false, "v_mail.server.database_error") end
        return true
    end

    if running then done(false, "v_mail.server.busy", { admin = running.admin }) return true end
    local wanted = nil
    if mode == "selected" then
        if type(names) ~= "table" or #names == 0 or #names > MAILER.MAX_SELECTED then
            done(false, "v_mail.server.no_recipients")
            return true
        end
        wanted = {}
        for _, n in ipairs(names) do
            if type(n) == "string" then wanted[n:lower()] = true end
        end
    elseif mode ~= "all" then
        return false
    end

    running = { admin = admin } -- holds the slot until the rows arrive
    local slot = running
    if not query({ done = function(rows)
        if running == slot then running = nil end
        if not rows then return done(false, "v_mail.server.database_error") end
        if running then return done(false, "v_mail.server.busy", { admin = running.admin }) end
        local list = {}
        for _, r in ipairs(rows) do
            if not wanted or (type(r.account_name) == "string" and wanted[r.account_name:lower()]) then
                list[#list + 1] = r
            end
        end
        if #list == 0 then return done(false, "v_mail.server.no_recipients") end
        if #list + queuedMailCount() > MAIL.MAX_QUEUE then
            return done(false, "v_mail.server.too_many", { count = #list, max = MAIL.MAX_QUEUE - queuedMailCount() })
        end
        answer(id, sendRows(admin, list, checked, false))
    end }, cols) then
        running = nil
        done(false, "v_mail.server.database_error")
    end
    return true
end

--------------------------------------------------------------------------------
-- history: the mails the server sent (`mails` table, server/store.lua)
--------------------------------------------------------------------------------

local function stamp(ts)
    ts = tonumber(ts) or 0
    return ts > 0 and os.date("!%Y.%m.%d %H:%M", ts) or ""
end

-- -> { ok, groups, more, page }
function mailAdminHistory(id, page)
    local answer = answerer()
    page = math.max(0, math.floor(tonumber(page) or 0))
    MAILDB.groups(page, function(groups, more)
        if not groups then return answer(id, message(false, "v_mail.server.database_error")) end
        for _, g in ipairs(groups) do g.date = stamp(g.created) end
        answer(id, { ok = true, groups = groups, more = more == true, page = page })
    end)
    return true
end

-- -> { ok, key, mails }
function mailAdminGroup(id, key)
    local answer = answerer()
    if type(key) ~= "string" then return false end
    MAILDB.group(key, function(mails)
        if not mails then return answer(id, message(false, "v_mail.server.database_error")) end
        for _, m in ipairs(mails) do m.date = stamp(m.sent > 0 and m.sent or m.created) end
        answer(id, { ok = true, key = key, mails = mails })
    end)
    return true
end

-- -> { ok, mail = { id, subject, body, error, status } }
function mailAdminMail(id, mailId)
    local answer = answerer()
    MAILDB.mail(mailId, function(mail)
        if not mail then return answer(id, message(false, "v_mail.server.database_error")) end
        answer(id, { ok = true, mail = mail })
    end)
    return true
end

--------------------------------------------------------------------------------
-- retry: the failed mails of a history group (or one mail) go out again
--------------------------------------------------------------------------------

local RETRY_MAX = 500
local NO_RETRY = { password_reset = true, test = true }   -- a reset code is masked in the stored text

-- key = a history group key ("#<id>" = one mail). The stored plain text is sent
-- again to the account's CURRENT email; the same row gets the new answer.
-- Answer: { ok, message, count }
function mailAdminRetry(id, admin, key)
    local answer = answerer()
    local function done(ok, k, params, count) local r = message(ok, k, params) r.count = count answer(id, r) end
    if type(key) ~= "string" or key == "" then return false end
    if not isMailConfigured() then done(false, "v_mail.server.not_configured") return true end
    if not dbReady() then done(false, "v_mail.server.database_error") return true end
    local where, arg = "group_key = ?", key
    local single = key:match("^#(%d+)$")
    if single then where, arg = "id = ?", tonumber(single) end

    MYSQL.query(function(rows)
        if not rows then return done(false, "v_mail.server.database_error") end
        local list, names, seen = {}, {}, {}
        for _, r in ipairs(rows) do
            if not NO_RETRY[r.kind] and type(r.account_name) == "string" and type(r.body) == "string" and r.body ~= "" then
                list[#list + 1] = r
                if not seen[r.account_name] then seen[r.account_name] = true names[#names + 1] = r.account_name end
            end
        end
        if #list == 0 then return done(false, "v_mail.server.retry_nothing") end
        MYSQL.query(function(accounts)
            if not accounts then return done(false, "v_mail.server.database_error") end
            local email = {}
            for _, a in ipairs(accounts) do email[a.account_name] = a.email end
            local queued = 0
            for _, r in ipairs(list) do
                local to = email[r.account_name]
                if validEmail(to) then
                    MYSQL.query(nil, "UPDATE `" .. MAILER.TABLE .. "` SET status = 'sending', error = NULL WHERE id = ?", tonumber(r.id))
                    local ok, err = queueMail({ to = to, toName = r.account_name, subject = r.subject, text = r.body,
                        bulk = true, log = { rowId = tonumber(r.id) } }, nil, "v_mail retry")
                    if ok then queued = queued + 1 else MAILDB.finish(tonumber(r.id), "failed", err) end
                else
                    MAILDB.finish(tonumber(r.id), "skipped", "the account has no email any more")
                end
            end
            outputServerLog(("[v_mail] %s retried %d failed mail(s) of %s"):format(tostring(admin), queued, key))
            done(queued > 0, queued > 0 and "v_mail.server.retry_queued" or "v_mail.server.retry_nothing", { count = queued }, queued)
        end, "SELECT account_name, email FROM `accounts` WHERE account_name IN (" .. ("?,"):rep(#names):sub(1, -2) .. ")", unpack(names))
    end, "SELECT id, kind, account_name, subject, body FROM `" .. MAILER.TABLE .. "` WHERE " .. where
        .. " AND status = 'failed' ORDER BY id LIMIT ?", arg, RETRY_MAX)
    return true
end
