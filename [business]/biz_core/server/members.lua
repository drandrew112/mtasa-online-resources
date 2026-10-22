if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- biz_core / server/members.lua
-- Temporary associates. Memory only (never in MySQL): a membership ends when
-- the associate leaves, disconnects or is removed, and when the founder
-- disconnects (the company stops then). An associate may own a company of his
-- own; the two roles are independent. Founder + BIZ.MAX_ASSOCIATES members.
--
-- The phone app (ui_phone Organization) drives it through these exports:
--   inviteAssociate(founder, target)        -> true | false, err
--   acceptInvite(player, companyId)         -> true | false, err
--   declineInvite(player, companyId)
--   leaveCompany(player)
--   removeAssociate(founder, target)
--   getMembershipState(player)              -> table for the phone
-- Event onBizMembershipChanged (companyId, joined, reason) - source = the associate.

MEM = { of = {}, list = {}, invites = {} }
-- MEM.list[companyId] = { [player] = joinedTimestamp }
-- MEM.of[player]      = companyId
-- MEM.invites[player] = { [companyId] = expiresTick }

addEvent("onBizMembershipChanged", false)
addEvent("onBizInvitesChanged", false)    -- source = the invited player

function MEM.membersOf(companyId)
    return MEM.list[companyId] or {}
end

function MEM.count(companyId)
    local n = 0
    for _ in pairs(MEM.list[companyId] or {}) do n = n + 1 end
    return n
end

--- associates of a company; withPlayers adds the player elements (phone app)
function MEM.publicList(companyId, withPlayers)
    local out = {}
    for p, since in pairs(MEM.list[companyId] or {}) do
        if isElement(p) then
            out[#out + 1] = { name = getPlayerName(p):gsub("#%x%x%x%x%x%x", ""), account = CO.accountOf(p), since = since,
                              player = withPlayers and p or nil }
        end
    end
    table.sort(out, function(a, b) return a.since < b.since end)
    return out
end

local function setMemberData(player, c)
    if not isElement(player) then return end
    if c then
        setElementData(player, "biz:member", { id = c.id, name = c.name }, "local")
    else
        removeElementData(player, "biz:member")
    end
end

local function changed(player, companyId, joined, reason)
    triggerEvent("onBizMembershipChanged", player, companyId, joined, reason)
    triggerEvent("onBizAccessChanged", player)
    local c = CO.byId[companyId]
    if c then CO.publish(c) end
end

local function purgeInvites(player)
    local inv = MEM.invites[player]
    if not inv then return end
    local now = getTickCount()
    for id, exp in pairs(inv) do
        if exp < now or not CO.byId[id] then inv[id] = nil end
    end
end

function MEM.invitesOf(player)
    purgeInvites(player)
    local out = {}
    for id, exp in pairs(MEM.invites[player] or {}) do
        local c = CO.byId[id]
        if c then
            out[#out + 1] = {
                companyId = id, name = c.name,
                founder = isElement(c.founder) and getPlayerName(c.founder):gsub("#%x%x%x%x%x%x", "") or "",
                expiresIn = math.max(0, math.floor((exp - getTickCount()) / 1000)),
            }
        end
    end
    table.sort(out, function(a, b) return a.companyId < b.companyId end)
    return out
end

--------------------------------------------------------------------------------

function MEM.invite(founder, target)
    local c = CO.ofPlayer(founder)
    if not c or c.founder ~= founder then return false, "no_company" end
    if not isElement(target) or getElementType(target) ~= "player" or target == founder then return false, "bad_target" end
    if not CO.accountOf(target) then return false, "not_logged_in" end
    if MEM.of[target] == c.id then return false, "already_member" end
    if MEM.of[target] then return false, "member_elsewhere" end
    if MEM.count(c.id) >= BIZ.MAX_ASSOCIATES then return false, "full" end
    MEM.invites[target] = MEM.invites[target] or {}
    MEM.invites[target][c.id] = getTickCount() + BIZ.INVITE_TTL * 1000
    triggerEvent("onBizInvitesChanged", target)
    NOTIFY.player(target, L.msg("biz_core.members.invited_you", { company = c.name, founder = getPlayerName(founder) }))
    NOTIFY.player(founder, L.msg("biz_core.members.invite_sent", { player = getPlayerName(target) }))
    return true
end

function MEM.accept(player, companyId)
    companyId = tonumber(companyId)
    purgeInvites(player)
    local inv = MEM.invites[player]
    if not companyId or not inv or not inv[companyId] then return false, "no_invite" end
    local c = CO.byId[companyId]
    if not c or not isElement(c.founder) then return false, "no_company" end
    if MEM.of[player] then return false, "member_elsewhere" end
    if MEM.count(c.id) >= BIZ.MAX_ASSOCIATES then return false, "full" end
    inv[companyId] = nil
    MEM.list[c.id] = MEM.list[c.id] or {}
    MEM.list[c.id][player] = BIZ.now()
    MEM.of[player] = c.id
    setMemberData(player, c)
    triggerEvent("onBizInvitesChanged", player)
    changed(player, c.id, true, "joined")
    NOTIFY.company(c, "all", L.msg("biz_core.members.joined", { player = getPlayerName(player) }))
    return true
end

function MEM.decline(player, companyId)
    companyId = tonumber(companyId)
    local inv = MEM.invites[player]
    if not inv or not companyId or not inv[companyId] then return false end
    inv[companyId] = nil
    triggerEvent("onBizInvitesChanged", player)
    local c = CO.byId[companyId]
    if c and isElement(c.founder) then
        NOTIFY.player(c.founder, L.msg("biz_core.members.declined", { player = getPlayerName(player) }))
    end
    return true
end

--- ends a membership. reason: "left" | "quit" | "removed" | "founder_quit" | "sold"
function MEM.leave(player, reason)
    local id = MEM.of[player]
    if not id then return false end
    MEM.of[player] = nil
    if MEM.list[id] then MEM.list[id][player] = nil end
    if isElement(player) and reason ~= "quit" then setMemberData(player, nil) end
    local c = CO.byId[id]
    local name = isElement(player) and getPlayerName(player) or "?"
    if reason ~= "quit" then
        local key = reason == "removed" and "biz_core.members.you_were_removed"
            or (reason == "founder_quit" or reason == "sold") and "biz_core.members.company_closed"
            or "biz_core.members.you_left"
        NOTIFY.player(player, L.msg(key, { company = c and c.name or "" }))
    end
    if c and reason ~= "founder_quit" and reason ~= "sold" then
        NOTIFY.player(c.founder, L.msg(reason == "removed" and "biz_core.members.removed" or "biz_core.members.left", { player = name }))
    end
    if isElement(player) then changed(player, id, false, reason) end
    return true
end

function MEM.removeAll(companyId, reason)
    local list = {}
    for p in pairs(MEM.list[companyId] or {}) do list[#list + 1] = p end
    for _, p in ipairs(list) do MEM.leave(p, reason) end
    MEM.list[companyId] = nil
    -- pending invitations of that company die with it
    for p, inv in pairs(MEM.invites) do
        if inv[companyId] then
            inv[companyId] = nil
            if isElement(p) then triggerEvent("onBizInvitesChanged", p) end
        end
    end
end

function MEM.remove(founder, target)
    local c = CO.ofPlayer(founder)
    if not c or c.founder ~= founder then return false, "no_company" end
    if MEM.of[target] ~= c.id then return false, "not_member" end
    return MEM.leave(target, "removed")
end

addEventHandler("onPlayerQuit", root, function()
    MEM.leave(source, "quit")
    MEM.invites[source] = nil
end)

--------------------------------------------------------------------------------
-- exports
--------------------------------------------------------------------------------

function inviteAssociate(founder, target) return MEM.invite(founder, target) end
function acceptInvite(player, companyId) return MEM.accept(player, companyId) end
function declineInvite(player, companyId) return MEM.decline(player, companyId) end
function leaveCompany(player) return MEM.leave(player, "left") end
function removeAssociate(founder, target) return MEM.remove(founder, target) end

--- "founder" | "associate" | false
function getPlayerRole(player, companyId)
    local c = CO.byId[tonumber(companyId)]
    if not c or not isElement(player) then return false end
    if c.founder == player then return "founder" end
    if MEM.of[player] == c.id then return "associate" end
    return false
end

--- founder + associates (online players)
function getCompanyMembers(companyId)
    local c = CO.byId[tonumber(companyId)]
    if not c then return {} end
    local out = {}
    if isElement(c.founder) then out[#out + 1] = c.founder end
    for p in pairs(MEM.list[c.id] or {}) do
        if isElement(p) then out[#out + 1] = p end
    end
    return out
end

function getAssociateCount(companyId)
    return MEM.count(tonumber(companyId))
end

--- company id the player is an associate of, or false
function getPlayerMembership(player)
    return MEM.of[player] or false
end

--- everything the phone app shows
function getMembershipState(player)
    if not isElement(player) then return false end
    local state = { invites = MEM.invitesOf(player), max = BIZ.MAX_ASSOCIATES }
    local own = CO.ofPlayer(player)
    if own and own.founder == player then
        state.own = { id = own.id, name = own.name, associates = MEM.publicList(own.id, true) }
        -- who could be invited: logged-in players of this instance, not in this company
        local candidates = {}
        local fx, fy, fz = getElementPosition(player)
        for _, p in ipairs(getElementsByType("player")) do
            if p ~= player and CO.accountOf(p) and MEM.of[p] ~= own.id and not getElementData(p, "intro.active") then
                local x, y, z = getElementPosition(p)
                candidates[#candidates + 1] = {
                    player = p, name = getPlayerName(p):gsub("#%x%x%x%x%x%x", ""),
                    distance = math.floor(getDistanceBetweenPoints3D(fx, fy, fz, x, y, z)),
                    busy = MEM.of[p] and true or false,
                    invited = MEM.invites[p] and MEM.invites[p][own.id] and MEM.invites[p][own.id] > getTickCount() or false,
                }
            end
        end
        table.sort(candidates, function(a, b) return a.distance < b.distance end)
        state.candidates = candidates
    end
    local mid = MEM.of[player]
    local mc = mid and CO.byId[mid]
    if mc then
        state.member = {
            id = mc.id, name = mc.name, since = MEM.list[mc.id] and MEM.list[mc.id][player] or 0,
            founder = isElement(mc.founder) and getPlayerName(mc.founder):gsub("#%x%x%x%x%x%x", "") or "",
            associates = MEM.publicList(mc.id), share = BIZ.ASSOCIATE_SHARE,
        }
    end
    return state
end
