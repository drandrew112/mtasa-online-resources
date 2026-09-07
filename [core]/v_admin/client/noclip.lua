-- ============================================================
--  v_admin / client/noclip.lua
--  NoClip ("fly") mode.  Original base: noclip by chris1384.
--  Toggle: /fly command (server checks permission) or N key.
-- ============================================================

local speed     = { horizontal = 3, vertical = 1 }
local activated = false
local pos       = { 0, 0, 0 }

local setNoclip   -- forward declaration (defined below, after the render function)

local function info(text)
    exports.ui_core:setAlert(text)
end

-- ------------------------------------------------------------
--  Render: move the player along the camera direction
-- ------------------------------------------------------------
local function noclipRender()
    if isPedDead(localPlayer) or getCameraTarget() ~= localPlayer or getPedOccupiedVehicle(localPlayer) then
        setNoclip(false)
        info("#FF6464NoClip force-disabled!")
        return
    end

    local _, _, camZ = getElementRotation(getCamera())

    if not isMTAWindowActive() and not isCursorShowing() then
        local vertical =
            (getKeyState("space")  and pos[3] + speed.vertical) or
            (getKeyState("lshift") and pos[3] - speed.vertical) or
            pos[3]

        if getKeyState("w") then
            local ang = (getKeyState("d") and 45 - camZ) or (getKeyState("a") and -45 - camZ) or -camZ
            setElementPosition(localPlayer,
                pos[1] + math.sin(math.rad(ang)) * speed.horizontal,
                pos[2] + math.cos(math.rad(ang)) * speed.horizontal, vertical)
        elseif getKeyState("s") then
            local ang = (getKeyState("d") and -45 - camZ) or (getKeyState("a") and 45 - camZ) or -camZ
            setElementPosition(localPlayer,
                pos[1] - math.sin(math.rad(ang)) * speed.horizontal,
                pos[2] - math.cos(math.rad(ang)) * speed.horizontal, vertical)
        elseif getKeyState("d") then
            setElementPosition(localPlayer,
                pos[1] + math.sin(math.rad(90 - camZ)) * speed.horizontal,
                pos[2] + math.cos(math.rad(90 - camZ)) * speed.horizontal, vertical)
        elseif getKeyState("a") then
            setElementPosition(localPlayer,
                pos[1] - math.sin(math.rad(90 - camZ)) * speed.horizontal,
                pos[2] - math.cos(math.rad(90 - camZ)) * speed.horizontal, vertical)
        else
            setElementPosition(localPlayer, pos[1], pos[2], vertical)
        end
    else
        setElementPosition(localPlayer, pos[1], pos[2], pos[3])
    end

    setElementRotation(localPlayer, 0, 0, -camZ)
    pos = { getElementPosition(localPlayer) }
end

-- ------------------------------------------------------------
--  Actually toggle NoClip on/off (physics in one place).
--  setElementPosition alone is not enough: without freezing,
--  gravity + collision drag the ped back, so there is no flight.
-- ------------------------------------------------------------
function setNoclip(state)
    if state then
        if activated then return end
        if isPedDead(localPlayer) or getPedOccupiedVehicle(localPlayer) then return end
        activated = true
        pos = { getElementPosition(localPlayer) }
        setElementVelocity(localPlayer, 0, 0, 0)
        setElementFrozen(localPlayer, true)
        setElementCollisionsEnabled(localPlayer, false)
        addEventHandler("onClientPreRender", root, noclipRender)
    else
        if not activated then return end
        activated = false
        removeEventHandler("onClientPreRender", root, noclipRender)
        setElementCollisionsEnabled(localPlayer, true)
        setElementFrozen(localPlayer, false)
    end
end

-- ------------------------------------------------------------
--  Toggle on/off
-- ------------------------------------------------------------
local function toggleNoclip()
    if activated then
        setNoclip(false)
        info("#FFFFFFNoClip: #FF6464OFF")
    else
        setNoclip(true)
        if activated then
            info("#FFFFFFNoClip: #55FF55ON")
        end
    end
end

-- /fly: the server checks the permission, then tells us to toggle.
addEvent(ADMIN.events.toggleNoclip, true)
addEventHandler(ADMIN.events.toggleNoclip, localPlayer, toggleNoclip)

-- When the resource stops, don't leave the player frozen / collision-less
addEventHandler("onClientResourceStop", resourceRoot, function()
    if activated then setNoclip(false) end
end)

-- N key -> toggle directly (admin level is synced onto the player element
-- by the server, so no client<->server round-trip is needed here).
bindKey("n", "down", function()
    local level = tonumber(getElementData(localPlayer, "admin_level")) or 0
    if level < ADMIN.perms.noclip then return end
    toggleNoclip()
end)

-- ------------------------------------------------------------
--  /flyspd <number>  – noclip speed (0.1 - 20)
-- ------------------------------------------------------------
addCommandHandler("flyspd", function(cmd, x)
    local n = tonumber(x)
    if not n then
        return info("#FF6464NoClip speed must be a number!")
    end
    if n < 0.1 or n > 20 then
        return info("#FF6464NoClip speed must be between 0.1 and 20!")
    end
    speed = { horizontal = n, vertical = n / 3 }
    info("#FFFFFFNoClip speed: #55FF55" .. n)
end)
