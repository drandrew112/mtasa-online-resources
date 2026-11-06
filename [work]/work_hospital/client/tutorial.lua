-- Hospital tutorial, client side: a DX card at the bottom of the screen with the step's text, a purple
-- marker and a 3D arrow at the next point; reaching it (or Enter on a text step) goes on.

local T = { on = false, i = 0, marker = nil }
local SX, SY = guiGetScreenSize()
local S = math.max(0.7, math.min(SY / 1080, 1.4))
local function s(v) return v * S end
local font, fontB

local function cfg() return HOSPW_TUTORIAL end
local function step() return cfg().steps[T.i] end

local function clearMarker()
    if isElement(T.marker) then destroyElement(T.marker) end
    T.marker = nil
end

local function enter(i)
    clearMarker()
    T.i = i
    local st = step()
    if not st then return end
    triggerServerEvent("hosp:tut:step", resourceRoot, i - 1)
    if st.pos then
        T.marker = createMarker(st.pos[1], st.pos[2], st.pos[3] - 0.05, "cylinder", 1.2, 160, 90, 230, 150)
        setElementInterior(T.marker, cfg().interior) setElementDimension(T.marker, cfg().dimension)
    end
    playSoundFrontEnd(11)
end

local function finish()
    clearMarker()
    T.on = false
    triggerServerEvent("hosp:tut:step", resourceRoot, #cfg().steps - 1)
    triggerServerEvent("hosp:tut:done", resourceRoot)
end

addEvent("hosp:tut:start", true)
addEventHandler("hosp:tut:start", resourceRoot, function()
    font, fontB = "default", "default-bold"
    T.on = true
    enter(1)
end)
addEvent("hosp:tut:stop", true)
addEventHandler("hosp:tut:stop", resourceRoot, function() T.on = false clearMarker() end)
addEvent("hosp:tut:granted", true)
addEventHandler("hosp:tut:granted", resourceRoot, function(ok)
    local res = getResourceFromName("ui_core")
    if res and getResourceState(res) == "running" then
        exports.ui_core:addNotification(L("work_hospital.tut.title"), L(ok and "work_hospital.tut.granted" or "work_hospital.tut.walk_done"), false)
    end
end)

addEventHandler("onClientRender", root, function()
    if not T.on then return end
    local st = step()
    if not st then return end
    -- reached the point?
    if st.pos then
        local x, y, z = getElementPosition(localPlayer)
        local d = getDistanceBetweenPoints3D(x, y, z, st.pos[1], st.pos[2], st.pos[3])
        if d <= cfg().range then
            if T.i >= #cfg().steps then finish() else enter(T.i + 1) end
            return
        end
        -- bouncing arrow above the point
        local bz = st.pos[3] + 1.6 + math.sin(getTickCount() / 250) * 0.15
        dxDrawLine3D(st.pos[1], st.pos[2], bz + 0.5, st.pos[1], st.pos[2], bz, tocolor(170, 110, 240, 230), 6)
        local sx, sy = getScreenFromWorldPosition(st.pos[1], st.pos[2], bz + 0.7)
        if sx then dxDrawText(("%.0f m"):format(d), sx - 50, sy - 20, sx + 50, sy, tocolor(255, 255, 255), 1.2 * S, font, "center", "bottom") end
    end
    -- the card
    local w, h = s(620), s(150)
    local x, y = (SX - w) / 2, SY - h - s(40)
    dxDrawRectangle(x, y, w, h, tocolor(16, 18, 22, 225))
    dxDrawRectangle(x, y, s(4), h, tocolor(160, 90, 230))
    dxDrawText(L("work_hospital.tut.step_n", { i = T.i, n = #cfg().steps }) .. "  ·  " .. L("work_hospital.tut." .. st.id .. "_title"),
        x + s(18), y + s(10), x + w - s(16), y + s(36), tocolor(235, 225, 250), 1.35 * S, fontB, "left", "center", true)
    dxDrawText(L("work_hospital.tut." .. st.id .. "_text"), x + s(18), y + s(40), x + w - s(16), y + h - s(30), tocolor(225, 230, 236), 1.2 * S, font, "left", "top", true, true)
    dxDrawText(st.pos and L("work_hospital.tut.walk_hint") or L("work_hospital.tut.enter_hint"), x + s(18), y + h - s(28), x + w - s(16), y + h - s(6),
        tocolor(150, 160, 175), 1.1 * S, font, "right", "center", true)
end)

addEventHandler("onClientKey", root, function(key, press)
    if not T.on or not press then return end
    if key ~= "enter" and key ~= "num_enter" then return end
    local st = step()
    if not st or st.pos then return end
    if isChatBoxInputActive() or isCursorShowing() then return end
    if T.i >= #cfg().steps then finish() else enter(T.i + 1) end
end)
