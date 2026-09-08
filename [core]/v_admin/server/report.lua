-- ============================================================
--  v_admin / server/report.lua
--  Player <-> admin report system (replaces /pm, /pmv).
--
--    /report   – player: opens a panel, can call an admin,
--                chat inside the report, close it, and see
--                which admin claimed it. One open report / player.
--    /reports  – admin (ADMIN.perms.reports): live list of the
--                active reports, claim, chat, teleport, close.
-- ============================================================

local CFG = ADMIN.report

local reports        = {}   -- id     -> report table
local reportByPlayer = {}   -- player -> id  (the player's single open report)
local nextReportId   = 0

-- ------------------------------------------------------------
--  Helpers
-- ------------------------------------------------------------

local function now()
    local t = getRealTime()
    return string.format("%02d:%02d", t.hour, t.minute)
end

local function trim(text)
    if type(text) ~= "string" then return "" end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if (utf8.len(text) or #text) > CFG.maxLength then
        text = utf8.sub(text, 1, CFG.maxLength)
    end
    return text
end

local function playerReport(player)
    local id = reportByPlayer[player]
    return id and reports[id] or nil
end

local function isReportAdmin(player)
    return hasAdminLevel(player, ADMIN.perms.reports)
end

local function onlineReportAdmins()
    local list = {}
    for _, p in ipairs(getElementsByType("player")) do
        if isReportAdmin(p) then list[#list + 1] = p end
    end
    return list
end

--- Trim the message history to the configured maximum.
local function capHistory(r)
    local overflow = #r.messages - CFG.maxHistory
    if overflow > 0 then
        for _ = 1, overflow do table.remove(r.messages, 1) end
    end
end

local function addMessage(r, who, name, text)
    r.messages[#r.messages + 1] = { who = who, name = name, text = text, time = now() }
    capHistory(r)
end

--- Network-safe snapshot of a report.
local function packReport(r)
    return {
        id            = r.id,
        playerId      = r.playerId,
        playerName    = r.playerName,
        online        = isElement(r.player),
        status        = r.status,            -- "open" | "claimed"
        claimedByName = r.claimedByName,
        messages      = r.messages,
    }
end

local function reportList()
    local list = {}
    for _, r in pairs(reports) do
        list[#list + 1] = packReport(r)
    end
    return list
end

--- Push the current admin list to every online report admin.
local function syncAdmins()
    local list = reportList()
    for _, admin in ipairs(onlineReportAdmins()) do
        triggerClientEvent(admin, ADMIN.events.reportAdminList, resourceRoot, list)
    end
end

--- Push a single report to its owner.
local function syncPlayer(r)
    if isElement(r.player) then
        triggerClientEvent(r.player, ADMIN.events.reportSync, resourceRoot, packReport(r))
    end
end

local function syncAll(r)
    syncPlayer(r)
    syncAdmins()
end

local function ping(player)
    if isElement(player) then
        triggerClientEvent(player, ADMIN.events.reportNotify, player)
    end
end

-- ------------------------------------------------------------
--  Log persistence  (report_logs/<date>-<player>.json + index.json)
-- ------------------------------------------------------------

local LOG_DIR    = CFG.logDir or "report_logs/"
local INDEX_FILE = LOG_DIR .. "index.json"

local function readJSONFile(path)
    if not fileExists(path) then return nil end
    local f = fileOpen(path, true)
    if not f then return nil end
    local raw = fileRead(f, fileGetSize(f)) or ""
    fileClose(f)
    return fromJSON(raw)
end

local function writeJSONFile(path, value)
    local f = fileCreate(path)          -- overwrites if it exists
    if not f then return false end
    -- pretty-print when this MTA build supports it, else compact.
    local ok, pretty = pcall(toJSON, value, false, "tabs")
    fileWrite(f, (ok and pretty) or toJSON(value))
    fileClose(f)
    return true
end

local function logIndex()
    local idx = readJSONFile(INDEX_FILE)
    return (type(idx) == "table") and idx or {}
end

--- Write a closed report to its own JSON file and append to the index.
local function saveReportLog(r)
    if not r or not r.messages or #r.messages == 0 then return end

    local t       = getRealTime()
    local dateStr = string.format("%04d-%02d-%02d", t.year + 1900, t.month + 1, t.monthday)
    local safe    = tostring(r.playerName or "Unknown"):gsub("[^%w%-_]", "_")
    local base    = dateStr .. "-" .. safe

    local name = base .. ".json"
    local n = 1
    while fileExists(LOG_DIR .. name) do
        n = n + 1
        name = base .. "-" .. n .. ".json"
    end

    local msgs = {}
    for _, m in ipairs(r.messages) do
        msgs[#msgs + 1] = {
            sender = (m.who == "system") and "SYSTEM" or m.name,
            text   = m.text,
            time   = tostring(m.time or ""),
        }
    end

    local ok = writeJSONFile(LOG_DIR .. name, {
        info = {
            player       = r.playerName,
            adminClaimed = r.claimedByName or "",
        },
        messages = msgs,
    })
    if not ok then
        outputServerLog("[v_admin] Failed to write report log: " .. name)
        return
    end

    local idx = logIndex()
    idx[#idx + 1] = {
        file   = name,
        player = r.playerName,
        admin  = r.claimedByName or "",
        date   = dateStr,
        closed = t.timestamp,
    }
    writeJSONFile(INDEX_FILE, idx)
end

-- ------------------------------------------------------------
--  Commands
-- ------------------------------------------------------------

addCommandHandler("report", function(player)
    local r = playerReport(player)
    triggerClientEvent(player, ADMIN.events.reportOpen, resourceRoot, r and packReport(r) or false)
end)

addCommandHandler("reports", function(player)
    if not isReportAdmin(player) then
        return denyAccess(player, ADMIN.perms.reports)
    end
    triggerClientEvent(player, ADMIN.events.reportAdminOpen, resourceRoot, reportList())
end)

-- ------------------------------------------------------------
--  Player -> create a report
-- ------------------------------------------------------------
addEvent(ADMIN.events.reportCreate, true)
addEventHandler(ADMIN.events.reportCreate, root, function(text)
    local player = client
    if not isElement(player) then return end

    if playerReport(player) then
        return adminAlert(player, "You already have an open report.", 255, 90, 90)
    end

    text = trim(text)
    if (utf8.len(text) or #text) < CFG.minLength then
        return adminAlert(player, "Please describe your problem first.", 255, 90, 90)
    end

    nextReportId = nextReportId + 1
    local r = {
        id            = nextReportId,
        player        = player,
        playerName    = getPlayerName(player),
        playerId      = tonumber(getElementData(player, "ID")) or 0,
        status        = "open",
        claimedBy     = nil,
        claimedByName = nil,
        messages      = {},
    }
    addMessage(r, "player", r.playerName, text)

    reports[r.id]          = r
    reportByPlayer[player] = r.id

    adminAlert(player, "#55FF55Report sent. An admin will be with you shortly.")

    for _, admin in ipairs(onlineReportAdmins()) do
        adminAlert(admin, "#FFAA00[REPORT] #FFFFFF" .. r.playerName .. " #FFFF00(ID " .. r.playerId ..
            ")#FFFFFF: " .. text .. "  #AAAAAA— /reports", nil, nil, nil, 9000)
        ping(admin)
    end

    syncAll(r)
end)

-- ------------------------------------------------------------
--  Player / admin -> chat message in a report
-- ------------------------------------------------------------
addEvent(ADMIN.events.reportMsg, true)
addEventHandler(ADMIN.events.reportMsg, root, function(id, text)
    local sender = client
    local r = reports[tonumber(id) or 0]
    if not r then return end

    local who
    if sender == r.player then
        who = "player"
    elseif isReportAdmin(sender) then
        who = "admin"
    else
        return
    end

    text = trim(text)
    if text == "" then return end

    -- An admin writing into an unclaimed report claims it.
    if who == "admin" and not (r.claimedBy and isElement(r.claimedBy)) then
        r.claimedBy     = sender
        r.claimedByName = getPlayerName(sender)
        r.status        = "claimed"
        if isElement(r.player) then
            adminAlert(r.player, "#55FF55" .. r.claimedByName .. " #FFFFFFhas claimed your report.")
        end
    end

    addMessage(r, who, getPlayerName(sender), text)

    if who == "player" then
        ping(r.claimedBy)
    else
        ping(r.player)
    end

    syncAll(r)
end)

-- ------------------------------------------------------------
--  Admin -> claim a report
-- ------------------------------------------------------------
addEvent(ADMIN.events.reportClaim, true)
addEventHandler(ADMIN.events.reportClaim, root, function(id)
    local admin = client
    if not isReportAdmin(admin) then return end

    local r = reports[tonumber(id) or 0]
    if not r then return end

    if r.claimedBy and isElement(r.claimedBy) and r.claimedBy ~= admin then
        return adminAlert(admin, "This report is already claimed by " .. r.claimedByName .. ".", 255, 90, 90)
    end

    r.claimedBy     = admin
    r.claimedByName = getPlayerName(admin)
    r.status        = "claimed"
    addMessage(r, "system", "", r.claimedByName .. " claimed this report.")

    if isElement(r.player) then
        adminAlert(r.player, "#55FF55" .. r.claimedByName .. " #FFFFFFhas claimed your report.")
    end

    syncAll(r)
end)

-- ------------------------------------------------------------
--  Player / admin -> close a report
-- ------------------------------------------------------------
--- Remove a report from the tables and refresh the admin panels.
--- `playerAlert` (optional) is shown to the (online) reporter.
local function closeReport(r, playerAlert)
    saveReportLog(r)

    reports[r.id] = nil
    if isElement(r.player) and reportByPlayer[r.player] == r.id then
        reportByPlayer[r.player] = nil
    end

    if isElement(r.player) then
        triggerClientEvent(r.player, ADMIN.events.reportSync, resourceRoot, false)
        if playerAlert then
            adminAlert(r.player, playerAlert)
        end
    end

    syncAdmins()
end

addEvent(ADMIN.events.reportClose, true)
addEventHandler(ADMIN.events.reportClose, root, function(id)
    local sender = client
    local r = reports[tonumber(id) or 0]
    if not r then return end

    if sender == r.player then
        if r.claimedBy and isElement(r.claimedBy) then
            adminAlert(r.claimedBy, "#FFAA00" .. r.playerName .. " closed their own report (#" .. r.id .. ").")
        end
        closeReport(r)  -- no alert: the player did it themselves
    elseif isReportAdmin(sender) then
        closeReport(r, "#FFAA00Your report was closed by " .. getPlayerName(sender) .. ".")
    end
end)

-- ------------------------------------------------------------
--  Admin -> teleport to the reporting player
-- ------------------------------------------------------------
addEvent(ADMIN.events.reportTP, true)
addEventHandler(ADMIN.events.reportTP, root, function(id)
    local admin = client
    if not isReportAdmin(admin) then return end

    local r = reports[tonumber(id) or 0]
    if not r then return end
    if not isElement(r.player) then
        return adminAlert(admin, "That player is offline.", 255, 90, 90)
    end

    local x, y, z = getElementPosition(r.player)
    setElementPosition(admin, x + 1.5, y, z)
    setElementInterior(admin, getElementInterior(r.player))
    setElementDimension(admin, getElementDimension(r.player))

    adminAlert(r.player, "#FFFF00" .. getPlayerName(admin) .. " #FFFFFFteleported to you.")
    adminAlert(admin, "#FFFFFFYou teleported to #FFFF00" .. r.playerName)
end)

-- ------------------------------------------------------------
--  Housekeeping
-- ------------------------------------------------------------

-- Reporter leaves -> close their report.
addEventHandler("onPlayerQuit", root, function()
    local r = playerReport(source)
    if not r then return end
    if r.claimedBy and isElement(r.claimedBy) then
        adminAlert(r.claimedBy, "#FFAA00Reporter " .. r.playerName .. " disconnected — report #" .. r.id .. " closed.")
    end
    closeReport(r)
end)

-- An admin finishes loading -> give them the current list if their panel is open
-- (the panel asks again on /reports, this just keeps an already-open one fresh).
-- onPlayerLoaded, so their synced admin_level is already in place.
addEvent("onPlayerLoaded")
addEventHandler("onPlayerLoaded", root, function()
    if isReportAdmin(source) then
        triggerClientEvent(source, ADMIN.events.reportAdminList, resourceRoot, reportList())
    end
end)

-- ------------------------------------------------------------
--  Admin panel: refresh active list / browse saved logs
-- ------------------------------------------------------------

addEvent(ADMIN.events.reportWantActive, true)
addEventHandler(ADMIN.events.reportWantActive, root, function()
    if not isReportAdmin(client) then return end
    triggerClientEvent(client, ADMIN.events.reportAdminList, resourceRoot, reportList())
end)

addEvent(ADMIN.events.reportLogList, true)
addEventHandler(ADMIN.events.reportLogList, root, function()
    if not isReportAdmin(client) then return end

    local idx = logIndex()
    local out = {}
    for i = #idx, math.max(1, #idx - 200 + 1), -1 do   -- newest first, last 200
        out[#out + 1] = idx[i]
    end
    triggerClientEvent(client, ADMIN.events.reportLogList, resourceRoot, out)
end)

addEvent(ADMIN.events.reportLogOpen, true)
addEventHandler(ADMIN.events.reportLogOpen, root, function(fileName)
    if not isReportAdmin(client) then return end
    if type(fileName) ~= "string" or fileName:find("[/\\]") or fileName:find("%.%.")
        or not fileName:find("%.json$") then
        return
    end

    local data = readJSONFile(LOG_DIR .. fileName)
    if type(data) ~= "table" then
        return adminAlert(client, "Could not read that log file.", 255, 90, 90)
    end
    triggerClientEvent(client, ADMIN.events.reportLogData, resourceRoot, fileName, data)
end)
