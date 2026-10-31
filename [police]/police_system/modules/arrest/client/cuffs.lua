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

local function pose()
    for el in pairs(CF.list) do
        if isElement(el) and isElementStreamedIn(el) and not isPedDead(el) and not getPedOccupiedVehicle(el) then
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

addEventHandler("onClientElementDataChange", root, function(key) if key == "pol.cuffed" then track(source) end end)
addEventHandler("onClientElementStreamIn", root, function() track(source) end)
addEventHandler("onClientElementStreamOut", root, function() if CF.list[source] then CF.list[source] = nil; refresh() end end)
addEventHandler("onClientElementDestroy", root, function() if CF.list[source] then CF.list[source] = nil; refresh() end end)

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
