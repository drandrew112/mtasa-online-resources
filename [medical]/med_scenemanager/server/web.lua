-- Web console (web/index.html, http://<server>:<httpport>/med_scenemanager/): the browser
-- twin of /medscenesummon + /medscenelist + /medsceneclear. Login with the v_accounts account
-- (httpLogin); MSM.MIN_ADMIN_LEVEL is re-checked on every call. English only.

local SESSION_TIMEOUT = 15 * 60
local LEVEL_CACHE = 10          -- seconds an admin level lookup is reused
local MAX_FAILS, FAIL_WINDOW = 5, 60

local sessions = {}             -- [token] = { account, lastSeen, level, levelAt }
local fails = {}                -- [client] = { timestamps }
local DENIED = { ok = false, error = "unauthorized" }

local function now() return getRealTime().timestamp end

local function accountsRunning()
    local res = getResourceFromName("v_accounts")
    return res and getResourceState(res) == "running"
end

local function adminLevelOf(account)
    if accountsRunning() then
        for _, p in ipairs(getElementsByType("player")) do
            if exports.v_accounts:getName(p) == account then
                return tonumber(exports.v_mysql:getAccData(p, "admin_level")) or 0
            end
        end
    end
    local rows = exports.v_mysql:mysqlQuerySync("SELECT admin_level FROM `accounts` WHERE account_name = ? LIMIT 1", account)
    return rows and rows[1] and tonumber(rows[1].admin_level) or 0
end

local function callerId()
    return exports.web_api:getCallerId(hostname)
end

local function tooManyFails(id)
    local t, keep = now(), {}
    for _, ts in ipairs(fails[id] or {}) do
        if t - ts < FAIL_WINDOW then keep[#keep + 1] = ts end
    end
    fails[id] = keep
    return #keep >= MAX_FAILS
end

local function newToken(account)
    return hash("sha256", table.concat({
        tostring(getTickCount()), tostring(now()), account,
        tostring(math.random(1, 2 ^ 30)), tostring(math.random(1, 2 ^ 30)),
    }, ":"))
end

local function check(token)
    local s = type(token) == "string" and sessions[token]
    if not s then return nil end
    local t = now()
    if t - s.lastSeen > SESSION_TIMEOUT then
        sessions[token] = nil
        return nil
    end
    s.lastSeen = t
    if t - s.levelAt > LEVEL_CACHE then
        s.level, s.levelAt = adminLevelOf(s.account), t
    end
    if s.level < MSM.MIN_ADMIN_LEVEL then
        sessions[token] = nil
        return nil
    end
    return s
end

setTimer(function()
    local t = now()
    for token, s in pairs(sessions) do
        if t - s.lastSeen > SESSION_TIMEOUT then sessions[token] = nil end
    end
end, 60000, 0)

---------------------------------------------------------------- http exports

function msmWebLogin(_, username, password)
    local id = callerId()
    if tooManyFails(id) then return { ok = false, error = "Too many failed attempts. Try again in a minute." } end
    if not accountsRunning() then return { ok = false, error = "Account system is not available." } end

    local ok, account = exports.v_accounts:httpLogin(username, password)
    local level = ok and adminLevelOf(account) or 0
    if not ok or level < MSM.MIN_ADMIN_LEVEL then
        table.insert(fails[id], now())
        msmLog("failed web login from %s", id)
        return { ok = false, error = ok and ("You need admin level " .. MSM.MIN_ADMIN_LEVEL .. " or higher.") or account }
    end

    local token = newToken(account)
    sessions[token] = { account = account, lastSeen = now(), level = level, levelAt = now() }
    msmLog("web login: %s (%s)", account, id)
    return { ok = true, token = token, account = account, level = level }
end

function msmWebLogout(token)
    sessions[token] = nil
    return { ok = true }
end

-- every scene as a compact row (the browser filters them itself):
-- { name, location, category, title, priority, peds, vehicles, enabled, interior }
function msmWebScenes(token)
    if not check(token) then return DENIED end
    local rows = {}
    for _, s in ipairs(Storage.list()) do
        rows[#rows + 1] = {
            s.name, s.location or "", s.category or "", s.title or "", s.priority or 0,
            s.peds or 0, s.vehicles or 0, s.enabled ~= false, (s.interior or 0) ~= 0,
        }
    end
    return { ok = true, scenes = rows }
end

local function ermRunning()
    local res = getResourceFromName(MSM.ERM)
    return res and getResourceState(res) == "running"
end

-- live scenes + generator state; polled by the page
function msmWebState(token)
    if not check(token) then return DENIED end
    local out = { ok = true, time = now(), scenes = {}, erm = ermRunning() and true or false, free = 0, auto = Auto.enabled }
    if out.erm then
        for _, u in ipairs(exports[MSM.ERM]:getUnits() or {}) do
            if u.status == "available" then out.free = out.free + 1 end
        end
    end
    for _, scene in pairs(Live.scenes) do
        local pub = Live.public(scene)
        pub.title = Storage.summary[scene.name] and Storage.summary[scene.name].title or ""
        pub.ageSec = math.floor((getTickCount() - scene.createdAt) / 1000)
        pub.patients = scene.patients
        if scene.taskId and out.erm then
            local task = exports[MSM.ERM]:getTask(scene.taskId)
            if task then
                pub.taskStatus = task.status
                pub.units = type(task.units) == "table" and #task.units or 0
            end
        end
        out.scenes[#out.scenes + 1] = pub
    end
    table.sort(out.scenes, function(a, b) return a.id < b.id end)
    return out
end

function msmWebSpawn(token, name)
    local s = check(token)
    if not s then return DENIED end
    local id, err = Live.spawn(tostring(name), "web:" .. s.account)
    if not id then return { ok = false, error = tostring(err) } end
    return { ok = true, id = id, warning = err }
end

function msmWebRemove(token, id)
    local s = check(token)
    if not s then return DENIED end
    if id == "all" then
        local ids = {}
        for sid in pairs(Live.scenes) do ids[#ids + 1] = sid end
        for _, sid in ipairs(ids) do Live.remove(sid, "web: " .. s.account) end
        return { ok = true, removed = #ids }
    end
    if not Live.remove(tonumber(id), "web: " .. s.account) then
        return { ok = false, error = "Scene not found" }
    end
    return { ok = true, removed = 1 }
end

function msmWebAuto(token, on)
    local s = check(token)
    if not s then return DENIED end
    Auto.setEnabled(on == true, "web " .. s.account)
    return { ok = true, auto = Auto.enabled }
end
