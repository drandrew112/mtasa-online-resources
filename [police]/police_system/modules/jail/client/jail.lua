-- police_system / modules/jail/client/jail.lua
-- The jailed player's remaining time (pol.jail = the end, epoch; subscribe: only the player gets it). Redrawn once a
-- second into a small canvas; the time also runs while the player is offline (said on the panel).

local cv = POL.canvas()
local untilTs, timer

local function paint()
    local left = math.max(0, (untilTs or 0) - getRealTime().timestamp)
    local w, h = POL.px(300), POL.px(64)
    cv:paint(w, h, function()
        local c = POL.colors
        dxDrawRectangle(0, 0, w, h, c.bg)
        dxDrawRectangle(0, 0, w, POL.px(3), c.red)
        dxDrawText(L("police_system.jail.title") .. "  " .. ("%02d:%02d"):format(math.floor(left / 60), left % 60),
            0, POL.px(6), w, POL.px(34), c.white, 1, POL.font(13, true), "center", "center")
        dxDrawText(L("police_system.jail.offline_note"), POL.px(8), POL.px(34), w - POL.px(8), h - POL.px(4), c.dim, 1,
            POL.font(8), "center", "center", false, true)
    end)
end

local function draw() cv:draw((POL.sw - cv.w) / 2, POL.px(90)) end
POL.layers.add("jail", draw, 50)

local function refresh()
    untilTs = tonumber(getElementData(localPlayer, "pol.jail"))
    if untilTs and not timer then
        paint()
        timer = setTimer(paint, 1000, 0)
        POL.layers.set("jail", true)
    elseif not untilTs and timer then
        killTimer(timer)
        timer = nil
        POL.layers.set("jail", false)
    end
end

addEventHandler("onClientElementDataChange", localPlayer, function(key) if key == "pol.jail" then refresh() end end)
addEventHandler("onClientResourceStart", resourceRoot, refresh)
