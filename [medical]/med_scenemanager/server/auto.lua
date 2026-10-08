-- Automatic task generator + the admin commands of the live scenes.
--
-- Works only while med_erm has free units (no task, status Available). The next
-- scene comes after a random INTERVAL_MIN..INTERVAL_MAX seconds divided by the number
-- of free units, so more free units -> more scenes. At most PENDING_PER_UNIT waiting
-- (unassigned) scene tasks per free unit are allowed at a time. A scene is only
-- generated within MAX_UNIT_DISTANCE of a free unit, so an ambulance can reach it in time.

Auto = {
    enabled = true,
    nextAt = nil,       -- tick of the next scene, nil = not scheduled
    lastFree = 0,
}

addEvent("onMedSceneAutoChange", false)

local function freeUnitList()
    if not msmResourceRunning(MSM.ERM) then return {} end
    local units = exports[MSM.ERM]:getFreeUnits(MSM.AUTO.UNIT_TYPES)
    return type(units) == "table" and units or {}
end

local function freeUnits()
    return #freeUnitList()
end

local function randomDelay(free)
    local a = MSM.AUTO
    local seconds = a.INTERVAL_MIN + math.random() * (a.INTERVAL_MAX - a.INTERVAL_MIN)
    return math.floor(seconds * 1000 / math.max(1, free))
end

local function nearestPlayerDistance(c, interior, dimension)
    local best = math.huge
    for _, player in ipairs(getElementsByType("player")) do
        if getElementDimension(player) == dimension and getElementInterior(player) == interior then
            local x, y, z = getElementPosition(player)
            best = math.min(best, getDistanceBetweenPoints3D(x, y, z, c[1], c[2], c[3]))
        end
    end
    return best
end

local function nearestSceneDistance(c)
    local best = math.huge
    for _, scene in pairs(Live.scenes) do
        local s = scene.center
        best = math.min(best, getDistanceBetweenPoints3D(s[1], s[2], s[3], c[1], c[2], c[3]))
    end
    return best
end

-- 2D distance to the nearest free unit and that unit (the probable recipient: med_erm_auto
-- sends the nearest one). Interior scenes have no world position to compare with, they
-- always count as in range.
local function nearestUnit(c, interior, units)
    if interior ~= 0 then return 0, nil end
    local best, bestUnit = math.huge, nil
    for _, u in ipairs(units) do
        if u.x and u.y then
            local d = getDistanceBetweenPoints2D(u.x, u.y, c[1], c[2])
            if d < best then best, bestUnit = d, u end
        end
    end
    return best, bestUnit
end

-- Scenes that pass the mandatory checks: enabled, weight > 0, not active, and with
-- checkDistance (the generator) MIN_PLAYER_DISTANCE / MIN_SCENE_DISTANCE / MAX_UNIT_DISTANCE.
-- These are never relaxed. -> { { scene = summary, accounts = nearest unit's accounts | nil }, ... }
function Auto.candidates(checkDistance)
    local candidates = {}
    local maxUnit = tonumber(MSM.AUTO.MAX_UNIT_DISTANCE) or 0
    local units = checkDistance and freeUnitList() or nil
    for _, s in ipairs(Storage.list()) do
        local ok = s.enabled and s.weight > 0 and not Live.isActive(s.name)
        local unit
        if ok and checkDistance then
            ok = nearestPlayerDistance(s.center, s.interior, s.dimension) >= MSM.AUTO.MIN_PLAYER_DISTANCE
                and nearestSceneDistance(s.center) >= MSM.AUTO.MIN_SCENE_DISTANCE
            if ok then
                local dist
                dist, unit = nearestUnit(s.center, s.interior, units)
                ok = maxUnit <= 0 or dist <= maxUnit
            end
        end
        if ok then
            candidates[#candidates + 1] = { scene = s, accounts = unit and unit.accounts or nil }
        end
    end
    return candidates
end

-- Pick for the generator (checkDistance = true) or /medscenerandom: mandatory checks,
-- then the variety rules + weights + random draw of server/variety.lua
-- -> name, relaxation level, pool size, candidate count | nil
function Auto.pickScene(checkDistance)
    local candidates = Auto.candidates(checkDistance)
    local s, level, pool = Variety.choose(candidates)
    if not s then return nil end
    Variety.last = { name = s.name, level = level, pool = pool, candidates = #candidates, time = Variety.now() }
    return s.name, level, pool, #candidates
end

local function tick()
    if not Auto.enabled then return end
    local free = freeUnits()
    if free == 0 then
        Auto.nextAt, Auto.lastFree = nil, 0
        return
    end

    local now = getTickCount()
    -- more free units than before: bring the next scene closer
    if not Auto.nextAt or free > Auto.lastFree then
        local at = now + randomDelay(free)
        Auto.nextAt = Auto.nextAt and math.min(Auto.nextAt, at) or at
    end
    Auto.lastFree = free
    if now < Auto.nextAt then return end

    if Live.count() >= MSM.AUTO.MAX_ACTIVE then return end
    if Live.pendingCount() >= free * MSM.AUTO.PENDING_PER_UNIT then return end

    local name, level, pool, total = Auto.pickScene(true)
    if not name then
        Auto.nextAt = now + 15000 -- nothing usable right now (players nearby, units too far, all active ...)
        return
    end
    msmLog("auto: picked '%s' (variety level %d: %s, %d of %d candidates)",
        name, level, Variety.LEVELS[level] or "?", pool, total)
    local id, err = Live.spawn(name, "auto")
    if not id then msmLog("auto: could not spawn '%s': %s", name, tostring(err)) end
    Auto.nextAt = now + randomDelay(free)
end

function Auto.setEnabled(on, by)
    on = on and true or false
    if on == Auto.enabled then return true end
    Auto.enabled = on
    Auto.nextAt = nil
    set("autoEnabled", on and "true" or "false")
    msmLog("auto generator %s by %s", on and "ENABLED" or "DISABLED", tostring(by or "script"))
    triggerEvent("onMedSceneAutoChange", resourceRoot, on, tostring(by or "script"))
    return true
end

addEventHandler("onResourceStart", resourceRoot, function()
    local v = get("autoEnabled")
    Auto.enabled = v == true or v == "true"
    setTimer(tick, MSM.CHECK_INTERVAL, 0)
end)

---------------------------------------------------------------- commands

local function guard(player)
    if player and getElementType(player) == "player" and not msmIsAllowed(player) then return false end
    return true
end

local function playerName(player)
    return isElement(player) and getPlayerName(player) or "console"
end

-- /medscenerandom [name]  - spawns a random (or the named) scene; free units are not required
addCommandHandler(MSM.CMD_RANDOM, function(player, _, name)
    if not guard(player) then return end
    if not name then
        name = Auto.pickScene(false)
        if not name then
            msmSay(player, "No enabled, inactive scene to spawn.")
            return
        end
    elseif not Storage.exists(name) then
        msmSay(player, "Unknown scene: #ffd24a" .. name)
        return
    end
    local id, err = Live.spawn(name, "command:" .. playerName(player))
    if id then
        msmSay(player, ("Scene #ffd24a%s#ffffff spawned (#%d).%s"):format(name, id, err and (" #ff9a3c" .. err) or ""))
    else
        msmSay(player, "Could not spawn: " .. tostring(err))
    end
end)

-- /medsceneauto [on|off]
addCommandHandler(MSM.CMD_AUTO, function(player, _, arg)
    if not guard(player) then return end
    if arg == "on" or arg == "off" then
        Auto.setEnabled(arg == "on", playerName(player))
    end
    local wait = Auto.nextAt and math.max(0, math.floor((Auto.nextAt - getTickCount()) / 1000))
    msmSay(player, ("Auto generator: %s#ffffff, free units: %d, active scenes: %d%s"):format(
        Auto.enabled and "#5ad25aON" or "#ff5a5aOFF", freeUnits(), Live.count(),
        (Auto.enabled and wait) and (", next in ~" .. wait .. " s") or ""))
end)

-- /medscenelist  - live scenes
addCommandHandler(MSM.CMD_LIST, function(player)
    if not guard(player) then return end
    if Live.count() == 0 then
        msmSay(player, ("No active scenes. %d scene file(s) loaded."):format(#Storage.names))
        return
    end
    for _, scene in pairs(Live.scenes) do
        msmSay(player, ("#%d #ffd24a%s#ffffff task %s, %s, %d ped(s)%s"):format(scene.id, scene.name,
            scene.taskId and ("#" .. scene.taskId) or "-", scene.source, #scene.peds,
            scene.closedAt and " #aaaaaa(closed, cleaning up)" or ""))
    end
end)

-- /medsceneclear [id|all]
addCommandHandler(MSM.CMD_CLEAR, function(player, _, arg)
    if not guard(player) then return end
    local n = 0
    if arg == nil or arg == "all" then
        local ids = {}
        for id in pairs(Live.scenes) do ids[#ids + 1] = id end
        for _, id in ipairs(ids) do
            if Live.remove(id, "cleared by " .. playerName(player)) then n = n + 1 end
        end
    elseif Live.remove(tonumber(arg), "cleared by " .. playerName(player)) then
        n = 1
    end
    msmSay(player, ("Removed %d scene(s)."):format(n))
end)

-- /medscenereload  - re-read the scene files (summaries)
addCommandHandler(MSM.CMD_RELOAD, function(player)
    if not guard(player) then return end
    msmSay(player, ("%d scene(s) loaded."):format(Storage.reload()))
end)

-- /medscenevariety            - history + last pick
-- /medscenevariety sim [n]    - n dry-run picks (no spawn, history untouched) among the
--                               enabled inactive scenes, as /medscenerandom would pick them
-- /medscenevariety clear      - deletes the history (file too)
local function topCategories(counts, limit)
    local list = {}
    for cat, n in pairs(counts) do list[#list + 1] = { cat ~= "" and cat or "-", n } end
    table.sort(list, function(a, b) return a[2] > b[2] or (a[2] == b[2] and a[1] < b[1]) end)
    local parts = {}
    for i = 1, math.min(limit, #list) do parts[i] = list[i][1] .. " " .. list[i][2] end
    return #parts > 0 and table.concat(parts, ", ") or "-"
end

addCommandHandler(MSM.CMD_VARIETY, function(player, _, action, arg)
    if not guard(player) then return end
    local V = MSM.VARIETY

    if action == "clear" then
        Variety.clear()
        msmSay(player, "Scene variety history deleted.")
        return
    end

    if action == "sim" then
        local n = math.max(1, math.min(100, math.floor(tonumber(arg) or 30)))
        local candidates = Auto.candidates(false)
        local history = {}
        for i, e in ipairs(Variety.global) do history[i] = e end
        local levels, cats, picked, repeats, t = {}, {}, {}, 0, Variety.now()
        for _ = 1, n do
            local s, level = Variety.choose(candidates, history)
            if not s then break end
            for _, prev in ipairs(picked) do
                local dx, dy = prev[1] - s.center[1], prev[2] - s.center[2]
                if dx * dx + dy * dy < V.LOCATION_RADIUS * V.LOCATION_RADIUS then
                    repeats = repeats + 1
                    break
                end
            end
            picked[#picked + 1] = s.center
            levels[level] = (levels[level] or 0) + 1
            cats[s.category] = (cats[s.category] or 0) + 1
            history[#history + 1] = Variety.makeEntry(s.name, s.category, s.center[1], s.center[2], s.interior, t)
        end
        local lv = {}
        for level = 0, Variety.MAX_LEVEL do lv[#lv + 1] = "L" .. level .. " " .. (levels[level] or 0) end
        msmSay(player, ("Simulated %d pick(s) from %d candidate(s), location repeats: %d"):format(#picked, #candidates, repeats))
        msmSay(player, "Levels: " .. table.concat(lv, ", "))
        msmSay(player, "Categories: " .. topCategories(cats, 20))
        return
    end

    local players, recent = 0, {}
    for _ in pairs(Variety.players) do players = players + 1 end
    for i = math.max(1, #Variety.global - V.GLOBAL.categoryWindow + 1), #Variety.global do
        local cat = Variety.global[i].category
        recent[cat] = (recent[cat] or 0) + 1
    end
    msmSay(player, ("Variety: %s#ffffff, history: %d global entr%s, %d account(s), kept %d h"):format(
        V.ENABLED and "#5ad25aON" or "#ff5a5aOFF", #Variety.global, #Variety.global == 1 and "y" or "ies",
        players, math.floor(V.RETENTION / 3600)))
    msmSay(player, ("Last %d categories: %s"):format(V.GLOBAL.categoryWindow, topCategories(recent, 8)))
    local last = Variety.last
    if last then
        msmSay(player, ("Last pick: #ffd24a%s#ffffff, level %d (%s), %d of %d candidates, %d s ago"):format(
            last.name, last.level, Variety.LEVELS[last.level] or "?", last.pool, last.candidates,
            Variety.now() - last.time))
    end
end)
