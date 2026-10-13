if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ============================================================
--  v_admin / server/report.lua
--  Player <-> admin report system (replaces /pm, /pmv).
--
--    /report   – player: opens a panel, can call an admin,
--                chat inside the report, close it, and see
--                which admin claimed it. One open report / player.
--    /reports  – admin (ADMIN.perms.reports): opens the admin
--                panel's Reports tab (client/panel/reports.lua):
--                active reports, claim, chat, teleport, close, logs.
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

-- Account of an admin (player element or web actor) - the identity of a claim.
local function actorAccount(admin)
    if isWebActor(admin) then return admin.account end
    return exports.v_accounts:getName(admin) or false
end

-- Someone holds the claim right now: the claiming player is online, or (web claim)
-- the admin's web session is alive (WebAdmin.accountActive, server/web.lua).
local function claimActive(r)
    if not r.claimedByName then return false end
    if r.claimedBy and isElement(r.claimedBy) then return true end
    return r.claimedAcc and WebAdmin and WebAdmin.accountActive(r.claimedAcc) or false
end

-- The report is claimed by an admin other than `admin`.
local function claimedByOther(r, admin)
    return claimActive(r) and r.claimedAcc ~= actorAccount(admin)
end

local function setClaim(r, admin)
    r.claimedBy     = actorPlayer(admin)
    r.claimedAcc    = actorAccount(admin)
    r.claimedByName = actorName(admin)
    r.status        = "claimed"
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
            sender = (m.who == "system") and L.msg("v_admin.report.system") or m.name,
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
    -- The admin report manager is the admin panel's Reports tab.
    openAdminPanel(player, "reports")
end)

-- ------------------------------------------------------------
--  Player -> create a report
-- ------------------------------------------------------------
addEvent(ADMIN.events.reportCreate, true)
addEventHandler(ADMIN.events.reportCreate, root, function(text)
    local player = client
    if not isElement(player) then return end

    if playerReport(player) then
        return adminAlert(player, L.msg("v_admin.report.you_already_have_open_report"), 255, 90, 90)
    end

    text = trim(text)
    if (utf8.len(text) or #text) < CFG.minLength then
        return adminAlert(player, L.msg("v_admin.report.please_describe_your_problem_first"), 255, 90, 90)
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

    adminAlert(player, L.msg("v_admin.report.report_sent_admin_will_be_with"))

    for _, admin in ipairs(onlineReportAdmins()) do
        adminAlert(admin, L.msg("v_admin.report.report_id_reports", { player_name = r.playerName, player_id = r.playerId, text = text }), nil, nil, nil, 9000)
        ping(admin)
    end

    syncAll(r)
end)

-- ------------------------------------------------------------
--  Player / admin -> chat message in a report
-- ------------------------------------------------------------
--- Admin (player or web actor) writes into a report; an unclaimed report is claimed.
function adminReportMessage(sender, id, text)
    local r = reports[tonumber(id) or 0]
    if not r then return false end

    text = trim(text)
    if text == "" then return false end

    if not claimActive(r) then
        setClaim(r, sender)
        if isElement(r.player) then
            adminAlert(r.player, L.msg("v_admin.report.has_claimed_your_report", { claimed_by_name = r.claimedByName }))
        end
    end

    addMessage(r, "admin", actorName(sender), text)
    ping(r.player)
    syncAll(r)
    return true
end

addEvent(ADMIN.events.reportMsg, true)
addEventHandler(ADMIN.events.reportMsg, root, function(id, text)
    local sender = client
    local r = reports[tonumber(id) or 0]
    if not r then return end

    if sender == r.player then
        text = trim(text)
        if text == "" then return end
        addMessage(r, "player", getPlayerName(sender), text)
        ping(r.claimedBy)
        syncAll(r)
    elseif isReportAdmin(sender) then
        adminReportMessage(sender, id, text)
    end
end)

-- ------------------------------------------------------------
--  Admin -> claim a report
-- ------------------------------------------------------------
function adminReportClaim(admin, id)
    local r = reports[tonumber(id) or 0]
    if not r then return false end

    if claimedByOther(r, admin) then
        adminAlert(admin, L.msg("v_admin.report.this_report_is_already_claimed_by", { claimed_by_name = r.claimedByName }), 255, 90, 90)
        return false
    end

    setClaim(r, admin)
    addMessage(r, "system", "", L.msg("v_admin.report.claimed_this_report", { claimed_by_name = r.claimedByName }))

    if isElement(r.player) then
        adminAlert(r.player, L.msg("v_admin.report.has_claimed_your_report", { claimed_by_name = r.claimedByName }))
    end

    syncAll(r)
    return true
end

addEvent(ADMIN.events.reportClaim, true)
addEventHandler(ADMIN.events.reportClaim, root, function(id)
    if not isReportAdmin(client) then return end
    adminReportClaim(client, id)
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
            adminAlert(r.claimedBy, L.msg("v_admin.report.closed_their_own_report", { player_name = r.playerName, id = r.id }))
        end
        closeReport(r)  -- no alert: the player did it themselves
    elseif isReportAdmin(sender) then
        adminReportClose(sender, id)
    end
end)

function adminReportClose(admin, id)
    local r = reports[tonumber(id) or 0]
    if not r then return false end
    closeReport(r, L.msg("v_admin.report.your_report_was_closed_by", { player = actorName(admin) }))
    return true
end

-- ------------------------------------------------------------
--  Admin -> teleport to the reporting player
-- ------------------------------------------------------------
function adminReportTP(admin, id)
    local r = reports[tonumber(id) or 0]
    if not r then return false end
    if not isElement(r.player) then
        adminAlert(admin, L.msg("v_admin.report.that_player_is_offline"), 255, 90, 90)
        return false
    end
    local me = actorPlayer(admin)
    if not me then
        adminAlert(admin, "You need to be online in game (on this account) to teleport.", 255, 90, 90)
        return false
    end

    local x, y, z = getElementPosition(r.player)
    setElementPosition(me, x + 1.5, y, z)
    setElementInterior(me, getElementInterior(r.player))
    setElementDimension(me, getElementDimension(r.player))

    adminAlert(r.player, L.msg("v_admin.report.teleported_to_you", { player = actorName(admin) }))
    adminAlert(admin, L.msg("v_admin.report.you_teleported_to", { player_name = r.playerName }))
    return true
end

addEvent(ADMIN.events.reportTP, true)
addEventHandler(ADMIN.events.reportTP, root, function(id)
    if not isReportAdmin(client) then return end
    adminReportTP(client, id)
end)

-- ------------------------------------------------------------
--  Housekeeping
-- ------------------------------------------------------------

-- Reporter leaves -> close their report.
addEventHandler("onPlayerQuit", root, function()
    local r = playerReport(source)
    if not r then return end
    if r.claimedBy and isElement(r.claimedBy) then
        adminAlert(r.claimedBy, L.msg("v_admin.report.reporter_disconnected_report_closed", { player_name = r.playerName, id = r.id }))
    end
    closeReport(r)
end)

-- An admin finishes loading -> give them the current list (the panel's Reports
-- tab caches it and asks again whenever it is shown).
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

--- Active reports with every text resolved to English (web panel).
function adminReportListEnglish()
    local list = reportList()
    for _, r in ipairs(list) do
        local msgs = {}
        for i, m in ipairs(r.messages) do
            msgs[i] = { who = m.who, name = m.name, time = m.time, text = L.resolveFor("en", m.text) }
        end
        r.messages = msgs
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

--- Saved report logs, newest first (last 200).
function adminReportLogList()
    local idx = logIndex()
    local out = {}
    for i = #idx, math.max(1, #idx - 200 + 1), -1 do out[#out + 1] = idx[i] end
    return out
end

--- One saved log file, or nil for an invalid name / unreadable file.
function adminReportLogRead(fileName)
    if type(fileName) ~= "string" or fileName:find("[/\]") or fileName:find("%.%.")
        or not fileName:find("%.json$") then
        return nil
    end
    local data = readJSONFile(LOG_DIR .. fileName)
    return type(data) == "table" and data or nil
end

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
        return adminAlert(client, L.msg("v_admin.report.could_not_read_that_log_file"), 255, 90, 90)
    end
    triggerClientEvent(client, ADMIN.events.reportLogData, resourceRoot, fileName, data)
end)
