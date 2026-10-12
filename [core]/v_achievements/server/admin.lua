if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
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
    triggerClientEvent(player, "ach:notify", player, L.msg("v_achievements.admin.achievements"), text)
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

local USAGE = L.msg("v_achievements.admin.usage_ach_list_give_prog_stat")

addCommandHandler("ach", function(player, _, sub, who, a, b)
    if not isAdmin(player) then return reply(player, L.msg("v_achievements.admin.you_have_no_permission")) end
    who = target(who)
    if not sub or not who then return reply(player, USAGE) end

    if sub == "list" then
        local recs = getPlayerAchievements(who)
        if not recs then return reply(player, L.msg("v_achievements.admin.unknown_account")) end
        outputConsole("--- achievements of " .. tostring(isElement(who) and getPlayerName(who) or who) .. " ---", player)
        for _, def in ipairs(REG.list) do
            local r = recs[def.id]
            outputConsole(string.format("[%s] %-20s %s/%s  %s", r.done and "x" or " ",
                def.id, tostring(r.progress), tostring(r.goal), def.name), player)
        end
        local s = getPlayerAchievementSummary(who)
        reply(player, L.msg("v_achievements.admin.unlocked_list_printed_to_f8", { done = s.done, total = s.total }))
    elseif sub == "give" then
        if not REG.byId[a] then return reply(player, L.msg("v_achievements.admin.unknown_achievement_id")) end
        reply(player, unlockAchievement(who, a) and (L.msg("v_achievements.admin.unlocked", { a = a })) or L.msg("v_achievements.admin.already_unlocked_no_account"))
    elseif sub == "prog" then
        reply(player, addAchievementProgress(who, a, b) and L.msg("v_achievements.admin.progress_added") or L.msg("v_achievements.admin.ignored_done_bad_id_bad_amount"))
    elseif sub == "stat" then
        reply(player, addStat(who, a, b) and L.msg("v_achievements.admin.stat_added") or L.msg("v_achievements.admin.ignored_all_done_unknown_stat_bad"))
    elseif sub == "reset" then
        if not a then return reply(player, L.msg("v_achievements.admin.usage_ach_reset_player_id_all")) end
        local ok = resetPlayerAchievement(who, a ~= "all" and a or nil)
        reply(player, ok and L.msg("v_achievements.admin.reset_done") or L.msg("v_achievements.admin.unknown_account_id"))
    else
        reply(player, USAGE)
    end
end)
