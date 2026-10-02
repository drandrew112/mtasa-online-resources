-- Plays the modules the server sent, scene by scene. There is no skip: Continue
-- (INTRO.CONTINUE_KEY) works only when the scene's minimum time has passed, its tasks are done
-- and no panel is open. Every finished module is reported to the server right away.

local R = {
    active = false,
    modules = nil, mIndex = 0, sIndex = 0,
    module = nil, scene = nil, handler = nil,
    sceneStart = 0, minTime = 0,
    keyTicks = {},
    transition = false, waiting = false,
    toast = nil,
}

local function handlerOf(scene) return Scenes[scene.type] end

local function stepLabel()
    local total = #R.modules
    local prefix = R.mode == "new" and "What's new  ·  " or ""
    local title = R.module.update and ("Update: " .. R.module.title) or R.module.title
    return ("%sChapter %d / %d  ·  %s"):format(prefix, R.mIndex, total, title)
end

-- nextScene: the scene that follows in the same module (keeps the practice vehicle if it needs it)
local function stopScene(nextScene)
    local h = R.handler
    if h and h.stop then h.stop(R.scene, R) end
    Scenes.cameraStop(R.scene, nextScene)
    R.scene, R.handler = nil, nil
end

local function wantsHud(scene, handler)
    if scene.hud ~= nil then return scene.hud end
    return handler.hud == true
end

local startModule -- forward

local function startScene(j)
    local scene = R.module.scenes[j]
    stopScene(scene)
    R.sIndex = j
    R.scene, R.handler = scene, handlerOf(scene)
    R.sceneStart = getTickCount()
    R.minTime = INTRO.sceneMinTime(scene)
    R.stepLabel = stepLabel()
    Lock.setHud(wantsHud(scene, R.handler))
    if R.handler.start then R.handler.start(scene, R) end
end

local function finishAll()
    stopScene()
    R.waiting = true
    fadeCamera(false, 0.5)
    triggerServerEvent("intro:finished", resourceRoot)
end

local function nextModule()
    triggerServerEvent("intro:moduleDone", resourceRoot, R.module.id)
    if R.mIndex >= #R.modules then return finishAll() end
    stopScene()
    R.transition = true
    fadeCamera(false, 0.4)
    setTimer(function()
        if not R.active then return end
        R.transition = false
        startModule(R.mIndex + 1)
        fadeCamera(true, 0.4)
    end, 450, 1)
end

local function nextScene()
    if R.sIndex < #R.module.scenes then
        startScene(R.sIndex + 1)
    else
        nextModule()
    end
end

function startModule(i)
    R.mIndex = i
    R.module = R.modules[i]
    if not R.module or #R.module.scenes == 0 then
        -- every scene was left out (missing resources): nothing to show, it still counts
        if R.module then return nextModule() end
        return finishAll()
    end
    startScene(1)
end

---------------------------------------------------------------- continue

-- -> ready, state for Draw.continue
local function continueState()
    local h, sc = R.handler, R.scene
    if h.complete and not h.complete(sc, R) then
        return false, { message = h.message and h.message(sc, R) or "Complete the task to continue" }
    end
    local panel = Lock.openPanel()
    if panel then return false, { message = "Close the " .. panel .. " to continue" } end
    local passed = (getTickCount() - R.sceneStart) / 1000
    if passed < R.minTime then
        return false, { ready = false, remaining = R.minTime - passed, fraction = passed / R.minTime }
    end
    return true, { ready = true }
end

local function onContinue()
    if not R.active or R.transition or R.waiting or not R.scene then return end
    if R.handler.autoNext then return end
    local ready = continueState()
    if ready then
        playSoundFrontEnd(41)
        nextScene()
    end
end

local function onKey(key, press)
    if press and R.active then R.keyTicks[key:lower()] = getTickCount() end
end

---------------------------------------------------------------- render

local function render()
    if not R.active or R.waiting or R.transition or not R.scene then return end
    local sc, h = R.scene, R.handler

    -- the pause menu and the bigmap switch the HUD themselves; in the other scenes keep ours
    if not Lock.openPanel() then
        local want = not wantsHud(sc, h)
        if (getElementData(localPlayer, "hideHUD") and true or false) ~= want then Lock.setHud(not want) end
    end

    if h.letterbox then Draw.letterbox() end
    if h.render then h.render(sc, R) end
    Draw.progress(R.mIndex, #R.modules, R.stepLabel)

    local ready, state = continueState()
    if h.autoNext then
        if ready then
            playSoundFrontEnd(41)
            return nextScene()
        end
        if state.message then Draw.continue(state) end
    else
        Draw.continue(state)
    end

    if R.toast then
        local age = (getTickCount() - R.toast.tick) / 1000
        if age > 3.5 then
            R.toast = nil
        else
            Draw.toast(R.toast.text, math.min(1, (3.5 - age) / 0.5, age / 0.2))
        end
    end
end

---------------------------------------------------------------- start / stop

local function stopAll()
    if not R.active then return end
    stopScene()
    R.active, R.waiting, R.transition = false, false, false
    removeEventHandler("onClientRender", root, render)
    removeEventHandler("onClientKey", root, onKey)
    unbindKey(INTRO.CONTINUE_KEY, "down", onContinue)
    Mirror.clear()
    Mirror.dimension = nil
    Lock.disable()
    setCameraTarget(localPlayer)
end

addEvent("intro:start", true)
addEventHandler("intro:start", resourceRoot, function(payload)
    stopAll()
    R.active = true
    R.mode = payload.mode
    R.modules = payload.modules or {}
    R.keyTicks = {}
    R.waiting, R.transition, R.toast = false, false, nil
    Mirror.dimension = payload.dimension
    Lock.enable()
    addEventHandler("onClientRender", root, render)
    addEventHandler("onClientKey", root, onKey)
    bindKey(INTRO.CONTINUE_KEY, "down", onContinue)
    startModule(1)
    fadeCamera(true, INTRO.FADE_TIME)
end)

addEvent("intro:stop", true)
addEventHandler("intro:stop", resourceRoot, function()
    stopAll()
end)

addEvent("intro:reward", true)
addEventHandler("intro:reward", resourceRoot, function(_, xp)
    R.toast = { text = ("+%d XP"):format(xp), tick = getTickCount() }
end)

---------------------------------------------------------------- exports

function isIntroActive() return R.active end

function getIntroAllow()
    return getElementData(localPlayer, "intro.allow")
end

---------------------------------------------------------------- /introcam (admin helper)

-- prints the current camera matrix as a module camera entry
addCommandHandler("introcam", function()
    if (tonumber(getElementData(localPlayer, "admin_level")) or 0) < INTRO.ADMIN_LEVEL then return end
    local x, y, z, lx, ly, lz = getCameraMatrix()
    local line = ("{ %.1f, %.1f, %.1f, %.1f, %.1f, %.1f }"):format(x, y, z, lx, ly, lz)
    outputChatBox("[Intro] camera: " .. line)
    setClipboard(line)
end)
