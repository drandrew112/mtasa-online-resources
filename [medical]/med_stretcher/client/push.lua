-- Pushing the stretcher. The pusher walks with GTA's own on-foot movement (forced to walk speed),
-- which MTA syncs natively; the stretcher is attached in front of them. A looped walk animation via
-- setPedAnimation cannot be used: its root motion is drawn forward and snaps back on every loop.
-- While a pusher stands still, every client plays PUSH_IDLE_ANIM (arms forward) on them locally
-- and drops it as soon as they move again.

local D = STRETCHER_DATA

local pushers = {}     -- ped -> { anim, x, y, tick, moving }
local local_ = nil     -- { keys, lockedControls, stillSince } while the local player pushes

local IDLE_DELAY = 150 -- ms standing still before the idle pose comes back
local MOVE_CONTROLS = { "forwards", "backwards", "left", "right" }

-- ---------------------------------------------------------------------------------------------
-- Local player
-- ---------------------------------------------------------------------------------------------

local function readBoundKeys()
    local keys = {}
    for _, control in ipairs(MOVE_CONTROLS) do
        for key in pairs(getBoundKeys(control) or {}) do keys[#keys + 1] = key end
    end
    return keys
end

-- Is a movement key held? Read from the keys, because the idle pose makes GTA ignore the controls.
local function wantsToMove()
    if isChatBoxInputActive() or isConsoleActive() or isMainMenuActive() then return false end
    for _, key in ipairs(local_.keys) do
        if getKeyState(key) then return true end
    end
    return false
end

local function startLocal()
    if local_ then return end
    local_ = { keys = readBoundKeys(), lockedControls = {}, stillSince = getTickCount() }
    for _, control in ipairs(STRETCHER.PUSH_LOCKED_CONTROLS) do
        if isControlEnabled(control) then
            toggleControl(control, false)
            local_.lockedControls[#local_.lockedControls + 1] = control
        end
    end
end

local function stopLocal()
    if not local_ then return end
    for _, control in ipairs(local_.lockedControls) do toggleControl(control, true) end
    setPedControlState(localPlayer, "walk", false)
    local_ = nil
end

-- ---------------------------------------------------------------------------------------------
-- Idle pose (every client, every pusher)
-- ---------------------------------------------------------------------------------------------

local function isMoving(ped, p)
    local now = getTickCount()
    if ped == localPlayer then
        if wantsToMove() then
            local_.stillSince = nil
            return true
        end
        local_.stillSince = local_.stillSince or now
        return now - local_.stillSince < IDLE_DELAY
    end
    if now - p.tick >= IDLE_DELAY then
        local x, y = getElementPosition(ped)
        p.moving = getDistanceBetweenPoints2D(x, y, p.x, p.y) > 0.05
        p.x, p.y, p.tick = x, y, now
    end
    return p.moving
end

local function updatePushers()
    for ped, p in pairs(pushers) do
        if not isElement(ped) then
            pushers[ped] = nil
        elseif isElementStreamedIn(ped) and not isPedDead(ped) then
            if ped == localPlayer then setPedControlState(localPlayer, "walk", true) end
            local moving = isMoving(ped, p)
            if moving and p.anim then
                p.anim = false
                setPedAnimation(ped)            -- hand the ped back to GTA's walking
            elseif not moving and not p.anim then
                p.anim = true
                local a = STRETCHER.PUSH_IDLE_ANIM
                setPedAnimation(ped, a[1], a[2], -1, true, false, false, false)
            end
        end
    end
end

-- ---------------------------------------------------------------------------------------------
-- Pusher bookkeeping
-- ---------------------------------------------------------------------------------------------

local function setPusher(ped, stretcher)
    if isElement(stretcher) then
        if not pushers[ped] then
            local x, y = getElementPosition(ped)
            pushers[ped] = { anim = false, x = x, y = y, tick = getTickCount(), moving = false }
        end
        if ped == localPlayer then startLocal() end
    elseif pushers[ped] then
        local hadAnim = pushers[ped].anim
        pushers[ped] = nil
        if hadAnim and isElement(ped) and not isPedDead(ped) then setPedAnimation(ped) end
        if ped == localPlayer then stopLocal() end
    end
end

addEventHandler("onClientElementDataChange", root, function(key)
    if key == D.PUSHING then setPusher(source, getElementData(source, D.PUSHING)) end
end)

-- a pusher streaming back in gets the pose again
addEventHandler("onClientElementStreamIn", root, function()
    if pushers[source] then pushers[source].anim = false end
end)

addEventHandler("onClientPlayerQuit", root, function()
    pushers[source] = nil
end)

addEventHandler("onClientPreRender", root, function()
    if next(pushers) then updatePushers() end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do
        local stretcher = getElementData(player, D.PUSHING)
        if stretcher then setPusher(player, stretcher) end
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    stopLocal()
end)
