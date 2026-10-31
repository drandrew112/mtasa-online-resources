-- police_system / modules/hud/client/mini.lua
-- The mini panel while signed in to a unit, bottom right: callsign + officers, the status in its colour (+ the Busy
-- sub label, e.g. Traffic stop) and the colour coded F keys under it. Drawn into a render target only when the state
-- changes; the layer draws one image per frame.

local HUD = POL.module("hud", {})
local cv = POL.canvas()

local SUBS = { traffic_stop = "police_system.status.sub_traffic_stop", ped_stop = "police_system.status.sub_ped_stop" }

function HUD.rect()
    local w, h = POL.px(300), POL.px(96)
    return POL.sw - w - POL.px(22), POL.sh - h - POL.px(22), w, h
end

local function redraw()
    local u = POL.unit
    if not u then return end
    local _, _, w, h = HUD.rect()
    cv:paint(w, h, function()
        local c = POL.colors
        dxDrawRectangle(0, 0, w, h, c.bg)
        dxDrawRectangle(0, 0, POL.px(4), h, POL.statusColor(u.status))
        local pad = POL.px(12)
        local names = table.concat(u.members or {}, " · ")
        dxDrawText(u.callsign, pad, POL.px(6), w, POL.px(30), c.white, 1, POL.font(15, true), "left", "center")
        local cw = dxGetTextWidth(u.callsign, 1, POL.font(15, true))
        dxDrawText(L.upper(names), pad + cw + POL.px(10), POL.px(6), w - pad, POL.px(30), c.dim, 1, POL.font(9, true),
            "left", "center", true)
        local status = L.upper(L("police_system.status." .. tostring(u.status)))
        if u.sub and SUBS[u.sub] then status = status .. " · " .. L.upper(L(SUBS[u.sub])) end
        dxDrawText(status, pad, POL.px(32), w - pad, POL.px(56), POL.statusColor(u.status), 1, POL.font(12, true), "left", "center", true)
        local kw = (w - pad * 2 - POL.px(9)) / 4
        for i, st in ipairs(UNIT_STATUS_ORDER) do
            local def = UNIT_STATUS[st]
            local x = pad + (i - 1) * (kw + POL.px(3))
            local y = POL.px(62)
            local col = tocolor(def.color[1], def.color[2], def.color[3], u.status == st and 255 or 90)
            dxDrawRectangle(x, y, kw, POL.px(24), col)
            dxDrawText(def.key .. " " .. L.upper(L("police_system.status.short_" .. st)), x, y, x + kw, y + POL.px(24),
                u.status == st and tocolor(10, 18, 34, 255) or c.white, 1, POL.font(9, true), "center", "center")
        end
    end)
end

local function draw()
    local x, y = HUD.rect()
    cv:draw(x, y)
end
POL.layers.add("mini", draw, 10)

local function refresh()
    local show = POL.onDuty() and POL.hasRight()
    if show then redraw() end
    POL.layers.set("mini", show)
end

POL.on("unit", refresh)
POL.on("right", refresh)
addEventHandler("onClientRestore", root, function(cleared) if cleared then refresh() end end)
L.onChange(refresh)

------------------------------------------------------------------------ F4-F7

local KEYS = { f4 = "STATUS_PURSUIT", f5 = "STATUS_AVAILABLE", f6 = "STATUS_RESPONDING", f7 = "STATUS_BUSY" }

POL.key("fkeys", function(button, press)
    local id = KEYS[button]
    if not id or not POL.onDuty() or not POL.hasRight() then return false end
    if press then
        local args
        if id == "STATUS_PURSUIT" and POL.stopc then args = { target = POL.stopc.pursuitTarget() } end
        POL.send("radio", id, args)
    end
    return true
end, 10)
