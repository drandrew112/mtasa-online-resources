if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- biz_missions / server/common.lua
-- Mission registry and the shared helpers: the team (founder + associates
-- online), radar objectives, the HUD (time left + trackers), notifications,
-- cleanup. One mission per property at a time; missions are instance-local.
--
-- Mission record: { id, kind ("supply" | "sell"), unitId, companyId, founder,
--   startTick, endTick, elements = { el }, objectives = { [player] = { [key] = id } },
--   hudPlayers = { [player] = true }, update = fn(m), onEnd = fn(m, result), ... }

M = { list = {}, byUnit = {}, nextId = 1 }

local function running(name)
    local r = getResourceFromName(name)
    return r and getResourceState(r) == "running"
end
M.running = running

function M.core() return exports.biz_core end

function M.rand(range) return math.random(range[1], range[2]) end

function M.pick(list) return list[math.random(1, #list)] end

function M.name(p)
    if not isElement(p) then return "?" end
    local d = getElementData(p, "displayName")
    if type(d) ~= "string" or d == "" then d = getPlayerName(p) end
    return (d:gsub("#%x%x%x%x%x%x", ""))
end

--- founder + associates online
function M.team(m)
    if not running("biz_core") then return {} end
    return M.core():getCompanyMembers(m.companyId) or {}
end

function M.isTeam(m, player)
    return running("biz_core") and M.core():getPlayerRole(player, m.companyId) and true or false
end

function M.notify(player, key, params)
    if running("biz_core") then M.core():notifyPlayer(player, L.msg(key, params)) end
end

function M.notifyTeam(m, key, params)
    for _, p in ipairs(M.team(m)) do M.notify(p, key, params) end
end

function M.secondsLeft(m)
    return math.max(0, math.floor((m.endTick - getTickCount()) / 1000))
end

--------------------------------------------------------------------------------
-- radar objectives (v_radar): one per player and key
--------------------------------------------------------------------------------

function M.objective(m, player, key, x, y, z, label)
    if not isElement(player) or not running("v_radar") then return end
    m.objectives[player] = m.objectives[player] or {}
    local id = m.objectives[player][key]
    if id then
        exports.v_radar:updateObjective(player, id, x, y, z, label)
    else
        m.objectives[player][key] = exports.v_radar:addObjective(player, x, y, z, label)
    end
end

function M.clearObjective(m, player, key)
    local list = m.objectives[player]
    if not list or not list[key] then return end
    if running("v_radar") and isElement(player) then exports.v_radar:removeObjective(player, list[key]) end
    list[key] = nil
end

function M.clearObjectives(m, player)
    for key in pairs(m.objectives[player] or {}) do M.clearObjective(m, player, key) end
    m.objectives[player] = nil
end

--------------------------------------------------------------------------------
-- HUD: time left + stat rows (client/hud.lua)
--------------------------------------------------------------------------------

--- rows = { { id, label = msg, value = text } }
function M.hud(m, player, rows)
    if not isElement(player) then return end
    m.hudPlayers[player] = true
    triggerClientEvent(player, "bizmis:hud", resourceRoot, { left = M.secondsLeft(m), rows = rows or {} })
end

function M.hudOff(m, player)
    if not m.hudPlayers[player] then return end
    m.hudPlayers[player] = nil
    if isElement(player) then triggerClientEvent(player, "bizmis:hud", resourceRoot, false) end
end

--------------------------------------------------------------------------------
-- lifecycle
--------------------------------------------------------------------------------

function M.track(m, el)
    if isElement(el) then m.elements[#m.elements + 1] = el end
    return el
end

function M.create(kind, unitId, companyId, founder)
    local m = {
        id = M.nextId, kind = kind, unitId = unitId, companyId = companyId, founder = founder,
        startTick = getTickCount(), endTick = getTickCount() + MIS.DEADLINE * 1000,
        startedAt = getRealTime().timestamp,
        elements = {}, objectives = {}, hudPlayers = {}, peds = {}, areas = {},
    }
    M.nextId = M.nextId + 1
    M.list[m.id] = m
    M.byUnit[unitId] = m
    return m
end

--- ends a mission. result: "success" | "failed" | "timeout" | "cancelled" | "founder_left"
function M.finish(m, result, info)
    if not M.list[m.id] then return end
    M.list[m.id] = nil
    if M.byUnit[m.unitId] == m then M.byUnit[m.unitId] = nil end
    if m.onEnd then pcall(m.onEnd, m, result, info) end

    for p in pairs(m.objectives) do M.clearObjectives(m, p) end
    for p in pairs(m.hudPlayers) do M.hudOff(m, p) end
    for _, id in ipairs(m.areas) do
        if running("v_radar") then exports.v_radar:removeCircleArea(id) end
    end
    for ped in pairs(m.peds) do
        if isElement(ped) and running("ai_peds") then exports.ai_peds:destroyAIPed(ped) end
    end
    for _, el in ipairs(m.elements) do if isElement(el) then destroyElement(el) end end
    if running("biz_weed") then exports.biz_weed:setMissionCooldown(m.unitId, MIS.COOLDOWN) end

    if running("v_mysql") then
        exports.v_mysql:mysqlExec([[INSERT INTO biz_missions (unit_id, company_id, kind, result, amount, vehicles,
            payout_company, payouts_json, started_at, ended_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
            m.unitId, m.companyId, m.kind, result, m.amount or 0, m.vehicleCount or 0, m.payoutCompany or 0,
            toJSON(m.payouts or {}, true), m.startedAt, getRealTime().timestamp)
    end
end

-- one loop for every running mission
setTimer(function()
    for _, m in pairs(M.list) do
        if getTickCount() >= m.endTick then
            M.finish(m, "timeout")
        elseif m.update then
            local ok, err = pcall(m.update, m)
            if not ok then outputDebugString("[biz_missions] update: " .. tostring(err), 1) end
        end
    end
end, 1000, 0)
