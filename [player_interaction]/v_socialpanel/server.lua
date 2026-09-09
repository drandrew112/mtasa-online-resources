--[[
    v_socialpanel / server.lua
    Friends, friend requests, crews, profiles and private / crew messaging.

    Storage:
      - Friends / requests / crew membership: account data in the shared
        `accounts` table (exports.v_mysql:getAccData / setAccData). Works for
        offline accounts too (keyed by account-name string).
      - Crews:    crews.xml     (global, cached in memory)
      - Messages: messages.xml  (global, cached in memory) -> readable later, offline too
]]

local CREWS_FILE = "crews.xml"
local MSGS_FILE  = "messages.xml"

-- crews[ name:lower() ] = { name, tag, color={r,g,b}, founder, desc, members={accName,...} }
local crews = {}

-- dms[ SP.pairKey(a,b) ]   = { {from, to, text, time, read}, ... }
-- crewMsgs[ crewName:lower() ] = { {from, text, time}, ... }
local dms, crewMsgs = {}, {}
local saveMsgTimer

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

-- Canonical account name for an input string if the account exists, else nil.
local function accountByName(name)
    if type(name) ~= "string" or name == "" then return nil end
    local canonical = exports.v_accounts:accountNameExists(name)
    return canonical or nil
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

-- level + played time: prefer live element data, fall back to account data.
local function getProgress(name, onlinePlayer)
    local level, playtime = "n/a", "n/a"
    if onlinePlayer then
        level = getElementData(onlinePlayer, "level") or level
        playtime = getElementData(onlinePlayer, "Játékidő") or playtime
    elseif name then
        level = getData(name, "level") or level
        local h = getData(name, "Online.hours")
        local m = getData(name, "Online.minutes")
        if h or m then playtime = SP.formatPlaytime(h, m) end
    end
    return tostring(level), tostring(playtime)
end

local function getListFor(name, key)
    return SP.split(name and getData(name, key) or "")
end

local function setListFor(name, key, list)
    if name then setData(name, key, SP.join(list)) end
end

local function notify(player, msg, r, g, b)
    if isElement(player) then
        outputChatBox("#f0c800[Social] #ffffff" .. msg, player, r or 255, g or 255, b or 255, true)
    end
end

--------------------------------------------------------------------------------
-- Crews: load / save
--------------------------------------------------------------------------------

local function loadCrews()
    crews = {}
    local xml = xmlLoadFile(CREWS_FILE)
    if not xml then
        xml = xmlCreateFile(CREWS_FILE, "crews")
        if xml then xmlSaveFile(xml); xmlUnloadFile(xml) end
        return
    end
    for _, node in ipairs(xmlNodeGetChildren(xml) or {}) do
        local name = xmlNodeGetAttribute(node, "name")
        if name and name ~= "" then
            local members = {}
            for _, m in ipairs(xmlNodeGetChildren(node) or {}) do
                local mn = xmlNodeGetAttribute(m, "name")
                if mn and mn ~= "" then members[#members + 1] = mn end
            end
            crews[name:lower()] = {
                name    = name,
                tag     = xmlNodeGetAttribute(node, "tag") or "CREW",
                color   = {
                    tonumber(xmlNodeGetAttribute(node, "r")) or 255,
                    tonumber(xmlNodeGetAttribute(node, "g")) or 200,
                    tonumber(xmlNodeGetAttribute(node, "b")) or 0,
                },
                founder = xmlNodeGetAttribute(node, "founder") or (members[1] or ""),
                desc    = xmlNodeGetAttribute(node, "desc") or "",
                members = members,
            }
        end
    end
    xmlUnloadFile(xml)
end

local function saveCrews()
    local xml = xmlCreateFile(CREWS_FILE, "crews")
    if not xml then return end
    for _, crew in pairs(crews) do
        local node = xmlCreateChild(xml, "crew")
        xmlNodeSetAttribute(node, "name", crew.name)
        xmlNodeSetAttribute(node, "tag", crew.tag)
        xmlNodeSetAttribute(node, "founder", crew.founder)
        xmlNodeSetAttribute(node, "desc", crew.desc or "")
        xmlNodeSetAttribute(node, "r", tostring(crew.color[1]))
        xmlNodeSetAttribute(node, "g", tostring(crew.color[2]))
        xmlNodeSetAttribute(node, "b", tostring(crew.color[3]))
        for _, mn in ipairs(crew.members) do
            xmlNodeSetAttribute(xmlCreateChild(node, "member"), "name", mn)
        end
    end
    xmlSaveFile(xml)
    xmlUnloadFile(xml)
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
    dms, crewMsgs = {}, {}
    local xml = xmlLoadFile(MSGS_FILE)
    if not xml then
        xml = xmlCreateFile(MSGS_FILE, "messages")
        if xml then xmlSaveFile(xml); xmlUnloadFile(xml) end
        return
    end
    for _, node in ipairs(xmlNodeGetChildren(xml) or {}) do
        local tag = xmlNodeGetName(node)
        local from = xmlNodeGetAttribute(node, "from")
        local time = tonumber(xmlNodeGetAttribute(node, "time")) or 0
        local text = xmlNodeGetValue(node) or ""
        if tag == "dm" then
            local to = xmlNodeGetAttribute(node, "to")
            if from and to and text ~= "" then
                local key = SP.pairKey(from, to)
                dms[key] = dms[key] or {}
                table.insert(dms[key], {
                    from = from, to = to, text = text, time = time,
                    read = xmlNodeGetAttribute(node, "read") == "1",
                })
            end
        elseif tag == "crew" then
            local crew = xmlNodeGetAttribute(node, "crew")
            if crew and from and text ~= "" then
                local key = crew:lower()
                crewMsgs[key] = crewMsgs[key] or {}
                table.insert(crewMsgs[key], { from = from, text = text, time = time, crew = crew })
            end
        end
    end
    xmlUnloadFile(xml)
end

local function saveMessages()
    local xml = xmlCreateFile(MSGS_FILE, "messages")
    if not xml then return end
    for _, list in pairs(dms) do
        for _, m in ipairs(list) do
            local node = xmlCreateChild(xml, "dm")
            xmlNodeSetAttribute(node, "from", m.from)
            xmlNodeSetAttribute(node, "to", m.to)
            xmlNodeSetAttribute(node, "time", tostring(m.time))
            xmlNodeSetAttribute(node, "read", m.read and "1" or "0")
            xmlNodeSetValue(node, m.text)
        end
    end
    for _, list in pairs(crewMsgs) do
        for _, m in ipairs(list) do
            local node = xmlCreateChild(xml, "crew")
            xmlNodeSetAttribute(node, "crew", m.crew)
            xmlNodeSetAttribute(node, "from", m.from)
            xmlNodeSetAttribute(node, "time", tostring(m.time))
            xmlNodeSetValue(node, m.text)
        end
    end
    xmlSaveFile(xml)
    xmlUnloadFile(xml)
end

-- Debounced save so a burst of messages doesn't hammer the disk.
local function queueSaveMessages()
    if isTimer(saveMsgTimer) then killTimer(saveMsgTimer) end
    saveMsgTimer = setTimer(saveMessages, 3000, 1)
end

local function trimHistory(list)
    while #list > SP.MSG_HISTORY do
        table.remove(list, 1)
    end
end

--------------------------------------------------------------------------------
-- Snapshot to the client
--------------------------------------------------------------------------------

local function friendEntry(name)
    local online = onlinePlayerByAccount(name)
    local level, playtime = getProgress(name, online)
    local crew = crewOf(name)
    return {
        name = name, online = online ~= nil, level = level, playtime = playtime,
        crew = crew and crew.name or nil,
    }
end

-- Builds the "conversations" list for a player (DM partners + crew).
local function buildConversations(player, myName)
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
            last = last and (last.from .. ": " .. last.text) or "No messages yet.",
            time = last and last.time or 0, unread = unread,
        }
    end

    table.sort(convos, function(a, b) return (a.time or 0) > (b.time or 0) end)
    return convos
end

local function buildSnapshot(player)
    local myName = accName(player)
    if not myName then return nil end

    local friends = {}
    for _, fn in ipairs(getListFor(myName, SP.KEY_FRIENDS)) do
        friends[#friends + 1] = friendEntry(fn)
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
            local level, playtime = getProgress(mn, online)
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
        dir[#dir + 1] = { name = crew.name, tag = crew.tag, color = crew.color,
            founder = crew.founder, members = #crew.members }
    end
    table.sort(dir, function(a, b) return a.name:lower() < b.name:lower() end)

    return {
        account       = myName,
        friends       = friends,
        requests      = getListFor(myName, SP.KEY_REQ_IN),
        crew          = crewData,
        crews         = dir,
        conversations = buildConversations(player, myName),
    }
end

local function pushSnapshot(player)
    if not isElement(player) then return end
    applyCrewIdentity(player) -- keep crew name/tag/colour data in sync on every refresh
    local snap = buildSnapshot(player)
    if snap then triggerClientEvent(player, "sp:push", player, snap) end
end

local function pushBoth(a, b)
    if isElement(a) then pushSnapshot(a) end
    if isElement(b) and b ~= a then pushSnapshot(b) end
end

--------------------------------------------------------------------------------
-- Pull
--------------------------------------------------------------------------------

addEvent("sp:pull", true)
addEventHandler("sp:pull", root, function()
    if isElement(client) then pushSnapshot(client) end
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
    if targetName:lower() == myName:lower() then
        return notify(player, "You can't add yourself.", 255, 120, 120)
    end

    local targetAcc = accountByName(targetName)
    if not targetAcc then
        return notify(player, "No such player: " .. targetName, 255, 120, 120)
    end
    targetName = targetAcc

    local myAcc = myName
    local myFriends = getListFor(myAcc, SP.KEY_FRIENDS)
    if SP.contains(myFriends, targetName) then
        return notify(player, targetName .. " is already your friend.", 255, 200, 0)
    end
    if #myFriends >= SP.MAX_FRIENDS then
        return notify(player, "Your friend list is full.", 255, 120, 120)
    end

    -- If they already sent me a request, become friends immediately.
    local myIncoming = getListFor(myAcc, SP.KEY_REQ_IN)
    if SP.contains(myIncoming, targetName) then
        setListFor(myAcc, SP.KEY_REQ_IN, SP.removeValue(myIncoming, targetName))
        myFriends[#myFriends + 1] = targetName
        setListFor(myAcc, SP.KEY_FRIENDS, myFriends)

        local tFriends = getListFor(targetAcc, SP.KEY_FRIENDS)
        if not SP.contains(tFriends, myName) then
            tFriends[#tFriends + 1] = myName
            setListFor(targetAcc, SP.KEY_FRIENDS, tFriends)
        end
        notify(player, "You are now friends with " .. targetName, 0, 220, 0)
        local tp = onlinePlayerByAccount(targetName)
        notify(tp, "You are now friends with " .. myName, 0, 220, 0)
        return pushBoth(player, tp)
    end

    local tIncoming = getListFor(targetAcc, SP.KEY_REQ_IN)
    if SP.contains(tIncoming, myName) then
        return notify(player, "You already sent them a request.", 255, 200, 0)
    end
    tIncoming[#tIncoming + 1] = myName
    setListFor(targetAcc, SP.KEY_REQ_IN, tIncoming)
    notify(player, "Friend request sent to " .. targetName, 0, 220, 0)
    local tp = onlinePlayerByAccount(targetName)
    if tp then
        notify(tp, myName .. " sent you a friend request.", 0, 220, 0)
        pushSnapshot(tp)
    end
end)

addEvent("sp:friend:accept", true)
addEventHandler("sp:friend:accept", root, function(senderName)
    local player = client
    local myName = accName(player)
    if not myName or type(senderName) ~= "string" then return end

    local myAcc = myName
    local incoming = getListFor(myAcc, SP.KEY_REQ_IN)
    local ok, exact = SP.contains(incoming, senderName)
    if not ok then return notify(player, "No such request.", 255, 120, 120) end
    senderName = exact

    setListFor(myAcc, SP.KEY_REQ_IN, SP.removeValue(incoming, senderName))

    local senderAcc = accountByName(senderName)
    if not senderAcc then return notify(player, "That account no longer exists.", 255, 120, 120) end

    local myFriends = getListFor(myAcc, SP.KEY_FRIENDS)
    if not SP.contains(myFriends, senderName) then
        myFriends[#myFriends + 1] = senderName
        setListFor(myAcc, SP.KEY_FRIENDS, myFriends)
    end
    local sFriends = getListFor(senderAcc, SP.KEY_FRIENDS)
    if not SP.contains(sFriends, myName) then
        sFriends[#sFriends + 1] = myName
        setListFor(senderAcc, SP.KEY_FRIENDS, sFriends)
    end

    notify(player, "You accepted " .. senderName .. "'s request.", 0, 220, 0)
    local sp = onlinePlayerByAccount(senderName)
    notify(sp, myName .. " accepted your friend request.", 0, 220, 0)
    pushBoth(player, sp)
end)

addEvent("sp:friend:decline", true)
addEventHandler("sp:friend:decline", root, function(senderName)
    local player = client
    local myName = accName(player)
    if not myName or type(senderName) ~= "string" then return end
    local myAcc = myName
    local incoming = getListFor(myAcc, SP.KEY_REQ_IN)
    if not SP.contains(incoming, senderName) then return end
    setListFor(myAcc, SP.KEY_REQ_IN, SP.removeValue(incoming, senderName))
    notify(player, "Request declined.", 255, 200, 0)
    pushSnapshot(player)
end)

addEvent("sp:friend:remove", true)
addEventHandler("sp:friend:remove", root, function(friendName)
    local player = client
    local myName = accName(player)
    if not myName or type(friendName) ~= "string" then return end

    local myAcc = myName
    local myFriends = getListFor(myAcc, SP.KEY_FRIENDS)
    local ok, exact = SP.contains(myFriends, friendName)
    if not ok then return end
    friendName = exact

    setListFor(myAcc, SP.KEY_FRIENDS, SP.removeValue(myFriends, friendName))
    local fAcc = accountByName(friendName)
    if fAcc then
        setListFor(fAcc, SP.KEY_FRIENDS, SP.removeValue(getListFor(fAcc, SP.KEY_FRIENDS), myName))
    end
    notify(player, friendName .. " removed from your friend list.", 255, 200, 0)
    local fp = onlinePlayerByAccount(friendName)
    notify(fp, myName .. " removed you from their friend list.", 255, 200, 0)
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

    local acc = accountByName(name)
    if not acc then
        return triggerClientEvent(player, "sp:profile:show", player, false, name)
    end
    name = acc
    local online = onlinePlayerByAccount(name)
    local level, playtime = getProgress(name, online)
    local crew = crewOf(name)
    local myFriends = getListFor(myName, SP.KEY_FRIENDS)

    triggerClientEvent(player, "sp:profile:show", player, {
        name      = name,
        online    = online ~= nil,
        level     = level,
        playtime  = playtime,
        crew      = crew and crew.name or nil,
        crewTag   = crew and crew.tag or nil,
        crewColor = crew and crew.color or nil,
        isFriend  = (SP.contains(myFriends, name)),
        isSelf    = name:lower() == myName:lower(),
    })
end)

--------------------------------------------------------------------------------
-- Player search (online AND offline)
--------------------------------------------------------------------------------

addEvent("sp:search", true)
addEventHandler("sp:search", root, function(query)
    local player = client
    if not accName(player) or type(query) ~= "string" then return end
    query = query:gsub("^%s+", ""):gsub("%s+$", "")
    if #query < SP.SEARCH_MIN then
        return triggerClientEvent(player, "sp:search:results", player, {}, "Type at least " .. SP.SEARCH_MIN .. " characters.")
    end

    local needle = query:lower()
    local seen, results = {}, {}

    -- Online players first (live data).
    for _, p in ipairs(getElementsByType("player")) do
        local nm = accName(p)
        if nm and nm:lower():find(needle, 1, true) then
            seen[nm:lower()] = true
            results[#results + 1] = {
                name = nm, online = true,
                level = tostring(getElementData(p, "level") or "n/a"),
                playtime = tostring(getElementData(p, "Játékidő") or "n/a"),
            }
        end
    end

    -- Then registered accounts (offline).
    for _, nm in ipairs(exports.v_accounts:getAllAccountNames() or {}) do
        if #results >= SP.SEARCH_LIMIT then break end
        if nm and not seen[nm:lower()] and not nm:find("^#") and nm:lower():find(needle, 1, true) then
            seen[nm:lower()] = true
            local h, m = getData(nm, "Online.hours"), getData(nm, "Online.minutes")
            results[#results + 1] = {
                name = nm, online = false,
                level = tostring(getData(nm, "level") or "n/a"),
                playtime = (h or m) and SP.formatPlaytime(h, m) or "n/a",
            }
        end
    end

    table.sort(results, function(a, b)
        if a.online ~= b.online then return a.online end
        return a.name:lower() < b.name:lower()
    end)
    triggerClientEvent(player, "sp:search:results", player, results)
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
        local changed = false
        for _, m in ipairs(dms[SP.pairKey(myName, target)] or {}) do
            if m.to:lower() == myName:lower() and not m.read then
                m.read = true
                changed = true
            end
        end
        if changed then queueSaveMessages() end
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
    local now = getRealTime().timestamp

    if kind == "dm" then
        if target:lower() == myName:lower() then return end
        local targetAcc = accountByName(target)
        if not targetAcc then return notify(player, "No such player: " .. target, 255, 120, 120) end
        target = targetAcc

        local key = SP.pairKey(myName, target)
        dms[key] = dms[key] or {}
        table.insert(dms[key], { from = myName, to = target, text = text, time = now, read = false })
        trimHistory(dms[key])
        queueSaveMessages()

        triggerClientEvent(player, "sp:msg:data", player, "dm", target, collectThread(myName, "dm", target))
        pushSnapshot(player)

        local tp = onlinePlayerByAccount(target)
        if tp then
            triggerClientEvent(tp, "sp:notify", tp, "dm", myName, text)
            triggerClientEvent(tp, "sp:msg:data", tp, "dm", myName, collectThread(target, "dm", myName))
            pushSnapshot(tp)
        end

    elseif kind == "crew" then
        local crew = crewOf(myName)
        if not crew then return notify(player, "You are not in a crew.", 255, 120, 120) end
        crewMsgs[crew.name:lower()] = crewMsgs[crew.name:lower()] or {}
        table.insert(crewMsgs[crew.name:lower()], { from = myName, text = text, time = now, crew = crew.name })
        trimHistory(crewMsgs[crew.name:lower()])
        queueSaveMessages()

        for _, mn in ipairs(crew.members) do
            local mp = onlinePlayerByAccount(mn)
            if mp then
                if mp ~= player then
                    triggerClientEvent(mp, "sp:notify", mp, "crew", myName, text, crew.tag)
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
    if crewOf(myName) then return notify(player, "You already have a crew. Leave it first.", 255, 120, 120) end

    local okN, cleanName = SP.validateCrewName(name)
    if not okN then return notify(player, cleanName, 255, 120, 120) end
    local okT, cleanTag = SP.validateCrewTag(tag)
    if not okT then return notify(player, cleanTag, 255, 120, 120) end
    if crews[cleanName:lower()] then return notify(player, "A crew with that name already exists.", 255, 120, 120) end

    r = math.max(0, math.min(255, tonumber(r) or 255))
    g = math.max(0, math.min(255, tonumber(g) or 200))
    b = math.max(0, math.min(255, tonumber(b) or 0))

    crews[cleanName:lower()] = {
        name = cleanName, tag = cleanTag, color = { r, g, b },
        founder = myName, desc = "", members = { myName },
    }
    setData(player, SP.KEY_CREW, cleanName)
    saveCrews()
    notify(player, "Crew created: " .. cleanName .. " [" .. cleanTag .. "]", 0, 220, 0)
    pushSnapshot(player)
end)

addEvent("sp:crew:join", true)
addEventHandler("sp:crew:join", root, function(crewName)
    local player = client
    local myName = accName(player)
    if not myName or type(crewName) ~= "string" then return end
    if crewOf(myName) then return notify(player, "You already have a crew. Leave it first.", 255, 120, 120) end
    local crew = crews[crewName:lower()]
    if not crew then return notify(player, "No such crew.", 255, 120, 120) end
    if #crew.members >= SP.MAX_CREW_MEMBERS then return notify(player, "That crew is full.", 255, 120, 120) end

    crew.members[#crew.members + 1] = myName
    setData(player, SP.KEY_CREW, crew.name)
    saveCrews()
    notify(player, "You joined the crew " .. crew.name, 0, 220, 0)
    for _, mn in ipairs(crew.members) do
        local mp = onlinePlayerByAccount(mn)
        if mp and mp ~= player then notify(mp, myName .. " joined the crew.", 0, 220, 0) end
        if mp then pushSnapshot(mp) end
    end
end)

local function leaveCrew(player, silent)
    local myName = accName(player)
    if not myName then return end
    local crew = crewOf(myName)
    if not crew then
        if not silent then notify(player, "You are not in a crew.", 255, 120, 120) end
        return
    end

    crew.members = SP.removeValue(crew.members, myName)
    setData(player, SP.KEY_CREW, "")

    local disbanded = false
    if #crew.members == 0 then
        crews[crew.name:lower()] = nil
        crewMsgs[crew.name:lower()] = nil
        disbanded = true
    elseif myName:lower() == crew.founder:lower() then
        crew.founder = crew.members[1] -- founder passes to the oldest member
        notify(onlinePlayerByAccount(crew.founder), "You are now the founder of " .. crew.name .. ".", 255, 200, 0)
    end
    saveCrews()
    queueSaveMessages()

    if not silent then
        notify(player, disbanded and ("The crew " .. crew.name .. " was disbanded.") or ("You left " .. crew.name), 255, 200, 0)
    end
    for _, mn in ipairs(crew.members) do
        local mp = onlinePlayerByAccount(mn)
        if mp then
            notify(mp, myName .. " left the crew.", 255, 200, 0)
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
    local crew = crewOf(myName)
    if not crew or myName:lower() ~= crew.founder:lower() then
        return notify(player, "Only the founder can kick members.", 255, 120, 120)
    end
    if memberName:lower() == myName:lower() then return end
    local ok, exact = SP.contains(crew.members, memberName)
    if not ok then return end

    crew.members = SP.removeValue(crew.members, exact)
    local kAcc = accountByName(exact)
    if kAcc then setData(kAcc, SP.KEY_CREW, "") end
    saveCrews()

    local kp = onlinePlayerByAccount(exact)
    notify(kp, "You were kicked from the crew " .. crew.name .. ".", 255, 120, 120)
    if kp then pushSnapshot(kp) end
    notify(player, exact .. " kicked.", 255, 200, 0)
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
        return notify(player, "Only the founder can edit the crew.", 255, 120, 120)
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
    saveCrews()
    notify(player, "Crew updated.", 0, 220, 0)
    for _, mn in ipairs(crew.members) do
        local mp = onlinePlayerByAccount(mn)
        if mp then pushSnapshot(mp) end
    end
end)

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

addEventHandler("onResourceStart", resourceRoot, function()
    loadCrews()
    loadMessages()
    for _, player in ipairs(getElementsByType("player")) do
        if accName(player) then pushSnapshot(player) end
    end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    if isTimer(saveMsgTimer) then killTimer(saveMsgTimer) end
    saveMessages()
end)

-- onPlayerLoaded fires after the shared MySQL account-data sync. Keep a short
-- cushion so the other resources' onPlayerLoaded handlers (level, played-time)
-- have run before the snapshot is built.
addEvent("onPlayerLoaded")
addEventHandler("onPlayerLoaded", root, function()
    setTimer(pushSnapshot, 500, 1, source)
end)
