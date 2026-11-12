-- police_system / modules/hud/client/mini.lua
-- The bottom right mini panel was removed (2026-11-12); only the F4-F7 unit status keys remain here.

------------------------------------------------------------------------ F4-F7

local KEYS = { f4 = "STATUS_PURSUIT", f5 = "STATUS_AVAILABLE", f6 = "STATUS_RESPONDING", f7 = "STATUS_BUSY" }

POL.key("fkeys", function(button, press)
    local id = KEYS[button]
    if not id or not POL.onDuty() or not POL.hasRight() then return false end
    if press then
        local args
        if id == "STATUS_PURSUIT" and POL.stopc then args = { target = POL.stopc.pursuitTarget() } end
        POL.send("radio", id, args)
    end
    return true
end, 10)
