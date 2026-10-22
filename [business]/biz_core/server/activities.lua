-- biz_core / server/activities.lua
-- Activity resources (biz_weed, biz_casino, later more) register themselves:
--
--   exports.biz_core:registerActivity("weed", {
--       kind    = "supply_deliver",        -- or "passive"
--       valueFn = "getUnitStockValue",     -- optional export of the caller: (unitId) -> euro
--   })
--
-- Register on your own onResourceStart AND on "biz_core:ready" (root), which
-- biz_core fires when it (re)starts. Registrations of a stopping resource are
-- dropped. The online tick reaches the activities as the server event
--   onBizCompanyTick (companyId, seconds)     -- only while the company is not paused

ACT = { list = {} }

addEvent("biz_core:ready", false)
addEvent("onBizCompanyTick", false)

function registerActivity(key, def)
    if type(key) ~= "string" or key == "" or not sourceResource then return false end
    def = type(def) == "table" and def or {}
    ACT.list[key] = {
        key = key,
        kind = def.kind == BIZ.KIND_SUPPLY_DELIVER and BIZ.KIND_SUPPLY_DELIVER or BIZ.KIND_PASSIVE,
        valueFn = type(def.valueFn) == "string" and def.valueFn or nil,
        resource = getResourceName(sourceResource),
    }
    return true
end

function getActivityKind(key)
    local a = ACT.list[key]
    return a and a.kind or false
end

--- resource name of a registered activity, or false
function getActivityResource(key)
    local a = ACT.list[key]
    return a and a.resource or false
end

addEventHandler("onResourceStop", root, function(res)
    local name = getResourceName(res)
    for key, a in pairs(ACT.list) do
        if a.resource == name then ACT.list[key] = nil end
    end
end)
