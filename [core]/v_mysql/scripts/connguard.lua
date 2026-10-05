-- v_mysql :: connection guard
--
-- A lost MySQL connection used to take the whole server down with it: every
-- blocking mysqlQuerySync/mysqlInsert call stalls the single game loop for
-- the whole round trip, so once the DB stopped answering, every client ran
-- out of sync and MTA's own network timeout dropped the entire playerbase.
--
-- This reacts to mysql:connected / mysql:disconnected (core/mysql.lua) by
-- freezing every player instead - no camera/control, with a "database
-- issues" message - and unfreezing them the moment the connection is back.
-- It never fights with other systems that freeze players for their own
-- reasons (login screen, ban panel, cutscenes, ...): it remembers whether a
-- player was already frozen before this kicked in and only restores that.

if not MYSQL_ENABLE_SYNC then return end

local held = {}        -- [player] = true while held by this guard
local wasFrozen = {}    -- [player] = frozen state to restore afterwards

local function holdPlayer(player)
    if held[player] then return end
    held[player] = true
    wasFrozen[player] = isElementFrozen(player)
    setElementFrozen(player, true)
    toggleAllControls(player, false, true, false)
    triggerClientEvent(player, "mysql:guardNotice", player, true)
end

local function releasePlayer(player)
    if not held[player] then return end
    held[player] = nil
    if not wasFrozen[player] then
        setElementFrozen(player, false)
    end
    wasFrozen[player] = nil
    toggleAllControls(player, true, true, true)
    if isElement(player) then
        triggerClientEvent(player, "mysql:guardNotice", player, false)
    end
end

addEventHandler("mysql:disconnected", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do
        holdPlayer(player)
    end
end)

addEventHandler("mysql:connected", resourceRoot, function()
    for player in pairs(held) do
        releasePlayer(player)
    end
end)

-- Covers a player who joins mid-outage, after mysql:disconnected already
-- fired once for everybody who was online at the time.
addEventHandler("onPlayerJoin", root, function()
    if not mysqlIsConnected() then
        holdPlayer(source)
    end
end)

addEventHandler("onPlayerQuit", root, function()
    held[source]     = nil
    wasFrozen[source] = nil
end)
