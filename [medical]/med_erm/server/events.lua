-- Server events for other resources (automation / scenario systems).
--
-- All events are triggered on erm's resourceRoot, so listen with:
--   addEventHandler("onErmTaskClosed", root, function(taskId, reason) ... end)
--
--   onErmTaskCreated          (taskId)
--   onErmTaskUpdated          (taskId)
--   onErmTaskPriorityChanged  (taskId, priority, oldPriority | false)
--   onErmTaskAssigned         (taskId, unitId)
--   onErmTaskUnassigned       (taskId, unitId)
--   onErmTaskClosed           (taskId, reason)
--   onErmUnitSignIn           (unitId)
--   onErmUnitSignOut          (unitId, callsign, reason)
--   onErmUnitStatusChange     (unitId, status, oldStatus)
--   onErmUnitHandoverStart    (unitId, taskId | false, durationMs)   CANCELLABLE:
--       cancelEvent() = no automatic finish; the caller ends it with
--       exports.erm:completeHandover(unitId) or times it with setHandoverTime
--   onErmUnitHandoverComplete (unitId, taskId | false)
--   onErmMessage              (messageId, channel, target, from, fromDispatch, text)

Events = {}

local NAMES = {
    "onErmTaskCreated", "onErmTaskUpdated", "onErmTaskPriorityChanged",
    "onErmTaskAssigned", "onErmTaskUnassigned", "onErmTaskClosed",
    "onErmUnitSignIn", "onErmUnitSignOut", "onErmUnitStatusChange",
    "onErmUnitHandoverStart", "onErmUnitHandoverComplete", "onErmMessage",
}

for _, name in ipairs(NAMES) do
    addEvent(name, false)
end

-- Returns false when a handler cancelled the event.
function Events.fire(name, ...)
    return triggerEvent(name, resourceRoot, ...)
end
