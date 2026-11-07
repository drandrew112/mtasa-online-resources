if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Animation wheel (works like wp_selector). Hold F9: the wheel opens with the 8 favourites, the
-- camera stops and the mouse movement steers the selection (transparent cursor re-centred every
-- frame -> virtual pointer). Releasing F9 plays the selected animation; releasing in the centre
-- does nothing. A short tap of F9 (released before TAP_MS) stops the running animation.

local KEY = "F9"
local TAP_MS = 200

local sx, sy = guiGetScreenSize()
local CX, CY = sx / 2, sy / 2
local S = sy / 1080
local R_OUT, R_IN = 290 * S, 118 * S
local GAP_DEG = 1.6
local ARC_STEPS = 10
local POINTER_MAX = 140 * S
local DEAD_ZONE = 30 * S
local SLOTS = ANIMS.MAX_FAVS

local COLOR = {
    seg      = tocolor(18, 18, 20, 200),
    segEmpty = tocolor(18, 18, 20, 120),
    segSel   = tocolor(239, 159, 39, 235),
    centre   = tocolor(0, 0, 0, 185),
    text     = tocolor(241, 239, 232, 255),
    textDim  = tocolor(255, 255, 255, 90),
    textSub  = tocolor(255, 255, 255, 140),
    textSel  = tocolor(65, 36, 2, 255),
    subSel   = tocolor(99, 56, 6, 255),
    playing  = tocolor(140, 215, 150, 255),
}

local fonts = {}
local function font(size, bold)
    local key = (bold and "b" or "r") .. size
    if not fonts[key] then
        fonts[key] = dxCreateFont(bold and "client/fonts/RobotoB.ttf" or "client/fonts/Roboto.ttf", math.max(7, math.floor(size * S)), false, "antialiased") or "default"
    end
    return fonts[key]
end

local pressTick = nil -- F9 held since (nil = not held)
local isOpen = false
local sel = 0         -- 0 = centre
local px, py = 0, 0

local function polar(deg, r)
    local a = math.rad(deg)
    return CX + r * math.cos(a), CY + r * math.sin(a)
end

-- segment i centred at -90 + 45*(i-1) degrees: slot 1 at the top, then clockwise
local segments = {}
do
    local span = 360 / SLOTS
    for i = 1, SLOTS do
        local mid = -90 + span * (i - 1)
        local a1, a2 = mid - span / 2 + GAP_DEG, mid + span / 2 - GAP_DEG
        local v = {}
        for k = 0, ARC_STEPS - 1 do
            local t1 = a1 + (a2 - a1) * k / ARC_STEPS
            local t2 = a1 + (a2 - a1) * (k + 1) / ARC_STEPS
            local ox1, oy1 = polar(t1, R_OUT)
            local ox2, oy2 = polar(t2, R_OUT)
            local ix1, iy1 = polar(t1, R_IN)
            local ix2, iy2 = polar(t2, R_IN)
            v[#v + 1] = { ox1, oy1 }; v[#v + 1] = { ox2, oy2 }; v[#v + 1] = { ix1, iy1 }
            v[#v + 1] = { ix1, iy1 }; v[#v + 1] = { ox2, oy2 }; v[#v + 1] = { ix2, iy2 }
        end
        segments[i] = { mid = mid, v = v }
    end
end

local centreDisc = {}
do
    local r, n = R_IN - 8 * S, 48
    centreDisc[1] = { CX, CY }
    for k = 0, n do
        local x, y = polar(360 * k / n, r)
        centreDisc[#centreDisc + 1] = { x, y }
    end
end

local function drawPrimitive(kind, points, color)
    local v = {}
    for i, p in ipairs(points) do v[i] = { p[1], p[2], color } end
    dxDrawPrimitive(kind, false, unpack(v))
end

local function indexOfAngle(deg)
    local span = 360 / SLOTS
    return math.floor((((deg + 90) % 360) + span / 2) / span) % SLOTS + 1
end

local function slotAnim(i)
    local id = Anims.favs[i]
    return id and ANIMS.byId[id] or nil
end

--------------------------------------------------------------------------------
-- open / close
--------------------------------------------------------------------------------

local function uiOpen(resName, fn)
    local res = getResourceFromName(resName)
    if not res or getResourceState(res) ~= "running" then return false end
    local ok, result = pcall(function() return exports[resName][fn]() end)
    return ok and result == true
end

local function canUse()
    if isCursorShowing() or isConsoleActive() or isMainMenuActive() or isChatBoxInputActive() then return false end
    if isPedDead(localPlayer) or getPedOccupiedVehicle(localPlayer) then return false end
    if uiOpen("ui_interactobject", "isInteractMenuOpen") or uiOpen("ui_inac", "isTempMenuOpen") then return false end
    for _, key in ipairs({ "showChatInput", "inventoryOpen", "textInputOpen", "paused", "socialPanelOpen", "animPanelOpen" }) do
        if getElementData(localPlayer, key) == true then return false end
    end
    return true
end

local render

local function finish(confirm)
    pressTick = nil
    removeEventHandler("onClientRender", root, render)
    if not isOpen then return end
    isOpen = false
    setCursorAlpha(255)
    showCursor(false)
    if confirm and sel > 0 and not isPedDead(localPlayer) then
        local a = slotAnim(sel)
        if a then Anims.play(a.id) end
    end
end

local function open()
    isOpen = true
    px, py, sel = 0, 0, 0
    showCursor(true, false) -- controls stay on, the visible cursor stops the camera
    setCursorAlpha(0)
    setCursorPosition(CX, CY)
end

addEventHandler("onClientKey", root, function(button, press)
    if button == KEY then
        if press and not pressTick and canUse() then
            pressTick = getTickCount()
            addEventHandler("onClientRender", root, render)
            cancelEvent()
        end
        return
    end
    if isOpen and (button == "mouse1" or button == "mouse2" or button == "mouse_wheel_up" or button == "mouse_wheel_down") then
        cancelEvent()
    end
end)

addEventHandler("onClientPlayerWasted", localPlayer, function() finish(false) end)
addEventHandler("onClientVehicleStartEnter", root, function(player) if player == localPlayer then finish(false) end end)
addEventHandler("onClientResourceStop", resourceRoot, function() finish(false) end)
addEventHandler("onClientMinimize", root, function() finish(false) end)

--------------------------------------------------------------------------------
-- frame
--------------------------------------------------------------------------------

local function updatePointer()
    local rx, ry = getCursorPosition()
    if rx then
        px, py = px + (rx * sx - CX), py + (ry * sy - CY)
        setCursorPosition(CX, CY)
    end
    local len = math.sqrt(px * px + py * py)
    if len > POINTER_MAX then
        px, py = px / len * POINTER_MAX, py / len * POINTER_MAX
        len = POINTER_MAX
    end
    if len > DEAD_ZONE then
        sel = indexOfAngle(math.deg(math.atan2(py, px)))
    else
        sel = 0
    end
end

local function drawWheel()
    updatePointer()
    local cur = Anims.current()
    local fTitle, fSub = font(15, true), font(12, false)
    local fName, fSmall = font(19, true), font(12, false)
    local midR = (R_OUT + R_IN) / 2
    local chord = 2 * midR * math.sin(math.rad(180 / SLOTS)) * 0.9

    for i = 1, SLOTS do
        local seg = segments[i]
        local a = slotAnim(i)
        local on = i == sel and a ~= nil
        drawPrimitive("trianglelist", seg.v, on and COLOR.segSel or (a and COLOR.seg or COLOR.segEmpty))
        local tx, ty = polar(seg.mid, midR)
        if a then
            local playing = cur and cur.id == a.id
            local title = L.fit(Anims.label(a), chord, 1, fTitle)
            local sub = L.fit(Anims.command(a), chord, 1, fSub)
            dxDrawText(title, tx - chord, ty - 26 * S, tx + chord, ty, on and COLOR.textSel or (playing and COLOR.playing or COLOR.text), 1, fTitle, "center", "bottom")
            dxDrawText(sub, tx - chord, ty + 2 * S, tx + chord, ty + 24 * S, on and COLOR.subSel or COLOR.textSub, 1, fSub, "center", "top")
        else
            dxDrawText(tostring(i), tx - chord, ty - 12 * S, tx + chord, ty + 12 * S, COLOR.textDim, 1, fTitle, "center", "center")
        end
    end

    drawPrimitive("trianglefan", centreDisc, COLOR.centre)
    local w = (R_IN - 16 * S) * 2
    local a = sel > 0 and slotAnim(sel) or nil
    local head, name, foot
    if a then
        head, name, foot = Anims.catLabel(a.cat), Anims.label(a), Anims.command(a)
    elseif #Anims.favs == 0 then
        head, name, foot = L("v_anims.title"), L("v_anims.wheel.no_favs"), L("v_anims.wheel.open_panel")
    elseif cur then
        head, name, foot = L("v_anims.wheel.playing"), Anims.label(cur), L("v_anims.wheel.tap_stop")
    else
        head, name, foot = L("v_anims.title"), L("v_anims.wheel.pick"), L("v_anims.wheel.tap_stop")
    end
    dxDrawText(L.fit(head, w, 1, fSmall), CX - w / 2, CY - 50 * S, CX + w / 2, CY - 26 * S, COLOR.textSub, 1, fSmall, "center", "bottom")
    dxDrawText(L.fit(name, w, 1, fName), CX - w / 2, CY - 24 * S, CX + w / 2, CY + 6 * S, COLOR.text, 1, fName, "center", "center")
    dxDrawText(L.fit(foot, w, 1, fSmall), CX - w / 2, CY + 8 * S, CX + w / 2, CY + 32 * S, COLOR.textSub, 1, fSmall, "center", "top")
end

render = function()
    if not pressTick then return end
    local held = getTickCount() - pressTick
    if not getKeyState(KEY) then
        if not isOpen and held < TAP_MS then
            finish(false)
            Anims.stop() -- tap = stop
        else
            finish(true)
        end
        return
    end
    if isPedDead(localPlayer) or getPedOccupiedVehicle(localPlayer) then finish(false) return end
    if not isOpen then
        if held < TAP_MS then return end
        open()
    end
    drawWheel()
end
