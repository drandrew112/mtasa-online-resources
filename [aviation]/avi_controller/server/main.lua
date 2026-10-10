-- ATC software, server side: positions (login / logout), static data for the scope (airspaces,
-- nav points, airports), traffic updates and controller clearances.
-- Data comes from avi_airspace / avi_nav / avi_airports / avi_traffic through exports; never keep
-- an exports table in a local (a restarted resource gets a new one).

local staff = {}        -- [posId] = player
local playerPos = {}    -- [player] = posId
local sessions = {}     -- [player] = { start = tick, actions = n } (one per logged-in position)
local lastSent = {}     -- [player] = tick of the last traffic update (radar refresh)

local function running(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function call(resName, fn, ...)
    if not running(resName) then return nil end
    local ok, a, b = pcall(function(...) return exports[resName][fn](exports[resName], ...) end, ...)
    if not ok then
        outputDebugString(("[avi_controller] %s:%s failed: %s"):format(resName, fn, tostring(a)), 2)
        return nil
    end
    return a, b
end

local function notify(player, text)
    triggerClientEvent(player, "avi:notify", root, "ATC", text)
end

local function playerName(p) return (getPlayerName(p):gsub("#%x%x%x%x%x%x", "")) end

-- ---------------------------------------------------------------- positions
function getPositions()
    local list = { { id = CTL.CENTER.id, type = "CTR", name = CTL.CENTER.name } }
    local airports = call("avi_airports", "getAirports") or {}
    local icaos = {}
    for icao in pairs(airports) do icaos[#icaos + 1] = icao end
    table.sort(icaos)
    for _, icao in ipairs(icaos) do
        local city = airports[icao].city or icao
        list[#list + 1] = { id = icao .. "_APP", type = "APP", airport = icao, name = city .. " " .. CTL.APP_SUFFIX }
        list[#list + 1] = { id = icao .. "_TWR", type = "TWR", airport = icao, name = city .. " " .. CTL.TWR_SUFFIX }
    end
    return list
end

local function positionById(id)
    for _, p in ipairs(getPositions()) do
        if p.id == id then return p end
    end
end

local function hasAccess(player)
    if not running("avi_core") then return true end
    return call("avi_core", "hasATCAccess", player) == true
end

-- may the player staff this position (tower / approach / radar rights of avi_core)
local function canStaff(player, pos)
    if not running("avi_core") then return true end
    return call("avi_core", "canStaffPosition", player, pos.type) == true
end

-- { [posId] = player name } (avi_traffic only checks the keys)
function getStaffedPositions()
    local out = {}
    for pos, p in pairs(staff) do
        if isElement(p) then out[pos] = playerName(p) end
    end
    return out
end

-- scope views reported by the controller clients (v_monitors mirrors them on the wall screens)
local views = {}    -- [posId] = { x, y, scale, sx, sy, showList, visible, off = { [id] = { dx, dy } } }

function getPositionViews()
    local out = {}
    for pos, v in pairs(views) do
        if staff[pos] and isElement(staff[pos]) then out[pos] = v end
    end
    return out
end

addEvent("avi:ctlView", true)
addEventHandler("avi:ctlView", resourceRoot, function(v)
    local pos = playerPos[client]
    if not pos or type(v) ~= "table" then return end
    views[pos] = {
        x = tonumber(v.x) or 0, y = tonumber(v.y) or 0, scale = tonumber(v.scale) or 0.1,
        sx = tonumber(v.sx) or 1920, sy = tonumber(v.sy) or 1080,
        showList = v.showList and true or false, visible = v.visible and true or false,
        off = type(v.off) == "table" and v.off or {},
    }
end)

function getPlayerATCPosition(player)
    return playerPos[player]
end

local function positionList(player)
    local list = {}
    for _, p in ipairs(getPositions()) do
      if canStaff(player, p) then   -- only the positions the player has the right for
        local who = staff[p.id]
        list[#list + 1] = { id = p.id, type = p.type, name = p.name, airport = p.airport,
            occupant = who and isElement(who) and playerName(who) or nil, mine = who == player,
            allowed = true }
      end
    end
    return list
end

-- everything the scope draws that does not move
local function staticData()
    local nav = call("avi_nav", "getNavData") or {}
    return {
        airspaces = call("avi_airspace", "getAirspaces") or {},
        nav = { fixes = nav.fixes or {}, ndbs = nav.ndbs or {}, vors = nav.vors or {}, procedures = nav.procedures or {} },
        airports = call("avi_airports", "getAirports") or {},
        runways = call("avi_airports", "getActiveRunways") or {},
        wind = call("avi_airports", "getWind") or { dir = 0, speed = 0 },
        positions = getPositions(),
        turnRate = call("avi_traffic", "getTurnRate") or 6,
    }
end

local function sendStatic(player)
    local pos = positionById(playerPos[player])
    if not pos then return end
    triggerLatentClientEvent(player, "avi:ctlData", resourceRoot, pos, staticData())
end

local function broadcastStatic()
    for player in pairs(playerPos) do sendStatic(player) end
end

-- pay for the finished position session: actions * rate, multiplied by the time spent, minus the
-- mistakes (separation losses). Mistakes are always paid for: a negative total comes from the bank.
local function paySession(player, sess)
    if not sess then return end
    local items = {}
    if sess.actions >= CTL.PAY_MIN_ACTIONS then
        local minutes = (getTickCount() - sess.start) / 60000
        local mult = math.min(1 + minutes * CTL.PAY_MINUTE_BONUS, CTL.PAY_MAX_MULT)
        local base = sess.actions * CTL.PAY_PER_ACTION
        local bonus = math.floor(base * mult + 0.5) - base
        items[#items + 1] = { label = ("Traffic actions (%d)"):format(sess.actions), amount = base }
        if bonus > 0 then
            items[#items + 1] = { label = ("Time on position (%d min)"):format(math.floor(minutes)), amount = bonus }
        end
    end
    if sess.mistakes > 0 then
        items[#items + 1] = { label = ("Mistakes (%d)"):format(sess.mistakeCount), amount = -sess.mistakes }
    end
    if #items == 0 then return end
    local ok, total = call("work_core", "payWork", player, CTL.WORK_ID, items, "Position closed")
    -- payWork pays only a positive total; the rest of the fines is taken here (may go into debt)
    if ok and total and total < 0 then call("v_bank", "forceTakeMoney", player, -total) end
end

function logoutATC(player, silent)
    local pos = playerPos[player]
    if not pos then return false end
    playerPos[player] = nil
    local sess = sessions[player]
    sessions[player] = nil
    paySession(player, sess)
    if staff[pos] == player then staff[pos] = nil; views[pos] = nil end
    if isElement(player) then
        triggerClientEvent(player, "avi:ctlClosed", resourceRoot)
        if not silent then notify(player, "Logged out from " .. pos) end
    end
    triggerEvent("onATCPositionChange", resourceRoot, pos, nil, player)
    return true
end

local function login(player, posId)
    if not hasAccess(player) then
        notify(player, "You do not have any ATC rights.")
        return false
    end
    local pos = positionById(posId)
    if not pos then
        notify(player, "Unknown position " .. tostring(posId))
        return false
    end
    if not canStaff(player, pos) then
        notify(player, "You do not have the right for " .. pos.id .. ".")
        return false
    end
    local who = staff[pos.id]
    if who and who ~= player and isElement(who) then
        notify(player, pos.id .. " is staffed by " .. playerName(who))
        return false
    end
    if playerPos[player] and playerPos[player] ~= pos.id then logoutATC(player, true) end
    staff[pos.id] = player
    playerPos[player] = pos.id
    sessions[player] = { start = getTickCount(), actions = 0, mistakes = 0, mistakeCount = 0 }
    lastSent[player] = nil     -- the first traffic update goes out at the next check
    sendStatic(player)
    notify(player, "Logged in as " .. pos.id .. " (" .. pos.name .. ")")
    triggerEvent("onATCPositionChange", resourceRoot, pos.id, player)
    return true
end

-- opens the login window on the player's screen (work_atc can call it)
function openATCLogin(player)
    if not isElement(player) then return false end
    if not hasAccess(player) then
        notify(player, "You do not have any ATC rights.")
        return false
    end
    triggerClientEvent(player, "avi:ctlPositions", resourceRoot, positionList(player), playerPos[player])
    return true
end

addEvent("onATCPositionChange")     -- source: resourceRoot, args: posId, player|nil, oldPlayer|nil

addEvent("avi:ctlOpen", true)
addEventHandler("avi:ctlOpen", resourceRoot, function()
    openATCLogin(client)
end)

addEvent("avi:ctlLogin", true)
addEventHandler("avi:ctlLogin", resourceRoot, function(posId)
    login(client, posId)
end)

addEvent("avi:ctlLogout", true)
addEventHandler("avi:ctlLogout", resourceRoot, function()
    logoutATC(client)
end)

addEvent("avi:ctlCmd", true)
addEventHandler("avi:ctlCmd", resourceRoot, function(action, id, value)
    local player = client
    local pos = playerPos[player]
    if not pos then return end
    local cur = positionById(pos)
    if not hasAccess(player) or not cur or not canStaff(player, cur) then
        logoutATC(player)
        return
    end
    local ctl = call("avi_traffic", "getAircraftController", id)
    if ctl ~= pos then
        notify(player, "That aircraft is not under your control" .. (ctl and (" (" .. ctl .. ")") or ""))
        return
    end
    local ok, err
    if action == "cfl" then
        ok, err = call("avi_traffic", "setClearedAltitude", id, value)
    elseif action == "dct" then
        ok, err = call("avi_traffic", "setDirectTo", id, value)
    elseif action == "nodct" then
        ok, err = call("avi_traffic", "clearDirectTo", id)
    elseif action == "hdg" then
        -- value = heading, or { hdg = heading, dir = "L" / "R" / nil }
        if type(value) == "table" then
            ok, err = call("avi_traffic", "setHeading", id, value.hdg, value.dir)
        else
            ok, err = call("avi_traffic", "setHeading", id, value)
        end
    elseif action == "nohdg" then
        ok, err = call("avi_traffic", "clearHeading", id)
    elseif action == "star" then
        -- arrival procedures: approach and the centre (radar)
        if cur.type ~= "APP" and cur.type ~= "CTR" then
            notify(player, "Arrival procedures are given by approach / radar")
            return
        end
        ok, err = call("avi_traffic", "setArrivalProcedure", id, value)
    elseif action == "xfer" then
        ok, err = call("avi_traffic", "transferAircraft", id, value)
    elseif action == "approach" then
        -- cleared approach: whoever controls the arrival (APP / centre / tower)
        ok, err = call("avi_traffic", "giveClearance", id, "approach")
    elseif action == "ifr" or action == "push" or action == "taxi" or action == "takeoff" or action == "land"
            or action == "cross" or action == "lineup" or action == "backtrack" or action == "vacate" or action == "goaround" then
        -- delivery / ground / runway clearances belong to the tower (no top-down cover)
        if action ~= "goaround" and cur.type ~= "TWR" then
            notify(player, "That clearance is given by the tower")
            return
        end
        ok, err = call("avi_traffic", "giveClearance", id, action, value)
    end
    if not ok then
        notify(player, "Not accepted: " .. tostring(err or "no answer"))
        return
    end
    local sess = sessions[player]
    if sess then sess.actions = sess.actions + 1 end
    call("work_core", "giveWorkXp", player, CTL.WORK_ID, CTL.XP_ACTIONS[action] or CTL.XP_DEFAULT)
end)

-- separation loss on aircraft of these positions (avi_traffic): a mistake for each staffing controller
local SEP_TEXT = { GND = "head-on on the ground", TMA = "separation lost in the TMA", CTA = "separation lost in the CTA" }

addEvent("onAviSeparationLoss")
addEventHandler("onAviSeparationLoss", root, function(kind, positions, cs1, cs2)
    local amount = CTL.PENALTY[kind]
    if not amount or type(positions) ~= "table" then return end
    for _, posId in ipairs(positions) do
        local player = staff[posId]
        local sess = player and isElement(player) and sessions[player]
        if sess then
            sess.mistakes = sess.mistakes + amount
            sess.mistakeCount = sess.mistakeCount + 1
            notify(player, ("STCA %s / %s: %s (-€%d)"):format(tostring(cs1), tostring(cs2), SEP_TEXT[kind] or kind, amount))
        end
    end
end)

addEventHandler("onPlayerQuit", root, function()
    logoutATC(source, true)
    lastSent[source] = nil
end)

-- a right was taken away: log out when it was the one of the current position
addEvent("onPlayerATCChange")
addEventHandler("onPlayerATCChange", root, function(right, enabled)
    if enabled then return end
    local cur = playerPos[source] and positionById(playerPos[source])
    if cur and not canStaff(source, cur) then logoutATC(source) end
end)

-- The ATC marker of avi_core calls this: login window (or the scope toggle when logged in).
-- There is no /atc command any more.
function useATCConsole(player)
    if not isElement(player) then return false end
    if playerPos[player] then
        triggerClientEvent(player, "avi:ctlToggle", resourceRoot)
        return true
    end
    return openATCLogin(player)
end

-- ---------------------------------------------------------------- updates
-- Every position gets its traffic at its own radar refresh (CTL.UPDATE_MS: TWR 1 s, APP 2 s,
-- radar 3 s). Tower sees only the traffic of its airport (departing / arriving / on its ground)
-- and what it controls. Approach sees the same, plus the aircraft that are in its TMA / CTR or
-- will cross it: their remaining route (heading or direct included) passes through it while they
-- are below its ceiling (e.g. a low LS departure toward the north-west through the SF TMA).
-- The radar (centre) sees every aircraft.
local function pointIn(x, y, poly)
    local inside, j = false, #poly
    for i = 1, #poly do
        local xi, yi, xj, yj = poly[i][1], poly[i][2], poly[j][1], poly[j][2]
        if (yi > y) ~= (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi then inside = not inside end
        j = i
    end
    return inside
end

local function segCross(ax, ay, bx, by, cx, cy, dx, dy)
    local function side(px, py, qx, qy, rx, ry) return (qx - px) * (ry - py) - (qy - py) * (rx - px) end
    local d1, d2 = side(cx, cy, dx, dy, ax, ay), side(cx, cy, dx, dy, bx, by)
    local d3, d4 = side(ax, ay, bx, by, cx, cy), side(ax, ay, bx, by, dx, dy)
    return ((d1 > 0) ~= (d2 > 0)) and ((d3 > 0) ~= (d4 > 0))
end

local function segmentInPoly(ax, ay, bx, by, poly)
    if pointIn(ax, ay, poly) or pointIn(bx, by, poly) then return true end
    local j = #poly
    for i = 1, #poly do
        if segCross(ax, ay, bx, by, poly[j][1], poly[j][2], poly[i][1], poly[i][2]) then return true end
        j = i
    end
    return false
end

-- the path still ahead of the aircraft: position -> heading leg | direct -> remaining route
local function pathOf(s, nav)
    local pts = { { s.x, s.y } }
    if s.ahdg then
        local h = math.rad(s.ahdg)
        pts[2] = { s.x + math.sin(h) * CTL.APP_HEADING_LOOKAHEAD, s.y + math.cos(h) * CTL.APP_HEADING_LOOKAHEAD }
        return pts
    end
    local p = s.dct and nav[s.dct]
    if p then pts[#pts + 1] = { p.x, p.y } end
    for _, id in ipairs(s.route or {}) do
        p = nav[id]
        if p then pts[#pts + 1] = { p.x, p.y } end
    end
    return pts
end

-- airspaces of the approach sectors (TMA + CTR of the airport), nav points by id
local function sectorData()
    local sectors = {}
    for _, a in ipairs(call("avi_airspace", "getAirspaces") or {}) do
        if a.airport and (a.type == "TMA" or a.type == "CTR") and type(a.polygon) == "table" and #a.polygon >= 3 then
            local t = sectors[a.airport] or {}
            sectors[a.airport] = t
            t[#t + 1] = a
        end
    end
    local nav = {}
    for _, p in ipairs(call("avi_nav", "getNavPoints") or {}) do nav[p.id] = p end
    return sectors, nav
end

local function crossesSector(s, areas, nav)
    if s.gnd or not areas then return false end
    local path
    for _, a in ipairs(areas) do
        -- low enough to be in it: the current or the cleared level below the ceiling
        local low = math.min(s.alt or 0, s.cfl or s.alt or 0)
        if low <= (a.ceiling or 99999) then
            path = path or pathOf(s, nav)
            if #path == 1 then
                if pointIn(path[1][1], path[1][2], a.polygon) then return true end
            else
                for i = 1, #path - 1 do
                    if segmentInPoly(path[i][1], path[i][2], path[i + 1][1], path[i + 1][2], a.polygon) then return true end
                end
            end
        end
    end
    return false
end

local function visibleTo(pos, s, sectors, nav)
    if pos.type == "CTR" or not pos.airport then return true end
    local icao = pos.airport
    if s.ctl == pos.id or s.dep == icao or s.arr == icao or s.apt == icao then return true end
    return pos.type == "APP" and crossesSector(s, sectors[icao], nav)
end

local function sendTraffic()
    local now = getTickCount()
    local due = {}
    for p, posId in pairs(playerPos) do
        local pos = isElement(p) and positionById(posId)
        local every = pos and (CTL.UPDATE_MS[pos.type] or 1000)
        if every and now - (lastSent[p] or 0) >= every - CTL.UPDATE_TICK_MS / 2 then
            due[#due + 1] = { p = p, pos = pos }
        end
    end
    if #due == 0 then return end
    local all = call("avi_traffic", "getTrafficSnapshot") or {}
    local staffed = getStaffedPositions()
    local sectors, nav = {}, {}
    for _, d in ipairs(due) do
        if d.pos.type == "APP" then sectors, nav = sectorData(); break end
    end
    for _, d in ipairs(due) do
        local list = {}
        for _, s in ipairs(all) do
            if visibleTo(d.pos, s, sectors, nav) then list[#list + 1] = s end
        end
        lastSent[d.p] = now
        triggerClientEvent(d.p, "avi:ctlTraffic", resourceRoot, list, staffed)
    end
end

addEventHandler("onResourceStart", resourceRoot, function()
    setTimer(sendTraffic, CTL.UPDATE_TICK_MS, 0)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for p in pairs(playerPos) do
        if isElement(p) then triggerClientEvent(p, "avi:ctlClosed", resourceRoot) end
    end
end)

-- data changes -> everyone logged in gets the new static data
addEvent("onAviNavChange")
addEventHandler("onAviNavChange", root, broadcastStatic)

addEvent("onAviRunwayChange")
addEventHandler("onAviRunwayChange", root, function()
    local runways = call("avi_airports", "getActiveRunways") or {}
    local wind = call("avi_airports", "getWind")
    for p in pairs(playerPos) do
        if isElement(p) then triggerClientEvent(p, "avi:ctlRunways", resourceRoot, runways, wind) end
    end
end)

addEventHandler("onResourceStart", root, function(res)
    local name = getResourceName(res)
    if name == "avi_airspace" or name == "avi_nav" or name == "avi_airports" then
        setTimer(broadcastStatic, 500, 1)
    end
end)
