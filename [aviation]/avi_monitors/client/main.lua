-- v_monitors (client): lays the screens out on the wall, keeps the data, renders each screen into
-- a render target when its data changes (every 5 s) and draws it with dxDrawMaterialLine3D.

local W = MON.WALL
local HIST_DOTS = 6
local mons = {}             -- { kind = "radar" | "ctl", pos, cx, cy, cz, rt, dirty }
local monsPosCount = -1
local data = { traffic = {}, positions = {}, staffed = {}, views = {}, hist = {} }
local static
local hist = {}             -- [aircraft id] = { {x, y}, ... } one dot per refresh
local watching = false
local visible = false


-- ---------------------------------------------------------------- layout
local function wallPoint(u, z)
    return W.ox + W.ux * u + W.nx * MON.OFFSET, W.oy + W.uy * u + W.ny * MON.OFFSET, z
end

-- pixel sizes of a monitor of the given width (m): picture 16:9 + the name plate
local function pixels(rtW)
    local sh = math.floor(rtW * 9 / 16)
    return rtW, sh, sh + math.floor(rtW * MON.PLATE_RATIO)
end

-- monitor 1 = fixed radar (upper wall); the others follow the avi_controller positions in their
-- order, in one row across the wall band at eye height, the width follows from their number.
local function buildLayout()
    local need = #data.positions
    if #mons == need + 1 and monsPosCount == need then
        for i = 2, #mons do mons[i].pos = data.positions[i - 1] end
        return
    end
    for _, m in ipairs(mons) do if isElement(m.rt) then destroyElement(m.rt) end end
    mons, monsPosCount = {}, need

    local R = MON.RADAR
    local rh = R.width * 9 / 16 + R.width * MON.PLATE_RATIO
    local x, y, z = wallPoint(R.u, R.zBottom + rh / 2)
    local sw, sh, h = pixels(R.rtW)
    mons[1] = { kind = "radar", cx = x, cy = y, cz = z, w = R.width, h = rh, sw = sw, sh = sh, rth = h, dirty = true }

    if need == 0 then return end
    local usable = (W.uMax - W.uMin) - 2 * MON.MARGIN
    local mw = math.min(MON.MAX_WIDTH, (usable - (need - 1) * MON.GAP) / need)
    local plateH = mw * MON.PLATE_RATIO
    local mh = mw * 9 / 16 + plateH
    local rowW = need * mw + (need - 1) * MON.GAP
    local mid = (W.uMin + W.uMax) / 2
    local cz = MON.EYE_Z - plateH / 2           -- picture centre at eye height, the plate below it
    sw, sh, h = pixels(MON.RT_W)
    for i = 1, need do
        -- u grows to the viewer's left: the first monitor is the left-most
        local uc = mid + rowW / 2 - mw / 2 - (i - 1) * (mw + MON.GAP)
        local x, y, z = wallPoint(uc, cz)
        mons[i + 1] = { kind = "ctl", pos = data.positions[i], cx = x, cy = y, cz = z, w = mw, h = mh,
            sw = sw, sh = sh, rth = h, dirty = true }
    end
end

-- ---------------------------------------------------------------- data
addEvent("vmon:static", true)
addEventHandler("vmon:static", resourceRoot, function(s)
    static = s
    for _, m in ipairs(mons) do m.dirty = true end
end)

addEvent("vmon:data", true)
addEventHandler("vmon:data", resourceRoot, function(d)
    local seen = {}
    for _, s in ipairs(d.traffic) do
        seen[s.id] = true
        if s.gnd then
            hist[s.id] = {}
        else
            local h = hist[s.id]
            if not h then h = {}; hist[s.id] = h end
            table.insert(h, 1, { s.x, s.y })
            while #h > HIST_DOTS do table.remove(h) end
        end
    end
    for id in pairs(hist) do if not seen[id] then hist[id] = nil end end
    d.hist = hist
    data = d
    buildLayout()
    for _, m in ipairs(mons) do m.dirty = true end
end)

-- ---------------------------------------------------------------- range / visibility
local function distToWall()
    local px, py = getElementPosition(localPlayer)
    local cx, cy = wallPoint((W.uMin + W.uMax) / 2, 0)
    return math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
end

local function setWatching(on)
    if on == watching then return end
    watching = on
    triggerServerEvent("vmon:watch", resourceRoot, on)
    if not on then
        for _, m in ipairs(mons) do
            if isElement(m.rt) then destroyElement(m.rt) end
            m.rt = nil
        end
        visible = false
    end
end

local function losClear()
    local cx, cy, cz = getCameraMatrix()
    local mid = (W.uMin + W.uMax) / 2
    for _, u in ipairs({ mid, W.uMin + 1, W.uMax - 1 }) do
        for _, z in ipairs({ MON.EYE_Z - 0.6, MON.EYE_Z + 0.6, MON.RADAR.zBottom + 2 }) do
            local x, y = wallPoint(u, z)
            -- a point a little in front of the surface, so the wall itself does not block the ray
            if isLineOfSightClear(cx, cy, cz, x + W.nx * 0.15, y + W.ny * 0.15, z, true, false, false, true, false, false, false, localPlayer) then
                return true
            end
        end
    end
    return false
end

setTimer(function()
    local inRange = getElementDimension(localPlayer) == 0 and getElementInterior(localPlayer) == 0
        and distToWall() <= MON.RANGE
    setWatching(inRange)
    if not inRange then return end
    -- plain dxDraw has no depth test: only draw when the wall can be seen, and from its front
    local cx, cy = getCameraMatrix()
    local front = ((cx - W.ox) * W.nx + (cy - W.oy) * W.ny) > 0
    visible = front and losClear()
end, 300, 0)

-- ---------------------------------------------------------------- render
local function ensureRT(m)
    if isElement(m.rt) then return true end
    m.rt = dxCreateRenderTarget(m.sw, m.rth, false)
    m.dirty = true
    return isElement(m.rt)
end

addEventHandler("onClientRender", root, function()
    if not watching or #mons == 0 or not MonRender then return end
    -- re-render at most two screens per frame (a refresh is spread over a few frames)
    local budget = 2
    for _, m in ipairs(mons) do
        if budget == 0 then break end
        if m.dirty and static and ensureRT(m) then
            dxSetRenderTarget(m.rt, true)
            MonRender.monitor(m, data, static, m.sw, m.sh, m.rth)
            dxSetRenderTarget()
            m.dirty = false
            budget = budget - 1
        end
    end
    if not visible then return end
    local white = tocolor(255, 255, 255, 255)
    for _, m in ipairs(mons) do
        if isElement(m.rt) and not m.dirty then
            -- vertical line down the monitor centre, its width = the monitor width, facing the room
            dxDrawMaterialLine3D(m.cx, m.cy, m.cz + m.h / 2, m.cx, m.cy, m.cz - m.h / 2,
                MON.FLIP_UV, m.rt, m.w, white, m.cx + W.nx * 10, m.cy + W.ny * 10, m.cz)
        end
    end
end)

addEventHandler("onClientRestore", root, function(cleared)
    if cleared then for _, m in ipairs(mons) do m.dirty = true end end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if watching then triggerServerEvent("vmon:watch", resourceRoot, false) end
end)
