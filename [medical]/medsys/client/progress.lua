-- Progress bar of a timed procedure without a minigame (e.g. giving a medicine).
-- medic:progress starts it, medic:busy false (the procedure ended in any way) hides it.

addEvent("medic:progress", true)

local screenW, screenH = guiGetScreenSize()
local scale = math.max(0.65, screenH / 1080)
local W, H = 360 * scale, 14 * scale
local X, Y = (screenW - W) / 2, screenH * 0.78

local progress -- { text, start, duration }

local function render()
    if not progress then return end
    local p = math.min(1, (getTickCount() - progress.start) / progress.duration)
    dxDrawText(progress.text, X, Y - 30 * scale, X + W, Y - 4 * scale, tocolor(235, 238, 245, 255),
        1.1 * scale, "default-bold", "center", "bottom")
    dxDrawRectangle(X - 2, Y - 2, W + 4, H + 4, tocolor(16, 18, 24, 220))
    dxDrawRectangle(X, Y, W * p, H, tocolor(215, 55, 65, 255))
end

local function hide()
    if not progress then return end
    progress = nil
    removeEventHandler("onClientRender", root, render)
end

addEventHandler("medic:progress", resourceRoot, function(text, duration)
    if not progress then addEventHandler("onClientRender", root, render) end
    progress = { text = tostring(text), start = getTickCount(), duration = math.max(1, tonumber(duration) or 1) }
end)

addEventHandler("medic:busy", resourceRoot, function(state)
    if state ~= true then hide() end
end)
