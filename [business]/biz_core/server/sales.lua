if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- biz_core / server/sales.lua
-- Payout of a delivered supply/deliver shipment and the weekly sale
-- multipliers (set by v_weekly, Business bonuses; supply_deliver kinds only).
--
--   exports.biz_core:paySaleDelivery(companyId, player, baseValue, units, activity)
--     -> { role, value, toPlayer, toCompany } | false
--   role "founder":   whole value to the company (dirty)
--   role "associate": BIZ.ASSOCIATE_SHARE to his bank, the rest to the company
--   role "stranger":  BIZ.THIEF_SHARE to his bank, nothing to the company
--                     (0 when he shares serial / IP with the founder)

SALES = { mult = {} }

function setSaleMultiplier(activity, mult)
    if type(activity) ~= "string" then return false end
    mult = tonumber(mult)
    if not mult or mult <= 0 or mult == 1 then SALES.mult[activity] = nil else SALES.mult[activity] = mult end
    return true
end

function clearSaleMultipliers()
    SALES.mult = {}
    return true
end

--- multiplier of an activity (1 for passive kinds)
function getSaleMultiplier(activity)
    local a = ACT.list[activity]
    if a and a.kind ~= BIZ.KIND_SUPPLY_DELIVER then return 1 end
    return SALES.mult[activity] or 1
end

function getSaleMultipliers()
    local out = {}
    for k, v in pairs(SALES.mult) do out[k] = v end
    return out
end

local function sameMachine(a, b)
    if not isElement(a) or not isElement(b) then return false end
    return getPlayerSerial(a) == getPlayerSerial(b) or getPlayerIP(a) == getPlayerIP(b)
end

local function bankGive(player, amount)
    if amount <= 0 or not BIZ.running("v_bank") then return end
    exports.v_bank:giveBankMoney(player, amount)
end

function paySaleDelivery(companyId, player, baseValue, units, activity)
    local c = CO.byId[tonumber(companyId)]
    if not c or not isElement(player) then return false end
    units = math.floor(tonumber(units) or 0)
    local value = math.floor((tonumber(baseValue) or 0) * getSaleMultiplier(activity))
    if value <= 0 then return false end
    local name = getPlayerName(player):gsub("#%x%x%x%x%x%x", "")
    local out = { value = value, toPlayer = 0, toCompany = 0 }

    if c.founder == player then
        out.role, out.toCompany = "founder", value
        MONEY.credit(c, value, (activity or "sale") .. ".sale", ("Delivery by %s (%d units)"):format(name, units), c.account, true)
        STAT.add(player, STAT.IDS.sales_income, value)
    elseif MEM.of[player] == c.id then
        out.role = "associate"
        out.toPlayer = math.floor(value * BIZ.ASSOCIATE_SHARE)
        out.toCompany = value - out.toPlayer
        bankGive(player, out.toPlayer)
        ACTION.addDirtyAcc(player, BIZ.ACC_DIRTY_RECEIVED, out.toPlayer)
        MONEY.credit(c, out.toCompany, (activity or "sale") .. ".sale",
            ("Delivery by %s (%d units), %d%% share"):format(name, units, math.floor((1 - BIZ.ASSOCIATE_SHARE) * 100 + 0.5)), c.account, true)
        STAT.add(player, STAT.IDS.assoc_deliveries, 1)
        STAT.add(player, STAT.IDS.assoc_income, out.toPlayer)
        STAT.add(player, STAT.IDS.sales_income, out.toPlayer)
        if isElement(c.founder) then STAT.add(c.founder, STAT.IDS.sales_income, out.toCompany) end
    else
        out.role = "stranger"
        if not sameMachine(player, c.founder) then
            out.toPlayer = math.floor(value * BIZ.THIEF_SHARE)
            bankGive(player, out.toPlayer)
            ACTION.addDirtyAcc(player, BIZ.ACC_DIRTY_RECEIVED, out.toPlayer)
            STAT.add(player, STAT.IDS.hijacks, 1)
            STAT.unlock(player, "biz_highwayman")
        end
    end
    if out.role ~= "stranger" and units > 0 then
        STAT.add(player, STAT.IDS.weed_sold, units)
        STAT.add(player, STAT.IDS.deliveries, 1)
    end
    return out
end
