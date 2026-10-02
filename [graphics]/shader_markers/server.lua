--[[
    shader_markers (server)
    After any server-side setMarkerColor on a cylinder marker, bumps an element data counter.
    The data packet follows the color packet, so clients re-hide the GTA cylinder in the same
    network pulse, before it could be rendered with the new color (no flash on color change).
]]

local REV_KEY = "shader_markers:rev"

addDebugHook("postFunction", function(...)
    for _, arg in ipairs({ ... }) do
        if isElement(arg) and getElementType(arg) == "marker" then
            if getMarkerType(arg) == "cylinder" then
                setElementData(arg, REV_KEY, (getElementData(arg, REV_KEY) or 0) + 1)
            end
            return
        end
    end
end, { "setMarkerColor" })
