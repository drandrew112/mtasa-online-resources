if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- biz_missions / server/main.lua
-- Exports for the activity resources (biz_weed now) and the mission log table.
--
--   startSupplyMission(founder, unitId)                                 -> true | false, err
--   startSellMission(founder, unitId, amount, unitValue, perVehicle)    -> true | false, err
--   getUnitMission(unitId)          -> { kind, label, left, vehicles } | false
--   cancelUnitMission(unitId)

local function checkFounder(founder, unitId)
    if not M.running("biz_core") then return nil, "activity_offline" end
    if M.byUnit[unitId] then return nil, "mission_running" end
    if M.core():canAccessUnit(founder, unitId) ~= "founder" then return nil, "no_access" end
    local st = M.running("biz_weed") and exports.biz_weed:getWeedState(unitId)
    if not st then return nil, "activity_offline" end
    if (st.cooldown or 0) > 0 then return nil, "mission_cooldown" end
    return st
end

function startSupplyMission(founder, unitId)
    unitId = tonumber(unitId)
    local st, err = checkFounder(founder, unitId)
    if not st then return false, err end
    return SUPPLY.start(founder, unitId, st)
end

function startSellMission(founder, unitId, amount, unitValue, perVehicle)
    unitId, amount = tonumber(unitId), math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, "no_product" end
    local st, err = checkFounder(founder, unitId)
    if not st then return false, err end
    return SELL.start(founder, unitId, st, amount, tonumber(unitValue) or 1500, tonumber(perVehicle) or 40)
end

function getUnitMission(unitId)
    local m = M.byUnit[tonumber(unitId)]
    if not m then return false end
    local vans = 0
    if m.kind == "sell" then vans = #SELL.activeVans(m) end
    return {
        kind = m.kind, left = M.secondsLeft(m), vehicles = vans,
        label = m.kind == "supply" and ("Supply run: " .. m.spot.name) or ("Delivery: " .. (m.amount or 0) .. " units"),
    }
end

function cancelUnitMission(unitId)
    local m = M.byUnit[tonumber(unitId)]
    if not m then return false end
    M.finish(m, "cancelled")
    return true
end

-- the founder left (or the company was sold): the company stops, so do its missions
addEvent("onBizCompanyUnloaded", false)
addEventHandler("onBizCompanyUnloaded", root, function(companyId)
    local list = {}
    for _, m in pairs(M.list) do if m.companyId == companyId then list[#list + 1] = m end end
    for _, m in ipairs(list) do M.finish(m, "founder_left") end
end)

addEvent("onBizUnitRemoved", false)
addEventHandler("onBizUnitRemoved", root, function(unitId)
    local m = M.byUnit[unitId]
    if m then M.finish(m, "cancelled") end
end)

-- the team changed: objectives / HUD for the new set of players
addEvent("onBizMembershipChanged", false)
addEventHandler("onBizMembershipChanged", root, function(companyId, joined)
    for _, m in pairs(M.list) do
        if m.companyId == companyId then
            if not joined then
                M.clearObjectives(m, source)
                M.hudOff(m, source)
            end
            if m.kind == "sell" then SELL.refresh(m) end
        end
    end
end)

addEventHandler("onResourceStart", resourceRoot, function()
    math.randomseed(getTickCount())
    if M.running("v_mysql") then
        exports.v_mysql:mysqlExec([[CREATE TABLE IF NOT EXISTS biz_missions (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            unit_id INT UNSIGNED NOT NULL,
            company_id INT UNSIGNED NOT NULL,
            kind VARCHAR(16) NOT NULL,
            result VARCHAR(16) NOT NULL,
            amount INT NOT NULL DEFAULT 0,
            vehicles INT NOT NULL DEFAULT 0,
            payout_company BIGINT NOT NULL DEFAULT 0,
            payouts_json TEXT NULL,
            started_at INT UNSIGNED NOT NULL,
            ended_at INT UNSIGNED NOT NULL,
            PRIMARY KEY (id),
            KEY idx_company (company_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    end
end)

-- a restart ends every mission (product of sell missions goes back half, like a disconnect)
addEventHandler("onResourceStop", resourceRoot, function()
    local list = {}
    for _, m in pairs(M.list) do list[#list + 1] = m end
    for _, m in ipairs(list) do M.finish(m, "cancelled") end
end)
