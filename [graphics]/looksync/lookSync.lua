
-- on by default; ui_pause Settings > Display switches it (setLookSyncEnabled)
local enabled = true
local syncTimer

function lookSync ()
    for _, player in pairs(getElementsByType("player", root, true)) do
        if (getPedTask(player, "secondary", 0) ~= "TASK_SIMPLE_USE_GUN" and (not isPedDoingGangDriveby(player))) then
            local rot = getPedCameraRotation(player)
            local x, y, z = getElementPosition(player)
            local vx = x + math.sin(math.rad(rot)) * 10
            local vy = y + math.cos(math.rad(rot)) * 10
            if (player ~= localPlayer) then
                setPedAimTarget(player, vx, vy, z)
            end
            setPedLookAt(player, vx, vy, z, 150, 0)
        end
    end
end
syncTimer = setTimer(lookSync, 120, 0)

-- off: the timer stops, the 150 ms look runs out and every head stays straight ahead
function setLookSyncEnabled (state)
    state = state and true or false
    if state == enabled then return true end
    enabled = state
    if enabled then
        syncTimer = setTimer(lookSync, 120, 0)
    elseif isTimer(syncTimer) then
        killTimer(syncTimer)
        syncTimer = nil
    end
    return true
end

function isLookSyncEnabled ()
    return enabled
end
