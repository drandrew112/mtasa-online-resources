-- Alternately flashing red lights on the crossing posts while the barriers are down.

local glow = dxCreateTexture(32, 32)
do
    local g = dxGetTexturePixels(glow)
    if g then
        for x = 0, 31 do
            for y = 0, 31 do
                local d = math.sqrt((x - 15.5) ^ 2 + (y - 15.5) ^ 2) / 15.5
                local a = math.max(0, 1 - d)
                dxSetPixelColor(g, x, y, 255, 255, 255, math.floor(255 * a * a))
            end
        end
        dxSetTexturePixels(glow, g)
    end
end

-- red lamps along the lowered barrier arm (traincross2: the arm runs along its +y from
-- 1.4 m to 9.2 m), two groups flashing in turn
local LAMPS = {
    { { 0, 2.6, 0.45 }, { 0, 6.6, 0.45 } },
    { { 0, 4.6, 0.45 }, { 0, 8.6, 0.45 } },
}

local function lampWorld(m, l)
    return l[1] * m[1][1] + l[2] * m[2][1] + l[3] * m[3][1] + m[4][1],
           l[1] * m[1][2] + l[2] * m[2][2] + l[3] * m[3][2] + m[4][2],
           l[1] * m[1][3] + l[2] * m[2][3] + l[3] * m[3][3] + m[4][3]
end

addEventHandler("onClientRender", root, function()
    local cx, cy, cz = getCameraMatrix()
    local maxD = CROSS.LIGHT_DISTANCE
    local phase = math.floor(getTickCount() / 500) % 2
    for _, cr in ipairs(getElementsByType("rwcrossing")) do
        if getElementData(cr, "rw.crossing") then
            for _, arm in ipairs(getElementChildren(cr)) do
                if getElementType(arm) == "object" and getElementModel(arm) == 1374 and isElementStreamedIn(arm) then
                    local px, py, pz = getElementPosition(arm)
                    local d = getDistanceBetweenPoints3D(cx, cy, cz, px, py, pz)
                    if d < maxD then
                        local m = getElementMatrix(arm)
                        local size = 0.45 + d / 180
                        for _, l in ipairs(LAMPS[phase + 1]) do
                            local x, y, z = lampWorld(m, l)
                            dxDrawMaterialLine3D(x, y, z + size / 2, x, y, z - size / 2, glow, size, tocolor(255, 40, 30, 230), cx, cy, cz)
                        end
                    end
                end
            end
        end
    end
end)
