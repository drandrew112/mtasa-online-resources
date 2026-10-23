if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- biz_pc / server/main.lua
-- OrgOS, the computer inside every office and property (biz_int puts a PC
-- there). Only the founder can use it. The page (web/index.html, a web_api
-- app opened full screen in game) calls the exports below; each one checks
-- that the caller is the founder standing inside that unit.
--
-- The office computer manages the company (finance, buying properties,
-- settings, selling the organization). A site computer (weed farm, casino)
-- manages only that site: its activity app and selling the site itself.
--
-- Activity apps (Weed farm, Casino) come from the activity resources:
--   exports.<resource>:getPanelState(unitId)                 -> table for the page
--   exports.<resource>:panelAction(player, unitId, action, args) -> { ok, error, ... }

local function running(name)
    local r = getResourceFromName(name)
    return r and getResourceState(r) == "running"
end

local function core() return exports.biz_core end

addEvent("onBizComputerUse", false)
addEvent("bizpc:closed", true)

local open = {}   -- player -> unitId

addEventHandler("onBizComputerUse", root, function(unitId)
    local player = source
    if not running("biz_core") then return end
    if core():canAccessUnit(player, unitId) ~= "founder" then
        core():notifyPlayer(player, L.msg("biz_pc.only_founder"))
        return
    end
    local unit = core():getUnit(unitId)
    if not unit then return end
    open[player] = unitId
    triggerClientEvent(player, "bizpc:open", resourceRoot, unitId, unit.kind)
end)

addEventHandler("bizpc:closed", resourceRoot, function()
    open[client] = nil
end)

addEventHandler("onPlayerQuit", root, function() open[source] = nil end)

-- leaving the unit closes the computer
addEvent("onPlayerExitBizUnit", false)
addEventHandler("onPlayerExitBizUnit", root, function()
    if open[source] then
        open[source] = nil
        triggerClientEvent(source, "bizpc:close", resourceRoot)
    end
end)

--------------------------------------------------------------------------------
-- page API
--------------------------------------------------------------------------------

local DENIED = { ok = false, error = "no_access" }

--- the founder at this unit's computer, or nil
local function founderAt(unitId)
    if not running("web_api") or not running("biz_core") or not running("biz_int") then return nil end
    local p = exports.web_api:getCallerPlayer()
    unitId = tonumber(unitId)
    if not isElement(p) or not unitId then return nil end
    if exports.biz_int:getPlayerUnit(p) ~= unitId then return nil end
    if core():canAccessUnit(p, unitId) ~= "founder" then return nil end
    return p, unitId
end

local function activityResource(unit)
    if not unit or not unit.activity then return nil end
    local res = core():getActivityResource(unit.activity)
    return res and running(res) and res or nil
end

function pcState(unitId)
    local player
    player, unitId = founderAt(unitId)
    if not player then return DENIED end
    local unit = core():getUnit(unitId)
    local my = core():getMyOrganization(player)
    if not unit or not my or not my.company then return DENIED end
    local ledger = core():getCompanyLedger(player, nil, 80) or {}
    local summary = core():getCompanySummary(player, 7) or {}
    local state = {
        ok = true, now = getRealTime().timestamp,
        unit = unit, company = my.company, config = core():getBizConfig(),
        ledger = ledger.rows or {}, income7 = summary.income or 0, expenses7 = summary.expenses or 0,
        catalog = core():getCatalog() or {}, bank = tonumber(getElementData(player, "bank_money")) or 0,
        multipliers = core():getSaleMultipliers() or {},
    }
    -- the page finds this unit's refund / stock value in company.units: a second
    -- reference to the same table would reach it as a toJSON "^T^n" string
    local res = activityResource(unit)
    if res then
        local ok, panel = pcall(call, getResourceFromName(res), "getPanelState", unitId)
        state.activity = ok and panel or false
    end
    return state
end

-- office computer: the company
local OFFICE_ACTIONS = {
    deposit   = function(p, a) return core():depositToCompany(p, a.amount) end,
    withdraw  = function(p, a) return core():withdrawFromCompany(p, a.amount, a.part) end,
    buy       = function(p, a) return core():buyProperty(p, a.propertyId) end,
    rename    = function(p, a) return core():renameCompany(p, a.name) end,
    quote     = function(p)    return core():getCompanySaleQuote(p) end,
    sellorg   = function(p, a) return core():sellCompany(p, a.confirm) end,
    ledger    = function(p, a) return core():getCompanyLedger(p, a.category, 200) end,
}

-- site computer: only this site
local SITE_ACTIONS = {
    sell = function(p, a, unitId)
        if running("biz_missions") and exports.biz_missions:getUnitMission(unitId) then
            return { ok = false, error = "mission_running" }
        end
        return core():sellProperty(p, unitId)
    end,
}

function pcAction(unitId, action, args)
    local player
    player, unitId = founderAt(unitId)
    if not player then return DENIED end
    args = type(args) == "table" and args or {}
    action = tostring(action or "")
    local unit = core():getUnit(unitId)
    if not unit then return DENIED end
    local fn = (unit.kind == "office" and OFFICE_ACTIONS or SITE_ACTIONS)[action]
    if fn then return fn(player, args, unitId) or { ok = false, error = "failed" } end
    if OFFICE_ACTIONS[action] or SITE_ACTIONS[action] then return { ok = false, error = "wrong_computer" } end

    -- "activity:<name>" goes to the unit's activity resource
    local sub = action:match("^activity:([%w_]+)$")
    if sub then
        local res = activityResource(unit)
        if not res then return { ok = false, error = "activity_offline" } end
        local ok, r = pcall(call, getResourceFromName(res), "panelAction", player, unitId, sub, args)
        if not ok then
            outputDebugString("[biz_pc] " .. res .. " panelAction " .. sub .. ": " .. tostring(r), 1)
            return { ok = false, error = "failed" }
        end
        return r or { ok = false, error = "failed" }
    end
    return { ok = false, error = "unknown_action" }
end

--- the page closes itself (Esc / close button) - also handled client side
function pcClose()
    local p = running("web_api") and exports.web_api:getCallerPlayer()
    if isElement(p) then
        open[p] = nil
        triggerClientEvent(p, "bizpc:close", resourceRoot)
    end
    return { ok = true }
end
