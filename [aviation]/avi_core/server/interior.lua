-- SA Control interior (config AVI.INTERIOR), registered in world_interiors on start and on
-- world_interiors:ready (a restart of world_interiors drops every registered interior).

addEvent("world_interiors:ready", false)

local function registerControl()
    local I = AVI.INTERIOR
    if not I then return end
    local wi = getResourceFromName("world_interiors")
    if not wi or getResourceState(wi) ~= "running" then
        outputDebugString("[avi_core] world_interiors is not running, " .. I.name .. " has no entrance", 2)
        return
    end
    local e, x = I.enterMarker, I.exitMarker
    exports.world_interiors:registerInterior(I.id, {
        name      = I.name,
        dimension = I.dim,
        enter   = { x = e.x, y = e.y, z = e.z, rot = e.rot, interior = 0, dimension = 0 },
        exit    = { x = x.x, y = x.y, z = x.z, rot = x.rot, interior = I.int },
        inside  = I.entrance,
        outside = I.exit,
    })
end

addEventHandler("onResourceStart", resourceRoot, registerControl)
addEventHandler("world_interiors:ready", root, registerControl)
