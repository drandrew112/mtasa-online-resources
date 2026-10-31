-- police_system / modules/wanted/client/stars.lua
-- The wanted player's side: the stars blink in the evasion phase (ui_core setWantedBlinking; the stars themselves are
-- ui_core's, GTA's level), "Hold E to surrender" while a unit is close and the player stands, and the reports of the
-- player's own acts against the police: ramming a police car, damaging one, shots (1 / s, the server checks whether
-- police were near).

local WC = POL.module("wantedc", { level = 0, phase = "active", offer = false })
local C = POLICE.WANTED

local function ui() return getResourceFromName("ui_core") and getResourceState(getResourceFromName("ui_core")) == "running" and exports.ui_core end

POL.handle("wanted:state", function(level, phase)
    WC.level, WC.phase = level or 0, phase or "active"
    local u = ui()
    if u then u:setWantedBlinking(WC.level > 0 and WC.phase == "evading", C.BLINK_PERIOD) end
end)

------------------------------------------------------------------------ surrender (hold E)

local hold = { at = nil }
local PROMPT = "police_system.wanted.hold_e_surrender"

local function drawSurrender()
    local sw, sh = POL.sw, POL.sh
    local text = L(PROMPT)
    local f = POL.font(13, true)
    local w = dxGetTextWidth(text, 1, f) + POL.px(40)
    local h = POL.px(46)
    local x, y = (sw - w) / 2, sh * 0.72
    dxDrawRectangle(x, y, w, h, POL.colors.bg)
    dxDrawText(text, x, y, x + w, y + h - POL.px(6), POL.colors.text, 1, f, "center", "center")
    if hold.at then
        local p = math.min(1, (getTickCount() - hold.at) / C.SURRENDER_HOLD)
        dxDrawRectangle(x, y + h - POL.px(5), w * p, POL.px(5), POL.colors.yellow)
        if p >= 1 then
            hold.at = nil
            POL.send("wanted:surrender")
        end
    end
end
POL.layers.add("surrender", drawSurrender, 40)

POL.handle("wanted:surrender", function(offer)
    WC.offer = offer and true or false
    if not WC.offer then hold.at = nil end
    POL.layers.set("surrender", WC.offer)
end)

POL.key("surrender", function(button, press)
    if not WC.offer or button ~= "e" then return false end
    hold.at = press and getTickCount() or nil
    return true
end, 60)

------------------------------------------------------------------------ reports of acts against the police

local function isPoliceVeh(veh)
    if not isElement(veh) or getElementType(veh) ~= "vehicle" then return false end
    return getElementData(veh, "pol.ai") == true or isPoliceModelVehicle(veh)
end

local lastRam, lastShot, lastDmg = 0, 0, 0

addEventHandler("onClientVehicleCollision", root, function(hit, force)
    if force < C.RAM_FORCE or getVehicleController(source) ~= localPlayer or not isPoliceVeh(hit) then return end
    local now = getTickCount()
    if now - lastRam < 3000 then return end
    lastRam = now
    POL.send("wanted:ram", hit)
end)

addEventHandler("onClientVehicleDamage", root, function(attacker)
    if not isPoliceVeh(source) then return end
    local mine = attacker == localPlayer or (isElement(attacker) and getElementType(attacker) == "vehicle" and getVehicleController(attacker) == localPlayer)
    if not mine or getVehicleController(source) == localPlayer then return end
    local now = getTickCount()
    if now - lastDmg < 1000 then return end
    lastDmg = now
    POL.send("wanted:vehdmg", source)
end)

addEventHandler("onClientPlayerWeaponFire", localPlayer, function(weapon, _, _, hx, hy, hz)
    if not weapon or weapon < 22 or weapon > 38 or POL.onDuty() then return end
    local now = getTickCount()
    if now - lastShot < 1000 then return end
    lastShot = now
    POL.send("wanted:shot", hx, hy, hz)
end)
