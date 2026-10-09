-- /ach admin command. Feedback goes to a ui_core notification (the chatbox is
-- hidden by v_chat); /ach list prints to the F8 console.
--
--   /ach list   <player>
--   /ach give   <player> <id>
--   /ach prog   <player> <id> <amount>
--   /ach stat   <player> <stat> <amount>
--   /ach reset  <player> <id|all>

local function isAdmin(player)
    if getElementData(player, "isLogged") ~= true then return false end
    return (tonumber(exports.v_mysql:getAccData(player, "admin_level")) or 0) > ACH.ADMIN_LEVEL
end

local function reply(player, text)
    triggerClientEvent(player, "ach:notify", player, "Achievements", text)
end

-- online player by (partial) nick, else the argument as an account name
local function target(arg)
    if not arg then return nil end
    local p = getPlayerFromName(arg)
    if p then return p end
    local lower = arg:lower()
    for _, pl in ipairs(getElementsByType("player")) do
        if getPlayerName(pl):lower():find(lower, 1, true) then return pl end
    end
    return arg
end

local USAGE = "Usage: /ach list|give|prog|stat|reset <player> ..."

addCommandHandler("ach", function(player, _, sub, who, a, b)
    if not isAdmin(player) then return reply(player, "You have no permission.") end
    who = target(who)
    if not sub or not who then return reply(player, USAGE) end

    if sub == "list" then
        local recs = getPlayerAchievements(who)
        if not recs then return reply(player, "Unknown account.") end
        outputConsole("--- achievements of " .. tostring(isElement(who) and getPlayerName(who) or who) .. " ---", player)
        for _, def in ipairs(REG.list) do
            local r = recs[def.id]
            outputConsole(string.format("[%s] %-20s %s/%s  %s", r.done and "x" or " ",
                def.id, tostring(r.progress), tostring(r.goal), def.name), player)
        end
        local s = getPlayerAchievementSummary(who)
        reply(player, string.format("%d/%d unlocked - list printed to F8.", s.done, s.total))
    elseif sub == "give" then
        if not REG.byId[a] then return reply(player, "Unknown achievement id.") end
        reply(player, unlockAchievement(who, a) and ("Unlocked " .. a .. ".") or "Already unlocked / no account.")
    elseif sub == "prog" then
        reply(player, addAchievementProgress(who, a, b) and "Progress added." or "Ignored (done / bad id / bad amount).")
    elseif sub == "stat" then
        reply(player, addStat(who, a, b) and "Stat added." or "Ignored (all done / unknown stat / bad amount).")
    elseif sub == "reset" then
        if not a then return reply(player, "Usage: /ach reset <player> <id|all>") end
        local ok = resetPlayerAchievement(who, a ~= "all" and a or nil)
        reply(player, ok and "Reset done." or "Unknown account / id.")
    else
        reply(player, USAGE)
    end
end)
