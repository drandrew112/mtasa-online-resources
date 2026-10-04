-- Signal heads (dx 3D on top of the pole objects) + the client-side signal lookup rw_loco uses.
-- The list comes once from the server, aspect changes arrive as small diffs.

local A = SIG.ASPECT
local signals = {}            -- [id] = { id, name, track, tp, dir, x, y, z, fx, fy, aspect }
local byTrack = {}            -- [track] = sorted list
local ready = false
local loops = {}              -- [track] = length of looped tracks (distances wrap)

local LAMP_COLOR = {
    [A.GREEN]  = { 40, 255, 110 },
    [A.YELLOW] = { 255, 200, 40 },
    [A.RED]    = { 255, 40, 30 },
}
local LAMP_ORDER = { A.GREEN, A.YELLOW, A.RED }   -- top to bottom

local white = dxCreateTexture(1, 1)
local glow = dxCreateTexture(32, 32)
do
    local px = dxGetTexturePixels(white)
    if px then dxSetPixelColor(px, 0, 0, 255, 255, 255, 255) dxSetTexturePixels(white, px) end
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

addEvent("onClientRailSignalChange", false)   -- (signalId, aspect, name)

-- next signal in front of a train head: track, head tp, direction (+1/-1)
-- -> id, name, aspect, distance (metres) | false
function getSignalAhead(track, headTp, dir)
    local list = byTrack[track]
    if not list or dir == 0 then return false end
    local best, bestD
    for _, s in ipairs(list) do
        if s.dir == dir then
            local d = (s.tp - headTp) * dir
            if loops[track] then d = d % loops[track] end
            if d >= -2 and (not bestD or d < bestD) then best, bestD = s, d end
        end
    end
    if not best then return false end
    return best.id, best.name, best.aspect, math.max(0, bestD)
end

function getSignalAspect(id)
    local s = signals[id]
    return s and s.aspect or false
end

local function render()
    local cx, cy, cz = getCameraMatrix()
    local maxD = SIG.DRAW_DISTANCE
    for _, s in pairs(signals) do
        local dx, dy = s.x - cx, s.y - cy
        if dx * dx + dy * dy < maxD * maxD then
            local hz = s.z + SIG.HEAD_HEIGHT
            local front = -(dx * s.fx + dy * s.fy) > 0          -- camera in front of the head
            local d = math.sqrt(dx * dx + dy * dy)
            local px, py = s.x + s.fx * 0.05, s.y + s.fy * 0.05
            local faceX, faceY = s.x + s.fx * 10, s.y + s.fy * 10
            if d < 220 then
                -- black head plate with a thin white border look
                dxDrawMaterialLine3D(s.x, s.y, hz + 0.55, s.x, s.y, hz - 0.55, white, 0.5, tocolor(12, 12, 12, 255), faceX, faceY, hz)
            end
            for i, asp in ipairs(LAMP_ORDER) do
                local lz = hz + 0.3 - (i - 1) * 0.3
                local lit = s.aspect == asp
                local c = LAMP_COLOR[asp]
                if d < 220 and front then
                    local col = lit and tocolor(c[1], c[2], c[3], 255) or tocolor(c[1] * 0.12, c[2] * 0.12, c[3] * 0.12, 255)
                    dxDrawMaterialLine3D(px, py, lz + 0.09, px, py, lz - 0.09, white, 0.18, col, faceX, faceY, lz)
                end
                if lit and front then
                    local size = 0.7 + d / 120
                    dxDrawMaterialLine3D(px + s.fx * 0.05, py + s.fy * 0.05, lz + size / 2, px + s.fx * 0.05, py + s.fy * 0.05, lz - size / 2,
                        glow, size, tocolor(c[1], c[2], c[3], 210), faceX, faceY, lz)
                end
            end
            if d < 35 and front then
                local sx, sy = getScreenFromWorldPosition(s.x, s.y, hz - 0.8)
                if sx then
                    dxDrawText(s.name, sx + 1, sy + 1, sx + 1, sy + 1, tocolor(0, 0, 0, 220), 1, "default-bold", "center", "top")
                    dxDrawText(s.name, sx, sy, sx, sy, tocolor(255, 255, 255, 255), 1, "default-bold", "center", "top")
                end
            end
        end
    end
end

addEvent("rw:sig:list", true)
addEventHandler("rw:sig:list", resourceRoot, function(list, loopLengths)
    signals, byTrack = {}, {}
    loops = loopLengths or {}
    for _, r in ipairs(list) do
        local s = { id = r[1], name = r[2], track = r[3], tp = r[4], dir = r[5], x = r[6], y = r[7], z = r[8], fx = r[9], fy = r[10], aspect = r[11] }
        signals[s.id] = s
        byTrack[s.track] = byTrack[s.track] or {}
        table.insert(byTrack[s.track], s)
    end
    for _, l in pairs(byTrack) do table.sort(l, function(a, b) return a.tp < b.tp end) end
    if not ready then
        ready = true
        addEventHandler("onClientRender", root, render)
    end
end)

addEvent("rw:sig:aspects", true)
addEventHandler("rw:sig:aspects", resourceRoot, function(changes)
    for id, a in pairs(changes) do
        local s = signals[tonumber(id)]
        if s then
            s.aspect = a
            triggerEvent("onClientRailSignalChange", localPlayer, s.id, a, s.name)
        end
    end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("rw:sig:request", resourceRoot)
end)
