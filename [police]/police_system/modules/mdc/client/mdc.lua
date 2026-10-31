-- police_system / modules/mdc/client/mdc.lua
-- The Mobile Data Computer: J in a police vehicle (driver or passenger), only with the police right; the Skoda 598
-- only with the hu_pd paintjob (isPoliceModelVehicle). No warning for anyone else (the key just goes on to other
-- resources). 80 % of the screen (width and height), menu in the top bar, navy theme, the status colours of F4-F7.
-- Without a unit only the smaller sign-in window shows. Drawn into a render target only when something changed
-- (data, hover, typing); one dxDrawImage a frame. Data: request / reply (pol:mdc:call), the Overview feed only while
-- open. Movement is locked while open (ui_core toggleMoveControls + the vehicle controls), the vehicle stands.

local MDC = POL.module("mdc", { open = false, page = "overview", view = nil, data = {}, dirty = true })
local cv = POL.canvas()
local seq, pending = 0, {}
MDC.pages = {}
MDC.MENU = { "overview", "calls", "pursuits", "wanted", "warrants", "citizens", "vehicles", "reports", "penal" }

local VEH_CONTROLS = { "accelerate", "brake_reverse", "vehicle_left", "vehicle_right", "steer_forward", "steer_back",
                       "vehicle_fire", "vehicle_secondary_fire", "horn" }

function MDC.isOpen() return MDC.open end

function MDC.rect()
    local sw, sh = POL.sw, POL.sh
    if not POL.onDuty() then
        local w, h = math.min(POL.px(640), sw - POL.px(40)), math.min(POL.px(470), sh - POL.px(40))
        return math.floor((sw - w) / 2), math.floor((sh - h) / 2), w, h
    end
    local w, h = math.floor(sw * 0.8), math.floor(sh * 0.8)
    return math.floor((sw - w) / 2), math.floor((sh - h) / 2), w, h
end

function MDC.mark() MDC.dirty = true end

------------------------------------------------------------------------ requests

function MDC.call(action, args, cb)
    seq = seq + 1
    pending[seq] = cb or function() end
    POL.send("mdc:call", seq, action, args or {})
end

POL.handle("mdc:reply", function(id, result, err, extra)
    local cb = pending[id]
    pending[id] = nil
    if cb then
        local ok, e = pcall(cb, result, err, extra)
        if not ok then outputDebugString("[police_system] mdc reply: " .. tostring(e), 1) end
    end
    if result == false and err and err ~= "not_found" then MDC.error(err) end
    MDC.dirty = true
end)

POL.handle("mdc:feed", function(data)
    MDC.data.overview = data
    MDC.dirty = true
end)

POL.handle("mdc:refresh", function(page)
    if MDC.open and (MDC.page == page or (page == "signin" and not POL.onDuty())) then MDC.load() end
end)

function MDC.error(err)
    MDC.lastError = L.has("police_system.err." .. tostring(err)) and L("police_system.err." .. tostring(err))
        or tostring(err)
    MDC.errorAt = getTickCount()
    MDC.dirty = true
end

------------------------------------------------------------------------ pages

function MDC.go(page, view)
    MDC.page = page
    MDC.view = view
    W.scroll = {}
    W.focus = nil
    W.popup = nil
    MDC.load()
    MDC.dirty = true
end

function MDC.load()
    local name = POL.onDuty() and MDC.page or "signin"
    local p = MDC.pages[name]
    if p and p.load then p.load() end
end

local function drawTop(w, h)
    local c = POL.colors
    local u = POL.unit
    dxDrawRectangle(0, 0, w, POL.px(54), c.panel)
    dxDrawRectangle(0, POL.px(54), w, POL.px(2), c.accent)
    W.text("SAPD", POL.px(18), 0, POL.px(80), POL.px(54), c.accent, 16, true)
    W.text("MOBILE DATA COMPUTER", POL.px(80), 0, POL.px(300), POL.px(54), c.dim, 10, true)
    local rx = w - POL.px(18)
    W.button("close", rx - POL.px(36), POL.px(11), POL.px(36), POL.px(32), "✕", function() MDC.close() end, "ghost")
    rx = rx - POL.px(50)
    W.text(POL.clock(getRealTime().timestamp), rx - POL.px(60), 0, POL.px(60), POL.px(54), c.text, 12, true, "right")
    rx = rx - POL.px(76)
    if u then
        local st = L.upper(L("police_system.status." .. tostring(u.status)))
        local sw = dxGetTextWidth(st, 1, POL.font(9, true)) + POL.px(16)
        dxDrawRectangle(rx - sw, POL.px(15), sw, POL.px(24), POL.statusColor(u.status))
        W.text(st, rx - sw, POL.px(15), sw, POL.px(24), tocolor(10, 18, 34, 255), 9, true, "center")
        rx = rx - sw - POL.px(12)
        local names = table.concat(u.members or {}, " · ")
        W.text(names, rx - POL.px(300), 0, POL.px(300), POL.px(54), c.dim, 10, false, "right")
        local nw = math.min(POL.px(300), dxGetTextWidth(names, 1, POL.font(10)))
        W.text(u.callsign, rx - nw - POL.px(80), 0, POL.px(70), POL.px(54), c.white, 14, true, "right")
    end
end

local function counts()
    local o = MDC.data.overview or {}
    local drafts = o.pending or 0
    return { pursuits = #(o.pursuits or {}), wanted = #(o.wanted or {}), calls = 0, reports = drafts }
end

local function drawMenu(w)
    local c = POL.colors
    local y, h = POL.px(56), POL.px(40)
    dxDrawRectangle(0, y, w, h, c.panel2)
    local x = POL.px(10)
    local n = counts()
    for _, id in ipairs(MDC.MENU) do
        local label = L("police_system.mdc.menu_" .. id)
        if n[id] and n[id] > 0 then label = label .. "  " .. n[id] end
        local tw = dxGetTextWidth(label, 1, POL.font(10, true)) + POL.px(26)
        local active = MDC.page == id
        local hov = W.hit("menu:" .. id, x, y, tw, h, function() MDC.go(id) end)
        if active then dxDrawRectangle(x, y + h - POL.px(3), tw, POL.px(3), c.accent) end
        if hov and not active then dxDrawRectangle(x, y, tw, h, c.hover) end
        W.text(label, x, y, tw, h, active and c.white or c.dim, 10, true, "center")
        x = x + tw
    end
    local u = POL.unit
    if u then
        local leader = u.leader == POL.nameOfLocal()
        local label = leader and L("police_system.mdc.sign_off") or L("police_system.mdc.leave_unit")
        W.button("signoff", w - POL.px(150), y + POL.px(5), POL.px(140), h - POL.px(10), label, function()
            MDC.call("signOff", {}, function(ok, err, n)
                if ok then MDC.close() elseif err == "reports" then MDC.go("reports") end
            end)
        end, "danger")
    end
end

function POL.nameOfLocal()
    local d = getElementData(localPlayer, "displayName") or getElementData(localPlayer, "accName") or getPlayerName(localPlayer)
    return (tostring(d):gsub("#%x%x%x%x%x%x", ""))
end

local function drawAll(w, h)
    W.reset()
    local c = POL.colors
    dxDrawRectangle(0, 0, w, h, c.bg)
    if POL.onDuty() then
        drawTop(w, h)
        drawMenu(w)
        local p = MDC.pages[MDC.page]
        if p and p.draw then p.draw(POL.px(16), POL.px(108), w - POL.px(32), h - POL.px(124)) end
    else
        local p = MDC.pages.signin
        if p then p.draw(0, 0, w, h) end
    end
    if MDC.lastError and getTickCount() - (MDC.errorAt or 0) < 5000 then
        local tw = dxGetTextWidth(MDC.lastError, 1, POL.font(10, true)) + POL.px(30)
        dxDrawRectangle((w - tw) / 2, h - POL.px(44), tw, POL.px(32), c.red)
        W.text(MDC.lastError, (w - tw) / 2, h - POL.px(44), tw, POL.px(32), c.white, 10, true, "center")
    end
    if W.popupDraw then W.popupDraw() end
end

local lastBlink = 0
local function frame()
    local x, y, w, h = MDC.rect()
    local now = getTickCount()
    -- the caret blinks: a redraw twice a second while a field has the focus
    if W.focus and now - lastBlink > 500 then lastBlink = now; MDC.dirty = true end
    if MDC.lastError and now - (MDC.errorAt or 0) > 5000 and now - (MDC.errorAt or 0) < 5600 then MDC.dirty = true end
    if MDC.dirty then
        MDC.dirty = false
        cv:paint(w, h, drawAll)
    end
    cv:draw(x, y)
    if isCursorShowing() then
        local cx, cy = getCursorPosition()
        local hit = W.hitAt(cx * POL.sw - x, cy * POL.sh - y)
        local id = hit and hit.id or nil
        if id ~= W.hover then W.hover = id; MDC.dirty = true end
    end
end
POL.layers.add("mdc", frame, 100)

------------------------------------------------------------------------ open / close

local function setLock(on)
    if POL.running("ui_core") then exports.ui_core:toggleMoveControls(not on) end
    for _, c in ipairs(VEH_CONTROLS) do toggleControl(c, not on) end
    local veh = getPedOccupiedVehicle(localPlayer)
    if veh and getVehicleController(veh) == localPlayer then setPedControlState(localPlayer, "handbrake", on) end
end

function POL.running(name)
    local r = getResourceFromName(name)
    return r and getResourceState(r) == "running"
end

function MDC.openMdc()
    if MDC.open then return end
    MDC.open = true
    showCursor(true)
    setLock(true)
    POL.send("mdc:open", true)
    MDC.load()
    MDC.dirty = true
    POL.layers.set("mdc", true)
end

function MDC.close()
    if not MDC.open then return end
    MDC.open = false
    W.focus, W.popup = nil, nil
    showCursor(false)
    setLock(false)
    POL.send("mdc:open", false)
    POL.layers.set("mdc", false)
end

POL.on("unit", function(u, old)
    if MDC.open then
        if (u and true) ~= (old and true) then MDC.go(u and "overview" or MDC.page) end
        MDC.dirty = true
    end
end)
POL.on("right", function(on) if not on then MDC.close() end end)
addEventHandler("onClientPlayerVehicleExit", localPlayer, function() MDC.close() end)
addEventHandler("onClientPlayerWasted", localPlayer, function() MDC.close() end)
addEventHandler("onClientRestore", root, function(cleared) if cleared then MDC.dirty = true end end)
L.onChange(function() MDC.dirty = true end)

------------------------------------------------------------------------ input

POL.key("mdc", function(button, press)
    if not MDC.open then
        if button == "j" and press and POL.hasRight() and POL.inPoliceVehicle() then
            MDC.openMdc()
            return true
        end
        return false
    end
    -- a field has the focus: every key is its own (no chat, no binds); Ctrl+V must reach onClientPaste
    if W.focus then
        local f = W.fields[W.focus]
        -- the status keys never type: they go on to the F-key handler even while a field has the focus
        if button == "f4" or button == "f5" or button == "f6" or button == "f7" or button == "f8" then return false end
        if button == "v" and (getKeyState("lctrl") or getKeyState("rctrl")) then return false end
        if press and f then
            if button == "escape" then W.focus = nil
            elseif button == "a" and (getKeyState("lctrl") or getKeyState("rctrl")) then f:selectAll()
            elseif button == "tab" then W.focus = nil
            else f:key(button, getKeyState("lshift") or getKeyState("rshift")) end
            MDC.dirty = true
        end
        if button == "mouse1" or button == "mouse2" or button:find("mouse_wheel") then return false end
        return true
    end
    if button == "j" then
        if press then MDC.close() end
        return true
    end
    if button == "mouse_wheel_up" or button == "mouse_wheel_down" then
        local x, y = MDC.rect()
        local cx, cy = getCursorPosition()
        local mx, my = cx * POL.sw - x, cy * POL.sh - y
        local d = button == "mouse_wheel_up" and -1 or 1
        for _, a in ipairs(W.scrollAreas) do
            if mx >= a.x and mx <= a.x + a.w and my >= a.y and my <= a.y + a.h then
                if a.field then a.field:scrollBy(d * 2) else W.scroll[a.id] = math.max(0, math.min(a.max, (W.scroll[a.id] or 0) + d * 2)) end
                MDC.dirty = true
                break
            end
        end
        return true
    end
    -- the F keys (status) and chat keys go on; everything else stays in the MDC
    if button == "f4" or button == "f5" or button == "f6" or button == "f7" or button == "t" or button == "y"
        or button == "f8" or button == "escape" or button:find("mouse") then
        return false
    end
    return true
end, 100)

addEventHandler("onClientCharacter", root, function(ch)
    if not MDC.open or not W.focus then return end
    local f = W.fields[W.focus]
    if f then f:insert(ch); MDC.dirty = true end
end)

addEventHandler("onClientPaste", root, function(text)
    if not MDC.open or not W.focus then return end
    local f = W.fields[W.focus]
    if f then f:insert(text); MDC.dirty = true end
end)

addEventHandler("onClientClick", root, function(button, state, ax, ay)
    if not MDC.open or button ~= "left" or state ~= "down" then return end
    local x, y, w, h = MDC.rect()
    local mx, my = ax - x, ay - y
    local hit = W.hitAt(mx, my)
    local hadPopup = W.popup
    if not hit or not (W.fields[hit.id]) then W.focus = nil end
    if hit and hit.fn then hit.fn(mx, my) end
    if hadPopup and W.popup == hadPopup and (not hit or not tostring(hit.id):find(hadPopup, 1, true)) then W.popup = nil end
    MDC.dirty = true
end)
