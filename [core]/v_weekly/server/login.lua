-- Login bonus: money and/or XP paid when a player logs in, once per period
-- (WEEKLY.LOGIN_BONUS_PERIOD = "day" | "week"). The amount comes from the
-- running week's loginBonus.

LOGIN = {}

local function periodId()
    if WEEKLY.LOGIN_BONUS_PERIOD == "week" then return SCHED.currentWeek() end
    local ts = getRealTime().timestamp
    return math.floor((ts + tzOffset(ts)) / 86400) -- Budapest calendar day
end

local function accName(player)
    local n = getElementData(player, "accName")
    return (getElementData(player, "isLogged") == true and type(n) == "string" and n ~= "") and n or nil
end

-- Pays the bonus if it is due. -> money, xp  (nil when nothing was paid)
function LOGIN.claim(player)
    local name = accName(player)
    if not name or not STORE.isLoaded() then return nil end

    local bonus = SCHED.resolve(SCHED.currentWeek()).loginBonus
    if not bonus or (bonus.money <= 0 and bonus.xp <= 0) then return nil end

    local id = periodId()
    if tonumber(exports.v_mysql:getAccData(name, WEEKLY.LOGIN_KEY)) == id then return nil end
    exports.v_mysql:setAccData(name, WEEKLY.LOGIN_KEY, id)

    local money, xp = bonus.money, bonus.xp
    if money > 0 then givePlayerMoney(player, money) end
    if xp > 0 then
        local res = getResourceFromName("v_levelsys")
        if res and getResourceState(res) == "running" then
            exports.v_levelsys:giveXp(player, xp)
        else
            xp = 0
        end
    end
    if money <= 0 and xp <= 0 then return nil end
    return money, xp
end
