-- Debug drawing of the network: /rwnet toggles it, /rwnet pts also shows the control points.
-- Centre lines coloured by kind, a chevron every 25 m pointing towards the segment's b end,
-- labels (segment + s every 50 m, nodes), switch legs (green = set, red = not set), and a
-- line about the nearest track under the player.

local D = NET.DRAW
local enabled, showPts = false, false
local lines = {}              -- cached { x1, y1, z1, x2, y2, z2, color, width }
local labels = {}             -- cached { x, y, z, text, color }
local lastBuild, lastCam = 0, { 0, 0 }
local sx, sy = guiGetScreenSize()

local function color(kind, a)
    local c = D.COLORS[kind] or D.COLORS.other
    return tocolor(c[1], c[2], c[3], a or 220)
end

local function rebuildCache(cx, cy)
    lines, labels = {}, {}
    local seenSpan = {}
    local segsNear = {}
    Net.forSpansNear(cx, cy, D.DIST, function(id, i)
        local key = id .. ":" .. i
        if seenSpan[key] then return end
        seenSpan[key] = true
        segsNear[id] = true
        local g = Net.segment(id)
        if i % 2 == 1 then     -- one line per 2 m
            local j = math.min(i + 2, g.N + 1)
            local x1, y1, z1 = g.xs[i], g.ys[i], g.zs[i]
            if getDistanceBetweenPoints2D(cx, cy, x1, y1) < D.DIST then
                lines[#lines + 1] = { x1, y1, z1 + 0.3, g.xs[j], g.ys[j], g.zs[j] + 0.3, color(g.kind), 10 }
            end
        end
    end)

    for id in pairs(segsNear) do
        local g = Net.segment(id)
        local col = color(g.kind)
        -- chevrons towards b every 25 m, labels every 50 m
        for s = 12.5, g.len - 1, 25 do
            local x, y, z, tx, ty = Net.pointAt(id, s)
            if getDistanceBetweenPoints2D(cx, cy, x, y) < D.DIST then
                local nx, ny = -ty, tx
                local bx, by = x - tx * 1.5, y - ty * 1.5
                lines[#lines + 1] = { bx + nx * 1.2, by + ny * 1.2, z + 0.3, x, y, z + 0.3, col, 6 }
                lines[#lines + 1] = { bx - nx * 1.2, by - ny * 1.2, z + 0.3, x, y, z + 0.3, col, 6 }
            end
        end
        for s = 0, g.len, 50 do
            local x, y, z = Net.pointAt(id, s)
            if getDistanceBetweenPoints2D(cx, cy, x, y) < D.LABEL_DIST then
                local review = false
                for _, t in ipairs(g.tags) do if t == "review" then review = true end end
                labels[#labels + 1] = { x, y, z + 1.2, string.format("%s  s %.0f%s", id, s, review and "  [review]" or ""), col }
            end
        end
        if showPts and g.raw and g.raw.pts then
            for k, p in ipairs(g.raw.pts) do
                if getDistanceBetweenPoints2D(cx, cy, p[1], p[2]) < D.LABEL_DIST then
                    lines[#lines + 1] = { p[1], p[2], p[3], p[1], p[2], p[3] + 1.5, tocolor(255, 255, 255, 230), 3 }
                    labels[#labels + 1] = { p[1], p[2], p[3] + 1.7, id .. "#" .. k, tocolor(255, 255, 255, 200) }
                end
            end
        end
    end

    -- nodes
    for nid, n in pairs(Net.nodes()) do
        local x, y, z = n.x, n.y, n.z
        if not x then x, y, z = Net.endPoint(Net.nodeEnds(n)[1] or "") end
        if x and getDistanceBetweenPoints2D(cx, cy, x, y) < D.DIST then
            local text = nid .. " " .. n.type
            if n.type == "switch" then
                local st = Net.getState(n.group)
                local e = NetClient.switches[n.group] or {}
                local flags = (n.spring and ", spring" or "") .. (e[2] and ", LOCKED" or "")
                    .. (e[3] and (", " .. tostring(e[3])) or "") .. (e[4] and ", DAMAGED" or "")
                text = string.format("%s  [%s: %s%s]", nid, tostring(n.group), st, flags)
                -- first 12 m of each leg
                for _, role in ipairs({ "normal", "reverse" }) do
                    local id, e = Net.parseRef(n[role])
                    local g = id and Net.segment(id)
                    if g then
                        local on = (role == st)
                        local c = on and tocolor(60, 255, 60, 255) or tocolor(255, 60, 60, 200)
                        local prev
                        for d = 0, math.min(12, g.len), 2 do
                            local px, py, pz = Net.pointAt(id, e == "a" and d or g.len - d)
                            if prev then lines[#lines + 1] = { prev[1], prev[2], prev[3] + 0.25, px, py, pz + 0.25, c, on and 8 or 5 } end
                            prev = { px, py, pz }
                        end
                    end
                end
            end
            local c = n.type == "buffer" and tocolor(255, 60, 60) or n.type == "switch" and tocolor(255, 230, 80) or tocolor(255, 255, 255)
            lines[#lines + 1] = { x, y, z, x, y, z + 3, c, 6 }
            labels[#labels + 1] = { x, y, z + 3.4, text, c }
        end
    end

    for _, c in ipairs(Net.crossings()) do
        if c.x and getDistanceBetweenPoints2D(cx, cy, c.x, c.y) < D.DIST then
            local _, _, z = Net.pointAt(c.a, c.sa)
            labels[#labels + 1] = { c.x, c.y, z + 2, "X " .. c.a .. " / " .. c.b, tocolor(255, 80, 255) }
        end
    end
end

addEventHandler("onClientRender", root, function()
    if not enabled or not NetClient.ready then return end
    local cx, cy, cz = getCameraMatrix()
    local now = getTickCount()
    if now - lastBuild > 400 or getDistanceBetweenPoints2D(cx, cy, lastCam[1], lastCam[2]) > 20 then
        lastBuild, lastCam = now, { cx, cy }
        rebuildCache(cx, cy)
    end
    for i = 1, #lines do
        local l = lines[i]
        dxDrawLine3D(l[1], l[2], l[3], l[4], l[5], l[6], l[7], l[8])
    end
    for i = 1, #labels do
        local l = labels[i]
        local px, py = getScreenFromWorldPosition(l[1], l[2], l[3], 0.05)
        if px then
            dxDrawText(l[4], px + 1, py + 1, px + 1, py + 1, tocolor(0, 0, 0, 200), 1, "default-bold", "center", "center")
            dxDrawText(l[4], px, py, px, py, l[5], 1, "default-bold", "center", "center")
        end
    end

    -- nearest track under the player
    local x, y, z = getElementPosition(localPlayer)
    local seg, s, d = Net.project(x, y, z, 40)
    local text = "rwnet: no track within 40 m"
    if seg then
        local g = Net.segment(seg)
        local r = Net.radiusAt(seg, s)
        text = string.format("rwnet: %s (%s)  s %.1f / %.1f  dist %.1f m  R %s  grade %.1f %%  %s -> %s",
            seg, g.kind, s, g.len, d, r > 5000 and "straight" or string.format("%.0f m", r), Net.gradeAt(seg, s) * 100,
            tostring(g.a), tostring(g.b))
    end
    dxDrawText(text, 21, sy - 61, 0, 0, tocolor(0, 0, 0, 220), 1.1, "default-bold")
    dxDrawText(text, 20, sy - 62, 0, 0, tocolor(120, 200, 255), 1.1, "default-bold")
end)

addCommandHandler(D.CMD, function(_, arg)
    if arg == "pts" then
        showPts = not showPts
        enabled = true
    else
        enabled = not enabled
    end
    lastBuild = 0
    outputChatBox("[SLR] Pálya debug: " .. (enabled and "be" or "ki") .. (showPts and " (kontrollpontok)" or ""), 120, 200, 255)
end)

addEventHandler("rw:net:onClientNetworkReady", resourceRoot, function() lastBuild = 0 end)
