-- Module hooks (like work_ems): a later police tutorial can register here without touching the core.
--
--   PoliceWorkModules.register("tutorial", {
--       canGoOnDuty = function(player) return false, "Finish the police tutorial first." end,
--       onDutyStart = function(player, skin) end,
--       onDutyEnd   = function(player, reason) end,
--   })

PoliceWorkModules = { list = {} }

function PoliceWorkModules.register(id, hooks)
    if type(id) ~= "string" or type(hooks) ~= "table" then return false end
    for i, m in ipairs(PoliceWorkModules.list) do
        if m.id == id then table.remove(PoliceWorkModules.list, i) break end
    end
    PoliceWorkModules.list[#PoliceWorkModules.list + 1] = { id = id, hooks = hooks }
    return true
end

local function call(m, name, ...)
    local fn = m.hooks[name]
    if type(fn) ~= "function" then return true end
    local ok, a, b = pcall(fn, ...)
    if not ok then
        outputDebugString(("[work_police] module %s.%s: %s"):format(m.id, name, tostring(a)), 1)
        return true
    end
    return a, b
end

function PoliceWorkModules.canGoOnDuty(player)
    for _, m in ipairs(PoliceWorkModules.list) do
        local ok, reason = call(m, "canGoOnDuty", player)
        if ok == false then return false, reason end
    end
    return true
end

function PoliceWorkModules.fire(name, ...)
    for _, m in ipairs(PoliceWorkModules.list) do call(m, name, ...) end
end
