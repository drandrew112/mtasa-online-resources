-- police_system / modules/callouts/client/popup.lua
-- The call offer of the CalloutManager: a small window right of the minimap, next to the speedometer (v_radar
-- getMinimapRect; the speedometer slot is kept free in a land vehicle), bottom aligned with the map. Title,
-- description, zone + distance, Y accept / N decline and a countdown bar. Drawn into a canvas when the offer changes;
-- per frame only the image and the bar.

local CP = POL.module("callout", { offer = nil, deadline = 0 })
local cv = POL.canvas()
local rect = { 0, 0, 0, 0 }
local rectTimer

local LAND = { Automobile = true, Bike = true, BMX = true, Quad = true, ["Monster Truck"] = true }
local KINDS = { phone = "police_system.callouts.kind_phone", scene = "police_system.callouts.kind_scene",
                agency = "police_system.callouts.kind_agency" }

local function size() return POL.px(310), POL.px(158) end

-- right of the minimap (and of the speedometer when it shows), bottom aligned with the map
local function updateRect()
    local w, h = size()
    local mx, my, mw, mh
    local res = getResourceFromName("v_radar")
    if res and getResourceState(res) == "running" then
        local ok, a, b, c, d = pcall(function() return exports.v_radar:getMinimapRect() end)
        if ok and tonumber(a) then mx, my, mw, mh = a, b, c, d end
    end
    if not mx then mx, my, mw, mh = POL.px(20), POL.sh - POL.px(220), POL.px(300), POL.px(200) end
    local x = mx + mw
    local veh = getPedOccupiedVehicle(localPlayer)
    if veh and LAND[getVehicleType(veh)] then x = x + math.floor(math.min(mw * 0.375, mh * 0.5333)) end
    rect[1], rect[2], rect[3], rect[4] = x + POL.px(10), my + mh - h, w, h
end

local function redraw()
    local o = CP.offer
    if not o then return end
    local w, h = size()
    cv:paint(w, h, function()
        local c = POL.colors
        local pad = POL.px(12)
        dxDrawRectangle(0, 0, w, h, c.bg)
        dxDrawRectangle(0, 0, w, POL.px(26), o.priority == 1 and c.red or c.accentDim)
        local head = L.upper(L("police_system.callouts.offer_header", { id = o.id }))
        if KINDS[o.kind] then head = head .. " · " .. L.upper(L(KINDS[o.kind])) end
        dxDrawText(head, pad, 0, w - pad, POL.px(26), c.white, 1, POL.font(10, true), "left", "center", true)
        dxDrawText("P" .. tostring(o.priority or 2), pad, 0, w - pad, POL.px(26), c.white, 1, POL.font(10, true), "right", "center")
        dxDrawText(o.title or "", pad, POL.px(30), w - pad, POL.px(54), c.white, 1, POL.font(13, true), "left", "center", true)
        dxDrawText(o.description or "", pad, POL.px(56), w - pad, POL.px(104), c.text, 1, POL.font(9), "left", "top", true, true)
        local zone = (o.zone or "") .. "  ·  " .. L("police_system.callouts.distance", { m = o.distance or 0 })
        dxDrawText(zone, pad, POL.px(104), w - pad, POL.px(122), c.dim, 1, POL.font(9, true), "left", "center", true)
        local bw = (w - pad * 2 - POL.px(6)) / 2
        local by = POL.px(126)
        dxDrawRectangle(pad, by, bw, POL.px(24), c.green)
        dxDrawText("Y  " .. L.upper(L("police_system.callouts.accept")), pad, by, pad + bw, by + POL.px(24),
            tocolor(10, 18, 34, 255), 1, POL.font(10, true), "center", "center")
        dxDrawRectangle(pad + bw + POL.px(6), by, bw, POL.px(24), c.panel2)
        dxDrawText("N  " .. L.upper(L("police_system.callouts.decline")), pad + bw + POL.px(6), by, w - pad, by + POL.px(24),
            c.white, 1, POL.font(10, true), "center", "center")
    end)
end

local function draw()
    if not CP.offer then return end
    local x, y, w, h = rect[1], rect[2], rect[3], rect[4]
    cv:draw(x, y)
    local total = (CP.offer.total or 30) * 1000
    local left = math.max(0, CP.deadline - getTickCount())
    dxDrawRectangle(x, y + h - POL.px(3), w * left / total, POL.px(3), POL.colors.yellow)
end
POL.layers.add("callout", draw, 12)

local function show(o)
    CP.offer = o or nil
    if CP.offer then
        CP.deadline = getTickCount() + (o.left or o.total or 30) * 1000
        updateRect()
        redraw()
        if not isTimer(rectTimer) then rectTimer = setTimer(updateRect, 500, 0) end
        playSoundFrontEnd(5)
    else
        if isTimer(rectTimer) then killTimer(rectTimer) end
        rectTimer = nil
        cv:free()
    end
    POL.layers.set("callout", CP.offer ~= nil)
end

POL.handle("callout:offer", show)
POL.on("unit", function(u) if not u then show(nil) end end)
POL.on("right", function(on) if not on then show(nil) end end)
addEventHandler("onClientRestore", root, function(cleared) if cleared then redraw() end end)
L.onChange(redraw)

POL.key("callout", function(button, press)
    local o = CP.offer
    if not o or (button ~= "y" and button ~= "n") then return false end
    if press then
        POL.send("callout:answer", o.id, button == "y")
        show(nil)
    end
    return true
end, 90)
