-- pt_web :: server/api.lua
-- The http="true" exports of the pages (POST /pt_web/call/<fn>; in game relayed by web_api).
-- Read-only and public, no login. The in-game ui_browser site is registered at the bottom.

local function fail(msg) return { ok = false, error = msg } end

---------------------------------------------------------------- site / planner (index.html)

-- operators, every stop, the lines and what is coming
function ptGetSite()
    local now = Util.now()
    return {
        ok = true, title = PT.TITLE, time = now, sec = Util.secOfDay(now),
        providers = Providers.info(), stops = Providers.stops(), lines = Providers.lines(),
        comingSoon = PT.COMING_SOON,
    }
end

-- "HH:MM" today (a time more than 30 min ago means tomorrow), a timestamp, or nil = now
local function parseWhen(when)
    local now = Util.now()
    if type(when) == "number" and when > 86400 then return math.floor(when) end
    if type(when) == "string" then
        local h, m = when:match("^%s*(%d%d?):(%d%d)%s*$")
        h, m = tonumber(h), tonumber(m)
        if h and m and h < 24 and m < 60 then
            local t = Util.dayStart(now) + h * 3600 + m * 60
            if t < now - 1800 then t = t + 86400 end
            return t
        end
    end
    return now
end

-- per caller: at most PLAN_LIMIT searches in PLAN_WINDOW ms
local PLAN_LIMIT, PLAN_WINDOW = 12, 10000
local planLog = {}
setTimer(function()            -- forget idle callers
    local tick = getTickCount()
    for k, v in pairs(planLog) do if tick - v.at > PLAN_WINDOW then planLog[k] = nil end end
end, 60000, 0)

function ptPlan(from, to, when)
    if type(from) ~= "string" or type(to) ~= "string" then return fail("Choose a departure and a destination stop.") end
    local caller = Util.call("web_api", "getCallerId", hostname) or "web"
    local tick = getTickCount()
    local log = planLog[caller]
    if not log or tick - log.at > PLAN_WINDOW then
        log = { at = tick, n = 0 }
        planLog[caller] = log
    end
    log.n = log.n + 1
    if log.n > PLAN_LIMIT then return fail("Too many searches, try again in a few seconds.") end

    local ok, result, err = pcall(Planner.search, from, to, parseWhen(when))
    if not ok then
        outputDebugString("pt_web: planner error: " .. tostring(result), 1)
        return fail("Server error while planning.")
    end
    if not result then return fail(err) end
    result.ok = true
    result.time = Util.now()
    return result
end

-- departure / arrival board of one stop (global id)
function ptGetBoard(stopId)
    local b = Providers.board(stopId, PT.BOARD_ROWS)
    if not b then return fail("No board for this stop.") end
    return { ok = true, board = b, time = Util.now() }
end

-- the "become a railway worker" section
function ptGetCareers()
    local rail = Util.call("work_traindriver", "getTrainDriverInfo")
    return {
        ok = true,
        rail = rail and Util.text(rail) or false,
        railwayRoleRequired = Util.call("rw_core", "isRailwayRoleRequired") ~= false,
    }
end

---------------------------------------------------------------- live railway map (map.html)

function ptRailNetwork() return RailMap.network() end
function ptRailState()   return RailMap.state() end
function ptRailBoards()  return RailMap.boards(PT.BOARD_ROWS) end

---------------------------------------------------------------- in-game site

local function registerSite()
    if not Util.running("web_api") then return end
    exports.web_api:registerApp({
        title       = PT.TITLE,
        site        = PT.SITE,
        category    = "services",
        description = PT.TITLE .. " - journey planner, departures and the live map of trains (buses soon).",
        page        = "web/index.html",
    })
end
addEventHandler("onResourceStart", resourceRoot, registerSite)
addEventHandler("onWebApiStart", root, registerSite)
