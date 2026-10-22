-- Weekly update on Discord: when a new week starts, the week's summary (weekly
-- news, bonuses per category, login bonus, time trial) goes out as an embed
-- through the v_discordmanager webhook WEEKLY.DISCORD_WEBHOOK. Always English.
--
-- Only the v_main server instance WEEKLY.DISCORD_INSTANCE_ID posts, and only
-- once per week: the week is claimed in the weekly_discord table (INSERT
-- IGNORE, unique week_start) and only an insert that went through sends. A server that boots more than
-- WEEKLY.DISCORD_POST_WINDOW after the week start does not post that week.
--
-- /weeklydiscord [offset] (admin level >= WEEKLY.DISCORD_ADMIN_LEVEL) is a test:
-- it sends the embed of the running (or offset-th next) week to
-- WEEKLY.DISCORD_TEST_WEBHOOK at once, without the claim.

if not MYSQL then loadstring(exports.v_mysql:importAsync())() end

DISCORD = {}

local CATEGORY = {
    official  = "🏁 Official Jobs",
    community = "👥 Community Jobs",
    work      = "💼 Work",
}
local FIELD_VALUE = 1024 -- Discord limit of one field value
local BLANK = "\226\128\139" -- zero-width space: name of a follow-up field

local tableReady = false

local function running(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

-- admin level through v_mysql, element data as a fallback
local function adminLevel(player)
    if running("v_mysql") then
        return tonumber(exports.v_mysql:getAccData(player, "admin_level")) or 0
    end
    return tonumber(getElementData(player, "admin_level")) or 0
end

local function str(v) return type(v) == "string" and v ~= "" and v or nil end

-- no MTA colour codes, trimmed
local function plain(text)
    return (tostring(text or ""):gsub("#%x%x%x%x%x%x", ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function money(v)
    local digits = tostring(math.floor(math.abs(tonumber(v) or 0) + 0.5))
    return "€" .. digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

local function mult(n)
    return (("%.2f"):format(tonumber(n) or 1):gsub("0+$", ""):gsub("%.$", "")) .. "x"
end

local function multipliers(m, x)
    local parts = {}
    if (tonumber(m) or 1) > 1 then parts[#parts + 1] = "`" .. mult(m) .. " Money`" end
    if (tonumber(x) or 1) > 1 then parts[#parts + 1] = "`" .. mult(x) .. " XP`" end
    return table.concat(parts, " · ")
end

-- lines -> fields of at most FIELD_VALUE characters; the follow-up fields get a blank name
local function addLineFields(fields, name, lines)
    local cur, curLen, first = {}, 0, true
    local function flush()
        if #cur == 0 then return end
        fields[#fields + 1] = { name = first and name or BLANK, value = table.concat(cur, "\n") }
        cur, curLen, first = {}, 0, false
    end
    for _, line in ipairs(lines) do
        local l = #line + 1
        if curLen + l > FIELD_VALUE then flush() end
        cur[#cur + 1] = line
        curLen = curLen + l
    end
    flush()
end

-- -> the embed of the week starting at ws
function DISCORD.embed(ws)
    local w = PANEL.payload(ws)
    local nextWs = weekStartAt(1, ws + 3.5 * 86400)

    local desc = { ("<t:%d:f> – <t:%d:f>"):format(ws, nextWs) }
    local n = w.news
    if type(n) == "table" and (str(n.title) or str(n.body)) then
        desc[#desc + 1] = ""
        if str(n.title) then desc[#desc + 1] = "**📣 " .. plain(n.title) .. "**" end
        if str(n.body) then desc[#desc + 1] = plain(n.body) end
    end

    local fields = {}
    if #w.bonuses == 0 then
        fields[#fields + 1] = { name = "🎁 Weekly Bonuses", value = "*No bonuses this week.*" }
    end
    for _, c in ipairs(w.bonuses) do
        local lines = {}
        for _, j in ipairs(c.items) do
            lines[#lines + 1] = "**" .. plain(j.name) .. "** — " .. multipliers(j.money, j.xp)
        end
        addLineFields(fields, CATEGORY[c.id] or c.id, lines)
    end

    local lb = w.loginBonus
    if lb then
        local parts = {}
        if (tonumber(lb.money) or 0) > 0 then parts[#parts + 1] = "**" .. money(lb.money) .. "**" end
        if (tonumber(lb.xp) or 0) > 0 then parts[#parts + 1] = "**" .. lb.xp .. " XP**" end
        fields[#fields + 1] = { name = "🎉 Login Bonus", inline = true,
            value = table.concat(parts, " + ") .. "\nonce per " .. (lb.period == "week" and "week" or "day") }
    end

    local tt = w.timetrial
    if tt then
        local lines = { "**" .. plain(tt.name) .. "**" }
        if (tonumber(tt.time) or 0) > 0 then lines[#lines + 1] = "Beat " .. tt.time .. " s" end
        if (tonumber(tt.reward) or 0) > 0 then lines[#lines + 1] = "Reward: " .. money(tt.reward) end
        fields[#fields + 1] = { name = "⏱️ Time Trial", inline = true, value = table.concat(lines, "\n") }
    end

    fields[#fields + 1] = { name = "⏰ Next Update", inline = true, value = ("<t:%d:R>"):format(nextWs) }

    return {
        title = "📅 Weekly Update",
        description = table.concat(desc, "\n"),
        color = WEEKLY.DISCORD_COLOR,
        fields = fields,
        thumbnail = str(WEEKLY.DISCORD_THUMBNAIL) and { url = WEEKLY.DISCORD_THUMBNAIL } or nil,
        footer = { text = str(WEEKLY.DISCORD_FOOTER) or getServerName() },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ", ws),
    }
end

-- true when queued at v_discordmanager
local function send(webhook, ws)
    if not running("v_discordmanager") then
        outputServerLog("[v_weekly] discord: v_discordmanager is not running")
        return false
    end
    -- only the mention of the config may ping
    local mention, mentions = str(WEEKLY.DISCORD_MENTION), {}
    if mention then
        if mention:find("@everyone", 1, true) or mention:find("@here", 1, true) then mentions[#mentions + 1] = "everyone" end
        if mention:find("<@&", 1, true) then mentions[#mentions + 1] = "roles" end
    end
    return exports.v_discordmanager:sendWebhookEmbed(webhook, DISCORD.embed(ws),
        { content = mention, mentions = mentions }) == true
end

local function ensureTable()
    if tableReady then return end
    exports.v_mysql:mysqlQuerySync([[CREATE TABLE IF NOT EXISTS weekly_discord (
        id INT AUTO_INCREMENT PRIMARY KEY,
        week_start INT NOT NULL,
        sent_at INT NOT NULL DEFAULT 0,
        UNIQUE KEY uq_week (week_start)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    tableReady = true
end

-- v_main server instance id, 0 while v_main is not running
local function instanceId()
    if not running("v_main") then return 0 end
    local ok, id = pcall(function() return exports.v_main:getServerInstanceId() end)
    return ok and tonumber(id) or 0
end

-- called by SCHED.check on boot and on every rollover
function DISCORD.weekStarted(ws)
    if not str(WEEKLY.DISCORD_WEBHOOK) then return end
    if getRealTime().timestamp - ws > WEEKLY.DISCORD_POST_WINDOW then return end
    -- only the sending instance posts (v_main starting later calls this again, see below)
    if instanceId() ~= WEEKLY.DISCORD_INSTANCE_ID then return end
    ensureTable()
    -- the insert id is a number only for the instance whose row went in
    MYSQL.insert(function(id)
        if type(id) ~= "number" then return end
        if send(WEEKLY.DISCORD_WEBHOOK, ws) then
            outputServerLog("[v_weekly] discord: weekly update of " .. formatUtc(ws) .. " sent")
        end
    end, "INSERT IGNORE INTO weekly_discord (week_start, sent_at) VALUES (?, ?)", ws, getRealTime().timestamp)
end

-- v_main started after v_weekly: the instance id is known only now
addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) == "v_main" and STORE.isLoaded() then
        setTimer(function() DISCORD.weekStarted(SCHED.currentWeek()) end, 1000, 1)
    end
end)

addCommandHandler("weeklydiscord", function(player, _, offsetArg)
    if adminLevel(player) < WEEKLY.DISCORD_ADMIN_LEVEL then
        return triggerClientEvent(player, "weekly:notify", player, "You do not have permission to use this command.", "Weekly")
    end
    if not STORE.isLoaded() then
        return triggerClientEvent(player, "weekly:notify", player, "The weekly schedule is not loaded yet.", "Weekly")
    end
    local offset = math.floor(tonumber(offsetArg) or 0)
    if offset < 0 or offset >= WEEKLY.ADMIN_WEEKS then
        return triggerClientEvent(player, "weekly:notify", player, "Usage: /weeklydiscord [week offset 0-" .. (WEEKLY.ADMIN_WEEKS - 1) .. "]", "Weekly")
    end
    local ws = weekStartAt(offset)
    if send(WEEKLY.DISCORD_TEST_WEBHOOK, ws) then
        triggerClientEvent(player, "weekly:notify", player, ("Weekly update of %s sent to the '%s' webhook."):format(formatUtc(ws), WEEKLY.DISCORD_TEST_WEBHOOK), "Weekly")
    else
        triggerClientEvent(player, "weekly:notify", player, "Sending failed (is v_discordmanager running and the webhook set?).", "Weekly")
    end
end)
