if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
--[[
    v_socialpanel / server.lua
    Friends, friend requests, crews, profiles and private / crew messaging.

    Storage (all through v_mysql - see db.lua):
      - Friends:        `friends` table, one row per friendship, so it is
                        always stored for both accounts (offline ones too).
      - Friend requests: `friendRequests` table.
      - Crews:           `crews` table    (global, cached in memory).
      - Messages:        `messages` table (global, cached in memory) -> readable
                         later, offline too.
]]

-- crews[ name:lower() ] = { name, tag, color={r,g,b}, founder, desc, members={accName,...} }
local crews = {}

-- dms[ SP.pairKey(a,b) ]      = { {id, from, to, text, time, read}, ... }
-- crewMsgs[ crewName:lower() ] = { {id, from, text, time, crew}, ... }
local dms, crewMsgs = {}, {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- Account data (shared `accounts` table). `who` is a player element or an
-- account-name string; both work, online or offline.
local function getData(who, key) return exports.v_mysql:getAccData(who, key) end
local function setData(who, key, value) return exports.v_mysql:setAccData(who, key, value) end

local function accName(player)
    if not isElement(player) then return nil end
    local n = exports.v_accounts:getName(player)
    return (type(n) == "string" and n ~= "") and n or nil
end

local function onlinePlayerByAccount(name)
    if not name then return nil end
    local needle = name:lower()
    for _, player in ipairs(getElementsByType("player")) do
        local a = accName(player)
        if a and a:lower() == needle then return player end
    end
    return nil
end

-- Canonical account name for an input string if the account exists, else nil.
-- An online player's name needs no database lookup.
local function accountByName(name)
    if type(name) ~= "string" or name == "" then return nil end
    local online = onlinePlayerByAccount(name)
    if online then return accName(online) end
    local canonical = exports.v_accounts:accountNameExists(name)
    return canonical or nil
end

-- Display name of an account, for showing only (account names stay the keys
-- everywhere else). offlineOK = false: an offline account is not prefetched, so
-- do not read it (that would block on the database) and show the account name.
local function dispOf(name, offlineOK)
    if type(name) ~= "string" then return name end
    local online = onlinePlayerByAccount(name)
    if online then return exports.v_accounts:getDisplayName(online) end
    if offlineOK == false then return name end
    return exports.v_accounts:getDisplayName(name)
end

-- level + played time: prefer live element data, fall back to account data.
-- offlineOK = false skips the account-data read of an offline account (its
-- prefetch failed, so a read would block on the database): "n/a" then.
local function getProgress(name, onlinePlayer, offlineOK)
    local level, playtime = "n/a", "n/a"
    if onlinePlayer then
        level = getElementData(onlinePlayer, "level") or level
        playtime = getElementData(onlinePlayer, "Játékidő") or playtime
    elseif name and offlineOK ~= false then
        level = getData(name, "level") or level
        local h = getData(name, "Online.hours")
        local m = getData(name, "Online.minutes")
        if h or m then playtime = SP.formatPlaytime(h, m) end
    end
    return tostring(level), tostring(playtime)
end

local function notify(player, msg, r, g, b)
    if isElement(player) then
        outputChatBox("#f0c800[Social] #ffffff" .. L.resolveFor(player, msg), player, r or 255, g or 255, b or 255, true)
        -- the chatbox is hidden (v_chat): API users (c_api.lua) show it themselves
        triggerClientEvent(player, "sp:info", player, msg)
    end
end

-- Per-player rate limit (PERF-01 / SEC-10): at most `max` actions of a kind in
-- `window` ms. -> true when the action may run.
local RATE = {
    search = { max = 1,  window = 1000 },
    msg    = { max = 8,  window = 10000 },
    action = { max = 12, window = 10000 },   -- friend / profile / crew actions
}
local rateLog = {}   -- rateLog[player][kind] = { tick, ... }

local function allow(player, kind)
    local cfg, now = RATE[kind], getTickCount()
    rateLog[player] = rateLog[player] or {}
    local keep = {}
    for _, t in ipairs(rateLog[player][kind] or {}) do
        if now - t < cfg.window then keep[#keep + 1] = t end
    end
    rateLog[player][kind] = keep
    if #keep >= cfg.max then return false end
    keep[#keep + 1] = now
    return true
end

local function slowDown(player)
    notify(player, L.msg("v_socialpanel.server.slow_down"), 255, 120, 120)
end

--------------------------------------------------------------------------------
-- Crews: load / save
--------------------------------------------------------------------------------

local function loadCrews()
    crews = SPDB.loadCrews()
end

-- Persist one crew (upsert). Pass the crew table that was just mutated.
local function saveCrew(crew)
    SPDB.saveCrew(crew)
end

local function crewOf(name)
    if not name then return nil end
    for _, crew in pairs(crews) do
        if SP.contains(crew.members, name) then return crew end
    end
    return nil
end

-- Publishes the player's crew name / tag / colour to BOTH element data (live,
-- synced to every client) and account data (persists offline). Other resources
-- (nametags, yoverlay, ...) can read these directly:
--   getElementData(player, "crewName" | "crewTag" | "crewColor")
--   crewColor element data is a {r,g,b} table; account data is an "r,g,b" string.
local function applyCrewIdentity(player)
    if not isElement(player) then return end
    local myName = accName(player)
    local crew = myName and crewOf(myName) or nil
    local nameV  = crew and crew.name or ""
    local tagV   = crew and crew.tag or ""
    local colorV = crew and crew.color or { 255, 255, 255 }

    local colorStr = table.concat(colorV, ",")
    if getElementData(player, "crewName") ~= nameV then setElementData(player, "crewName", nameV) end
    if getElementData(player, "crewTag")  ~= tagV  then setElementData(player, "crewTag", tagV) end
    local curCol = getElementData(player, "crewColor")
    if type(curCol) ~= "table" or curCol[1] ~= colorV[1] or curCol[2] ~= colorV[2] or curCol[3] ~= colorV[3] then
        setElementData(player, "crewColor", colorV)
    end

    if myName then
        if getData(myName, "crewName")  ~= nameV    then setData(myName, "crewName", nameV) end
        if getData(myName, "crewTag")   ~= tagV     then setData(myName, "crewTag", tagV) end
        if getData(myName, "crewColor") ~= colorStr then setData(myName, "crewColor", colorStr) end
    end
end

--------------------------------------------------------------------------------
-- Messages: load / save
--------------------------------------------------------------------------------

local function loadMessages()
    dms, crewMsgs = SPDB.loadMessages()
end

-- Caps a conversation to SP.MSG_HISTORY messages, deleting the overflow rows
-- from the DB as it drops them from the in-memory list.
local function trimHistory(list)
    while #list > SP.MSG_HISTORY do
        local removed = table.remove(list, 1)
        if removed then
            removed.dropped = true   -- a row still being inserted is deleted once its id arrives
            if removed.id then SPDB.deleteMessage(removed.id) end
        end
    end
end

--------------------------------------------------------------------------------
-- Snapshot to the client
--------------------------------------------------------------------------------

local function friendEntry(name, offlineOK)
    local online = onlinePlayerByAccount(name)
    local level, playtime = getProgress(name, online, offlineOK)
    local crew = crewOf(name)
    return {
        name = name, online = online ~= nil, level = level, playtime = playtime,
        crew = crew and crew.name or nil,
    }
end

-- Builds the "conversations" list for a player (DM partners + crew).
local function buildConversations(player, myName, offlineOK)
    local convos = {}
    local myLower = myName:lower()

    for key, list in pairs(dms) do
        local a, b = key:match("^(.-)\1(.+)$")
        if a == myLower or b == myLower then
            local last = list[#list]
            if last then
                local partner = (last.from:lower() == myLower) and last.to or last.from
                local unread = 0
                for _, m in ipairs(list) do
                    if m.to:lower() == myLower and not m.read then unread = unread + 1 end
                end
                convos[#convos + 1] = {
                    kind = "dm", with = partner,
                    last = last.text, time = last.time, unread = unread,
                    online = onlinePlayerByAccount(partner) ~= nil,
                }
            end
        end
    end

    local myCrew = crewOf(myName)
    if myCrew then
        local list = crewMsgs[myCrew.name:lower()] or {}
        local last = list[#list]
        local seen = tonumber(getData(player, SP.KEY_CREW_SEEN)) or 0
        local unread = 0
        for _, m in ipairs(list) do
            if m.time > seen and m.from:lower() ~= myLower then unread = unread + 1 end
        end
        convos[#convos + 1] = {
            kind = "crew", with = myCrew.name, crewTag = myCrew.tag, crewColor = myCrew.color,
            last = last and (dispOf(last.from, offlineOK) .. ": " .. last.text) or L.msg("v_socialpanel.server.no_messages_yet"),
            time = last and last.time or 0, unread = unread,
        }
    end

    table.sort(convos, function(a, b) return (a.time or 0) > (b.time or 0) end)
    return convos
end

-- friendList = the friends' account names, requests = the incoming friend
-- requests, offlineOK = the offline accounts' data was prefetched (see pushSnapshot).
local function buildSnapshot(player, friendList, requests, offlineOK)
    local myName = accName(player)
    if not myName then return nil end

    -- displayNames[lower account] = display name, only where it differs; the
    -- client draws names through it and keeps using the account names as keys
    local dnames = {}
    local function reg(name)
        if type(name) ~= "string" then return end
        local d = dispOf(name, offlineOK)
        if d ~= name then dnames[name:lower()] = d end
    end
    reg(myName)
    for _, rn in ipairs(requests or {}) do reg(rn) end

    local friends = {}
    for _, fn in ipairs(friendList) do
        reg(fn)
        friends[#friends + 1] = friendEntry(fn, offlineOK)
    end
    table.sort(friends, function(a, b)
        if a.online ~= b.online then return a.online end
        return a.name:lower() < b.name:lower()
    end)

    local myCrew = crewOf(myName)
    local crewData
    if myCrew then
        local members = {}
        for _, mn in ipairs(myCrew.members) do
            local online = onlinePlayerByAccount(mn)
            local level, playtime = getProgress(mn, online, offlineOK)
            reg(mn)
            members[#members + 1] = {
                name = mn, online = online ~= nil, level = level, playtime = playtime,
                isFounder = mn:lower() == myCrew.founder:lower(),
            }
        end
        table.sort(members, function(a, b)
            if a.isFounder ~= b.isFounder then return a.isFounder end
            if a.online ~= b.online then return a.online end
            return a.name:lower() < b.name:lower()
        end)
        crewData = {
            name = myCrew.name, tag = myCrew.tag, color = myCrew.color,
            founder = myCrew.founder, desc = myCrew.desc,
            isFounder = myName:lower() == myCrew.founder:lower(),
            members = members,
        }
    end

    local dir = {}
    for _, crew in pairs(crews) do
        reg(crew.founder)
        dir[#dir + 1] = { name = crew.name, tag = crew.tag, color = crew.color,
            founder = crew.founder, members = #crew.members }
    end
    table.sort(dir, function(a, b) return a.name:lower() < b.name:lower() end)

    local convos = buildConversations(player, myName, offlineOK)
    for _, c in ipairs(convos) do if c.kind == "dm" then reg(c.with) end end

    return {
        account       = myName,
        displayName   = dispOf(myName, offlineOK),
        friends       = friends,
        requests      = requests or {},
        crew          = crewData,
        crews         = dir,
        conversations = convos,
        names         = dnames,
    }
end

-- The snapshot needs the friends, the friend requests and the data of every
-- offline friend / crew member. All are fetched without blocking (PERF-01): the
-- friends first (their names feed the prefetch), then the requests with one
-- async query and the offline accounts with one v_mysql prefetch, after which
-- their getData reads are served from memory. A push asked for while one is in
-- flight is folded into a single re-run when it completes.
local snapState = {}   -- [player] = "busy" | "again"

local function pushSnapshot(player)
    if not isElement(player) then return end
    if snapState[player] then
        snapState[player] = "again"
        return
    end
    local myName = accName(player)
    if not myName then return end
    snapState[player] = "busy"

    SPDB.getFriendsAsync(function(friendList)
        if not isElement(player) then snapState[player] = nil return end
        if not friendList then
            -- the database failed: no snapshot rather than an empty friend list
            local again = snapState[player] == "again"
            snapState[player] = nil
            if again then pushSnapshot(player) end
            return
        end

        local names = {}
        for _, fn in ipairs(friendList) do names[#names + 1] = fn end
        local myCrew = crewOf(myName)
        if myCrew then
            for _, mn in ipairs(myCrew.members) do names[#names + 1] = mn end
        end

        local requests, offlineOK = {}, false
        local function done()
            local again = snapState[player] == "again"
            snapState[player] = nil
            if not isElement(player) then return end

            applyCrewIdentity(player) -- keep crew name/tag/colour data in sync on every refresh
            local snap = buildSnapshot(player, friendList, requests, offlineOK)
            if snap then triggerClientEvent(player, "sp:push", player, snap) end
            if again then pushSnapshot(player) end
        end

        -- the display names of the requests' senders, the DM partners and the crew
        -- founders are shown too: they join the one prefetch
        SPDB.getRequestsForAsync(function(list)
            requests = list
            for _, rn in ipairs(requests) do names[#names + 1] = rn end
            local mine = myName:lower()
            for key, msgs in pairs(dms) do
                local a, b = key:match("^(.-)\1(.+)$")
                local last = msgs[#msgs]
                if last and (a == mine or b == mine) then
                    names[#names + 1] = (last.from:lower() == mine) and last.to or last.from
                end
            end
            for _, crew in pairs(crews) do names[#names + 1] = crew.founder end
            MYSQL.prefetch(function(ok)
                offlineOK = ok == true
                done()
            end, names)
        end, myName)
    end, myName)
end

local function pushBoth(a, b)
    if isElement(a) then pushSnapshot(a) end
    if isElement(b) and b ~= a then pushSnapshot(b) end
end

--------------------------------------------------------------------------------
-- Pull
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Achievements (read-only view of v_achievements)
--------------------------------------------------------------------------------

-- Sends { available, categories, list, summary } to the client. Each list
-- entry is the definition merged with the player's state; hidden ones that
-- are still locked have their name / desc masked.
local function pushAchievements(player)
    local ach = getResourceFromName("v_achievements")
    if not ach or getResourceState(ach) ~= "running" then
        triggerClientEvent(player, "sp:ach:data", player, { available = false })
        return
    end

    local ok, defs, state, cats, summary = pcall(function()
        local ex = exports.v_achievements
        return ex:getAchievements(), ex:getPlayerAchievements(player),
            ex:getAchievementCategories(), ex:getPlayerAchievementSummary(player)
    end)
    if not ok or type(defs) ~= "table" or type(state) ~= "table" then
        triggerClientEvent(player, "sp:ach:data", player, { available = false })
        return
    end

    local list = {}
    for _, d in ipairs(defs) do
        local s = state[d.id] or {}
        local masked = d.hidden and not s.done
        list[#list + 1] = {
            id = d.id,
            category = d.category,
            name = masked and "???" or d.name,
            desc = masked and L.msg("v_socialpanel.server.hidden_achievement") or d.desc,
            xp = d.xp,
            unit = d.unit,
            hidden = masked,
            done = s.done == true,
            unlockedAt = s.unlockedAt or false,
            progress = s.progress or 0,
            goal = s.goal or 1,
            isProgress = d.type == "progress",
        }
    end
    triggerClientEvent(player, "sp:ach:data", player, {
        available = true,
        categories = type(cats) == "table" and cats or {},
        list = list,
        summary = type(summary) == "table" and summary or nil,
    })
end

addEvent("sp:ach:pull", true)
addEventHandler("sp:ach:pull", root, function()
    if isElement(client) then pushAchievements(client) end
end)

addEvent("sp:pull", true)
addEventHandler("sp:pull", root, function()
    if not isElement(client) then return end
    pushSnapshot(client)
    pushAchievements(client)
end)

-- Account settings: the display name (the account name never changes)
addEvent("sp:display:set", true)
addEventHandler("sp:display:set", root, function(name)
    local player = client
    local myName = accName(player)
    if not myName then return end
    if not allow(player, "action") then return slowDown(player) end
    local ok, clean = SP.validateDisplayName(name)
    if not ok then return triggerClientEvent(player, "sp:display:result", player, false, clean) end
    setData(myName, "display_name", clean)
    setElementData(player, "displayName", clean)
    triggerClientEvent(player, "sp:display:result", player, true, L.msg("v_socialpanel.server.display_name_saved"))
    pushSnapshot(player)
end)

--------------------------------------------------------------------------------
-- Friends
--------------------------------------------------------------------------------

addEvent("sp:friend:add", true)
addEventHandler("sp:friend:add", root, function(targetName)
    local player = client
    local myName = accName(player)
    if not myName then return end
    if type(targetName) ~= "string" or targetName == "" then return end
    if not allow(player, "action") then return slowDown(player) end
    if targetName:lower() == myName:lower() then
        return notify(player, L.msg("v_socialpanel.server.you_can_t_add_yourself"), 255, 120, 120)
    end

    local targetAcc = accountByName(targetName)
    if not targetAcc then
        return notify(player, L.msg("v_socialpanel.server.no_such_player", { target_name = dispOf(targetName) }), 255, 120, 120)
    end
    targetName = targetAcc

    local myAcc = myName
    local myFriends = SPDB.getFriends(myAcc)
    if SP.contains(myFriends, targetName) then
        return notify(player, L.msg("v_socialpanel.server.is_already_your_friend", { target_name = dispOf(targetName) }), 255, 200, 0)
    end
    if #myFriends >= SP.MAX_FRIENDS then
        return notify(player, L.msg("v_socialpanel.server.your_friend_list_is_full"), 255, 120, 120)
    end

    -- If they already sent me a request, become friends immediately.
    local myIncoming = SPDB.getRequestsFor(myAcc)
    local mine, mineExact = SP.contains(myIncoming, targetName)
    if mine then
        SPDB.removeRequest(mineExact, myAcc)
        SPDB.addFriend(myAcc, targetAcc)
        notify(player, L.msg("v_socialpanel.server.you_are_now_friends_with", { target_name = dispOf(targetName) }), 0, 220, 0)
        local tp = onlinePlayerByAccount(targetName)
        notify(tp, L.msg("v_socialpanel.server.you_are_now_friends_with_2", { my_name = dispOf(myName) }), 0, 220, 0)
        return pushBoth(player, tp)
    end

    if SP.contains(SPDB.getRequestsFor(targetAcc), myName) then
        return notify(player, L.msg("v_socialpanel.server.you_already_sent_them_request"), 255, 200, 0)
    end
    SPDB.addRequest(myName, targetAcc)
    notify(player, L.msg("v_socialpanel.server.friend_request_sent_to", { target_name = dispOf(targetName) }), 0, 220, 0)
    local tp = onlinePlayerByAccount(targetName)
    if tp then
        notify(tp, L.msg("v_socialpanel.server.sent_you_friend_request", { my_name = dispOf(myName) }), 0, 220, 0)
        pushSnapshot(tp)
    end
end)

addEvent("sp:friend:accept", true)
addEventHandler("sp:friend:accept", root, function(senderName)
    local player = client
    local myName = accName(player)
    if not myName or type(senderName) ~= "string" then return end
    if not allow(player, "action") then return slowDown(player) end

    local myAcc = myName
    local incoming = SPDB.getRequestsFor(myAcc)
    local ok, exact = SP.contains(incoming, senderName)
    if not ok then return notify(player, L.msg("v_socialpanel.server.no_such_request"), 255, 120, 120) end
    senderName = exact

    SPDB.removeRequest(senderName, myAcc)

    local senderAcc = accountByName(senderName)
    if not senderAcc then return notify(player, L.msg("v_socialpanel.server.that_account_no_longer_exists"), 255, 120, 120) end

    SPDB.addFriend(myAcc, senderAcc)

    notify(player, L.msg("v_socialpanel.server.you_accepted_s_request", { sender_name = dispOf(senderName) }), 0, 220, 0)
    local sp = onlinePlayerByAccount(senderName)
    notify(sp, L.msg("v_socialpanel.server.accepted_your_friend_request", { my_name = dispOf(myName) }), 0, 220, 0)
    pushBoth(player, sp)
end)

addEvent("sp:friend:decline", true)
addEventHandler("sp:friend:decline", root, function(senderName)
    local player = client
    local myName = accName(player)
    if not myName or type(senderName) ~= "string" then return end
    if not allow(player, "action") then return slowDown(player) end
    local myAcc = myName
    local ok, exact = SP.contains(SPDB.getRequestsFor(myAcc), senderName)
    if not ok then return end
    SPDB.removeRequest(exact, myAcc)
    notify(player, L.msg("v_socialpanel.server.request_declined"), 255, 200, 0)
    pushSnapshot(player)
end)

addEvent("sp:friend:remove", true)
addEventHandler("sp:friend:remove", root, function(friendName)
    local player = client
    local myName = accName(player)
    if not myName or type(friendName) ~= "string" then return end
    if not allow(player, "action") then return slowDown(player) end

    local myAcc = myName
    local ok, exact = SP.contains(SPDB.getFriends(myAcc), friendName)
    if not ok then return end
    friendName = exact

    SPDB.removeFriend(myAcc, friendName)
    notify(player, L.msg("v_socialpanel.server.removed_from_your_friend_list", { friend_name = dispOf(friendName) }), 255, 200, 0)
    local fp = onlinePlayerByAccount(friendName)
    notify(fp, L.msg("v_socialpanel.server.removed_you_from_their_friend_list", { my_name = dispOf(myName) }), 255, 200, 0)
    pushBoth(player, fp)
end)

--------------------------------------------------------------------------------
-- Profile view
--------------------------------------------------------------------------------

addEvent("sp:profile:view", true)
addEventHandler("sp:profile:view", root, function(name)
    local player = client
    local myName = accName(player)
    if not myName or type(name) ~= "string" then return end
    if not allow(player, "action") then return slowDown(player) end

    local acc = accountByName(name)
    if not acc then
        return triggerClientEvent(player, "sp:profile:show", player, false, name)
    end
    name = acc

    -- an offline account's level / played time come from one prefetch (PERF-01)
    MYSQL.prefetch(function(ok)
        if not isElement(player) or accName(player) ~= myName then return end
        local online = onlinePlayerByAccount(name)
        local level, playtime = getProgress(name, online, ok == true)
        local crew = crewOf(name)
        SPDB.getFriendsAsync(function(myFriends)
            if not isElement(player) or accName(player) ~= myName then return end
            triggerClientEvent(player, "sp:profile:show", player, {
                name      = name,
                display   = dispOf(name),
                online    = online ~= nil,
                level     = level,
                playtime  = playtime,
                crew      = crew and crew.name or nil,
                crewTag   = crew and crew.tag or nil,
                crewColor = crew and crew.color or nil,
                isFriend  = (SP.contains(myFriends or {}, name)),
                isSelf    = name:lower() == myName:lower(),
            })
        end, myName)
    end, { name })
end)

--------------------------------------------------------------------------------
-- Player search (online AND offline)
--------------------------------------------------------------------------------

addEvent("sp:search", true)
local searchBusy = {}   -- [player] = true while the account query / prefetch runs

addEventHandler("sp:search", root, function(query)
    local player = client
    if not accName(player) or type(query) ~= "string" then return end
    if searchBusy[player] then return end
    query = query:gsub("^%s+", ""):gsub("%s+$", "")
    if #query < SP.SEARCH_MIN then
        return triggerClientEvent(player, "sp:search:results", player, {}, L.msg("v_socialpanel.server.type_at_least_characters", { search_min = SP.SEARCH_MIN }))
    end
    if not allow(player, "search") then return slowDown(player) end

    local needle = query:lower()
    local seen, results = {}, {}

    local function finish()
        table.sort(results, function(a, b)
            if a.online ~= b.online then return a.online end
            return a.name:lower() < b.name:lower()
        end)
        triggerClientEvent(player, "sp:search:results", player, results)
    end

    -- Online players first (live data).
    for _, p in ipairs(getElementsByType("player")) do
        local nm = accName(p)
        if nm and nm:lower():find(needle, 1, true) then
            seen[nm:lower()] = true
            results[#results + 1] = {
                name = nm, display = dispOf(nm), online = true,
                level = tostring(getElementData(p, "level") or "n/a"),
                playtime = tostring(getElementData(p, "Játékidő") or "n/a"),
            }
        end
    end

    if #results >= SP.SEARCH_LIMIT then return finish() end

    -- Then registered accounts (offline): the matching names come from SQL,
    -- their data from one prefetch, so nothing here blocks (PERF-01). The online
    -- matches can come back from the query too, so it asks for that many more.
    searchBusy[player] = true
    SPDB.searchAccountsAsync(function(names)
        if not isElement(player) then searchBusy[player] = nil return end
        local offline = {}
        for _, nm in ipairs(names or {}) do
            if #results + #offline >= SP.SEARCH_LIMIT then break end
            if not seen[nm:lower()] and not nm:find("^#") then
                seen[nm:lower()] = true
                offline[#offline + 1] = nm
            end
        end
        if #offline == 0 then
            searchBusy[player] = nil
            return finish()
        end

        MYSQL.prefetch(function(ok)
            searchBusy[player] = nil
            if not isElement(player) then return end
            for _, nm in ipairs(offline) do
                local level, playtime = "n/a", "n/a"
                if ok == true then
                    local h, m = getData(nm, "Online.hours"), getData(nm, "Online.minutes")
                    level = tostring(getData(nm, "level") or "n/a")
                    playtime = (h or m) and SP.formatPlaytime(h, m) or "n/a"
                end
                results[#results + 1] = { name = nm, display = dispOf(nm, ok == true), online = false, level = level, playtime = playtime }
            end
            finish()
        end, offline)
    end, needle, SP.SEARCH_LIMIT + #results)
end)

--------------------------------------------------------------------------------
-- Messaging
--------------------------------------------------------------------------------

-- Builds a conversation's message list from the point of view of `myName`.
-- No side effects (safe to call on a snapshot / live update).
local function collectThread(myName, kind, target)
    local out, myLower = {}, myName:lower()
    local src
    if kind == "dm" then
        src = dms[SP.pairKey(myName, target)]
    elseif kind == "crew" then
        src = crewMsgs[target:lower()]
    end
    for _, m in ipairs(src or {}) do
        out[#out + 1] = { from = m.from, text = m.text, time = m.time, mine = m.from:lower() == myLower }
    end
    return out
end

-- Marks a conversation read/seen for a player. Called only when the player
-- explicitly opens it, never on a passive update -> no client<->server loop.
local function markRead(player, myName, kind, target)
    if kind == "dm" then
        local changedIds = {}
        for _, m in ipairs(dms[SP.pairKey(myName, target)] or {}) do
            if m.to:lower() == myName:lower() and not m.read then
                m.read = true   -- a row still being inserted is flagged once its id arrives
                if m.id then changedIds[#changedIds + 1] = m.id end
            end
        end
        SPDB.markMessagesRead(changedIds)
    elseif kind == "crew" then
        setData(player, SP.KEY_CREW_SEEN, tostring(getRealTime().timestamp))
    end
end

local function resolveTarget(myName, kind, target)
    if kind == "crew" then
        local crew = crewOf(myName)
        if crew and crew.name:lower() == target:lower() then return crew.name end
        return nil
    end
    return accountByName(target)
end

addEvent("sp:msg:open", true)
addEventHandler("sp:msg:open", root, function(kind, target)
    local player = client
    local myName = accName(player)
    if not myName or type(kind) ~= "string" or type(target) ~= "string" then return end
    target = resolveTarget(myName, kind, target)
    if not target then return end
    markRead(player, myName, kind, target)
    triggerClientEvent(player, "sp:msg:data", player, kind, target, collectThread(myName, kind, target))
    pushSnapshot(player)
end)

addEvent("sp:msg:send", true)
addEventHandler("sp:msg:send", root, function(kind, target, text)
    local player = client
    local myName = accName(player)
    if not myName then return end
    text = SP.cleanMessage(text)
    if not text or type(target) ~= "string" then return end
    if not allow(player, "msg") then return slowDown(player) end
    local now = getRealTime().timestamp

    if kind == "dm" then
        if target:lower() == myName:lower() then return end
        local targetAcc = accountByName(target)
        if not targetAcc then return notify(player, L.msg("v_socialpanel.server.no_such_player_2", { target = target }), 255, 120, 120) end
        target = targetAcc

        local key = SP.pairKey(myName, target)
        dms[key] = dms[key] or {}
        local msg = { id = nil, from = myName, to = target, text = text, time = now, read = false }
        table.insert(dms[key], msg)
        SPDB.insertDm(msg)   -- async: msg.id is filled in once the row is written
        trimHistory(dms[key])

        triggerClientEvent(player, "sp:msg:data", player, "dm", target, collectThread(myName, "dm", target))
        pushSnapshot(player)

        local tp = onlinePlayerByAccount(target)
        if tp then
            triggerClientEvent(tp, "sp:notify", tp, "dm", dispOf(myName), text)
            triggerClientEvent(tp, "sp:msg:data", tp, "dm", myName, collectThread(target, "dm", myName))
            pushSnapshot(tp)
        end

    elseif kind == "crew" then
        local crew = crewOf(myName)
        if not crew then return notify(player, L.msg("v_socialpanel.server.you_are_not_in_crew"), 255, 120, 120) end
        crewMsgs[crew.name:lower()] = crewMsgs[crew.name:lower()] or {}
        local msg = { id = nil, from = myName, text = text, time = now, crew = crew.name }
        table.insert(crewMsgs[crew.name:lower()], msg)
        SPDB.insertCrewMsg(msg)   -- async: msg.id is filled in once the row is written
        trimHistory(crewMsgs[crew.name:lower()])

        for _, mn in ipairs(crew.members) do
            local mp = onlinePlayerByAccount(mn)
            if mp then
                if mp ~= player then
                    triggerClientEvent(mp, "sp:notify", mp, "crew", dispOf(myName), text, crew.tag)
                end
                triggerClientEvent(mp, "sp:msg:data", mp, "crew", crew.name, collectThread(mn, "crew", crew.name))
                pushSnapshot(mp)
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- Crews
--------------------------------------------------------------------------------

addEvent("sp:crew:create", true)
addEventHandler("sp:crew:create", root, function(name, tag, r, g, b)
    local player = client
    local myName = accName(player)
    if not myName then return end
    if not allow(player, "action") then return slowDown(player) end
    if crewOf(myName) then return notify(player, L.msg("v_socialpanel.server.you_already_have_crew_leave_it"), 255, 120, 120) end

    local okN, cleanName = SP.validateCrewName(name)
    if not okN then return notify(player, cleanName, 255, 120, 120) end
    local okT, cleanTag = SP.validateCrewTag(tag)
    if not okT then return notify(player, cleanTag, 255, 120, 120) end
    if crews[cleanName:lower()] then return notify(player, L.msg("v_socialpanel.server.crew_with_that_name_already_exists"), 255, 120, 120) end

    r = math.max(0, math.min(255, tonumber(r) or 255))
    g = math.max(0, math.min(255, tonumber(g) or 200))
    b = math.max(0, math.min(255, tonumber(b) or 0))

    local crew = {
        name = cleanName, tag = cleanTag, color = { r, g, b },
        founder = myName, desc = "", members = { myName },
    }
    crews[cleanName:lower()] = crew
    setData(player, SP.KEY_CREW, cleanName)
    saveCrew(crew)
    notify(player, L.msg("v_socialpanel.server.crew_created", { clean_name = cleanName, clean_tag = cleanTag }), 0, 220, 0)
    pushSnapshot(player)
end)

addEvent("sp:crew:join", true)
addEventHandler("sp:crew:join", root, function(crewName)
    local player = client
    local myName = accName(player)
    if not myName or type(crewName) ~= "string" then return end
    if not allow(player, "action") then return slowDown(player) end
    if crewOf(myName) then return notify(player, L.msg("v_socialpanel.server.you_already_have_crew_leave_it"), 255, 120, 120) end
    local crew = crews[crewName:lower()]
    if not crew then return notify(player, L.msg("v_socialpanel.server.no_such_crew"), 255, 120, 120) end
    if #crew.members >= SP.MAX_CREW_MEMBERS then return notify(player, L.msg("v_socialpanel.server.that_crew_is_full"), 255, 120, 120) end

    crew.members[#crew.members + 1] = myName
    setData(player, SP.KEY_CREW, crew.name)
    saveCrew(crew)
    notify(player, L.msg("v_socialpanel.server.you_joined_crew", { name = crew.name }), 0, 220, 0)
    for _, mn in ipairs(crew.members) do
        local mp = onlinePlayerByAccount(mn)
        if mp and mp ~= player then notify(mp, L.msg("v_socialpanel.server.joined_crew", { my_name = dispOf(myName) }), 0, 220, 0) end
        if mp then pushSnapshot(mp) end
    end
end)

local function leaveCrew(player, silent)
    local myName = accName(player)
    if not myName then return end
    local crew = crewOf(myName)
    if not crew then
        if not silent then notify(player, L.msg("v_socialpanel.server.you_are_not_in_crew"), 255, 120, 120) end
        return
    end

    crew.members = SP.removeValue(crew.members, myName)
    setData(player, SP.KEY_CREW, "")

    local disbanded = false
    if #crew.members == 0 then
        crews[crew.name:lower()] = nil
        crewMsgs[crew.name:lower()] = nil
        disbanded = true
        SPDB.deleteCrew(crew.name)
        SPDB.deleteCrewMessages(crew.name)
    else
        if myName:lower() == crew.founder:lower() then
            crew.founder = crew.members[1] -- founder passes to the oldest member
            notify(onlinePlayerByAccount(crew.founder), L.msg("v_socialpanel.server.you_are_now_founder_of", { name = crew.name }), 255, 200, 0)
        end
        saveCrew(crew)
    end

    if not silent then
        notify(player, disbanded and (L.msg("v_socialpanel.server.crew_was_disbanded", { name = crew.name })) or (L.msg("v_socialpanel.server.you_left", { name = crew.name })), 255, 200, 0)
    end
    for _, mn in ipairs(crew.members) do
        local mp = onlinePlayerByAccount(mn)
        if mp then
            notify(mp, L.msg("v_socialpanel.server.left_crew", { my_name = dispOf(myName) }), 255, 200, 0)
            pushSnapshot(mp)
        end
    end
    pushSnapshot(player)
end

addEvent("sp:crew:leave", true)
addEventHandler("sp:crew:leave", root, function() leaveCrew(client, false) end)

addEvent("sp:crew:kick", true)
addEventHandler("sp:crew:kick", root, function(memberName)
    local player = client
    local myName = accName(player)
    if not myName or type(memberName) ~= "string" then return end
    if not allow(player, "action") then return slowDown(player) end
    local crew = crewOf(myName)
    if not crew or myName:lower() ~= crew.founder:lower() then
        return notify(player, L.msg("v_socialpanel.server.only_founder_can_kick_members"), 255, 120, 120)
    end
    if memberName:lower() == myName:lower() then return end
    local ok, exact = SP.contains(crew.members, memberName)
    if not ok then return end

    crew.members = SP.removeValue(crew.members, exact)
    local kAcc = accountByName(exact)
    if kAcc then setData(kAcc, SP.KEY_CREW, "") end
    saveCrew(crew)

    local kp = onlinePlayerByAccount(exact)
    notify(kp, L.msg("v_socialpanel.server.you_were_kicked_from_crew", { name = crew.name }), 255, 120, 120)
    if kp then pushSnapshot(kp) end
    notify(player, dispOf(exact) .. " kicked.", 255, 200, 0)
    for _, mn in ipairs(crew.members) do
        local mp = onlinePlayerByAccount(mn)
        if mp then pushSnapshot(mp) end
    end
end)

addEvent("sp:crew:customize", true)
addEventHandler("sp:crew:customize", root, function(tag, desc, r, g, b)
    local player = client
    local myName = accName(player)
    if not myName then return end
    local crew = crewOf(myName)
    if not crew or myName:lower() ~= crew.founder:lower() then
        return notify(player, L.msg("v_socialpanel.server.only_founder_can_edit_crew"), 255, 120, 120)
    end

    if tag and tag ~= "" then
        local okT, cleanTag = SP.validateCrewTag(tag)
        if not okT then return notify(player, cleanTag, 255, 120, 120) end
        crew.tag = cleanTag
    end
    if type(desc) == "string" then
        crew.desc = desc:sub(1, SP.CREW_DESC_MAX)
    end
    if r and g and b then
        crew.color = {
            math.max(0, math.min(255, tonumber(r) or crew.color[1])),
            math.max(0, math.min(255, tonumber(g) or crew.color[2])),
            math.max(0, math.min(255, tonumber(b) or crew.color[3])),
        }
    end
    saveCrew(crew)
    notify(player, L.msg("v_socialpanel.server.crew_updated"), 0, 220, 0)
    for _, mn in ipairs(crew.members) do
        local mp = onlinePlayerByAccount(mn)
        if mp then pushSnapshot(mp) end
    end
end)

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

addEventHandler("onResourceStart", resourceRoot, function()
    if SPDB.ensureFriendsTable() then SPDB.migrateFriends() end
    loadCrews()
    loadMessages()
    for _, player in ipairs(getElementsByType("player")) do
        if accName(player) then pushSnapshot(player) end
    end
end)

-- onPlayerLoaded fires after the shared MySQL account-data sync. Keep a short
-- cushion so the other resources' onPlayerLoaded handlers (level, played-time)
-- have run before the snapshot is built.
addEvent("onPlayerLoaded")
addEventHandler("onPlayerLoaded", root, function()
    setTimer(pushSnapshot, 500, 1, source)
end)

addEventHandler("onPlayerQuit", root, function()
    rateLog[source] = nil
    searchBusy[source] = nil
    snapState[source] = nil
end)
