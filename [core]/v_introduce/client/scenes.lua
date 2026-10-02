-- Scene types. Every scene is plain data from a module (server/registry.lua). Common fields:
--   type, title, text, hud (show the HUD; default: false for camera/world, true otherwise),
--   requires (left out by the server when a resource is not running), duration (seconds)
--
--   camera     camera = { from = { x, y, z, lx, ly, lz }, to = { ... } }  (to: optional ride)
--              bigTitle = { "small line", "BIG LINE" }  - the subtitle shows `text`
--   card       the card on the left
--   task       card with tasks the player must do. allow = { panelId, ... } may open meanwhile.
--              tasks = { { text, check = { data = "phoneOpen", equals = true } },
--                        { text, check = { key = "y" } },
--                        { text, check = { phoneApp = "myveh" } },
--                        { text, check = { vehicleData = "headlights:on", changed = true } } }
--
-- camera of every scene: a table as above, "vehicle" (looks at the practice vehicle from
-- INTRO.VEHICLE.camera) or nothing (the fixed INTRO.BACKDROP). The player is never shown.
-- vehicle = true: the player sits in the practice vehicle (INTRO.VEHICLE) during the scene.
--   highlight  darkens the screen except a rectangle: target = "minimap" | rect = { x, y, w, h }
--              (screen fractions). title + text are shown next to it.
--   world      camera + a ring and label on a place: point = { x, y, z }, label, radius,
--              blip = radar icon id (v_radar image), mapText
--   accept     the rules (client/rules.lua)
--
-- Handler: start(sc, R), render(sc, R), stop(sc, R), complete(sc, R) -> bool,
--          message(sc, R) -> text shown instead of Continue while not complete

Scenes = {}

-- {key:phone} -> "B"
function Scenes.resolve(str)
    if not str then return nil end
    return (str:gsub("{key:([%w_]+)}", function(name) return INTRO.KEYS[name] or name end))
end

---------------------------------------------------------------- camera helpers

local function smooth(t) return t * t * (3 - 2 * t) end

local function cameraAt(cam, elapsed, duration)
    if not cam then return end
    local a, b = cam.from or cam, cam.to
    if not b then
        setCameraMatrix(a[1], a[2], a[3], a[4], a[5], a[6], 0, 70)
        return
    end
    local t = smooth(math.min(1, math.max(0, elapsed / math.max(0.1, duration or 8))))
    local m = {}
    for i = 1, 6 do m[i] = a[i] + (b[i] - a[i]) * t end
    setCameraMatrix(m[1], m[2], m[3], m[4], m[5], m[6], 0, 70)
end

local function elapsed(R) return (getTickCount() - R.sceneStart) / 1000 end

local function practiceVehicle()
    local veh = getPedOccupiedVehicle(localPlayer)
    return veh and getElementModel(veh) == INTRO.VEHICLE.model and veh or nil
end
Scenes.practiceVehicle = practiceVehicle

-- looks at the practice vehicle from its local camera offset (backdrop until it is there)
local function vehicleCamera()
    local veh = practiceVehicle()
    if not veh then
        local b = INTRO.BACKDROP
        return setCameraMatrix(b[1], b[2], b[3], b[4], b[5], b[6], 0, 70)
    end
    local o, m = INTRO.VEHICLE.camera, getElementMatrix(veh)
    local x = m[4][1] + o[1] * m[1][1] + o[2] * m[2][1] + o[3] * m[3][1]
    local y = m[4][2] + o[1] * m[1][2] + o[2] * m[2][2] + o[3] * m[3][2]
    local z = m[4][3] + o[1] * m[1][3] + o[2] * m[2][3] + o[3] * m[3][3]
    setCameraMatrix(x, y, z, m[4][1], m[4][2], m[4][3] + 0.4, 0, 70)
    Mirror.show(m[4][1], m[4][2])
end

-- the dimension-0 objects around what the camera looks at (client/mirror.lua)
local function mirrorFor(sc)
    local cam = sc.camera
    if sc.point then
        Mirror.show(sc.point[1], sc.point[2])
    elseif type(cam) == "table" then
        local a, b = cam.from or cam, cam.to or cam.from or cam
        local spread = math.sqrt((a[4] - b[4]) ^ 2 + (a[5] - b[5]) ^ 2) / 2
        Mirror.show((a[4] + b[4]) / 2, (a[5] + b[5]) / 2, INTRO.MIRROR_RADIUS + spread)
    elseif cam == nil then
        Mirror.show(INTRO.BACKDROP[4], INTRO.BACKDROP[5])
    end
end

function Scenes.cameraStart(sc)
    if sc.vehicle then triggerServerEvent("intro:vehicle", resourceRoot, true) end
    mirrorFor(sc)
    if sc.camera == "vehicle" then
        vehicleCamera()
    elseif type(sc.camera) == "table" then
        cameraAt(sc.camera, 0, sc.duration)
    else
        cameraAt(INTRO.BACKDROP, 0)
    end
end
local cameraStart = Scenes.cameraStart

local function cameraRender(sc, R)
    if sc.camera == "vehicle" then
        vehicleCamera()
    elseif type(sc.camera) == "table" and sc.camera.to then
        cameraAt(sc.camera, elapsed(R), sc.duration)
    end
end

-- leaving a vehicle scene: the next scene asks for the vehicle again if it needs it
function Scenes.cameraStop(sc, nextScene)
    if sc and sc.vehicle and not (nextScene and nextScene.vehicle) then
        triggerServerEvent("intro:vehicle", resourceRoot, false)
    end
end

local function cardSpec(sc, R)
    return { step = R.stepLabel, title = Scenes.resolve(sc.title) or R.module.title, text = Scenes.resolve(sc.text) }
end

---------------------------------------------------------------- camera

Scenes.camera = {
    letterbox = true,
    start = function(sc) cameraStart(sc) end,
    render = function(sc, R)
        cameraRender(sc, R)
        if sc.bigTitle then Draw.bigTitle(sc.bigTitle[1] or "", sc.bigTitle[2] or "") end
        if sc.text then Draw.subtitle(Scenes.resolve(sc.text)) end
    end,
}

---------------------------------------------------------------- card

Scenes.card = {
    hud = true,
    start = function(sc) cameraStart(sc) end,
    render = function(sc, R)
        cameraRender(sc, R)
        Draw.card(cardSpec(sc, R))
    end,
}

---------------------------------------------------------------- task

local function taskDone(task, R)
    local c = task.check or {}
    if c.key then
        local t = R.keyTicks[c.key:lower()]
        return t ~= nil and t >= (task.since or 0)
    elseif c.vehicleData then
        local veh = practiceVehicle()
        if not veh then return false end
        local v = getElementData(veh, c.vehicleData)
        if c.changed then
            -- the value when the task became the current one, or when the vehicle appeared
            if not task.baseSet then task.base, task.baseSet = v, true end
            return v ~= task.base
        end
        if c.equals == false then return not v end
        if c.equals == nil or c.equals == true then return v and true or false end
        return v == c.equals
    elseif c.phoneApp then
        return getElementData(localPlayer, "phoneOpen") and getElementData(localPlayer, "phoneApp") == c.phoneApp
    elseif c.data then
        local v = getElementData(localPlayer, c.data)
        if c.equals == false then return not v end
        if c.equals == nil or c.equals == true then return v and true or false end
        return v == c.equals
    end
    return true
end

Scenes.task = {
    hud = true,
    start = function(sc, R)
        cameraStart(sc)
        R.tasks = {}
        for i, t in ipairs(sc.tasks or {}) do
            R.tasks[i] = { text = Scenes.resolve(t.text), check = t.check, done = false }
        end
        if R.tasks[1] then R.tasks[1].since = getTickCount() end
        Lock.allow(sc.allow)
    end,
    stop = function()
        Lock.allow(nil)
    end,
    render = function(sc, R)
        cameraRender(sc, R)
        -- the tasks are done in order: only the current one is checked
        for i, task in ipairs(R.tasks) do
            task.current = false
            if not task.done then
                if taskDone(task, R) then
                    task.done = true
                    playSound("assets/sounds/task_done.wav")
                    local nextTask = R.tasks[i + 1]
                    if nextTask then nextTask.since = getTickCount() end
                else
                    task.current = true
                end
                break
            end
        end
        local spec = cardSpec(sc, R)
        spec.tasks = R.tasks
        spec.note = Scenes.resolve(sc.note)
        Draw.card(spec)
    end,
    complete = function(_, R)
        for _, task in ipairs(R.tasks or {}) do
            if not task.done then return false end
        end
        return true
    end,
    message = function() return "Complete the task to continue" end,
}

---------------------------------------------------------------- highlight

local function targetRect(sc)
    if sc.target == "minimap" then
        local res = getResourceFromName("v_radar")
        if res and getResourceState(res) == "running" then
            local ok, x, y, w, h = pcall(function() return exports.v_radar:getMinimapRect() end)
            if ok and tonumber(x) and tonumber(w) and w > 0 then return { x, y, w, h } end
        end
        -- fallback: bottom left, where the minimap normally is
        return { Draw.sw * 0.012, Draw.sh * 0.73, Draw.sw * 0.17, Draw.sh * 0.21 }
    end
    local r = sc.rect or { 0.4, 0.4, 0.2, 0.2 }
    return { r[1] * Draw.sw, r[2] * Draw.sh, r[3] * Draw.sw, r[4] * Draw.sh }
end

Scenes.highlight = {
    hud = true,
    start = function(sc) cameraStart(sc) end,
    render = function(sc, R)
        cameraRender(sc, R)
        local r = targetRect(sc)
        Draw.spotlight(r)
        local s = Draw.s
        local cx = r[1] + r[3] + s(28)
        local cy = r[2] + r[4] / 2 - s(60)
        if cx + s(330) > Draw.sw then cx = r[1] - s(358) end
        Draw.callout(cx, cy, Scenes.resolve(sc.title) or R.module.title, Scenes.resolve(sc.text) or "")
    end,
}

---------------------------------------------------------------- world

local blipImages = {}
local function blipImage(id)
    if not id then return nil end
    if blipImages[id] == nil then
        local path = (":v_radar/radar/files/blips/%d.png"):format(id)
        blipImages[id] = fileExists(path) and path or false
    end
    return blipImages[id] or nil
end

Scenes.world = {
    letterbox = true,
    start = function(sc) cameraStart(sc) end,
    render = function(sc, R)
        cameraRender(sc, R)
        local p = sc.point
        if p then Draw.worldPoint(p[1], p[2], p[3], Scenes.resolve(sc.label), sc.radius) end
        if sc.blip or sc.mapText then
            Draw.mapIcon(blipImage(sc.blip), Scenes.resolve(sc.mapText) or "Look for this icon on your map")
        end
        if sc.text then Draw.subtitle(Scenes.resolve(sc.text), Draw.s(70)) end
    end,
}
