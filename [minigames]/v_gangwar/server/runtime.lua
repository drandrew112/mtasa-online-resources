-- Gang war runs (server). One run per gang war at a time, held in Runs[id]; no run = IDLE.
--
--   reserved  an armed player came within trigger_radius: red circle on his radar, nobody else can take it
--   active    he entered zone_radius: the attackers are spawned (ai_peds scripted peds, hostile to every player)
--   running   the first kill: the stats start ("Gang war / Started" banner)
--   cleanup   finished (every attacker dead) or aborted (starter beyond release_radius, left the server, the
--             reservation expired): the peds are removed one by one while no player camera sees them, then IDLE
--
-- Death does not end a reservation: the distance is not checked while the starter is dead.

local ai = setmetatable({}, { __index = function(_, name)
    return function(_, ...) return exports.ai_peds[name](exports.ai_peds, ...) end
end })

Runs = {}
local pedRun = {}       -- ped -> run
local starterRun = {}   -- player -> run (one reservation per player)
local claiming = {}     -- gang war id -> player, and player -> true: isRunning claim in flight (GangWars.claim)

local function resourceRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function dist2(x1, y1, x2, y2) return (x1 - x2) ^ 2 + (y1 - y2) ^ 2 end

local function tell(player, key, params)
    if isElement(player) then
        triggerClientEvent(player, "gangwar:notify", resourceRoot, L.msg("v_gangwar.main.title"), L.msg(key, params))
    end
end

--------------------------------------------------------------------------------
-- player checks
--------------------------------------------------------------------------------

-- a firearm with ammo (wp_manager owns the weapons; without it the GTA slots are read)
function isPlayerArmed(player)
    if resourceRunning("wp_manager") then
        local list = exports.wp_manager:getPlayerWeapons(player)
        if type(list) ~= "table" then return false end
        for _, w in ipairs(list) do
            if GW.isFirearm(w.id) and ((tonumber(w.ammo) or 0) + (tonumber(w.clip) or 0)) > 0 then return true end
        end
        return false
    end
    for slot = 2, 7 do
        if GW.isFirearm(getPedWeapon(player, slot)) and getPedTotalAmmo(player, slot) > 0 then return true end
    end
    return false
end

-- run.dimension: the gang war's own, or the admin's private editor dimension for a test run
local function inWorldOf(player, run)
    return getElementDimension(player) == run.dimension and getElementInterior(player) == run.gw.interior
end

local function playerDistance2(player, gw)
    local x, y = getElementPosition(player)
    return dist2(x, y, gw.x, gw.y)
end

--------------------------------------------------------------------------------
-- HUD (ui_core stat rows on the client) for the starter and the helpers in the zone
--------------------------------------------------------------------------------

local function hudData(run, player)
    return {
        id = run.gw.id,
        killed = run.kills[player] or 0,
        left = run.alive,
        total = run.total,
        elapsed = run.startedAt and (getTickCount() - run.startedAt) or false,
        finished = run.finished or false,
    }
end

local function sendHud(run, player)
    triggerClientEvent(player, "gangwar:hud", resourceRoot, hudData(run, player))
end

local function hideHud(run, player)
    run.viewers[player] = nil
    if isElement(player) then triggerClientEvent(player, "gangwar:hud", resourceRoot, false, run.gw.id) end
end

local function updateHud(run)
    for player in pairs(run.viewers) do
        if isElement(player) then sendHud(run, player) else run.viewers[player] = nil end
    end
end

-- who sees the rows: the starter (anywhere inside the release area) + players near the zone
local function refreshViewers(run)
    if run.state ~= "active" and run.state ~= "running" then return end
    local gw = run.gw
    local r2 = (gw.zone_radius * GW.HUD_RADIUS_FACTOR) ^ 2
    local want = {}
    if isElement(run.starter) then want[run.starter] = true end
    for _, player in ipairs(getElementsByType("player")) do
        if inWorldOf(player, run) and playerDistance2(player, gw) <= r2 then want[player] = true end
    end
    for player in pairs(run.viewers) do
        if not want[player] then hideHud(run, player) end
    end
    for player in pairs(want) do
        if not run.viewers[player] then
            run.viewers[player] = true
            sendHud(run, player)
        end
    end
end

local function bannerTo(run, key)
    for player in pairs(run.viewers) do
        if isElement(player) then triggerClientEvent(player, "gangwar:banner", resourceRoot, key) end
    end
end

--------------------------------------------------------------------------------
-- rewards
--------------------------------------------------------------------------------

local function pay(player, money, xp)
    if not isElement(player) then return end
    if money > 0 then givePlayerMoney(player, money) end
    if xp > 0 and resourceRunning("v_levelsys") then pcall(function() exports.v_levelsys:giveXp(player, xp) end) end
    triggerClientEvent(player, "gangwar:reward", resourceRoot, money, xp)
end

--------------------------------------------------------------------------------
-- life cycle
--------------------------------------------------------------------------------

local function removeCircle(run)
    if run.circle and resourceRunning("v_radar") then pcall(function() exports.v_radar:removeCircleArea(run.circle) end) end
    run.circle = nil
end

local function releaseStarter(run)
    if run.starter and starterRun[run.starter] == run then starterRun[run.starter] = nil end
end

-- isRunning back to 0 (only a real run holds it; test runs never touch the database)
local function releaseClaim(run)
    if run.claimed then
        run.claimed = nil
        GangWars.release(run.gw.id)
    end
end

-- reason: "left" | "expired" | "quit" | "admin" | "deleted" | "finished"
local function close(run, reason)
    if run.state == "cleanup" then return end
    run.state = "cleanup"
    run.closedAt = getTickCount()
    removeCircle(run)
    releaseStarter(run)
    releaseClaim(run)
    if reason == "finished" then
        -- the rows stay a little after the "Completed" banner
        local viewers = run.viewers
        run.viewers = {}
        setTimer(function()
            for player in pairs(viewers) do hideHud(run, player) end
        end, GW.END_HUD_TIME, 1)
    else
        for player in pairs(run.viewers) do hideHud(run, player) end
        if reason == "left" then tell(run.starter, "v_gangwar.main.cancelled_left")
        elseif reason == "expired" then tell(run.starter, "v_gangwar.main.cancelled_expired")
        elseif reason == "admin" or reason == "deleted" then tell(run.starter, "v_gangwar.main.cancelled_admin") end
    end
    if next(run.peds) == nil then Runs[run.gw.id] = nil end
end

local function reserve(gw, player, test, dimension)
    local run = {
        gw = gw, starter = player, state = "reserved", test = test or false, dimension = dimension or gw.dimension,
        claimed = not test,
        reservedAt = getTickCount(), peds = {}, alive = 0, total = 0, kills = {}, viewers = {},
    }
    Runs[gw.id] = run
    starterRun[player] = run
    if resourceRunning("v_radar") then
        local c = GW.CIRCLE_COLOR
        local ok, id = pcall(function()
            return exports.v_radar:addCircleArea(player, gw.x, gw.y, gw.zone_radius, c[1], c[2], c[3], c[4], false)
        end)
        run.circle = ok and id or nil
    end
    tell(player, test and "v_gangwar.main.test_reserved" or "v_gangwar.main.reserved", { name = gw.name })
    return run
end

local function spawn(run)
    local gw = run.gw
    local group = "gw_" .. gw.gang
    ai:setAIGroupRelation(group, "player", "hostile")
    for _, a in ipairs(gw.attackers) do
        local opts = {
            rot = a.rot, dimension = run.dimension, interior = gw.interior,
            behaviour = "enemy", group = group, health = a.health, armor = a.armor, accuracy = a.accuracy,
            aggroRadius = a.aggro, leash = gw.release_radius, role = "free", speed = a.speed, keepBody = true,
        }
        if a.weapon and a.weapon > 0 then opts.weapon, opts.ammo = a.weapon, a.ammo end
        if a.task == "patrol" then
            local pts = {}
            for i, p in ipairs(a.patrol) do pts[i] = { p[1], p[2], p[3] } end
            opts.task, opts.taskOpts = "patrol", { points = pts, loop = true, wait = { a.wait[1], a.wait[2] } }
            opts.home = { a.x, a.y, a.z }
        else
            opts.task, opts.taskOpts = "guard", { x = a.x, y = a.y, z = a.z, rot = a.rot }
        end
        local ped = ai:createAIPed(a.skin, a.x, a.y, a.z, opts)
        if ped then
            run.peds[ped] = true
            pedRun[ped] = run
            run.alive = run.alive + 1
            run.total = run.total + 1
        end
    end
    if run.total == 0 then
        outputDebugString(("[v_gangwar] %s: no attacker could be spawned (ai_peds running?)"):format(gw.name), 2)
        close(run, "admin")
        return
    end
    run.state = "active"
    refreshViewers(run)
end

local function finish(run)
    local gw = run.gw
    run.finished = true
    run.duration = run.startedAt and (getTickCount() - run.startedAt) or 0
    updateHud(run)
    bannerTo(run, "v_gangwar.main.completed")
    if not run.test then
        GangWars.setLastRun(gw.id, getRealTime().timestamp)
        if isElement(run.starter) then pay(run.starter, gw.reward_money, gw.reward_xp) end
    end
    if isElement(run.starter) then
        triggerClientEvent(run.starter, "gangwar:summary", resourceRoot, {
            name = gw.name, kills = run.kills[run.starter] or 0, total = run.total, duration = run.duration,
            money = run.test and 0 or gw.reward_money, xp = run.test and 0 or gw.reward_xp,
            killMoney = (run.kills[run.starter] or 0) * GW.KILL_MONEY, killXp = (run.kills[run.starter] or 0) * GW.KILL_XP,
            test = run.test,
        })
    end
    close(run, "finished")
end

-- the ped is out of the fight (dead, or removed by someone else)
local function pedDown(run, ped, killer)
    if not run.peds[ped] or run.peds[ped] == "down" then return end
    run.peds[ped] = "down"
    if run.state == "cleanup" then return end
    run.alive = math.max(0, run.alive - 1)
    if killer and isElement(killer) and getElementType(killer) == "player" then
        run.kills[killer] = (run.kills[killer] or 0) + 1
        if not run.test then pay(killer, GW.KILL_MONEY, GW.KILL_XP) end
    end
    if run.state == "active" then
        -- the gang war officially starts with the first kill
        run.state = "running"
        run.startedAt = getTickCount()
        refreshViewers(run)
        bannerTo(run, "v_gangwar.main.started")
    end
    if run.alive == 0 then
        finish(run)
    else
        updateHud(run)
    end
end

addEventHandler("onAIPedWasted", root, function(killer)
    local run = pedRun[source]
    if run then pedDown(run, source, killer) end
end)

-- removed by someone else (ai_peds stopped, admin clear): never counts as a kill; a living attacker gone ends the
-- run without rewards
addEventHandler("onAIPedRemoved", root, function()
    local run = pedRun[source]
    if not run then return end
    local wasAlive = run.peds[source] == true
    pedRun[source] = nil
    run.peds[source] = nil
    if wasAlive and run.state ~= "cleanup" then close(run, "admin") end
    if run.state == "cleanup" and next(run.peds) == nil and Runs[run.gw.id] == run then Runs[run.gw.id] = nil end
end)

--------------------------------------------------------------------------------
-- 1 Hz: reservations, zone entry, distances
--------------------------------------------------------------------------------

local function tickRun(run, now)
    local gw, starter = run.gw, run.starter
    if run.state == "cleanup" then return end
    if not isElement(starter) then return close(run, "quit") end
    local dead = isPedDead(starter)
    if not dead then
        if not inWorldOf(starter, run) or playerDistance2(starter, gw) > gw.release_radius ^ 2 then
            return close(run, "left")
        end
    end
    if run.state == "reserved" then
        if not dead and playerDistance2(starter, gw) <= gw.zone_radius ^ 2 then
            spawn(run)
        elseif now - run.reservedAt > GW.RESERVE_TIMEOUT then
            close(run, "expired")
        end
        return
    end
    refreshViewers(run)
end

-- may the player take this gang war right now (also re-checked when the isRunning claim answers)
local function canReserve(player, gw, rt, ignoreRunning)
    if starterRun[player] or Runs[gw.id] or isPedDead(player) or getElementData(player, "isLogged") ~= true then return false end
    if gw.dimension ~= getElementDimension(player) or gw.interior ~= getElementInterior(player) then return false end
    local px, py = getElementPosition(player)
    return dist2(px, py, gw.x, gw.y) <= gw.trigger_radius ^ 2 and GangWars.isOpen(gw, rt, ignoreRunning)
end

-- the reservation starts only after isRunning was set to 1 in the database (no other server runs it)
local function claimAndReserve(gw, player)
    local id = gw.id
    claiming[id], claiming[player] = player, true
    GangWars.claim(id, function(ok)
        claiming[id] = nil
        if isElement(player) then claiming[player] = nil end
        if not ok then return end
        local cur = GangWars.get(id)
        -- the flag is ours now, so isOpen is checked without it
        if cur and isElement(player) and canReserve(player, cur, nil, true) and isPlayerArmed(player) then
            reserve(cur, player)
            return
        end
        GangWars.release(id)
    end)
end

local function tryReserve(player, rt)
    if starterRun[player] or claiming[player] or isPedDead(player) or getElementData(player, "isLogged") ~= true then return end
    local px, py = getElementPosition(player)
    local dim, int = getElementDimension(player), getElementInterior(player)
    local armed
    for id, gw in pairs(GangWars.list) do
        if not Runs[id] and not claiming[id] and gw.dimension == dim and gw.interior == int
            and dist2(px, py, gw.x, gw.y) <= gw.trigger_radius ^ 2 and GangWars.isOpen(gw, rt) then
            if armed == nil then armed = isPlayerArmed(player) end
            if not armed then return end
            claimAndReserve(gw, player)
            return
        end
    end
end

local function tick()
    if not GangWars.loaded then return end
    local now = getTickCount()
    for _, run in pairs(Runs) do tickRun(run, now) end
    local rt = getRealTime()
    for _, player in ipairs(getElementsByType("player")) do tryReserve(player, rt) end
end

--------------------------------------------------------------------------------
-- cleanup: closed runs lose their peds while no camera sees them
--------------------------------------------------------------------------------

local function cleanup()
    local canSee = resourceRunning("ai_peds")
    for id, run in pairs(Runs) do
        if run.state == "cleanup" then
            for ped in pairs(run.peds) do
                local remove = not isElement(ped)
                if not remove then
                    local x, y, z = getElementPosition(ped)
                    remove = not canSee or not ai:isPointSeenByPlayers(x, y, z + 1, GW.CLEANUP_SEE_DIST, getElementDimension(ped))
                end
                if remove then
                    run.peds[ped] = nil
                    pedRun[ped] = nil
                    if isElement(ped) and not (canSee and ai:destroyAIPed(ped)) then destroyElement(ped) end
                end
            end
            if next(run.peds) == nil and Runs[id] == run then Runs[id] = nil end
        end
    end
end

--------------------------------------------------------------------------------
-- other entry points
--------------------------------------------------------------------------------

addEventHandler("onPlayerQuit", root, function()
    claiming[source] = nil
    local run = starterRun[source]
    if run then close(run, "quit") end
    for _, r in pairs(Runs) do r.viewers[source] = nil end
end)

-- editor: start a test run for the admin in his private editor dimension (no cooldown / time / weapon check, no
-- last_run, no rewards)
function Runtime_testRun(gw, player, dimension)
    if Runs[gw.id] then return false, "busy" end
    if starterRun[player] then return false, "own_busy" end
    if #gw.attackers == 0 then return false, "no_attackers" end
    reserve(gw, player, true, dimension)
    return true
end

-- editor closed: the admin's test run (if any) ends
function Runtime_abortTestOf(player)
    local run = starterRun[player]
    if run and run.test then close(run, "admin") end
end

-- editor: the gang war changed or was deleted -> its run (if any) ends
function Runtime_abort(id, reason)
    local run = Runs[tonumber(id)]
    if run then close(run, reason or "admin") end
end

-- "remote": isRunning = 1 without a run here (another server runs it, or one crashed and left the flag set)
function Runtime_status(id)
    local run = Runs[tonumber(id)]
    if not run then
        local gw = GangWars.get(id)
        return (gw and gw.isRunning and not claiming[gw.id]) and "remote" or "idle"
    end
    return run.state, run.starter
end

addEventHandler("onResourceStart", resourceRoot, function()
    setTimer(tick, GW.TICK, 0)
    setTimer(cleanup, GW.CLEANUP_TICK, 0)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for _, run in pairs(Runs) do
        removeCircle(run)
        releaseClaim(run)
        for ped in pairs(run.peds) do
            if isElement(ped) then
                if not (resourceRunning("ai_peds") and ai:destroyAIPed(ped)) then destroyElement(ped) end
            end
        end
    end
end)
