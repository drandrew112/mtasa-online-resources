-- v_monitors (client): lays the screens out on the wall, keeps the data, renders each screen into
-- a render target when its data changes (every 5 s) and draws it with dxDrawMaterialLine3D.

local W = MON.WALL
local HIST_DOTS = 6
local mons = {}             -- { kind = "radar" | "ctl", pos, cx, cy, cz, rt, dirty }
local monsSig            -- position ids the layout was built for
local data = { traffic = {}, positions = {}, staffed = {}, views = {}, hist = {} }
local static
local hist = {}             -- [aircraft id] = { {x, y}, ... } one dot per refresh
local watching = false
local wallVisible = false


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
-- Positions listed in MON.PLACED are left out of the row and hang on their own spot instead.
local function buildLayout()
    local ids = {}
    for i, p in ipairs(data.positions) do ids[i] = p.id end
    local sig = table.concat(ids, ",")
    if #mons > 0 and monsSig == sig then
        for _, m in ipairs(mons) do
            if m.posIndex then m.pos = data.positions[m.posIndex] end
        end
        return
    end
    for _, m in ipairs(mons) do if isElement(m.rt) then destroyElement(m.rt) end end
    mons, monsSig = {}, sig

    local R = MON.RADAR
    local sw, sh, h = pixels(R.rtW)
    local RP = MON.PLACED and MON.PLACED.RADAR
    if RP then
        local rh = RP.width * 9 / 16 + RP.width * MON.PLATE_RATIO
        mons[1] = { kind = "radar", cx = RP.x + RP.nx * MON.OFFSET, cy = RP.y + RP.ny * MON.OFFSET,
            cz = RP.zBottom + rh / 2, w = RP.width, h = rh, sw = sw, sh = sh, rth = h,
            nx = RP.nx, ny = RP.ny, int = RP.int or 0, dim = RP.dim or 0, dirty = true }
    else
        local rh = R.width * 9 / 16 + R.width * MON.PLATE_RATIO
        local x, y, z = wallPoint(R.u, R.zBottom + rh / 2)
        mons[1] = { kind = "radar", cx = x, cy = y, cz = z, w = R.width, h = rh, sw = sw, sh = sh, rth = h,
            nx = W.nx, ny = W.ny, int = 0, dim = 0, onWall = true, dirty = true }
    end

    sw, sh, h = pixels(MON.RT_W)
    local row = {}
    for i, p in ipairs(data.positions) do
        local P = MON.PLACED and MON.PLACED[p.id]
        if P then
            local mh = P.width * 9 / 16 + P.width * MON.PLATE_RATIO
            mons[#mons + 1] = { kind = "ctl", pos = p, posIndex = i,
                cx = P.x + P.nx * MON.OFFSET, cy = P.y + P.ny * MON.OFFSET, cz = P.zBottom + mh / 2,
                w = P.width, h = mh, sw = sw, sh = sh, rth = h,
                nx = P.nx, ny = P.ny, int = P.int or 0, dim = P.dim or 0, dirty = true }
        else
            row[#row + 1] = i
        end
    end

    local need = #row
    if need == 0 then return end
    local usable = (W.uMax - W.uMin) - 2 * MON.MARGIN
    local mw = math.min(MON.MAX_WIDTH, (usable - (need - 1) * MON.GAP) / need)
    local plateH = mw * MON.PLATE_RATIO
    local mh = mw * 9 / 16 + plateH
    local rowW = need * mw + (need - 1) * MON.GAP
    local mid = (W.uMin + W.uMax) / 2
    local cz = MON.EYE_Z - plateH / 2           -- picture centre at eye height, the plate below it
    for k, i in ipairs(row) do
        -- u grows to the viewer's left: the first monitor is the left-most
        local uc = mid + rowW / 2 - mw / 2 - (k - 1) * (mw + MON.GAP)
        local x, y, z = wallPoint(uc, cz)
        mons[#mons + 1] = { kind = "ctl", pos = data.positions[i], posIndex = i, cx = x, cy = y, cz = z,
            w = mw, h = mh, sw = sw, sh = sh, rth = h,
            nx = W.nx, ny = W.ny, int = 0, dim = 0, onWall = true, dirty = true }
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

-- near the tower wall (world) or near one of the MON.PLACED screens (their own interior/dimension)
local function inRange()
    local int, dim = getElementInterior(localPlayer), getElementDimension(localPlayer)
    if int == 0 and dim == 0 and distToWall() <= MON.RANGE then return true end
    local px, py, pz = getElementPosition(localPlayer)
    for _, P in pairs(MON.PLACED or {}) do
        if (P.int or 0) == int and (P.dim or 0) == dim
            and getDistanceBetweenPoints3D(px, py, pz, P.x, P.y, P.zBottom) <= MON.RANGE then
            return true
        end
    end
    return false
end

local renderMonitors -- onClientRender handler, attached only while watching

local function setWatching(on)
    if on == watching then return end
    watching = on
    if on then
        addEventHandler("onClientRender", root, renderMonitors)
    else
        removeEventHandler("onClientRender", root, renderMonitors)
    end
    triggerServerEvent("vmon:watch", resourceRoot, on)
    if not on then
        for _, m in ipairs(mons) do
            if isElement(m.rt) then destroyElement(m.rt) end
            m.rt = nil
            m.visible = false
        end
        wallVisible = false
    end
end

local function losTo(cx, cy, cz, x, y, z, nx, ny)
    -- a point a little in front of the surface, so the wall itself does not block the ray
    return isLineOfSightClear(cx, cy, cz, x + nx * 0.15, y + ny * 0.15, z, true, false, false, true, false, false, false, localPlayer)
end

local function wallLosClear(cx, cy, cz)
    local mid = (W.uMin + W.uMax) / 2
    for _, u in ipairs({ mid, W.uMin + 1, W.uMax - 1 }) do
        for _, z in ipairs({ MON.EYE_Z - 0.6, MON.EYE_Z + 0.6, MON.RADAR.zBottom + 2 }) do
            local x, y = wallPoint(u, z)
            if losTo(cx, cy, cz, x, y, z, W.nx, W.ny) then return true end
        end
    end
    return false
end

-- a placed screen: its centre and its four corners, any of them visible is enough
local function screenLosClear(m, cx, cy, cz)
    local hx, hy = -m.ny * m.w * 0.45, m.nx * m.w * 0.45
    local hz = m.h * 0.45
    for _, o in ipairs({ { 0, 0, 0 }, { hx, hy, hz }, { -hx, -hy, hz }, { hx, hy, -hz }, { -hx, -hy, -hz } }) do
        if losTo(cx, cy, cz, m.cx + o[1], m.cy + o[2], m.cz + o[3], m.nx, m.ny) then return true end
    end
    return false
end

setTimer(function()
    local on = inRange()
    setWatching(on)
    if not on then return end
    -- plain dxDraw has no depth test: only draw what can be seen, and from its front
    local cx, cy, cz = getCameraMatrix()
    local int, dim = getElementInterior(localPlayer), getElementDimension(localPlayer)
    wallVisible = int == 0 and dim == 0 and ((cx - W.ox) * W.nx + (cy - W.oy) * W.ny) > 0
        and wallLosClear(cx, cy, cz)
    for _, m in ipairs(mons) do
        if m.onWall then
            m.visible = wallVisible
        else
            m.visible = m.int == int and m.dim == dim
                and ((cx - m.cx) * m.nx + (cy - m.cy) * m.ny) > 0
                and screenLosClear(m, cx, cy, cz)
        end
    end
end, 300, 0)

-- ---------------------------------------------------------------- render
local function ensureRT(m)
    if isElement(m.rt) then return true end
    m.rt = dxCreateRenderTarget(m.sw, m.rth, false)
    m.dirty = true
    return isElement(m.rt)
end

renderMonitors = function()
    if #mons == 0 or not MonRender then return end
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
    local white = tocolor(255, 255, 255, 255)
    for _, m in ipairs(mons) do
        if m.visible and isElement(m.rt) and not m.dirty then
            -- vertical line down the monitor centre, its width = the monitor width, facing the room
            dxDrawMaterialLine3D(m.cx, m.cy, m.cz + m.h / 2, m.cx, m.cy, m.cz - m.h / 2,
                MON.FLIP_UV, m.rt, m.w, white, m.cx + m.nx * 10, m.cy + m.ny * 10, m.cz)
        end
    end
end

addEventHandler("onClientRestore", root, function(cleared)
    if cleared then for _, m in ipairs(mons) do m.dirty = true end end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if watching then triggerServerEvent("vmon:watch", resourceRoot, false) end
end)
