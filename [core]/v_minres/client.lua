local sw, sh = guiGetScreenSize()
local active = false
local blocker, dgsBlocker
local fontBig, fontSmall = "default-bold", "default"

local function tooSmall()
    return sw < MINRES.width or sh < MINRES.height
end

local function swallow()
    cancelEvent()
end

local function draw()
    dxDrawRectangle(0, 0, sw, sh, tocolor(8, 8, 12, 255), true)
    local s = math.max(0.6, math.min(sw / 1920, sh / 1080))
    local cx, cy = sw / 2, sh / 2
    dxDrawText("LOW RESOLUTION", 0, cy - 140 * s, sw, cy - 60 * s, tocolor(255, 90, 90), 3.2 * s, fontBig, "center", "center", false, false, true)
    dxDrawText(("Your screen is %dx%d.\nThis server requires at least %dx%d."):format(sw, sh, MINRES.width, MINRES.height),
        0, cy - 40 * s, sw, cy + 40 * s, tocolor(255, 255, 255), 1.8 * s, fontSmall, "center", "center", false, false, true)
    dxDrawText("Increase your resolution (Settings > Video > Resolution / maximize the window).\nThis message disappears automatically once the requirement is met.",
        0, cy + 70 * s, sw, cy + 170 * s, tocolor(190, 190, 200), 1.3 * s, fontSmall, "center", "top", false, false, true)
end

local function enable()
    if active then return end
    active = true
    -- native GUI blocker (eats mouse clicks) + DGS blocker kept on top of every DGS element
    blocker = guiCreateStaticImage(0, 0, sw, sh, "pixel.png", false)
    if blocker then guiBringToFront(blocker) end
    local ok, el = pcall(function() return exports.dgs:dgsCreateImage(0, 0, sw, sh, nil, false, nil, tocolor(0, 0, 0, 1)) end)
    if ok then dgsBlocker = el end
    showCursor(true, true)
    addEventHandler("onClientRender", root, draw, true, "low-100")
    addEventHandler("onClientClick", root, swallow, true, "high+100")
    addEventHandler("onClientKey", root, swallow, true, "high+100")
    addEventHandler("onClientCharacter", root, swallow, true, "high+100")
end

local function disable()
    if not active then return end
    active = false
    removeEventHandler("onClientRender", root, draw)
    removeEventHandler("onClientClick", root, swallow)
    removeEventHandler("onClientKey", root, swallow)
    removeEventHandler("onClientCharacter", root, swallow)
    if isElement(blocker) then destroyElement(blocker) end
    if dgsBlocker and isElement(dgsBlocker) then destroyElement(dgsBlocker) end
    blocker, dgsBlocker = nil, nil
    showCursor(false)
end

local function check()
    sw, sh = guiGetScreenSize()
    if tooSmall() then
        if active and isElement(blocker) then
            guiSetSize(blocker, sw, sh, false)
        end
        enable()
    else
        disable()
    end
end

-- keep on top: other UIs may create elements/cursor state later
setTimer(function()
    if not active then return end
    if not isCursorShowing() then showCursor(true, true) end
    if isElement(blocker) then guiBringToFront(blocker) end
    if dgsBlocker and isElement(dgsBlocker) then pcall(exports.dgs.dgsBringToFront, exports.dgs, dgsBlocker) end
end, 250, 0)

addEventHandler("onClientResourceStart", resourceRoot, check)
addEventHandler("onClientRestore", root, check)
setTimer(check, 1000, 0)
