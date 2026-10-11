-- Reports the local camera (position + look direction) to the server: traffic no camera sees is
-- removed there, and new vehicles are kept out of close view. Starts after the geometry loaded.

local ready = false

function Puppets.viewReady() ready = true end

setTimer(function()
    if not ready then return end
    local x, y, z, tx, ty, tz = getCameraMatrix()
    if not x then return end
    triggerServerEvent(EV_VIEW, resourceRoot, x, y, z, tx - x, ty - y, tz - z)
end, TRAFFIC.VIEW_SEND, 0)
