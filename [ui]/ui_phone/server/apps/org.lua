if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
--[[
    ui_phone / server/apps/org.lua
    Organization app: temporary associates of biz_core organizations.
    Founders invite players and remove associates, invited players accept or
    decline, associates leave. The memberships live in biz_core (memory only:
    they end on leave / disconnect); this file only relays.
]]

local function bizRunning()
    local r = getResourceFromName("biz_core")
    return r and getResourceState(r) == "running"
end

local function push(player)
    if not isElement(player) or getElementType(player) ~= "player" then return end
    local state = bizRunning() and exports.biz_core:getMembershipState(player) or false
    PhoneServer.push(player, "org:state", state or false)
end

local function pushCompany(companyId)
    if not bizRunning() or not companyId then return end
    for _, p in ipairs(exports.biz_core:getCompanyMembers(companyId) or {}) do push(p) end
end

PhoneServer.onPull(push)

local ERRORS = {
    no_company = "ui_phone.org.err_no_company",
    bad_target = "ui_phone.org.err_bad_target",
    not_logged_in = "ui_phone.org.err_not_logged_in",
    already_member = "ui_phone.org.err_already_member",
    member_elsewhere = "ui_phone.org.err_member_elsewhere",
    full = "ui_phone.org.err_full",
    no_invite = "ui_phone.org.err_no_invite",
    not_member = "ui_phone.org.err_not_member",
}

local function result(player, ok, err)
    if not ok and err then PhoneServer.toast(player, L.forPlayer(player, ERRORS[err] or "ui_phone.org.err_failed")) end
    push(player)
end

PhoneServer.on("org:invite", function(player, target)
    if not bizRunning() or not isElement(target) then return push(player) end
    local ok, err = exports.biz_core:inviteAssociate(player, target)
    result(player, ok, err)
    push(target)
end)

PhoneServer.on("org:accept", function(player, companyId)
    if not bizRunning() then return end
    local ok, err = exports.biz_core:acceptInvite(player, tonumber(companyId))
    result(player, ok, err)
    if ok then pushCompany(tonumber(companyId)) end
end)

PhoneServer.on("org:decline", function(player, companyId)
    if not bizRunning() then return end
    exports.biz_core:declineInvite(player, tonumber(companyId))
    push(player)
end)

PhoneServer.on("org:leave", function(player)
    if not bizRunning() then return end
    local companyId = exports.biz_core:getPlayerMembership(player)
    exports.biz_core:leaveCompany(player)
    push(player)
    pushCompany(companyId)
end)

PhoneServer.on("org:remove", function(player, target)
    if not bizRunning() or not isElement(target) then return end
    local ok, err = exports.biz_core:removeAssociate(player, target)
    result(player, ok, err)
    push(target)
end)

-- biz_core changes (another player's action, a disconnect, the founder leaving)
addEvent("onBizMembershipChanged", false)
addEvent("onBizInvitesChanged", false)
addEvent("onBizCompanyLoaded", false)

addEventHandler("onBizMembershipChanged", root, function(companyId)
    push(source)
    pushCompany(companyId)
end)

addEventHandler("onBizInvitesChanged", root, function()
    push(source)
end)

addEventHandler("onBizCompanyLoaded", root, function(companyId, founder)
    push(founder)
end)
