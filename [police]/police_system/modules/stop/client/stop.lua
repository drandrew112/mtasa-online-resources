-- police_system / modules/stop/client/stop.lua
-- The officer's side of a stop: hold E (0.8 s, a ring fills) on a pedestrian / player in front within 4 m (on foot),
-- left Shift in a police vehicle at the vehicle in front (25 m, +-12 deg; again = cancel). The ui_inac temp menu the
-- server builds (stop:menu) and its selection; the unit invite and "tow your police car?" confirmations.

local SC = POL.module("stopc", { hold = nil })
local C = POLICE.STOP

local function inac() return getResourceFromName("ui_inac") and getResourceState(getResourceFromName("ui_inac")) == "running" and exports.ui_inac end

-- the ped / player in front of the officer
local function personInFront()
    local x, y, z = getElementPosition(localPlayer)
    local _, _, rz = getElementRotation(localPlayer)
    local fx, fy = -math.sin(math.rad(rz)), math.cos(math.rad(rz))
    local best, bd
    for _, t in ipairs({ "ped", "player" }) do
        for _, e in ipairs(getElementsWithinRange(x, y, z, C.PED_RANGE, t, getElementInterior(localPlayer), getElementDimension(localPlayer))) do
            if e ~= localPlayer and not isPedDead(e) and not getPedOccupiedVehicle(e) and isElementStreamedIn(e) then
                local ex, ey = getElementPosition(e)
                local dx, dy = ex - x, ey - y
                local d = math.sqrt(dx * dx + dy * dy)
                if d > 0.1 and (dx * fx + dy * fy) / d > 0.5 and (not bd or d < bd) then best, bd = e, d end
            end
        end
    end
    return best
end

-- the vehicle in front of the police vehicle: ahead within VEH_RANGE and inside a corridor that widens with the
-- distance (a lane and a half close up, the VEH_CONE angle far away), so the car just ahead in the next lane counts
-- too. Vehicles with a driver first; the nearest and most central wins.
function SC.vehicleInFront()
    local pv = getPedOccupiedVehicle(localPlayer)
    if not pv then return nil end
    local px, py, pz = getElementPosition(pv)
    local m = getElementMatrix(pv)
    local fx, fy = m[2][1], m[2][2]
    local fl = math.sqrt(fx * fx + fy * fy)
    if fl < 0.1 then return nil end
    fx, fy = fx / fl, fy / fl
    local tanCone = math.tan(math.rad(C.VEH_CONE))
    local best, bestScore
    for _, v in ipairs(getElementsWithinRange(px, py, pz, C.VEH_RANGE + 5, "vehicle")) do
        if v ~= pv and isElementStreamedIn(v) then
            local vx, vy, vz = getElementPosition(v)
            local dx, dy = vx - px, vy - py
            local along = dx * fx + dy * fy
            local side = math.abs(dx * fy - dy * fx)
            if along > 2 and along <= C.VEH_RANGE and side <= 3.5 + along * tanCone and math.abs(vz - pz) < 6 then
                local score = along + side * 3 + (getVehicleController(v) and 0 or 100)
                if not bestScore or score < bestScore then best, bestScore = v, score end
            end
        end
    end
    return best
end

-- F4 / STATUS_PURSUIT target: the stopped element of the unit, else the vehicle in front
function SC.pursuitTarget()
    for _, t in ipairs({ "vehicle", "ped", "player" }) do
        for _, e in ipairs(getElementsByType(t, root, true)) do
            if POL.unit and getElementData(e, "pol.stop") == POL.unit.callsign then return e end
        end
    end
    return SC.vehicleInFront()
end

------------------------------------------------------------------------ hold E

local function drawHold()
    local h = SC.hold
    if not h then return end
    if not isElement(h.target) then SC.hold = nil; POL.layers.set("stophold", false) return end
    local p = math.min(1, (getTickCount() - h.at) / C.HOLD)
    local x, y, z = getElementPosition(h.target)
    local sx, sy = getScreenFromWorldPosition(x, y, z + 1.1)
    if sx then
        local r = POL.px(22)
        dxDrawCircle(sx, sy, r, 0, 360, POL.colors.bg, POL.colors.bg, 24)
        dxDrawCircle(sx, sy, r, -90, -90 + 360 * p, POL.colors.accent, POL.colors.accent, 24)
        dxDrawCircle(sx, sy, r - POL.px(5), 0, 360, POL.colors.bg, POL.colors.bg, 24)
        dxDrawText("E", sx - r, sy - r, sx + r, sy + r, POL.colors.white, 1, POL.font(11, true), "center", "center")
    end
    if p >= 1 then
        POL.send("stop:ped", h.target)
        SC.hold = nil
        POL.layers.set("stophold", false)
    end
end
POL.layers.add("stophold", drawHold, 20)

POL.key("stop", function(button, press)
    if not POL.onDuty() or not POL.hasRight() then return false end
    if button == "e" then
        if not press then
            if SC.hold then SC.hold = nil; POL.layers.set("stophold", false); return true end
            return false
        end
        if getPedOccupiedVehicle(localPlayer) then return false end
        local t = personInFront()
        if not t then return false end
        SC.hold = { target = t, at = getTickCount() }
        POL.layers.set("stophold", true)
        return true
    elseif button == "lshift" and press then
        local pv = POL.inPoliceVehicle()
        if not pv or getVehicleController(pv) ~= localPlayer then return false end
        local v = SC.vehicleInFront()
        if not v then return false end
        POL.send("stop:vehicle", v)
        return true
    end
    return false
end, 30)

------------------------------------------------------------------------ temp menus

local menuTarget, menuKind

POL.handle("stop:menu", function(target, title, items)
    local m = inac()
    if not m then return end
    menuTarget, menuKind = target, "stop"
    -- the interact menu may still be closing: close it and retry a few times while ui_inac refuses
    if getResourceState(getResourceFromName("ui_interactobject") or getThisResource()) == "running" then
        pcall(function() exports.ui_interactobject:closeInteractMenu() end)
    end
    local tries = 0
    local function open()
        tries = tries + 1
        if menuKind ~= "stop" or menuTarget ~= target or not isElement(target) then return end
        if not m:createTempMenu({ title = title, items = items }) and tries < 8 then setTimer(open, 120, 1) end
    end
    open()
end)

POL.handle("unit:invite", function(leaderName, callsign)
    local m = inac()
    if not m then return end
    menuKind = "invite"
    m:createTempMenu({ title = L("police_system.units.invite_title", { callsign = callsign, name = leaderName }), items = {
        { label = L("police_system.units.accept"), value = "accept" },
        { label = L("police_system.units.decline"), value = "decline" },
    } })
end)

POL.handle("tow:confirm", function(veh)
    local m = inac()
    if not m then return end
    menuTarget, menuKind = veh, "tow"
    m:createTempMenu({ title = L("police_system.tow.confirm_title"), items = {
        { label = L("police_system.tow.confirm_yes"), value = "yes" },
        { label = L("police_system.tow.confirm_no"), value = "no" },
    } })
end)

addEvent("ui_inac:tempMenuSelect")
addEventHandler("ui_inac:tempMenuSelect", localPlayer, function(rootId, value)
    if menuKind == "stop" and isElement(menuTarget) and type(value) == "string" then
        POL.send("stop:action", menuTarget, value)
    elseif menuKind == "invite" then
        POL.send("unit:answer", value == "accept")
        menuKind = nil
    elseif menuKind == "tow" then
        if value == "yes" and isElement(menuTarget) then POL.send("tow:confirm", menuTarget) end
        menuKind = nil
    end
end)

addEvent("ui_inac:tempMenuClose")
addEventHandler("ui_inac:tempMenuClose", localPlayer, function()
    if menuKind == "invite" then POL.send("unit:answer", false) end
    menuKind, menuTarget = nil, nil
end)
