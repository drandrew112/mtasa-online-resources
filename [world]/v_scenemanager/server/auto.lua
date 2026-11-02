-- Automatic scene generator + the admin commands of the live scenes.
--
-- Works only while an agency has free units. The next scene comes after a random INTERVAL_MIN..INTERVAL_MAX seconds
-- divided by the free units (each counted with its agency's RATE), so more free units -> more scenes. An agency is
-- "available" when it has a free unit and fewer waiting scene tasks than PENDING_PER_UNIT per free unit.
-- Agency rule (never relaxed): every agency with need 2 must be available with a free unit within its
-- MAX_UNIT_DISTANCE; a scene without need-2 agencies needs one need-1 agency like that.

Auto = {
    enabled = true,
    nextAt = nil,       -- tick of the next scene, nil = not scheduled
    lastFree = 0,
}

addEvent("onSceneAutoChange", false)

-- free units + availability of every agency -> { [agency] = { units, available } }, weighted free count
local function agencyState()
    local out, free = {}, 0
    for _, id in ipairs(VSM.AGENCY_ORDER) do
        local a = Agencies.get(id)
        local units = a.running() and a.freeUnits() or {}
        local cfg = VSM.AGENCIES[id]
        local available = #units > 0 and Live.pendingCount(id) < #units * (cfg.PENDING_PER_UNIT or 1)
        out[id] = { units = units, available = available }
        if available then free = free + #units * (cfg.RATE or 1) end
    end
    return out, free
end
Auto.agencyState = agencyState

local function randomDelay(free)
    local a = VSM.AUTO
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

-- agency rule of one scene -> ok, accounts of the probable recipient unit
local function agenciesAllow(s, state)
    local mandatory, accounts = false, nil
    for _, id in ipairs(VSM.AGENCY_ORDER) do
        if s.needs[id] == 2 then
            mandatory = true
            if not state[id].available then return false end
            local unit = Agencies.nearestFree(id, s.center, s.interior, state[id].units)
            if not unit then return false end
            accounts = accounts or unit.accounts
        end
    end
    if mandatory then return true, accounts end
    for _, id in ipairs(VSM.AGENCY_ORDER) do
        if s.needs[id] == 1 and state[id].available then
            local unit = Agencies.nearestFree(id, s.center, s.interior, state[id].units)
            if unit then return true, unit.accounts end
        end
    end
    return false
end

-- Scenes that pass the mandatory checks: enabled, weight > 0, valid, not active, and with
-- checkDistance (the generator) the agency rule + MIN_PLAYER_DISTANCE / MIN_SCENE_DISTANCE.
-- These are never relaxed. -> { { scene = summary, accounts = nearest unit's accounts | nil }, ... }
function Auto.candidates(checkDistance, state)
    local candidates = {}
    if checkDistance and not state then state = agencyState() end
    for _, s in ipairs(Storage.list()) do
        local ok = s.enabled and s.valid and s.weight > 0 and not Live.isActive(s.name)
        local accounts
        if ok and checkDistance then
            ok = nearestPlayerDistance(s.center, s.interior, s.dimension) >= VSM.AUTO.MIN_PLAYER_DISTANCE
                and nearestSceneDistance(s.center) >= VSM.AUTO.MIN_SCENE_DISTANCE
            if ok then ok, accounts = agenciesAllow(s, state) end
        end
        if ok then
            candidates[#candidates + 1] = { scene = s, accounts = accounts }
        end
    end
    return candidates
end

-- Pick for the generator (checkDistance = true) or /scenerandom: mandatory checks,
-- then the variety rules + weights + random draw of server/variety.lua
-- -> name, relaxation level, pool size, candidate count | nil
function Auto.pickScene(checkDistance, state)
    local candidates = Auto.candidates(checkDistance, state)
    local s, level, pool = Variety.choose(candidates)
    if not s then return nil end
    Variety.last = { name = s.name, level = level, pool = pool, candidates = #candidates, time = Variety.now() }
    return s.name, level, pool, #candidates
end

local function tick()
    if not Auto.enabled then return end
    local state, free = agencyState()
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
    if Live.count() >= VSM.AUTO.MAX_ACTIVE then return end

    local name, level, pool, total = Auto.pickScene(true, state)
    if not name then
        Auto.nextAt = now + 15000 -- nothing usable right now (players nearby, units too far, all active ...)
        return
    end
    vsmLog("auto: picked '%s' (variety level %d: %s, %d of %d candidates)",
        name, level, Variety.LEVELS[level] or "?", pool, total)
    local id, err = Live.spawn(name, "auto", { auto = true })
    if not id then vsmLog("auto: could not spawn '%s': %s", name, tostring(err)) end
    Auto.nextAt = now + randomDelay(free)
end

function Auto.setEnabled(on, by)
    on = on and true or false
    if on == Auto.enabled then return true end
    Auto.enabled = on
    Auto.nextAt = nil
    set("autoEnabled", on and "true" or "false")
    vsmLog("auto generator %s by %s", on and "ENABLED" or "DISABLED", tostring(by or "script"))
    triggerEvent("onSceneAutoChange", resourceRoot, on, tostring(by or "script"))
    return true
end

function Auto.freeCounts()
    local state = agencyState()
    local out = {}
    for _, id in ipairs(VSM.AGENCY_ORDER) do out[id] = #state[id].units end
    return out
end

addEventHandler("onResourceStart", resourceRoot, function()
    local v = get("autoEnabled")
    Auto.enabled = v == true or v == "true"
    setTimer(tick, VSM.CHECK_INTERVAL, 0)
end)

---------------------------------------------------------------- commands

local function guard(player)
    if player and getElementType(player) == "player" and not vsmIsAllowed(player) then return false end
    return true
end

local function spawnReply(player, name, id, err)
    if id then
        vsmSay(player, err and "v_scenemanager.cmd.spawned_warn" or "v_scenemanager.cmd.spawned",
            { name = name, id = id, warning = tostring(err or "") })
    else
        vsmSay(player, "v_scenemanager.cmd.spawn_failed", { error = err })
    end
end
Auto.spawnReply = spawnReply

-- /scenerandom [name]  - spawns a random (or the named) scene; free units are not required
addCommandHandler(VSM.CMD_RANDOM, function(player, _, name)
    if not guard(player) then return end
    if not name then
        name = Auto.pickScene(false)
        if not name then
            vsmSay(player, "v_scenemanager.cmd.nothing_to_spawn")
            return
        end
    elseif not Storage.exists(name) then
        vsmSay(player, "v_scenemanager.err.unknown_scene", { name = name })
        return
    end
    local id, err = Live.spawn(name, "command:" .. vsmPlayerName(player))
    spawnReply(player, name, id, err)
end)

-- /sceneauto [on|off]
addCommandHandler(VSM.CMD_AUTO, function(player, _, arg)
    if not guard(player) then return end
    if arg == "on" or arg == "off" then
        Auto.setEnabled(arg == "on", vsmPlayerName(player))
    end
    local wait = Auto.nextAt and math.max(0, math.floor((Auto.nextAt - getTickCount()) / 1000))
    local free = Auto.freeCounts()
    vsmSay(player, (Auto.enabled and wait) and "v_scenemanager.cmd.auto_state_next" or "v_scenemanager.cmd.auto_state", {
        state = L.msg(Auto.enabled and "v_scenemanager.common.on" or "v_scenemanager.common.off"),
        ems = free.ems or 0, pd = free.pd or 0, active = Live.count(), wait = wait or 0,
    })
end)

-- /scenelist  - live scenes
addCommandHandler(VSM.CMD_LIST, function(player)
    if not guard(player) then return end
    if Live.count() == 0 then
        vsmSay(player, "v_scenemanager.cmd.list_empty", { count = #Storage.names })
        return
    end
    for _, scene in pairs(Live.scenes) do
        vsmSay(player, scene.closedAt and "v_scenemanager.cmd.list_row_closed" or "v_scenemanager.cmd.list_row", {
            id = scene.id, name = scene.name,
            ems = scene.tasks.ems and ("#" .. scene.tasks.ems.id) or "-",
            pd = scene.tasks.pd and ("#" .. scene.tasks.pd.id) or "-",
            source = scene.source, peds = #scene.peds,
        })
    end
end)

-- /sceneclear [id|all]
addCommandHandler(VSM.CMD_CLEAR, function(player, _, arg)
    if not guard(player) then return end
    local n = 0
    if arg == nil or arg == "all" then
        local ids = {}
        for id in pairs(Live.scenes) do ids[#ids + 1] = id end
        for _, id in ipairs(ids) do
            if Live.remove(id, "cleared by " .. vsmPlayerName(player)) then n = n + 1 end
        end
    elseif Live.remove(tonumber(arg), "cleared by " .. vsmPlayerName(player)) then
        n = 1
    end
    vsmSay(player, "v_scenemanager.cmd.cleared", { count = n })
end)

-- /scenereload  - re-read the scene files (summaries)
addCommandHandler(VSM.CMD_RELOAD, function(player)
    if not guard(player) then return end
    vsmSay(player, "v_scenemanager.cmd.reloaded", { count = Storage.reload() })
end)

-- /scenevariety            - history + last pick
-- /scenevariety sim [n]    - n dry-run picks (no spawn, history untouched) among the
--                            enabled inactive scenes, as /scenerandom would pick them
-- /scenevariety clear      - deletes the history (file too)
local function topCategories(counts, limit)
    local list = {}
    for cat, n in pairs(counts) do list[#list + 1] = { cat ~= "" and cat or "-", n } end
    table.sort(list, function(a, b) return a[2] > b[2] or (a[2] == b[2] and a[1] < b[1]) end)
    local parts = {}
    for i = 1, math.min(limit, #list) do parts[i] = list[i][1] .. " " .. list[i][2] end
    return #parts > 0 and table.concat(parts, ", ") or "-"
end

addCommandHandler(VSM.CMD_VARIETY, function(player, _, action, arg)
    if not guard(player) then return end
    local V = VSM.VARIETY

    if action == "clear" then
        Variety.clear()
        vsmSay(player, "v_scenemanager.cmd.variety_cleared")
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
        vsmSay(player, "v_scenemanager.cmd.variety_sim", { picks = #picked, candidates = #candidates, repeats = repeats,
            levels = table.concat(lv, ", "), categories = topCategories(cats, 20) })
        return
    end

    local players, recent = 0, {}
    for _ in pairs(Variety.players) do players = players + 1 end
    for i = math.max(1, #Variety.global - V.GLOBAL.categoryWindow + 1), #Variety.global do
        local cat = Variety.global[i].category
        recent[cat] = (recent[cat] or 0) + 1
    end
    vsmSay(player, "v_scenemanager.cmd.variety_state", {
        state = L.msg(V.ENABLED and "v_scenemanager.common.on" or "v_scenemanager.common.off"),
        entries = #Variety.global, accounts = players, hours = math.floor(V.RETENTION / 3600),
        window = V.GLOBAL.categoryWindow, categories = topCategories(recent, 8),
    })
    local last = Variety.last
    if last then
        vsmSay(player, "v_scenemanager.cmd.variety_last", { name = last.name, level = last.level,
            pool = last.pool, candidates = last.candidates, ago = Variety.now() - last.time })
    end
end)
