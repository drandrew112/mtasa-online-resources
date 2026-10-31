-- police_system / modules/arrest/client/cuffs.lua
-- Cuffed peds and players (pol.cuffed, broadcast): hands behind the back (setElementBoneRotation in
-- onClientPedsProcessed, attached only while a cuffed element is streamed in), a cuff icon above the head of the
-- peds (players: v_nametags draws it next to the name). The officer's cuffing progress bar; "Busted" (AI arrest).

local CF = POL.module("cuffs", { list = {} })   -- [element] = true (streamed in and cuffed)
local IMG = "client/img/cuffs.png"
local attached = false

-- upper arms back, forearms crossed behind the back (bone ids: 22/23/24 right, 32/33/34 left)
-- BONES[bone] = { yaw, pitch, roll }; /cufftune <bone> <yaw> <pitch> <roll> changes one live (prints the table)
local BONES = {
    [22] = { 0, 30, -60 }, [23] = { 0, 60, 20 }, [24] = { 60, 0, 0 },
    [32] = { 0, 30, 60 }, [33] = { 0, 60, -20 }, [34] = { -60, 0, 0 },
}

addCommandHandler("cufftune", function(_, bone, y, p, r)
    bone = tonumber(bone)
    if bone and BONES[bone] and tonumber(y) and tonumber(p) and tonumber(r) then BONES[bone] = { tonumber(y), tonumber(p), tonumber(r) } end
    for b, v in pairs(BONES) do outputDebugString(("cuff bone %d = %d, %d, %d"):format(b, v[1], v[2], v[3])) end
end)

-- escorted (pol.escort = the officer): walk anim while the officer walks, by its smooth local speed with a
-- hysteresis and a minimum hold, so the anim is not restarted on every speed wobble
local WALK_ON, WALK_OFF, WALK_HOLD = 0.9, 0.4, 400   -- m/s, m/s, ms
CF.walk = {}   -- [element] = { on, at }

local function escortAnim(el, now)
    local o = getElementData(el, "pol.escort")
    local w = CF.walk[el]
    if not isElement(o) then
        if w then
            CF.walk[el] = nil
            if w.on then setPedAnimation(el) end
        end
        return
    end
    if not w then w = { on = false, at = 0 }; CF.walk[el] = w end
    -- an attached ped keeps its own heading (MTA moves it with the officer, never turns it): the officer's, every frame
    local _, _, rz = getElementRotation(o)
    setElementRotation(el, 0, 0, rz, "default", true)
    local vx, vy = getElementVelocity(o)
    local speed = math.sqrt(vx * vx + vy * vy) * 50
    local want = w.on and speed > WALK_OFF or (not w.on and speed > WALK_ON)
    if want ~= w.on and now - w.at >= WALK_HOLD then
        w.on, w.at = want, now
        -- updatePosition: the anim's root motion goes into the movement (the attach pins it back in front of the
        -- officer); without it the body slides forward over the loop and snaps back
        if want then setPedAnimation(el, "ped", "WALK_player", -1, true, true, false, false)
        else setPedAnimation(el) end
    end
end

local function pose()
    local now = getTickCount()
    for el in pairs(CF.list) do
        if isElement(el) and isElementStreamedIn(el) and not isPedDead(el) and not getPedOccupiedVehicle(el) then
            escortAnim(el, now)
            for b, v in pairs(BONES) do setElementBoneRotation(el, b, v[1], v[2], v[3]) end
            updateElementRpHAnim(el)
        end
    end
end

local function drawIcons()
    local s = POL.px(22)
    for el in pairs(CF.list) do
        if isElement(el) and getElementType(el) == "ped" and isElementOnScreen(el) then
            local x, y, z = getPedBonePosition(el, 8)
            local sx, sy = getScreenFromWorldPosition(x, y, z + 0.35)
            if sx then dxDrawImage(sx - s / 2, sy - s / 2, s, s, IMG) end
        end
    end
end
POL.layers.add("cuffs", drawIcons, 2)

local function refresh()
    local any = next(CF.list) ~= nil
    if any and not attached then
        attached = true
        addEventHandler("onClientPedsProcessed", root, pose)
    elseif not any and attached then
        attached = false
        removeEventHandler("onClientPedsProcessed", root, pose)
    end
    local peds = false
    for el in pairs(CF.list) do if isElement(el) and getElementType(el) == "ped" then peds = true break end end
    POL.layers.set("cuffs", peds)
end

local function track(el)
    local t = getElementType(el)
    if (t ~= "ped" and t ~= "player") then return end
    if getElementData(el, "pol.cuffed") == true and isElementStreamedIn(el) then CF.list[el] = true else CF.list[el] = nil end
    refresh()
end

addEventHandler("onClientElementDataChange", root, function(key)
    if key == "pol.cuffed" then
        track(source)
    elseif key == "pol.escort" and CF.walk[source] and not isElement(getElementData(source, "pol.escort")) then
        -- escort over: the walk anim off now (also when the pose loop is not running for it any more)
        if CF.walk[source].on then setPedAnimation(source) end
        CF.walk[source] = nil
    end
end)
addEventHandler("onClientElementStreamIn", root, function() track(source) end)
addEventHandler("onClientElementStreamOut", root, function() CF.walk[source] = nil; if CF.list[source] then CF.list[source] = nil; refresh() end end)
addEventHandler("onClientElementDestroy", root, function() CF.walk[source] = nil; if CF.list[source] then CF.list[source] = nil; refresh() end end)

function CF.start()
    for _, t in ipairs({ "ped", "player" }) do
        for _, e in ipairs(getElementsByType(t, root, true)) do track(e) end
    end
end

------------------------------------------------------------------------ cuffing progress, Busted

local prog
local function drawProgress()
    if not prog then return end
    local p = (getTickCount() - prog.at) / prog.ms
    if p >= 1 or not isElement(prog.target) then prog = nil; POL.layers.set("cuffprog", false) return end
    local w, h = POL.px(220), POL.px(10)
    local x, y = (POL.sw - w) / 2, POL.sh * 0.78
    dxDrawRectangle(x, y, w, h, POL.colors.bg)
    dxDrawRectangle(x, y, w * p, h, POL.colors.accent)
    dxDrawText(L("police_system.arrest.cuffing"), x, y - POL.px(24), x + w, y, POL.colors.white, 1, POL.font(10, true), "center", "bottom")
end
POL.layers.add("cuffprog", drawProgress, 30)

POL.handle("arrest:progress", function(target, ms)
    prog = { target = target, at = getTickCount(), ms = ms }
    POL.layers.set("cuffprog", true)
end)

local busted
local function drawBusted()
    if not busted then return end
    local t = getTickCount() - busted
    if t > 3200 then busted = nil; POL.layers.set("busted", false); fadeCamera(true, 1) return end
    local a = math.min(255, t / 4)
    dxDrawText(L.upper(L("police_system.arrest.busted")), 0, 0, POL.sw, POL.sh, tocolor(220, 220, 255, a), 1,
        POL.font(48, true), "center", "center")
end
POL.layers.add("busted", drawBusted, 90)

POL.handle("arrest:busted", function()
    busted = getTickCount()
    fadeCamera(false, 2.0)
    POL.layers.set("busted", true)
end)
