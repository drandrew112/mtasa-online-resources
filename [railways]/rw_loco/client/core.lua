-- Cab core: finds out when the local player drives a locomotive, runs that loco type's
-- modules (cab panel, timetable, vigilance), lays the panels out around the v_radar minimap,
-- handles the cursor, clickable areas and the traction lock.
--
-- A module: registerLocoModule(id, {
--     enter(ctx)  leave()  update(ctx) (every frame)  render(ctx) (unless the HUD is hidden)
--     layout(ctx)  restore()  vehicleChanged(ctx) })
-- ctx = Loco (fields below). Modules draw only in render and register click areas with
-- Loco.hit(x, y, w, h, fn).

Loco = {
    active = false, lead = nil, consistId = nil, type = nil, def = nil,
    sw = 0, sh = 0, s = 1,
    L = {},                 -- layout rectangles: panel (cab), tt (timetable panel), mini
    cursor = false,
}

local Modules = {}
local running = {}          -- module ids of the current loco
local hits, hitsNext = {}, {}
local locks = {}
local fonts = {}
local minimap = { 0, 0, 0, 0 }

function registerLocoModule(id, mod)
    Modules[id] = mod
end

------------------------------------------------------------------ helpers

function Loco.font(bold, size)
    local px = math.max(6, math.floor(size * Loco.s + 0.5))
    local key = (bold and "b" or "r") .. px
    if not fonts[key] then
        fonts[key] = dxCreateFont(bold and "fonts/RobotoB.ttf" or "fonts/Roboto.ttf", px, false, "antialiased") or "default"
    end
    return fonts[key]
end

function Loco.hit(x, y, w, h, fn)
    hitsNext[#hitsNext + 1] = { x, y, w, h, fn }
end

function Loco.cursorIn(x, y, w, h)
    if not isCursorShowing() then return false end
    local cx, cy = getCursorPosition()
    cx, cy = cx * Loco.sw, cy * Loco.sh
    return cx >= x and cx <= x + w and cy >= y and cy <= y + h
end

-- traction lock: while any reason is set the network train gets no tractive force
-- (rw_customtracks simulates the train; the request goes to the server on a change only)
-- rw_customtracks calls, harmless while it (re)starts
local function call(fn, ...)
    local res = getResourceFromName("rw_customtracks")
    if not res or getResourceState(res) ~= "running" then return false end
    local ok, a, b = pcall(function(...) return exports.rw_customtracks[fn](exports.rw_customtracks, ...) end, ...)
    if ok then return a, b end
    return false
end
local function net()
    return setmetatable({}, { __index = function(_, fn) return function(_, ...) return call(fn, ...) end end })
end
function Loco.lock(reason, on)
    on = on and true or nil
    if locks[reason] == on then return end
    locks[reason] = on
    net():netCab("lock", reason, on)
end

-- emergency brake of the network train (Sifa, signal passed at danger)
function Loco.emergency(on)
    net():netCab("emergency", on and true or false)
end

-- the network train the local player drives (rw_customtracks) or false
function Loco.train()
    return net():netGetMyTrain()
end

function Loco.isLocked(reason)
    if reason then return locks[reason] == true end
    return next(locks) ~= nil
end

function Loco.send(action, arg)
    triggerServerEvent("rw:loco:action", resourceRoot, action, arg)
end

function Loco.state()
    return isElement(Loco.lead) and getElementData(Loco.lead, "rw.loco") or {}
end

function Loco.doors()
    return isElement(Loco.lead) and getElementData(Loco.lead, "rw.doors") or "closed"
end

-- km/h (positive)
function Loco.speed()
    local t = Loco.train()
    return t and math.abs(t.speed) * 3.6 or 0
end

-- the lead's centre on the rw track scale, its moving / facing direction and the head
function Loco.trackInfo()
    if not isElement(Loco.lead) then return nil end
    local track = getElementData(Loco.lead, "rw.track")
    local facing = getElementData(Loco.lead, "rw.dir") or 1
    if not track then return nil end
    local x, y = getElementPosition(Loco.lead)
    local center = net():lineProject(track, x, y, 15)
    if not center then return nil end
    local t = Loco.train()
    local sp = t and t.speed or 0                      -- m/s, + = the way the lead faces
    local dir = math.abs(sp) > 0.1 and (sp > 0 and facing or -facing) or facing
    return track, center, dir, center + dir * LOCO.HALF_LENGTH
end

------------------------------------------------------------------ layout

local function readMinimap()
    local ok, x, y, w, h = pcall(function() return exports.v_radar:getMinimapRect() end)
    if ok and x then minimap = { x, y, w, h } else minimap = { 0, Loco.sh, 0, 0 } end
end

-- Bottom row: minimap (v_radar, left) | cab panel | timetable column (right corner).
-- Nothing may overlap the minimap; everything scales down together when it does not fit.
local PANEL_W, PANEL_H, COL_W, MINI_W, MINI_H = 900, 270, 420, 330, 136

local function layout()
    local sw, sh = guiGetScreenSize()
    Loco.sw, Loco.sh = sw, sh
    readMinimap()
    local mx, my, mw = minimap[1], minimap[2], minimap[3]
    local mapRight = mx + mw
    local s = sh / 1080
    local gap = 18 * s
    local fit = (sw - mapRight - 3 * gap) / (PANEL_W + COL_W)
    if fit < s then s = math.max(0.45, fit) gap = 18 * s end
    Loco.s = s
    -- timetable column, bottom right
    local colW = COL_W * s
    local colX = sw - gap - colW
    local top = 150 * (sh / 1080)
    local panelH = math.max(160 * s, math.min(640 * s, sh - gap - top))
    Loco.L.tt = { x = colX, y = sh - gap - panelH, w = colW, h = panelH }
    Loco.L.mini = { x = sw - gap - MINI_W * s, y = sh - gap - MINI_H * s, w = MINI_W * s, h = MINI_H * s }
    -- the cab panel: centred if it fits, else between the minimap and the column
    local w, h = PANEL_W * s, PANEL_H * s
    local x = math.max((sw - w) / 2, mapRight + gap)
    if x + w > colX - gap then x = math.max(mapRight + gap, colX - gap - w) end
    Loco.L.panel = { x = x, y = sh - h - 12 * s, w = w, h = h }
    for _, id in ipairs(running) do
        local m = Modules[id]
        if m and m.layout then m.layout(Loco) end
    end
end

------------------------------------------------------------------ enter / leave

local function moduleIds(def)
    local ids = { def.panel }
    for _, m in ipairs(def.modules or {}) do ids[#ids + 1] = m end
    return ids
end

local function render()
    if not Loco.active then return end
    hitsNext = {}
    for _, id in ipairs(running) do
        local m = Modules[id]
        if m and m.update then m.update(Loco) end
    end
    local hidden = getElementData(localPlayer, "hideHUD") or isPlayerMapVisible()
    if not hidden then
        for _, id in ipairs(running) do
            local m = Modules[id]
            if m and m.render then m.render(Loco) end
        end
    end
    hits = hitsNext
end

local function enter(lead, consistId, typeId)
    local def = LOCO.TYPES[typeId]
    if not def then return end
    Loco.active, Loco.lead, Loco.consistId, Loco.type, Loco.def = true, lead, consistId, typeId, def
    running = moduleIds(def)
    net():netSetHudEnabled(false)       -- the cab panel shows the controller / ATP instead
    layout()
    for _, id in ipairs(running) do
        local m = Modules[id]
        if m and m.enter then m.enter(Loco) end
    end
    addEventHandler("onClientRender", root, render)
end

local function leave()
    if not Loco.active then return end
    for _, id in ipairs(running) do
        local m = Modules[id]
        if m and m.leave then m.leave(Loco) end
    end
    removeEventHandler("onClientRender", root, render)
    Loco.active, Loco.lead, Loco.consistId = false, nil, nil
    running = {}
    hits = {}
    for r in pairs(locks) do locks[r] = nil end
    net():netSetHudEnabled(true)
    if Loco.cursor then Loco.cursor = false showCursor(false) end
end

-- polled: entering, leaving, and the lead being re-created by a switch (same consist id)
local function check()
    local v = getPedOccupiedVehicle(localPlayer)
    local lead, cid, typeId
    if v and getVehicleOccupant(v, 0) == localPlayer then
        cid = getElementData(v, "rw.consist")
        typeId = getElementData(v, "rw.type")
        if cid and LOCO.TYPES[typeId] then lead = v end
    end
    if not lead then
        if Loco.active then leave() end
        return
    end
    if Loco.active and Loco.consistId == cid then
        -- no traction without a running engine or with released doors
        local st = getElementData(lead, "rw.loco") or {}
        Loco.lock("engine", st.eng ~= "running")
        -- no engine sound / idle until the simulation runs the engine
        if st.eng ~= "running" and getVehicleEngineState(lead) then setVehicleEngineState(lead, false) end
        Loco.lock("doors", (getElementData(lead, "rw.doors") or "closed") ~= "closed")
        if Loco.lead ~= lead then
            Loco.lead = lead
            for _, id in ipairs(running) do
                local m = Modules[id]
                if m and m.vehicleChanged then m.vehicleChanged(Loco) end
            end
        end
        return
    end
    if Loco.active then leave() end
    enter(lead, cid, typeId)
end

setTimer(check, 250, 0)
setTimer(function() if Loco.active then readMinimap() layout() end end, 3000, 0)

addEventHandler("onClientClick", root, function(button, state)
    if not Loco.active or button ~= "left" or state ~= "down" then return end
    local cx, cy = getCursorPosition()
    if not cx then return end
    cx, cy = cx * Loco.sw, cy * Loco.sh
    for i = #hits, 1, -1 do
        local h = hits[i]
        if cx >= h[1] and cx <= h[1] + h[3] and cy >= h[2] and cy <= h[2] + h[4] then
            h[5]()
            return
        end
    end
end)

-- commands, so players can rebind them in the MTA settings
addCommandHandler("rw_cursor", function()
    if not Loco.active or isChatBoxInputActive() or isMainMenuActive() then return end
    Loco.cursor = not Loco.cursor
    showCursor(Loco.cursor, false)
end)
bindKey(LOCO.KEYS.cursor, "down", "rw_cursor")

addEventHandler("onClientRestore", root, function(cleared)
    if not cleared then return end
    for _, id in ipairs(running) do
        local m = Modules[id]
        if m and m.restore then m.restore(Loco) end
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if Loco.active then leave() end
end)

addEvent("rw:loco:notify", true)
addEventHandler("rw:loco:notify", resourceRoot, function(text)
    local res = getResourceFromName("ui_core")
    if res and getResourceState(res) == "running" then exports.ui_core:addNotification("Locomotive", text)
    else outputChatBox("[Locomotive] " .. text, 255, 200, 90) end
end)

-- the server put us down beside the cab: stand on the real ground (platform / ballast)
addEvent("rw:loco:placed", true)
addEventHandler("rw:loco:placed", resourceRoot, function(x, y, z, rz)
    local gz = getGroundPosition(x, y, z + 3)
    if gz and gz ~= 0 and gz > z - 4 then z = gz + 1 end
    setElementPosition(localPlayer, x, y, z)
    if rz then setElementRotation(localPlayer, 0, 0, rz, "default", true) end
end)
