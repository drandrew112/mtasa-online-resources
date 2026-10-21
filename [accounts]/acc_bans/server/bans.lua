if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Account bans
--
-- Bans live in the shared MySQL `bans` table (through v_mysql), so a ban made
-- on one server applies on every server using the same database. They are
-- keyed by ACCOUNT NAME. When the banned player is online at ban time their
-- SERIAL (and IP, for the record) is stored too, so a fresh account on the same
-- machine is caught on join as well. There are no temporary bans: a row is
-- active while lifted_at = 0.
--
-- The active rows are cached here and re-read every BAN_REFRESH ms (async), so
-- join/login checks never wait on the database. After each refresh the online
-- players are re-checked, which picks up bans / unbans made on another server.
--
-- The ban panel is drawn by acc_ui: the client gets
--   acc_bans:onClientBanState (banned)   -- source = the player
-- and reads the details from the banned_* element data.

local BAN_TABLE   = "bans"
local BAN_REFRESH = 30000

local activeBans = {}   -- { { id, account, serial, date, admin, reason }, ... }

local function resourceRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function banDbReady()
    if not resourceRunning("v_mysql") then return false end
    return exports.v_mysql:mysqlIsConnected() == true
end

-- logged-in account name (element data set by acc_auth), or nil
local function nameOf(player)
    if not isElement(player) or getElementData(player, "isLogged") ~= true then return nil end
    local n = getElementData(player, "accName")
    return (type(n) == "string" and n ~= "") and n or nil
end

local function playerOnAccount(accountName)
    local needle = accountName:lower()
    for _, player in ipairs(getElementsByType("player")) do
        local n = nameOf(player)
        if n and n:lower() == needle then return player end
    end
    return nil
end

-- canonical account name (acc_auth knows the accounts table), or false
local function canonicalName(accountName)
    if not resourceRunning("acc_auth") then return false end
    return exports.acc_auth:accountNameExists(accountName)
end

local function dateString(timestamp)
    local ts = tonumber(timestamp)
    local t = ts and getRealTime(ts) or getRealTime()
    return ("%04d.%02d.%02d"):format(t.year + 1900, t.month + 1, t.monthday)
end

local function nonEmpty(v)
    return (type(v) == "string" and v ~= "") and v or nil
end

local function rowToBan(row)
    return {
        id      = tonumber(row.id),
        account = nonEmpty(row.account_name),
        serial  = nonEmpty(row.serial),
        date    = dateString(row.created_at),
        admin   = nonEmpty(row.admin)  or "n/a",
        reason  = nonEmpty(row.reason) or "n/a",
    }
end

local BAN_SELECT = "SELECT id, account_name, serial, admin, reason, created_at FROM `"
    .. BAN_TABLE .. "` WHERE lifted_at = 0"

local function setActiveBans(rows)
    local list = {}
    for _, row in ipairs(rows) do list[#list + 1] = rowToBan(row) end
    activeBans = list
end

local function findBan(serial, accountName)
    local needle = type(accountName) == "string" and accountName:lower() or nil
    for _, ban in ipairs(activeBans) do
        if (serial and ban.serial == serial)
        or (needle and ban.account and ban.account:lower() == needle) then
            return ban
        end
    end
    return nil
end

-- Exported. The active ban matching this serial or account name, or false.
function getActiveBan(serial, accountName)
    local ban = findBan(serial, accountName)
    if not ban then return false end
    return { date = ban.date, admin = ban.admin, reason = ban.reason, account = ban.account }
end

-- A banned player stays connected but is frozen and stripped of GTA controls,
-- so all they can do is look at the ban panel.
local function applyBanState(player, ban)
    setElementData(player, "banned", true)
    setElementData(player, "banned_date", ban.date)
    setElementData(player, "banned_admin", ban.admin)
    setElementData(player, "banned_reason", ban.reason)
    setElementData(player, "banned_account", ban.account or false)

    setElementFrozen(player, true)
    toggleAllControls(player, false, true, false)
    triggerClientEvent(player, "acc_bans:onClientBanState", player, true)
end

local function clearBanState(player)
    setElementFrozen(player, false)
    toggleAllControls(player, true, true, true)
    for _, key in ipairs({ "banned_date", "banned_admin", "banned_reason", "banned_account" }) do
        setElementData(player, key, false)
    end
    setElementData(player, "banned", false)
    triggerClientEvent(player, "acc_bans:onClientBanState", player, false)
end

-- Exported. Puts the ban state on a player (e.g. acc_auth found the ban at login).
function applyBan(player, ban)
    if not isElement(player) or type(ban) ~= "table" then return false end
    applyBanState(player, {
        date = ban.date or dateString(), admin = ban.admin or "n/a",
        reason = ban.reason or "n/a", account = ban.account,
    })
    return true
end

function isPlayerBanned(player)
    return isElement(player) and getElementData(player, "banned") == true
end

-- Checked on join (serial only - the account is not known yet).
local function evaluateBan(player)
    local ban = findBan(getPlayerSerial(player), nil)
    if ban then
        applyBanState(player, ban)
        return true
    end
    if getElementData(player, "banned") == true then
        clearBanState(player) -- ban was lifted since the last check
    end
    setElementData(player, "banned", false)
    return false
end

-- Re-checks every online player against the cache (after a refresh). The
-- account is the logged-in one, or the one a rejected login was banned on.
local function syncBanStates()
    for _, player in ipairs(getElementsByType("player")) do
        local wasBanned = getElementData(player, "banned") == true
        local account = nameOf(player) or (wasBanned and getElementData(player, "banned_account")) or nil
        local ban = findBan(getPlayerSerial(player), account)
        if ban and not wasBanned then
            applyBanState(player, ban)
        elseif not ban and wasBanned then
            clearBanState(player)
        end
    end
end

addEvent("acc_bans:rows")
addEventHandler("acc_bans:rows", resourceRoot, function(_, rows)
    if type(rows) ~= "table" then return end -- DB error: keep the last known list
    setActiveBans(rows)
    syncBanStates()
end)

local function refreshBans()
    if not banDbReady() then return end
    exports.v_mysql:mysqlQueryAsync("acc_bans:rows", 0, BAN_SELECT)
end

addEventHandler("onPlayerJoin", root, function()
    evaluateBan(source)
end)

addEventHandler("onResourceStart", resourceRoot, function()
    if banDbReady() then
        exports.v_mysql:mysqlExec([[CREATE TABLE IF NOT EXISTS `]] .. BAN_TABLE .. [[` (
            `id`           INT AUTO_INCREMENT PRIMARY KEY,
            `account_name` VARCHAR(50)  DEFAULT NULL,
            `serial`       VARCHAR(32)  DEFAULT NULL,
            `ip`           VARCHAR(45)  DEFAULT NULL,
            `reason`       TEXT         NOT NULL,
            `admin`        VARCHAR(64)  NOT NULL DEFAULT '',
            `created_at`   INT          NOT NULL DEFAULT 0,
            `lifted_at`    INT          NOT NULL DEFAULT 0,
            `lifted_by`    VARCHAR(64)  DEFAULT NULL,
            KEY `idx_account` (`account_name`),
            KEY `idx_serial`  (`serial`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
        local rows = exports.v_mysql:mysqlQuerySync(BAN_SELECT)
        if type(rows) == "table" then setActiveBans(rows) end
    end
    for _, player in ipairs(getElementsByType("player")) do
        evaluateBan(player)
    end
    setTimer(refreshBans, BAN_REFRESH, 0)
end)

--------------------------------------------------------------------------------
-- Ban / unban API
--------------------------------------------------------------------------------

function banAccount(accountName, reason, adminName)
    if type(accountName) ~= "string" or accountName == "" then
        return false, L.msg("acc_bans.server.invalid_account_name")
    end
    if not banDbReady() then
        return false, L.msg("acc_bans.server.ban_database_unavailable")
    end

    local canonical = canonicalName(accountName)
    if not canonical then
        return false, L.msg("acc_bans.server.account_not_found", { account_name = accountName })
    end
    accountName = canonical

    -- stored in the database: plain text, not a message object
    reason    = (type(reason) == "string"    and reason    ~= "") and reason    or "No reason given"
    adminName = (type(adminName) == "string" and adminName ~= "") and adminName or "Console"

    local target = playerOnAccount(accountName)
    local serial = isElement(target) and getPlayerSerial(target) or nil
    local ip     = isElement(target) and getPlayerIP(target) or nil
    local now    = getRealTime().timestamp

    -- Re-banning an already banned account updates its active row.
    local existing = exports.v_mysql:mysqlQuerySync(
        "SELECT id, serial FROM `" .. BAN_TABLE .. "` WHERE account_name = ? AND lifted_at = 0 ORDER BY id DESC LIMIT 1",
        accountName)
    if existing == false then
        return false, L.msg("acc_bans.server.ban_database_unavailable")
    end

    local id
    if existing[1] then
        id = tonumber(existing[1].id)
        serial = serial or nonEmpty(existing[1].serial)
        if not exports.v_mysql:mysqlExec(
            "UPDATE `" .. BAN_TABLE .. "` SET serial = ?, ip = COALESCE(?, ip), reason = ?, admin = ?, created_at = ? WHERE id = ?",
            serial, ip, reason, adminName, now, id) then
            return false, L.msg("acc_bans.server.ban_database_unavailable")
        end
    else
        id = exports.v_mysql:mysqlInsert(
            "INSERT INTO `" .. BAN_TABLE .. "` (account_name, serial, ip, reason, admin, created_at) VALUES (?, ?, ?, ?, ?, ?)",
            accountName, serial, ip, reason, adminName, now)
        if type(id) ~= "number" then
            return false, L.msg("acc_bans.server.ban_database_unavailable")
        end
    end

    local ban = { id = id, account = accountName, serial = serial, date = dateString(now), admin = adminName, reason = reason }
    for i = #activeBans, 1, -1 do
        if activeBans[i].id == id then table.remove(activeBans, i) end
    end
    activeBans[#activeBans + 1] = ban

    if isElement(target) then
        applyBanState(target, ban)
    end

    outputServerLog(("[acc_bans] %s banned account '%s' (%s)"):format(adminName, accountName, reason))
    return true
end

function unbanAccount(accountName, adminName)
    if type(accountName) ~= "string" or accountName == "" then
        return false, L.msg("acc_bans.server.invalid_account_name")
    end
    if not banDbReady() then
        return false, L.msg("acc_bans.server.ban_database_unavailable")
    end

    local canonical = canonicalName(accountName)
    if canonical then accountName = canonical end
    adminName = (type(adminName) == "string" and adminName ~= "") and adminName or "Console"

    local rows = exports.v_mysql:mysqlQuerySync(
        "SELECT id FROM `" .. BAN_TABLE .. "` WHERE account_name = ? AND lifted_at = 0", accountName)
    if rows == false then
        return false, L.msg("acc_bans.server.ban_database_unavailable")
    end
    if not rows[1] then
        return false, L.msg("acc_bans.server.no_active_ban_for_account", { account_name = accountName })
    end

    if not exports.v_mysql:mysqlExec(
        "UPDATE `" .. BAN_TABLE .. "` SET lifted_at = ?, lifted_by = ? WHERE account_name = ? AND lifted_at = 0",
        getRealTime().timestamp, adminName, accountName) then
        return false, L.msg("acc_bans.server.ban_database_unavailable")
    end

    local needle = accountName:lower()
    for i = #activeBans, 1, -1 do
        local acc = activeBans[i].account
        if acc and acc:lower() == needle then table.remove(activeBans, i) end
    end

    -- Lift the panel for anyone held by this ban (by account, or by the serial
    -- it carried) unless another active ban still matches them.
    syncBanStates()

    outputServerLog(("[acc_bans] %s unbanned account '%s'"):format(adminName, accountName))
    return true
end
