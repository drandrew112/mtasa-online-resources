-- Module hooks, so features like a tutorial can be added later without touching the core.
--
-- Inside work_ems (e.g. modules/tutorial.lua, added to meta.xml after this file):
--   EmsModules.register("tutorial", {
--       canGoOnDuty    = function(player) return false, "Finish the EMS tutorial first." end,
--       onDutyStart    = function(player, skin) end,
--       onDutyEnd      = function(player, reason) end,
--       onVehicleSpawn = function(vehicle, player) end,
--   })
--
-- From another resource: the same points as events (source = player, or the vehicle):
--   onEmsDutyRequest (cancellable, cancelEvent(true, "reason")), onEmsDutyStart (skin),
--   onEmsDutyEnd (reason), onEmsVehicleSpawn (player).

EmsModules = { list = {} }

addEvent("onEmsDutyRequest")
addEvent("onEmsDutyStart")
addEvent("onEmsDutyEnd")
addEvent("onEmsVehicleSpawn")

function EmsModules.register(id, hooks)
    if type(id) ~= "string" or type(hooks) ~= "table" then return false end
    for i, m in ipairs(EmsModules.list) do
        if m.id == id then table.remove(EmsModules.list, i) break end
    end
    EmsModules.list[#EmsModules.list + 1] = { id = id, hooks = hooks }
    return true
end

function EmsModules.unregister(id)
    for i, m in ipairs(EmsModules.list) do
        if m.id == id then table.remove(EmsModules.list, i) return true end
    end
    return false
end

local function call(m, name, ...)
    local fn = m.hooks[name]
    if type(fn) ~= "function" then return true end
    local ok, a, b = pcall(fn, ...)
    if not ok then
        outputDebugString(("[work_ems] module %s.%s: %s"):format(m.id, name, tostring(a)), 1)
        return true
    end
    return a, b
end

-- -> true | false, reason
function EmsModules.canGoOnDuty(player)
    for _, m in ipairs(EmsModules.list) do
        local ok, reason = call(m, "canGoOnDuty", player)
        if ok == false then return false, reason end
    end
    if not triggerEvent("onEmsDutyRequest", player) then
        return false, getCancelReason()
    end
    return true
end

-- name = "onDutyStart" | "onDutyEnd" | "onVehicleSpawn"; source = player (vehicle for spawns)
function EmsModules.fire(name, source, ...)
    for _, m in ipairs(EmsModules.list) do call(m, name, source, ...) end
    local event = "onEms" .. name:sub(3)
    triggerEvent(event, source, ...)
end
