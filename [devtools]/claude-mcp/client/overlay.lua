-- Debug overlay on the probe client: entity labels, bounding boxes, heading
-- arrows, lines, points and road nodes. Drawn every frame, so it shows up in
-- screenshots (capture_view with overlay = true).

local state = { enabled = false, items = {}, lines = {}, points = {}, nodes = {} }
local font = "default-bold"
local COLORS = { vehicle = { 255, 170, 0 }, ped = { 80, 220, 120 }, object = { 90, 170, 255 } }

addEvent("cmcp:overlay", true)
addEventHandler("cmcp:overlay", resourceRoot, function(s)
    if type(s) == "table" then state = s end
end)

local function col(c, a)
    c = c or { 255, 255, 255 }
    return tocolor(c[1] or 255, c[2] or 255, c[3] or 255, a or 230)
end

local function box(el, color)
    local x1, y1, z1, x2, y2, z2 = getElementBoundingBox(el)
    if not x1 then return end
    local m = getElementMatrix(el)
    local function w(lx, ly, lz)
        return m[4][1] + lx * m[1][1] + ly * m[2][1] + lz * m[3][1],
            m[4][2] + lx * m[1][2] + ly * m[2][2] + lz * m[3][2],
            m[4][3] + lx * m[1][3] + ly * m[2][3] + lz * m[3][3]
    end
    local P = {}
    for i, c in ipairs({ { x1, y1, z1 }, { x2, y1, z1 }, { x2, y2, z1 }, { x1, y2, z1 }, { x1, y1, z2 }, { x2, y1, z2 }, { x2, y2, z2 }, { x1, y2, z2 } }) do
        P[i] = { w(c[1], c[2], c[3]) }
    end
    for _, e in ipairs({ { 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 1 }, { 5, 6 }, { 6, 7 }, { 7, 8 }, { 8, 5 }, { 1, 5 }, { 2, 6 }, { 3, 7 }, { 4, 8 } }) do
        local a, b = P[e[1]], P[e[2]]
        dxDrawLine3D(a[1], a[2], a[3], b[1], b[2], b[3], color, 2)
    end
    if state.axes ~= false then
        -- heading arrow (model front = +Y)
        local cx, cy, cz = w(0, 0, z2)
        local fx, fy, fz = w(0, y2 + 1.5, z2)
        dxDrawLine3D(cx, cy, cz, fx, fy, fz, tocolor(255, 60, 60, 255), 4)
    end
end

addEventHandler("onClientRender", root, function()
    if not state.enabled then return end
    local cx, cy, cz = getCameraMatrix()
    local maxD = state.maxDistance or 250
    for _, it in ipairs(state.items or {}) do
        local el = it.element
        if isElement(el) and isElementStreamedIn(el) then
            local x, y, z = getElementPosition(el)
            if M.dist3D(cx, cy, cz, x, y, z) < maxD then
                local c = col(COLORS[it.type], 230)
                if state.boxes ~= false then box(el, c) end
                if state.labels ~= false then
                    local _, _, rz = getElementRotation(el)
                    local sx, sy = getScreenFromWorldPosition(x, y, z + 1.4)
                    if sx then
                        local text = it.label .. "\n" .. string.format("%.1f° %s", rz, M.compass(rz))
                        dxDrawText(text, sx + 1, sy + 1, sx + 1, sy + 1, tocolor(0, 0, 0, 220), 1, font, "center", "bottom")
                        dxDrawText(text, sx, sy, sx, sy, c, 1, font, "center", "bottom")
                    end
                end
            end
        end
    end
    for _, l in ipairs(state.lines or {}) do
        dxDrawLine3D(l[1], l[2], l[3], l[4], l[5], l[6], col(l[7], 255), l[9] or 3)
        if l[8] then
            local sx, sy = getScreenFromWorldPosition((l[1] + l[4]) / 2, (l[2] + l[5]) / 2, (l[3] + l[6]) / 2 + 0.3)
            if sx then dxDrawText(tostring(l[8]), sx, sy, sx, sy, col(l[7], 255), 1, font, "center", "bottom") end
        end
    end
    for _, p in ipairs(state.points or {}) do
        if M.dist3D(cx, cy, cz, p[1], p[2], p[3]) < maxD then
            dxDrawLine3D(p[1], p[2], p[3], p[1], p[2], p[3] + 2.5, col(p[5], 255), 5)
            if p[4] then
                local sx, sy = getScreenFromWorldPosition(p[1], p[2], p[3] + 2.7)
                if sx then dxDrawText(tostring(p[4]), sx, sy, sx, sy, col(p[5], 255), 1, font, "center", "bottom") end
            end
        end
    end
    for _, n in ipairs(state.nodes or {}) do
        if n[1] and M.dist3D(cx, cy, cz, n[1], n[2], n[3]) < maxD then
            dxDrawLine3D(n[1], n[2], n[3], n[1], n[2], n[3] + 1.2, tocolor(220, 163, 30, 255), 6)
            for _, link in ipairs(n[5] or {}) do
                dxDrawLine3D(n[1], n[2], n[3] + 0.6, link[1], link[2], link[3] + 0.6, tocolor(220, 163, 30, 200), 3)
            end
            local sx, sy = getScreenFromWorldPosition(n[1], n[2], n[3] + 1.4)
            if sx and n[4] ~= "" then dxDrawText(tostring(n[4]), sx, sy, sx, sy, tocolor(255, 210, 90, 255), 1, font, "center", "bottom") end
        end
    end
end)
