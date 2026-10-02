-- The introduction session: one per player, in the player's own dimension. The server decides
-- which modules run, records every finished module (seen + XP) right away, and puts the player
-- back into the world at the end. The client plays the scenes (client/runner.lua).
--
-- Modes: "full" - the player has not finished the introduction yet (or INTRO.DEBUG): every
-- module they have not seen in its current version; "new" - only modules that are new or got a
-- higher version since. A quit in the middle keeps the finished modules, so the next login
-- continues from the first unfinished one.

Session = { list = {} }
local sessions = Session.list

local function isRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function isLogged(player)
    return isElement(player) and getElementData(player, "isLogged") == true
end

local function send(player, name, ...)
    if isElement(player) then triggerClientEvent(player, name, resourceRoot, ...) end
end

local function later(s, ms, fn)
    local timer = setTimer(function()
        if sessions[s.player] == s then fn() end
    end, ms, 1)
    s.timers[#s.timers + 1] = timer
end

local function fadeMs() return math.floor(INTRO.FADE_TIME * 1000) end

local function freeDimension()
    local used = {}
    for _, s in pairs(sessions) do used[s.dimension] = true end
    local d = INTRO.DIMENSION_BASE
    while used[d] do d = d + 1 end
    return d
end

local function destroyVehicle(s)
    if isElement(s.vehicle) then destroyElement(s.vehicle) end
    s.vehicle = nil
end

local function placeOnStage(s)
    local p, st = s.player, INTRO.STAGE
    if getPedOccupiedVehicle(p) then removePedFromVehicle(p) end
    destroyVehicle(s)
    setElementInterior(p, 0)
    setElementDimension(p, s.dimension)
    setElementPosition(p, st[1], st[2], st[3])
    setElementRotation(p, 0, 0, st[4] or 0)
    setElementFrozen(p, true)
end

---------------------------------------------------------------- which modules

-- Main-line modules: everything not seen in its current version (all of them with DEBUG).
-- Update modules: only for players who had already finished the main line (not with DEBUG,
-- which plays the introduction as a new player sees it).
-- -> list of module defs, mode
function Session.pending(player)
    local done = Progress.isDone(player)
    local seen = Progress.getSeen(player)
    local list = {}
    for _, def in ipairs(Intro.available()) do
        local unseen = (tonumber(seen[def.id]) or 0) < def.version
        if def.update then
            if done and not INTRO.DEBUG and unseen then list[#list + 1] = def end
        elseif INTRO.DEBUG or unseen then
            list[#list + 1] = def
        end
    end
    return list, (INTRO.DEBUG or not done) and "full" or "new"
end

-- every available main-line module was seen in its current version
function Session.allSeen(player)
    local seen = Progress.getSeen(player)
    for _, def in ipairs(Intro.available("main")) do
        if (tonumber(seen[def.id]) or 0) < def.version then return false end
    end
    return true
end

-- The main line is finished: the current updates are covered by it, the player never gets them
local function completeMainLine(player)
    Progress.setDone(player)
    Progress.markSeenMany(player, Intro.available("update"))
end

function Session.isIn(player)
    return sessions[player] ~= nil
end

---------------------------------------------------------------- start

-- opts = { modules = { def, ... }, mode = "full" | "new" | "preview" }
-- -> true | false, reason
function Session.start(player, opts)
    if sessions[player] then return false, "The introduction is already running." end
    if not isLogged(player) then return false, "The player is not logged in." end
    local defs = opts.modules
    if not defs or #defs == 0 then return false, "There is nothing to show." end

    local x, y, z = getElementPosition(player)
    local _, _, rot = getElementRotation(player)
    local s = {
        player = player,
        mode = opts.mode or "full",
        dimension = freeDimension(),
        saved = { x = x, y = y, z = z, rot = rot, int = getElementInterior(player), dim = getElementDimension(player) },
        defs = defs,
        copies = {},
        index = 1,
        moduleStart = 0,
        recorded = {},
        timers = {},
        ready = false,
    }
    for i, def in ipairs(defs) do s.copies[i] = Intro.clientCopy(def) end
    sessions[player] = s

    -- v_accounts saves this position instead of the stage
    setElementData(player, "save.position", { x, y, z, s.saved.int, s.saved.dim }, false)
    setElementData(player, "intro.active", true)

    fadeCamera(player, false, INTRO.FADE_TIME)
    later(s, fadeMs() + 200, function()
        placeOnStage(s)
        s.ready = true
        s.moduleStart = getTickCount()
        send(player, "intro:start", {
            mode = s.mode,
            modules = s.copies,
            dimension = s.dimension,
        })
        triggerEvent("onIntroStart", player, s.mode)
    end)
    return true
end

---------------------------------------------------------------- finish

local function restoreWorld(s, toSpawn)
    local p = s.player
    if not isElement(p) then return end
    setElementFrozen(p, false)
    if toSpawn then
        local sp = INTRO.SPAWN
        setElementInterior(p, sp.interior or 0)
        setElementDimension(p, sp.dimension or 0)
        setElementPosition(p, sp[1], sp[2], sp[3])
        setElementRotation(p, 0, 0, sp[4] or 0)
    else
        local o = s.saved
        setElementInterior(p, o.int)
        setElementDimension(p, o.dim)
        setElementPosition(p, o.x, o.y, o.z)
        setElementRotation(p, 0, 0, o.rot or 0)
    end
    removeElementData(p, "save.position")
    removeElementData(p, "intro.active")
    setCameraTarget(p, p)
end

local function cleanup(s)
    for _, t in ipairs(s.timers) do
        if isTimer(t) then killTimer(t) end
    end
    s.timers = {}
    if isElement(s.player) and s.vehicle and getPedOccupiedVehicle(s.player) == s.vehicle then
        removePedFromVehicle(s.player)
    end
    destroyVehicle(s)
    sessions[s.player] = nil
end

-- reason: "done" | "stopped" | "restart"
function Session.finish(player, reason)
    local s = sessions[player]
    if not s then return false end
    local finished = reason == "done"
    if finished and not Progress.isDone(player) and Session.allSeen(player) then completeMainLine(player) end
    -- the first finished introduction of a new account ends at the spawn (LS airport)
    local toSpawn = finished and getElementData(player, "acc.registered") == true

    cleanup(s)
    send(player, "intro:stop", reason)
    if reason == "stopped" then
        restoreWorld(s, false)
        fadeCamera(player, true, 0.5)
        return true
    end

    fadeCamera(player, false, INTRO.FADE_TIME)
    setTimer(function()
        if not isElement(player) then return end
        restoreWorld(s, toSpawn)
        if finished then removeElementData(player, "acc.registered") end
        fadeCamera(player, true, INTRO.FADE_TIME)
        if finished then triggerEvent("onIntroFinish", player, s.mode) end
    end, fadeMs() + 200, 1)
    return true
end

---------------------------------------------------------------- client reports

addEvent("intro:moduleDone", true)
addEventHandler("intro:moduleDone", resourceRoot, function(id)
    local player = client
    local s = sessions[player]
    if not s or not s.ready then return end
    local def, copy = s.defs[s.index], s.copies[s.index]
    if not def or def.id ~= id then return end

    -- not faster than the scenes allow (the client locks Continue for the same time)
    local elapsed = (getTickCount() - s.moduleStart) / 1000
    if elapsed < Intro.minDuration(copy) * INTRO.MIN_MODULE_SHARE then
        outputDebugString(("[v_introduce] %s finished '%s' too fast (%.1fs)"):format(getPlayerName(player), id, elapsed), 2)
        return
    end

    s.recorded[id] = true
    Progress.markSeen(player, id, def.version)
    if def.rules then Progress.setRules(player, INTRO.RULES_VERSION) end
    local xp = Progress.reward(player, def)
    if xp > 0 and isRunning("v_levelsys") then
        exports.v_levelsys:giveXp(player, xp)
        send(player, "intro:reward", id, xp)
    end
    triggerEvent("onIntroModuleDone", player, id)

    if s.vehicle then placeOnStage(s) end
    s.index = s.index + 1
    s.moduleStart = getTickCount()
end)

addEvent("intro:finished", true)
addEventHandler("intro:finished", resourceRoot, function()
    local player = client
    local s = sessions[player]
    if not s or not s.ready then return end
    for _, def in ipairs(s.defs) do
        if not s.recorded[def.id] then
            -- something was refused: play the missing modules again
            local missing = {}
            for _, d in ipairs(s.defs) do
                if not s.recorded[d.id] then missing[#missing + 1] = d end
            end
            local mode = s.mode
            Session.finish(player, "restart")
            setTimer(function()
                if isElement(player) then Session.start(player, { modules = missing, mode = mode }) end
            end, fadeMs() * 2 + 600, 1)
            return
        end
    end
    Session.finish(player, "done")
end)

-- The practice vehicle of a scene with vehicle = true (INTRO.VEHICLE): the player sits in the
-- driver seat; the client's locked controls keep it in place.
addEvent("intro:vehicle", true)
addEventHandler("intro:vehicle", resourceRoot, function(want)
    local player = client
    local s = sessions[player]
    if not s or not s.ready then return end
    if not want then
        if s.vehicle then placeOnStage(s) end
        return
    end
    if isElement(s.vehicle) then return end
    local copy = s.copies[s.index]
    local allowed = false
    for _, scene in ipairs(copy and copy.scenes or {}) do
        if scene.vehicle then allowed = true end
    end
    if not allowed then return end

    local v = INTRO.VEHICLE
    local p = v.position
    local vehicle = createVehicle(v.model, p[1], p[2], p[3], 0, 0, p[4] or 0, "INTRO")
    if not vehicle then return end
    s.vehicle = vehicle
    setElementDimension(vehicle, s.dimension)
    setVehicleDamageProof(vehicle, true)
    setElementFrozen(player, false)
    warpPedIntoVehicle(player, vehicle, 0)
    setVehicleEngineState(vehicle, true)
end)

---------------------------------------------------------------- world events

-- killed anyway (admin, script): back to the stage, the client keeps playing
addEventHandler("onPlayerSpawn", root, function()
    local s = sessions[source]
    if s and s.ready then
        later(s, 100, function() placeOnStage(s) end)
    end
end)

addEventHandler("onPlayerQuit", root, function()
    local s = sessions[source]
    if s then cleanup(s) end   -- save.position stays: v_accounts saves the original position
end)

---------------------------------------------------------------- automatic start

local function check(player)
    if not isLogged(player) or sessions[player] then return end
    -- another script keeps the player somewhere temporary (e.g. the EMS tutorial): next login
    if getElementData(player, "save.position") then return end
    if isPedDead(player) then return end
    local list, mode = Session.pending(player)
    if #list > 0 then Session.start(player, { modules = list, mode = mode }) end
end

addEvent("onPlayerLoaded")
addEventHandler("onPlayerLoaded", root, function()
    local player = source
    -- let the other resources finish their onPlayerLoaded work first (level, money, HUD)
    setTimer(function()
        if isElement(player) then check(player) end
    end, 1500, 1)
end)

addEvent("onIntroStart")
addEvent("onIntroModuleDone")
addEvent("onIntroFinish")
addEvent("onIntroduceStart")

addEventHandler("onResourceStart", resourceRoot, function()
    -- other resources (re)register their modules on this
    triggerEvent("onIntroduceStart", resourceRoot)
    setTimer(function()
        for _, player in ipairs(getElementsByType("player")) do check(player) end
    end, 3000, 1)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player, s in pairs(sessions) do
        cleanup(s)
        restoreWorld(s, false)
        fadeCamera(player, true, 0.5)
    end
end)

---------------------------------------------------------------- exports

function isInIntro(player) return sessions[player] ~= nil end

-- mode "full" ignores what the player has seen, "new" runs the pending modules
function startIntro(player, mode)
    if not isElement(player) then return false end
    local list
    if mode == "full" then list = Intro.available("main") else list = Session.pending(player) end
    return Session.start(player, { modules = list, mode = mode == "full" and "full" or "new" })
end

function resetIntro(who)
    if not who then return false end
    Progress.reset(who, false)
    return true
end
