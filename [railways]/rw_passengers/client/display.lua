-- Passenger information inside the coach: the display above the cockpit door (render target
-- drawn as a 3D material line, station display style) and the announcements (chime + banner):
-- "Next stop" after departing, the station + door side when the doors open, the terminus.

local I = RWP.INTERIORS.coach
local D = I.display
local RT_W, RT_H = 640, 270

local rt
local fonts = {}
local dirty = true
local lastDraw = 0

local C = {
    bg     = tocolor(10, 16, 30, 255),
    bar    = tocolor(22, 70, 160, 255),
    white  = tocolor(240, 244, 250, 255),
    muted  = tocolor(150, 165, 190, 255),
    amber  = tocolor(255, 190, 60, 255),
    green  = tocolor(90, 220, 120, 255),
    red    = tocolor(255, 90, 80, 255),
}

local function font(name, size)
    local key = name .. size
    if not fonts[key] then
        fonts[key] = dxCreateFont(":rw_core/fonts/" .. name .. ".ttf", size, false, "antialiased") or "default-bold"
    end
    return fonts[key]
end

local function hhmm(sec)
    if not sec then return "--:--" end
    sec = math.floor(sec) % 86400
    return ("%02d:%02d"):format(math.floor(sec / 3600), math.floor(sec % 3600 / 60))
end

local function service() return type(Ride.service) == "table" and Ride.service or nil end

local function nextStopOf(s)
    if not s or not s.stops then return nil end
    return s.stops[s.nextStop or 0], s.nextStop == #s.stops
end

local function doorsText(doors)
    if doors == "left" then return "Doors open – left side"
    elseif doors == "right" then return "Doors open – right side"
    elseif doors == "both" then return "Doors open – both sides" end
    return nil
end

------------------------------------------------------------------ display

local function redraw()
    if not rt then rt = dxCreateRenderTarget(RT_W, RT_H, false) end
    if not rt then return end
    dxSetRenderTarget(rt, true)
    dxDrawRectangle(0, 0, RT_W, RT_H, C.bg)

    local s = service()
    -- top bar: line + destination | clock
    dxDrawRectangle(0, 0, RT_W, 70, C.bar)
    local head = s and ((s.name or s.line or "") .. "  →  " .. (s.toName or "")) or "Sunline Rail"
    dxDrawText(head, 22, 0, RT_W - 140, 70, C.white, 1, font("RobotoB", 24), "left", "center", true)
    dxDrawText(hhmm(Ride.clock()), RT_W - 130, 0, RT_W - 20, 70, C.white, 1, font("RobotoB", 24), "right", "center")

    local doors = doorsText(Ride.doors)
    local stop, terminus = nextStopOf(s)
    if s and stop then
        local standing = math.abs(Ride.vNow) < 0.3 and doors
        dxDrawText(standing and "This station" or "Next stop", 22, 86, RT_W, 116, C.muted, 1, font("Roboto", 15), "left", "top")
        dxDrawText(stop.name or "?", 22, 112, RT_W - 150, 170, C.white, 1, font("RobotoB", 30), "left", "top", true)
        local due = stop.arr or stop.dep
        local delay = math.floor((s.delay or 0) / 60 + 0.5)
        dxDrawText(hhmm(due), RT_W - 150, 112, RT_W - 20, 150, C.white, 1, font("RobotoB", 24), "right", "top")
        if due then
            local txt, col = "on time", C.green
            if delay > 0 then txt, col = ("+%d min"):format(delay), delay >= 5 and C.red or C.amber end
            dxDrawText(txt, RT_W - 150, 146, RT_W - 20, 176, col, 1, font("Roboto", 15), "right", "top")
        end
        local line3 = doors or (terminus and "Terminus" or ("Final stop: " .. (s.toName or "")))
        dxDrawText(line3, 22, 196, RT_W - 160, 250, doors and C.amber or C.muted, 1, font("RobotoB", 18), "left", "center", true)
    else
        dxDrawText("Not in service", 22, 100, RT_W, 160, C.white, 1, font("RobotoB", 28), "left", "top")
        dxDrawText(doors or (Ride.train or ""), 22, 196, RT_W - 160, 250, doors and C.amber or C.muted, 1,
            font("RobotoB", 18), "left", "center", true)
    end
    dxDrawText(("%d km/h"):format(math.floor(math.abs(Ride.vNow) * 3.6 + 0.5)), RT_W - 160, 196, RT_W - 20, 250,
        C.muted, 1, font("RobotoB", 18), "right", "center")
    dxSetRenderTarget()
    dirty = false
end

addEventHandler("onClientRestore", root, function() dirty = true end)

addEventHandler("onClientRender", root, function()
    if not Ride.active then return end
    local now = getTickCount()
    if dirty or now - lastDraw > 500 then
        lastDraw = now
        redraw()
    end
    if not rt then return end
    -- vertical board facing the cabin (-y)
    dxDrawMaterialLine3D(D.x, D.y, D.z + D.h / 2, D.x, D.y, D.z - D.h / 2, rt, D.w, tocolor(255, 255, 255),
        D.x + D.nx, D.y + D.ny, D.z)
end)

------------------------------------------------------------------ announcements

local banner           -- { text, sub, untilT }
local lastNext, lastDoors, lastTrip

local function announce(text, sub)
    banner = { text = text, sub = sub, untilT = getTickCount() + RWP.ANNOUNCE_TIME }
    if rwpChime then rwpChime() end
end

local function watch()
    if not Ride.active then lastNext, lastDoors, lastTrip = nil, nil, nil return end
    local s = service()
    local doors = Ride.doors or "closed"
    local trip = s and s.id
    if s and s.stops then
        local stop, terminus = nextStopOf(s)
        -- doors opening at a stop
        if lastDoors == "closed" and doors ~= "closed" and stop then
            if terminus then
                announce(stop.name or "", "This train terminates here. Please leave the train.")
            else
                local side = doors == "both" and "both sides" or (doors .. " side")
                announce(stop.name or "", "Doors open on the " .. side .. ".")
            end
        -- departed: the next stop changed while running
        elseif lastTrip == trip and lastNext and s.nextStop ~= lastNext and stop then
            announce("Next stop: " .. (stop.name or ""), terminus and "Terminus. This train terminates there." or nil)
        end
        lastNext = s.nextStop
    else
        lastNext = nil
    end
    lastDoors, lastTrip = doors, trip
end
setTimer(watch, 250, 0)

addEventHandler("onClientRender", root, function()
    if not banner then return end
    local now = getTickCount()
    if now > banner.untilT or not Ride.active then banner = nil return end
    local sw = guiGetScreenSize()
    local a = math.min(1, (banner.untilT - now) / 400)
    local w, h = math.min(720, sw - 40), banner.sub and 92 or 64
    local x, y = (sw - w) / 2, 36
    dxDrawRectangle(x, y, w, h, tocolor(10, 16, 30, 225 * a))
    dxDrawRectangle(x, y, 6, h, tocolor(40, 110, 230, 255 * a))
    dxDrawText(banner.text, x + 22, y + 10, x + w - 16, y + 46, tocolor(240, 244, 250, 255 * a), 1, font("RobotoB", 17),
        "left", "center", true)
    if banner.sub then
        dxDrawText(banner.sub, x + 22, y + 48, x + w - 16, y + h - 8, tocolor(170, 185, 210, 255 * a), 1, font("Roboto", 13),
            "left", "center", true)
    end
end)
