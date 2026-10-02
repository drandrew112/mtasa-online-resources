--[[
    shader_markers
    Replaces the look of cylinder markers with a modern gradient (wall + ground disc).

    The original GTA cylinder is hidden locally (alpha 0, client only), and our own
    geometry is drawn with the marker's original RGBA, so every marker keeps its color.
    Other client scripts can read the real color via exports.shader_markers:getMarkerOriginalColor(marker).
]]

local CONFIG = {
    segments = 40,          -- wall/disc smoothness
    radiusScale = 0.5,      -- visual radius = marker size * radiusScale
    heightScale = 0.75,     -- wall height = marker size * heightScale
    minHeight = 0.6,
    maxHeight = 2.4,
    groundOffset = 0.04,    -- lifts the disc slightly to avoid z-fighting
    drawDistance = 160,
}

local TWO_PI = math.pi * 2
local cos, sin, min, max = math.cos, math.sin, math.min, math.max

local wallShader, groundShader
local enabled = false

-- The GTA cylinder is hidden with this alpha (practically invisible). It differs from 0 so an
-- alpha 0 set by another script/server still means "intentionally invisible".
local HIDDEN_ALPHA = 1
local REV_KEY = "shader_markers:rev"  -- bumped by server.lua after every server-side setMarkerColor

-- [marker] = { r, g, b, a, cache fields..., wall = {...}, ground = {...} }
local markers = {}
local settingColor = false

local function setColorInternal(marker, r, g, b, a)
    settingColor = true
    setMarkerColor(marker, r, g, b, a)
    settingColor = false
end

local function restoreMarker(marker, data)
    if isElement(marker) and getElementType(marker) == "marker" then
        local _, _, _, a = getMarkerColor(marker)
        if a == HIDDEN_ALPHA then
            setColorInternal(marker, data.r, data.g, data.b, data.a)
        end
    end
end

-- Keeps track of the original color and hides the GTA cylinder.
-- Returns the data table, or nil if the marker should not be drawn.
local function syncMarker(marker)
    local r, g, b, a = getMarkerColor(marker)
    local data = markers[marker]
    if not data then
        data = {}
        markers[marker] = data
    end

    if a == HIDDEN_ALPHA then
        -- Already hidden by us; data holds the real color
        if not data.r then
            data.r, data.g, data.b, data.a = r, g, b, 255
        end
    else
        -- Fresh color from another script/server (alpha 0 = intentionally invisible)
        data.r, data.g, data.b, data.a = r, g, b, a
        if a > 0 then
            setColorInternal(marker, r, g, b, HIDDEN_ALPHA)
        end
    end

    if data.a <= 0 then
        return nil
    end
    return data
end

local function isCylinder(element)
    return isElement(element) and getElementType(element) == "marker" and getMarkerType(element) == "cylinder"
end

-- Re-hide immediately, before GTA places the marker for the next frame (no one-frame flash)
local function syncNow(marker)
    if enabled and isCylinder(marker) then
        syncMarker(marker)
    end
end

local function buildGeometry(data, x, y, z, size)
    local radius = size * CONFIG.radiusScale
    local height = max(CONFIG.minHeight, min(CONFIG.maxHeight, size * CONFIG.heightScale))
    local color = tocolor(data.r, data.g, data.b, data.a)
    local segments = CONFIG.segments
    local gz = z + CONFIG.groundOffset

    local wall = {}
    local ground = { { x, y, gz, color, 0, 0 } }

    for i = 0, segments do
        local t = i / segments
        local angle = t * TWO_PI
        local px, py = x + cos(angle) * radius, y + sin(angle) * radius

        wall[#wall + 1] = { px, py, z, color, t, 0 }
        wall[#wall + 1] = { px, py, z + height, color, t, 1 }
        ground[#ground + 1] = { px, py, gz, color, 1, t }
    end

    data.wall = wall
    data.ground = ground
    data.cx, data.cy, data.cz, data.csize = x, y, z, size
    data.cr, data.cg, data.cb, data.ca = data.r, data.g, data.b, data.a
end

local function needsRebuild(data, x, y, z, size)
    return not data.wall
        or data.cx ~= x or data.cy ~= y or data.cz ~= z or data.csize ~= size
        or data.cr ~= data.r or data.cg ~= data.g or data.cb ~= data.b or data.ca ~= data.a
end

local function renderMarkers()
    local camX, camY, camZ = getCameraMatrix()
    local dimension = getElementDimension(localPlayer)
    local interior = getElementInterior(localPlayer)
    local maxDistSq = CONFIG.drawDistance * CONFIG.drawDistance

    for _, marker in ipairs(getElementsByType("marker", root, true)) do
        if getMarkerType(marker) == "cylinder" then
            local data = syncMarker(marker)
            if data
                and getElementDimension(marker) == dimension
                and getElementInterior(marker) == interior then

                local x, y, z = getElementPosition(marker)
                local dx, dy, dz = x - camX, y - camY, z - camZ
                if dx * dx + dy * dy + dz * dz <= maxDistSq then
                    local size = getMarkerSize(marker)
                    if needsRebuild(data, x, y, z, size) then
                        buildGeometry(data, x, y, z, size)
                    end
                    dxDrawMaterialPrimitive3D("trianglefan", groundShader, false, unpack(data.ground))
                    dxDrawMaterialPrimitive3D("trianglestrip", wallShader, false, unpack(data.wall))
                end
            end
        end
    end
end

local function enable()
    if enabled then return true end

    wallShader = dxCreateShader("fx/marker_wall.fx")
    groundShader = dxCreateShader("fx/marker_ground.fx")

    if not wallShader or not groundShader then
        if isElement(wallShader) then destroyElement(wallShader) end
        if isElement(groundShader) then destroyElement(groundShader) end
        wallShader, groundShader = nil, nil
        outputDebugString("[shader_markers] Shader could not be created (needs Shader Model 3), original markers stay visible.", 2)
        return false
    end

    addEventHandler("onClientPreRender", root, renderMarkers)
    enabled = true
    return true
end

local function disable()
    if not enabled then return true end

    removeEventHandler("onClientPreRender", root, renderMarkers)
    for marker, data in pairs(markers) do
        restoreMarker(marker, data)
    end
    markers = {}

    if isElement(wallShader) then destroyElement(wallShader) end
    if isElement(groundShader) then destroyElement(groundShader) end
    wallShader, groundShader = nil, nil
    enabled = false
    return true
end

addEventHandler("onClientResourceStart", resourceRoot, enable)
addEventHandler("onClientResourceStop", resourceRoot, disable)

addEventHandler("onClientElementDestroy", root, function()
    if markers[source] then
        markers[source] = nil
    end
end)

-- Instant re-hide hooks, so the original cylinder is never rendered for a frame:
-- stream in (new marker), server color change (server.lua bumps REV_KEY right after
-- setMarkerColor, the data packet arrives in the same network pulse), client-side setMarkerColor.
addEventHandler("onClientElementStreamIn", root, function()
    syncNow(source)
end)

addEventHandler("onClientElementDataChange", root, function(key)
    if key == REV_KEY then
        syncNow(source)
    end
end)

addDebugHook("postFunction", function(...)
    if settingColor then return end
    for _, arg in ipairs({ ... }) do
        if isCylinder(arg) then
            syncNow(arg)
            return
        end
    end
end, { "setMarkerColor" })

-- Exports ------------------------------------------------------------------

-- Real marker color, even while the GTA cylinder is hidden by this resource
function getMarkerOriginalColor(marker)
    if not isElement(marker) or getElementType(marker) ~= "marker" then
        return false
    end
    local data = markers[marker]
    if data then
        return data.r, data.g, data.b, data.a
    end
    return getMarkerColor(marker)
end

function setMarkerShaderEnabled(state)
    if state then
        return enable()
    end
    return disable()
end

addCommandHandler("markershader", function()
    if enabled then
        disable()
        outputChatBox("Marker shader: KI", 255, 200, 0)
    else
        local ok = enable()
        outputChatBox(ok and "Marker shader: BE" or "Marker shader: nem támogatott", 255, 200, 0)
    end
end)
