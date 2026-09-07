
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
setTimer(lookSync, 120, 0)