if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Weekly update mail. Every Tuesday UPDATES.HOUR:00 UTC the news of the last
-- UPDATES.NEWS_DAYS days (v_news) and the running week (v_weekly: weekly news,
-- Job multipliers, login bonus, time trial) go to every account with an email
-- whose accData receiveUpdateMails is not false, in the account's language.
--
-- Only the v_main server instance UPDATES.INSTANCE_ID does this; on any other
-- instance this file does nothing (the exports below work everywhere).
--
-- A run first stores every mail in the `mails` table as "pending" (group
-- "updates:<run timestamp>"), then sends at most UPDATES.DAILY_LIMIT of them in
-- any 24 hours; the rest waits there (also across restarts) for the next day.

addEvent("v_mail:setUpdates", true)
addEvent("v_mail:updatesReady", true)
addEvent("onPlayerAccountLogin")

local DAY = 86400
local KIND = "updates"
local FROM = "v_mail updates"
local INSERT_CHUNK = 25

local busy = false       -- a step is waiting for MySQL or Brevo
local doneRun = nil      -- the run already handled since the start
local recovered = false  -- "sending" rows of a stopped run were put back to "pending"

local function now() return getRealTime().timestamp end

local function running(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

--------------------------------------------------------------------------------
-- receiveUpdateMails (accData boolean, missing = true)
--------------------------------------------------------------------------------

-- accounts.account_data snippet starting at the key (see the SELECTs below)
local function optedOut(snippet)
    return type(snippet) == "string"
        and snippet:match('^"' .. UPDATES.SETTING_KEY .. '"%s*:%s*%[?%s*{[^}]-"v"%s*:%s*"false"') ~= nil
end

local SNIPPET = "SUBSTRING(account_data, LOCATE('\"" .. UPDATES.SETTING_KEY .. "\"', account_data), 80) AS upd"

local function accountOf(who)
    if type(who) == "string" then return who ~= "" and who or nil end
    if isElement(who) and getElementData(who, "isLogged") == true then
        local n = getElementData(who, "accName")
        return type(n) == "string" and n ~= "" and n or nil
    end
end

local function playerOf(name)
    for _, p in ipairs(getElementsByType("player")) do
        if getElementData(p, "accName") == name then return p end
    end
end

-- who = player | account name -> bool
function getReceiveUpdateMails(who)
    local name = accountOf(who)
    if not name then return false end
    return exports.v_mysql:getAccData(name, UPDATES.SETTING_KEY) ~= false
end

local function push(player)
    if isElement(player) and accountOf(player) then
        triggerClientEvent(player, "v_mail:updatesSetting", player, getReceiveUpdateMails(player))
    end
end

-- who = player | account name -> bool (saved)
function setReceiveUpdateMails(who, enabled)
    local name = accountOf(who)
    if not name then return false end
    if not exports.v_mysql:setAccData(name, UPDATES.SETTING_KEY, enabled == true) then return false end
    push(isElement(who) and who or playerOf(name))
    return true
end

addEventHandler("v_mail:setUpdates", root, function(enabled)
    if not accountOf(client) then return end
    setReceiveUpdateMails(client, enabled == true)
end)

addEventHandler("v_mail:updatesReady", root, function() push(client) end)
addEventHandler("onPlayerAccountLogin", root, function() push(source) end)

--------------------------------------------------------------------------------
-- content
--------------------------------------------------------------------------------

-- UTC timestamp of the latest run (Tuesday HOUR:00) at or before ts.
-- 1970-01-01 was a Thursday: weekday = (days + 4) % 7, 0 = Sunday.
local function runFor(ts)
    local days = math.floor(ts / DAY)
    local back = ((days + 4) % 7 - UPDATES.WEEK_DAY) % 7
    if back == 0 and ts - days * DAY < UPDATES.HOUR * 3600 then back = 7 end
    return (days - back) * DAY + UPDATES.HOUR * 3600
end

local function T(lang, key, params)
    return exports.v_locals:translate(lang, "v_mail.updates." .. key, params)
end

local function plain(text)
    return (tostring(text or ""):gsub("#%x%x%x%x%x%x", ""))
end

local function money(v)
    local digits = tostring(math.floor(math.abs(tonumber(v) or 0) + 0.5))
    return "€" .. digits:reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", "")
end

local function str(v) return type(v) == "string" and v ~= "" and v or nil end

local function collect(run)
    local news = {}
    if running("v_news") then
        local list = exports.v_news:getLatestNews(UPDATES.NEWS_MAX)
        for _, a in ipairs(type(list) == "table" and list or {}) do
            if tonumber(a.date) and a.date >= run - UPDATES.NEWS_DAYS * DAY and a.date <= now() then
                news[#news + 1] = a
            end
        end
    end
    local week = running("v_weekly") and exports.v_weekly:getWeeklyInfo(0) or nil
    if type(week) ~= "table" then week = nil end
    if week then
        local n = week.news
        week.hasNews = type(n) == "table" and (str(n.title) or str(n.body)) and true or false
        week.empty = not week.hasNews and (tonumber(week.bonusCount) or #(week.jobs or {})) == 0 and not week.loginBonus and not week.timetrial
    end
    return news, week
end

local function multipliers(lang, m, x)
    local parts = {}
    if (tonumber(m) or 1) > 1 then parts[#parts + 1] = T(lang, "x_money", { x = m }) end
    if (tonumber(x) or 1) > 1 then parts[#parts + 1] = T(lang, "x_xp", { x = x }) end
    return table.concat(parts, ", ")
end

-- -> { subject, paragraphs } of one language
local function content(lang, run, news, week)
    local p = { T(lang, "intro", { days = UPDATES.NEWS_DAYS }) }
    if #news > 0 then
        p[#p + 1] = { heading = T(lang, "news") }
        for _, a in ipairs(news) do
            -- the article in the mail's language, else v_news' default pick (English or the first written)
            local t = type(a.texts) == "table" and a.texts[lang] or a
            p[#p + 1] = { title = plain(t.title), text = os.date("!%Y.%m.%d", a.date) .. "\n" .. plain(t.body) }
        end
    end
    if week and not week.empty then
        p[#p + 1] = { heading = T(lang, "week", { from = week.from, to = week.to }) }
        if week.hasNews then p[#p + 1] = { title = plain(week.news.title), text = plain(week.news.body) } end
        -- one block per bonus category: Official Jobs, Community Jobs, Work
        for _, c in ipairs(week.bonuses or {}) do
            local lines = {}
            for _, j in ipairs(c.items) do
                lines[#lines + 1] = "• " .. plain(j.name) .. ": " .. multipliers(lang, j.money, j.xp)
            end
            p[#p + 1] = { title = T(lang, "bonus_" .. c.id), text = table.concat(lines, "\n") }
        end
        local b = week.loginBonus
        if b then
            local parts = {}
            if (tonumber(b.money) or 0) > 0 then parts[#parts + 1] = money(b.money) end
            if (tonumber(b.xp) or 0) > 0 then parts[#parts + 1] = b.xp .. " XP" end
            p[#p + 1] = { title = T(lang, "login_bonus"),
                          text = T(lang, b.period == "week" and "login_bonus_week" or "login_bonus_day", { reward = table.concat(parts, " + ") }) }
        end
        local tt = week.timetrial
        if tt then
            local text = plain(tt.name)
            if tonumber(tt.reward) and tt.reward > 0 then text = text .. "\n" .. T(lang, "reward", { reward = money(tt.reward) }) end
            p[#p + 1] = { title = T(lang, "timetrial"), text = text }
        end
    end
    return { subject = T(lang, "subject", { date = os.date("!%Y.%m.%d", run) }), paragraphs = p }
end

--------------------------------------------------------------------------------
-- run: store every mail as pending
--------------------------------------------------------------------------------

local sendDue -- below

local function release()
    busy = false
end

local function insertChunks(list, i, done)
    if i > #list then return done(true) end
    local marks, args = {}, {}
    for k = i, math.min(#list, i + INSERT_CHUNK - 1) do
        marks[#marks + 1] = "(?,?,?,?,?,?,?,?,?,?,?,?)"
        for _, v in ipairs(list[k]) do args[#args + 1] = v end
    end
    MYSQL.insert(function(id, err)
        if not id then
            outputServerLog("[v_mail] weekly update: storing the mails failed: " .. tostring(err))
            return done(false)
        end
        insertChunks(list, i + INSERT_CHUNK, done)
    end, "INSERT INTO `" .. MAILER.TABLE .. "` (group_key, kind, sender, server_id, account_name, language, subject, "
        .. "body, template, status, created_at, sent_at) VALUES " .. table.concat(marks, ","), unpack(args))
end

local function build(run)
    local news, week = collect(run)
    if #news == 0 and (not week or week.empty) then
        outputServerLog("[v_mail] weekly update: no news and no weekly content, nothing to send")
        doneRun = run
        return release()
    end
    local langs, info = enabledLanguages()
    local available = {}
    for _, l in ipairs(langs) do available[l] = true end
    MYSQL.query(function(rows)
        if not rows then return release() end
        local group, t, serverId = "updates:" .. run, now(), MAILDB.serverId()
        local byLang, list = {}, {}
        for _, r in ipairs(rows) do
            local name = r.account_name
            if type(name) == "string" and not optedOut(r.upd) then
                local lang = pickLanguage(rowLanguage(r.loc), available, info) or "en"
                byLang[lang] = byLang[lang] or content(lang, run, news, week)
                local c = byLang[lang]
                local tpl = {
                    title = c.subject,
                    greeting = T(lang, "greeting", { account = name }),
                    paragraphs = c.paragraphs,
                    note = T(lang, "footer", { account = name }),
                }
                list[#list + 1] = { group, KIND, FROM, serverId, name, lang, c.subject,
                                    (renderTemplate(tpl)), toJSON(tpl, true), "pending", t, 0 }
            end
        end
        if #list == 0 then
            outputServerLog("[v_mail] weekly update: no account wants it")
            doneRun = run
            return release()
        end
        insertChunks(list, 1, function(ok)
            if ok then
                outputServerLog(("[v_mail] weekly update %s: %d mails stored, at most %d go out per 24 hours")
                    :format(os.date("!%Y.%m.%d", run), #list, UPDATES.DAILY_LIMIT))
            end
            doneRun = run -- a broken run is not repeated (a part of it may be stored already)
            release()
            setTimer(function() if not busy then sendDue() end end, 1000, 1)
        end)
    end, "SELECT account_name, SUBSTRING(account_data, LOCATE('\"locale.language\"', account_data), 120) AS loc, "
        .. SNIPPET .. " FROM `accounts` WHERE email IS NOT NULL AND email <> ''")
end

--------------------------------------------------------------------------------
-- send the pending ones, DAILY_LIMIT per 24 hours
--------------------------------------------------------------------------------

local function inList(n)
    return ("?,"):rep(n):sub(1, -2)
end

local function sendRows(list)
    local ids, names = {}, {}
    for _, r in ipairs(list) do
        ids[#ids + 1] = tonumber(r.id)
        names[#names + 1] = r.account_name or ""
    end
    MYSQL.query(function(marked)
        if not marked then return release() end
        MYSQL.query(function(accounts)
            if not accounts then
                MYSQL.query(release, "UPDATE `" .. MAILER.TABLE .. "` SET status = 'pending', sent_at = 0 WHERE id IN ("
                    .. inList(#ids) .. ") AND status = 'sending'", unpack(ids))
                return
            end
            local byName = {}
            for _, a in ipairs(accounts) do
                if type(a.account_name) == "string" then byName[a.account_name] = a end
            end
            local left, sent, failed, skipped = #list, 0, 0, 0
            local function one(status)
                if status == "sent" then sent = sent + 1 elseif status == "skipped" then skipped = skipped + 1 else failed = failed + 1 end
                left = left - 1
                if left > 0 then return end
                outputServerLog(("[v_mail] weekly update: %d sent, %d failed, %d skipped"):format(sent, failed, skipped))
                release()
            end
            for _, r in ipairs(list) do
                local acc = byName[r.account_name]
                local tpl = type(r.template) == "string" and fromJSON(r.template) or nil
                if not acc or not validEmail(acc.email) then
                    MAILDB.finish(r.id, "skipped", "the account has no email any more")
                    one("skipped")
                elseif optedOut(acc.upd) then
                    MAILDB.finish(r.id, "skipped", "receiveUpdateMails turned off")
                    one("skipped")
                elseif type(tpl) ~= "table" then
                    MAILDB.finish(r.id, "failed", "stored template unreadable")
                    one("failed")
                else
                    -- the mail addresses the player by display name, applied only now: the
                    -- stored rows keep the account name
                    if type(acc.display_name) == "string" and acc.display_name ~= "" and type(r.language) == "string" and r.language ~= "" then
                        tpl.greeting = T(r.language, "greeting", { account = acc.display_name })
                    end
                    local queued, err = queueMail({
                        to = acc.email, toName = r.account_name, subject = r.subject, template = tpl,
                        bulk = true, log = { rowId = r.id },
                    }, function(ok) one(ok and "sent" or "failed") end, FROM)
                    if not queued then
                        MAILDB.finish(r.id, "failed", err)
                        one("failed")
                    end
                end
            end
        end, "SELECT account_name, display_name, email, " .. SNIPPET .. " FROM `accounts` WHERE account_name IN (" .. inList(#names) .. ")",
            unpack(names))
    end, "UPDATE `" .. MAILER.TABLE .. "` SET status = 'sending', sent_at = ? WHERE id IN (" .. inList(#ids)
        .. ") AND status = 'pending'", now(), unpack(ids))
end

sendDue = function()
    busy = true
    MYSQL.query(function(rows)
        if not rows then return release() end
        local room = UPDATES.DAILY_LIMIT - (tonumber(rows[1] and rows[1].n) or 0)
        if room <= 0 then return release() end
        MYSQL.query(function(list)
            if not list or #list == 0 then return release() end
            sendRows(list)
        end, "SELECT id, account_name, language, subject, template FROM `" .. MAILER.TABLE
            .. "` WHERE kind = ? AND status = 'pending' ORDER BY id LIMIT ?", KIND, room)
    end, "SELECT COUNT(*) AS n FROM `" .. MAILER.TABLE .. "` WHERE kind = ? AND status IN ('sending', 'sent') AND sent_at > ?",
        KIND, now() - DAY)
end

--------------------------------------------------------------------------------
-- schedule
--------------------------------------------------------------------------------

local function tick()
    if busy or not MAILDB.isReady() or not isMailConfigured() then return end
    if MAILDB.serverId() ~= UPDATES.INSTANCE_ID then return end
    busy = true
    if not recovered then
        -- the answers of a stopped resource never come: send those again
        recovered = true
        return MYSQL.query(release, "UPDATE `" .. MAILER.TABLE .. "` SET status = 'pending', sent_at = 0 "
            .. "WHERE kind = ? AND status = 'sending'", KIND)
    end
    local run = runFor(now())
    if doneRun ~= run and now() - run < UPDATES.CATCH_UP then
        return MYSQL.query(function(rows)
            if not rows then return release() end
            if (tonumber(rows[1] and rows[1].n) or 0) > 0 then
                doneRun = run
                return sendDue()
            end
            build(run)
        end, "SELECT COUNT(*) AS n FROM `" .. MAILER.TABLE .. "` WHERE group_key = ?", "updates:" .. run)
    end
    sendDue()
end

setTimer(tick, UPDATES.CHECK_INTERVAL, 0)
addEventHandler("v_mail:dbReady", resourceRoot, function() setTimer(tick, 5000, 1) end)

--------------------------------------------------------------------------------
-- v_admin Mail page (exports; answers through answerer(), server/circular.lua)
--------------------------------------------------------------------------------

-- -> { ok, configured, queued, instance, sendingInstance, isSender, nextRun, dailyLimit,
--      pending, sent24h, failed24h, lastRun = { group, total, sent, failed, waiting, skipped } | false }
function mailAdminStatus(id)
    local answer = answerer()
    local t = now()
    local function done(counts, last)
        answer(id, {
            ok = true, configured = isMailConfigured(), queued = queuedMailCount(),
            instance = MAILDB.serverId(), sendingInstance = UPDATES.INSTANCE_ID,
            isSender = MAILDB.serverId() == UPDATES.INSTANCE_ID,
            nextRun = runFor(t) + 7 * DAY, lastRunAt = runFor(t), dailyLimit = UPDATES.DAILY_LIMIT,
            pending = tonumber(counts and counts.pending) or 0, sent24h = tonumber(counts and counts.sent24) or 0,
            failed24h = tonumber(counts and counts.failed24) or 0, lastRun = last or false,
        })
    end
    if not MAILDB.isReady() then done() return true end
    MYSQL.query(function(rows)
        local counts = rows and rows[1]
        MYSQL.query(function(g)
            local r = g and g[1]
            done(counts, r and {
                group = r.group_key, total = tonumber(r.total) or 0, sent = tonumber(r.sent) or 0,
                failed = tonumber(r.failed) or 0, waiting = tonumber(r.waiting) or 0, skipped = tonumber(r.skipped) or 0,
            } or nil)
        end, "SELECT group_key, COUNT(*) AS total, SUM(status = 'sent') AS sent, SUM(status = 'failed') AS failed, "
            .. "SUM(status = 'pending' OR status = 'sending') AS waiting, SUM(status = 'skipped') AS skipped FROM `" .. MAILER.TABLE
            .. "` WHERE kind = ? GROUP BY group_key ORDER BY MIN(created_at) DESC LIMIT 1", KIND)
    end, "SELECT SUM(status = 'pending') AS pending, SUM(status = 'sent' AND sent_at > ?) AS sent24, "
        .. "SUM(status = 'failed' AND sent_at > ?) AS failed24 FROM `" .. MAILER.TABLE .. "` WHERE kind = ?", t - DAY, t - DAY, KIND)
    return true
end

-- The weekly update mail as it would go out now (news of the last NEWS_DAYS days +
-- the running week), to the admin's own account email only, in `lang` (or the
-- account language). Not a part of any run, not counted in DAILY_LIMIT; works on
-- every server instance. Answer: { ok, message }
function mailAdminUpdateTest(id, account, lang)
    local answer = answerer()
    local function done(ok, key, params) answer(id, adminMessage(ok, key, params)) end
    if type(account) ~= "string" or account == "" then done(false, "v_mail.server.no_own_email") return true end
    if not isMailConfigured() then done(false, "v_mail.server.not_configured") return true end
    local run = runFor(now())
    local news, week = collect(run)
    local langs, info = enabledLanguages()
    local available = {}
    for _, l in ipairs(langs) do available[l] = true end
    MYSQL.query(function(rows)
        local r = rows and rows[1]
        if not rows then return done(false, "v_mail.server.database_error") end
        if not r or not validEmail(r.email) then return done(false, "v_mail.server.no_own_email") end
        local l = available[lang] and lang or pickLanguage(rowLanguage(r.loc), available, info) or "en"
        local c = content(l, run, news, week)
        local queued, err = queueMail({
            to = r.email, toName = account, subject = c.subject,
            template = {
                title = c.subject,
                greeting = T(l, "greeting", { account = account }),
                paragraphs = c.paragraphs,
                note = T(l, "footer", { account = account }),
            },
            log = { kind = "test", account = account, language = l, sender = account },
        }, nil, FROM .. " (test)")
        if not queued then return done(false, "v_mail.server.update_test_failed", { reason = tostring(err) }) end
        outputServerLog(("[v_mail] test weekly update (%s) queued for %s"):format(l, account))
        done(true, "v_mail.server.update_test_queued", { lang = l:upper() })
    end, "SELECT email, SUBSTRING(account_data, LOCATE('\"locale.language\"', account_data), 120) AS loc FROM `accounts` WHERE account_name = ? LIMIT 1",
        account)
    return true
end
