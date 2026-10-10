-- Controller client state: logged-in position, static data, traffic (radar refresh per position:
-- TWR 1 s / APP 2 s / radar 3 s, no extrapolation), label offsets, fonts.

SC = {
    open = false,        -- logged in (scope exists)
    visible = false,     -- drawn + cursor (hidden via the ATC marker while staying logged in)
    pos = nil,           -- { id, type, name, airport }
    data = nil,          -- { airspaces, nav = {fixes, ndbs, vors}, airports, runways, wind }
    traffic = {},        -- [id] = { s = snapshot, t = tick of the snapshot, hist = { {x, y} } }
    labelOffset = {},    -- [id] = { dx, dy } screen px from the target (dragged by the controller)
    showList = true,
    staffed = {},        -- [posId] = controller name
    routeShown = {},     -- [id] = true: the flight plan route is drawn
    vectorStep = CTL.VECTOR_DEFAULT_STEPS,   -- leader line ahead of the aircraft in VECTOR_STEP_NM steps, 0 = off
}

-- distances are shown in nautical miles (and fractions of one)
M_PER_NM = 1852
function fmtNm(m)
    local nm = m / M_PER_NM
    if nm < 1 then return ("%.2f nm"):format(nm) end
    return ("%.1f nm"):format(nm)
end

local sx, sy = guiGetScreenSize()
SC.sx, SC.sy = sx, sy
U = math.max(0.75, math.min(1.5, sy / 1080))
LIST_W = 520 * U      -- flight lists on the right

F = {}
local function font(file, pt)
    return dxCreateFont(file, math.max(6, math.floor(pt * U + 0.5)), false, "cleartype") or "default"
end
addEventHandler("onClientResourceStart", resourceRoot, function()
    F.map    = font("fonts/Roboto.ttf", 7.5)
    F.label  = font("fonts/RobotoB.ttf", 8.5)
    F.gndCs  = font("fonts/RobotoB.ttf", 10)
    F.gndSm  = font("fonts/Roboto.ttf", 7.5)
    F.ui     = font("fonts/Roboto.ttf", 9)
    F.uiB    = font("fonts/RobotoB.ttf", 9)
    F.title  = font("fonts/RobotoB.ttf", 12)
end)

-- ---------------------------------------------------------------- helpers
function airportOf(icao)
    return SC.data and SC.data.airports and SC.data.airports[icao]
end

function navById(id)
    if not SC.data or not id then return end
    for _, key in ipairs({ "fixes", "vors", "ndbs" }) do
        for _, p in ipairs(SC.data.nav[key] or {}) do
            if p.id == id then return p end
        end
    end
end

-- position of a traffic entry: the last radar update. Targets jump at every refresh of the position
-- (CTL.UPDATE_MS), there is no extrapolation in between.
function trafficPos(e)
    return e.s.x, e.s.y
end

function isMine(s)
    return SC.pos and s.ctl == SC.pos.id
end

-- ---------------------------------------------------------------- server events
addEvent("avi:ctlData", true)
addEventHandler("avi:ctlData", resourceRoot, function(pos, data)
    local first = not SC.open or not SC.pos or SC.pos.id ~= pos.id
    SC.pos, SC.data = pos, data
    if first then
        SC.traffic, SC.labelOffset = {}, {}
        scopeOpen()
        resetView()
    end
end)

addEvent("avi:ctlRunways", true)
addEventHandler("avi:ctlRunways", resourceRoot, function(runways, wind)
    if not SC.data then return end
    SC.data.runways = runways or SC.data.runways
    SC.data.wind = wind or SC.data.wind
end)

addEvent("avi:ctlTraffic", true)
addEventHandler("avi:ctlTraffic", resourceRoot, function(list, staffed)
    if not SC.open then return end
    SC.staffed = staffed or {}
    local now = getTickCount()
    local seen = {}
    for _, s in ipairs(list) do
        seen[s.id] = true
        local e = SC.traffic[s.id]
        if not e then
            e = { hist = {}, lastHist = 0 }
            SC.traffic[s.id] = e
        end
        e.s, e.t = s, now
        if s.gnd then
            e.hist = {}
        elseif now - e.lastHist >= CTL.HISTORY_EVERY then
            e.lastHist = now
            table.insert(e.hist, 1, { s.x, s.y })
            while #e.hist > CTL.HISTORY_DOTS do table.remove(e.hist) end
        end
    end
    for id in pairs(SC.traffic) do
        if not seen[id] then
            SC.traffic[id] = nil
            SC.labelOffset[id] = nil
            SC.routeShown[id] = nil
            if MENU and MENU.ac == id then menuClose() end
        end
    end
end)

addEvent("avi:ctlClosed", true)
addEventHandler("avi:ctlClosed", resourceRoot, function()
    scopeClose()
end)

addEvent("avi:ctlToggle", true)
addEventHandler("avi:ctlToggle", resourceRoot, function()
    if not SC.open then return end
    if SC.visible then scopeHide() else scopeShow() end
end)

-- the scope view goes to the server every 5 s (the wall monitors of v_monitors mirror it)
setTimer(function()
    if not SC.open or not SC.pos then return end
    local off = {}
    for id, o in pairs(SC.labelOffset) do off[id] = { o[1] / U, o[2] / U } end
    triggerServerEvent("avi:ctlView", resourceRoot, { x = VIEW.x, y = VIEW.y, scale = VIEW.scale,
        sx = SC.sx, sy = SC.sy, showList = SC.showList, visible = SC.visible, off = off })
end, 5000, 0)
