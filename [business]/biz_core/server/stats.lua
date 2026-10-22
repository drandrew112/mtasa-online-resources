-- biz_core / server/stats.lua
-- Bridge to v_stats (Business category counters) and v_achievements. Every
-- call is a no-op while the target resource is not running.
--
--   exports.biz_core:addBizStat(playerOrAccount, statId, amount)
--   exports.biz_core:unlockBizAchievement(playerOrAccount, achievementId)

STAT = {}

local function running(name)
    local r = getResourceFromName(name)
    return r and getResourceState(r) == "running"
end

-- v_stats ids (v_stats/config.lua, category "business"); the same keys are the
-- achievement stats where an achievement counts them
STAT.IDS = {
    weed_sold        = "biz_weed_sold",
    sales_income     = "biz_sales_income",
    deliveries       = "biz_deliveries",
    deliveries_lost  = "biz_deliveries_lost",
    supply_stolen    = "biz_supply_stolen",
    supply_runs      = "biz_supply_runs",
    supply_bought    = "biz_supply_bought",
    hijacks          = "biz_hijacks",
    casino_income    = "biz_casino_income",
    laundered        = "biz_laundered",
    assoc_deliveries = "biz_assoc_deliveries",
    assoc_income     = "biz_assoc_income",
}

function STAT.add(who, id, amount)
    amount = tonumber(amount)
    if not who or not id or not amount or amount <= 0 then return false end
    if not running("v_stats") then return false end
    return exports.v_stats:addStat(who, id, amount)
end

function STAT.unlock(who, achId)
    if not who or not achId or not running("v_achievements") then return false end
    return exports.v_achievements:unlockAchievement(who, achId)
end

--- absolute achievement counter (never lowered by v_achievements)
function STAT.setAch(who, stat, value)
    if not who or not running("v_achievements") then return false end
    return exports.v_achievements:setStat(who, stat, math.floor(tonumber(value) or 0))
end

-- company value achievements: progress on the "biz_value" achievement stat
function STAT.value(account, value)
    if account then STAT.setAch(account, "biz_value", value) end
end

function addBizStat(who, id, amount)
    return STAT.add(who, id, amount)
end

function unlockBizAchievement(who, achId)
    return STAT.unlock(who, achId)
end
