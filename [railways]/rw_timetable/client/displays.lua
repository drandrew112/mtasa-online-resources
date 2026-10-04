-- Station displays: the departure / arrival board of a station drawn on its walls
-- (TT.DISPLAYS). A station near the camera gets a render target, its board data comes from
-- the server every TT.BOARD.REFRESH seconds (rw:tt:boards) and the picture is redrawn a few
-- times a second (clock, blinking "Boarding"). Far stations release their render target.

local B = TT.BOARD
local RT_W, RT_H = 1280, 640
local OFFSET = 0.05                 -- m in front of the wall

local boards = {}                   -- [stationId] = board from the server
local targets = {}                  -- [stationId] = render target
local dirty = {}                    -- [stationId] = true: redraw now
local lastDraw = {}                 -- [stationId] = tick of the last redraw
local near = {}                     -- [stationId] = true: within KEEP_DIST
local clockBase, clockTick = nil, 0 -- server seconds of the day at clockTick
local lastAsk = 0

local C = {
    bg     = tocolor(9, 20, 44, 255),
    head   = tocolor(5, 12, 28, 255),
    stripe = tocolor(14, 28, 58, 255),
    accent = tocolor(40, 112, 230, 255),
    text   = tocolor(236, 241, 250, 255),
    dim    = tocolor(132, 150, 182, 255),
    amber  = tocolor(255, 192, 46, 255),
    green  = tocolor(96, 214, 128, 255),
    red    = tocolor(240, 76, 64, 255),
    box    = tocolor(236, 241, 250, 255),
    boxTxt = tocolor(9, 20, 44, 255),
}

-- px = wanted text height in render target pixels (dxCreateFont takes points: 1 pt = 4/3 px)
local fonts = {}
local function font(bold, px)
    local key = (bold and "b" or "r") .. px
    if not fonts[key] then
        fonts[key] = dxCreateFont(bold and "fonts/RobotoB.ttf" or "fonts/Roboto.ttf", math.floor(px * 0.75 + 0.5), false, "antialiased") or "default-bold"
    end
    return fonts[key]
end

local function hhmm(sec)
    sec = math.floor(sec) % 86400
    return ("%02d:%02d"):format(math.floor(sec / 3600), math.floor(sec / 60) % 60)
end

local function clock()
    if not clockBase then return nil end
    return clockBase + (getTickCount() - clockTick) / 1000
end

------------------------------------------------------------------ drawing

-- remark text (one or two lines) + colour of an entry
local function remark(e, blink)
    local d = math.floor((e.delay or 0) / 60)
    local late = d >= 1 and ("+%d min"):format(d) or nil
    if e.state == "cancelled" then return "Cancelled", nil, C.red end
    if e.state == "departed" then return "Departed", nil, C.dim end
    if e.state == "arrived" then return "Arrived", late, C.green end
    if e.state == "platform" then return "At platform", late, C.text end
    if e.state == "boarding" then return blink and "Boarding" or "", late, C.text end
    -- the train does not exist physically yet: no delay / on-time claim
    if e.state == "scheduled" then return "Scheduled", nil, C.dim end
    if late then return late, nil, C.amber end
    return "On time", nil, C.green
end

local function drawColumn(list, x, y, w, title, placeTitle, isDep)
    local blink = math.floor(getTickCount() / 700) % 2 == 0
    dxDrawText(title, x, y, x + w, y + 40, C.text, 1, font(true, 30), "left", "center")
    dxDrawRectangle(x, y + 44, w, 2, C.accent)

    local hy = y + 52
    local hf = font(false, 16)
    dxDrawText("Time", x + 8, hy, 0, 0, C.dim, 1, hf)
    dxDrawText("Train", x + 92, hy, 0, 0, C.dim, 1, hf)
    dxDrawText(placeTitle, x + 196, hy, 0, 0, C.dim, 1, hf)
    dxDrawText("Track", x + 440, hy, x + 500, 0, C.dim, 1, hf, "center")
    dxDrawText("Remarks", x + 512, hy, 0, 0, C.dim, 1, hf)

    local ry, rh = hy + 26, 57
    if #list == 0 then
        dxDrawText(isDep and "No departures" or "No arrivals", x, ry, x + w, ry + rh * 2, C.dim, 1, font(false, 22), "center", "center")
        return
    end
    for i, e in ipairs(list) do
        local top = ry + (i - 1) * rh
        if i % 2 == 0 then dxDrawRectangle(x, top, w, rh, C.stripe) end
        local gone = e.state == "cancelled" or e.state == "departed"
        local main = gone and C.dim or C.text

        -- scheduled time, the expected one below when late
        local d = math.floor((e.delay or 0) / 60)
        if d >= 1 and e.state ~= "cancelled" then
            dxDrawText(hhmm(e.time), x + 8, top + 4, x + 90, top + 32, main, 1, font(true, 26), "left", "center")
            dxDrawText(hhmm(e.time + d * 60), x + 8, top + 32, x + 90, top + rh - 4, C.amber, 1, font(true, 17), "left", "center")
        else
            dxDrawText(hhmm(e.time), x + 8, top, x + 90, top + rh, main, 1, font(true, 26), "left", "center")
        end

        dxDrawText(e.train, x + 92, top + 4, x + 190, top + 32, main, 1, font(true, 21), "left", "center", true)
        dxDrawText(e.name or "", x + 92, top + 32, x + 190, top + rh - 4, C.dim, 1, font(false, 13), "left", "center", true)

        local place = isDep and e.to or e.from
        place = place:gsub(" Station$", "")
        local v = e.via and #e.via > 0 and ("via " .. table.concat(e.via, ", ")) or nil
        if v then
            dxDrawText(place, x + 196, top + 4, x + 432, top + 32, main, 1, font(true, 23), "left", "center", true)
            dxDrawText(v, x + 196, top + 32, x + 432, top + rh - 4, C.dim, 1, font(false, 15), "left", "center", true)
        else
            dxDrawText(place, x + 196, top, x + 432, top + rh, main, 1, font(true, 23), "left", "center", true)
        end

        -- track
        local bx, by = x + 446, top + 9
        if gone then
            dxDrawText(e.track, bx, by, bx + 48, by + 39, C.dim, 1, font(true, 26), "center", "center")
        else
            dxDrawRectangle(bx, by, 48, 39, C.box)
            dxDrawText(e.track, bx, by, bx + 48, by + 39, C.boxTxt, 1, font(true, 26), "center", "center")
        end

        local r1, r2, col = remark(e, blink)
        if r2 then
            dxDrawText(r1, x + 512, top + 4, x + w - 4, top + 32, col, 1, font(true, 18), "left", "center", true)
            dxDrawText(r2, x + 512, top + 32, x + w - 4, top + rh - 4, C.amber, 1, font(true, 17), "left", "center", true)
        else
            dxDrawText(r1, x + 512, top, x + w - 4, top + rh, col, 1, font(true, 18), "left", "center", true)
        end
    end
end

local function drawBoard(id)
    local rt = targets[id]
    local b = boards[id]
    if not rt then return end
    dxSetRenderTarget(rt, true)
    dxSetBlendMode("modulate_add")
    dxDrawRectangle(0, 0, RT_W, RT_H, C.bg)

    -- header: station, company, clock
    dxDrawRectangle(0, 0, RT_W, 84, C.head)
    dxDrawRectangle(0, 84, RT_W, 4, C.accent)
    local st
    for _, s in ipairs(TT.STATIONS) do if s.id == id then st = s end end
    dxDrawText(st and st.name or id, 28, 6, RT_W - 260, 56, C.text, 1, font(true, 38), "left", "center")
    dxDrawText("SUNLINE RAIL  ·  " .. string.upper(st and st.city or ""), 30, 54, RT_W - 260, 80, C.accent, 1, font(true, 15), "left", "center")
    local now = clock()
    if now then
        local s = math.floor(now) % 86400
        dxDrawText(("%s:%02d"):format(hhmm(s), s % 60), RT_W - 260, 0, RT_W - 28, 84, C.text, 1, font(true, 44), "right", "center")
    end

    if b then
        drawColumn(b.departures or {}, 20, 98, 610, "Departures", "Destination", true)
        drawColumn(b.arrivals or {}, 650, 98, 610, "Arrivals", "From", false)
        dxDrawRectangle(639, 100, 2, RT_H - 112, C.stripe)
    else
        dxDrawText("Loading timetable…", 0, 88, RT_W, RT_H, C.dim, 1, font(false, 26), "center", "center")
    end

    dxSetBlendMode("blend")
    dxSetRenderTarget()
    lastDraw[id] = getTickCount()
    dirty[id] = nil
end

------------------------------------------------------------------ frame

local function release(id)
    if isElement(targets[id]) then destroyElement(targets[id]) end
    targets[id] = nil
end

addEventHandler("onClientRender", root, function()
    if getElementDimension(localPlayer) ~= 0 or getElementInterior(localPlayer) ~= 0 then return end
    local cx, cy, cz = getCameraMatrix()
    local want = {}

    -- which stations are near, which displays to draw
    local draw = {}
    for _, d in ipairs(TT.DISPLAYS) do
        local dist = getDistanceBetweenPoints3D(cx, cy, cz, d.x, d.y, d.z)
        if dist <= B.KEEP_DIST then want[d.station] = true end
        if dist <= B.DRAW_DIST then draw[#draw + 1] = d end
    end
    for id in pairs(near) do
        if not want[id] then near[id] = nil; release(id) end
    end
    local ask, fresh = {}, false
    for id in pairs(want) do
        if not near[id] then fresh = true end
        near[id] = true
        ask[#ask + 1] = id
        if not targets[id] then
            targets[id] = dxCreateRenderTarget(RT_W, RT_H, false)
            dirty[id] = true
        end
    end

    -- board data
    if #ask > 0 and (fresh or getTickCount() - lastAsk > B.REFRESH * 1000) then
        lastAsk = getTickCount()
        triggerServerEvent("rw:tt:boards", resourceRoot, ask)
    end

    -- redraw: clock / blinking, or new data
    for id in pairs(want) do
        if targets[id] and (dirty[id] or getTickCount() - (lastDraw[id] or 0) >= 350) then drawBoard(id) end
    end

    for _, d in ipairs(draw) do
        local rt = targets[d.station]
        if rt then
            local off = d.off or OFFSET
            local x, y = d.x + d.nx * off, d.y + d.ny * off
            dxDrawMaterialLine3D(x, y, d.z + d.h / 2, x, y, d.z - d.h / 2, rt, d.w, tocolor(255, 255, 255, 255),
                x + d.nx, y + d.ny, d.z)
        end
    end
end)

addEvent("rw:tt:boardsResult", true)
addEventHandler("rw:tt:boardsResult", resourceRoot, function(list)
    for id, b in pairs(list or {}) do
        if b then
            boards[id] = b
            dirty[id] = true
            clockBase, clockTick = b.t, getTickCount()
        end
    end
end)

-- render targets are emptied when the game is minimized
addEventHandler("onClientRestore", root, function()
    for id in pairs(targets) do dirty[id] = true end
end)

------------------------------------------------------------------ placing helper

-- /rwboardpos [w] [h]: the wall the camera looks at -> a TT.DISPLAYS line (chat + console)
addCommandHandler("rwboardpos", function(_, w, h)
    local cx, cy, cz, tx, ty, tz = getCameraMatrix()
    local dx, dy, dz = tx - cx, ty - cy, tz - cz
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    if len == 0 then return end
    local hit, x, y, z, _, nx, ny = processLineOfSight(cx, cy, cz, cx + dx / len * 80, cy + dy / len * 80, cz + dz / len * 80,
        true, false, false, true, false, false, false, false, localPlayer)
    if not hit then return outputChatBox("[Timetable] No wall in front of the camera.", 255, 160, 90) end
    local nl = math.sqrt(nx * nx + ny * ny)
    if nl < 0.5 then return outputChatBox("[Timetable] That is not a wall (floor / ceiling).", 255, 160, 90) end
    nx, ny = nx / nl, ny / nl
    local best, bestD
    for _, s in ipairs(TT.STATIONS) do
        local d = getDistanceBetweenPoints2D(x, y, s.x, s.y)
        if not bestD or d < bestD then best, bestD = s.id, d end
    end
    w, h = tonumber(w) or 6, tonumber(h) or 3
    local line = ('{ station = "%s", x = %.2f, y = %.2f, z = %.2f, nx = %.3f, ny = %.3f, w = %.1f, h = %.1f },')
        :format(best, x, y, z, nx, ny, w, h)
    outputChatBox("[Timetable] " .. line, 120, 200, 255)
    outputConsole(line)
end)
