-- Blood Transport web page API. The functions are exported with http="true" (meta.xml) and called by
-- the page over HTTP (POST /bt_web/call/<function>) or through the web_api bridge in ui_browser.
-- Public: btPublic, btStock. Admin: btAdminLogin / btAdminLogout / btAdminQuery (v_accounts login,
-- the admin level is re-checked on every call). English only.

local DENIED = { ok = false, error = "unauthorized" }
local CACHE_MS = 2000

local function isRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function now() return getRealTime().timestamp end

---------------------------------------------------------------- public

local publicCache = { at = -1e9, data = nil }
local stockCache = { at = -1e9, data = nil }

local function institutions()
    local list = {}
    if isRunning("bt_core") then
        for _, i in ipairs(exports.bt_core:getInstitutions()) do
            list[#list + 1] = { id = i.id, name = i.name, kind = i.kind, city = i.city, x = i.x, y = i.y }
        end
    end
    return list
end

function btPublic()
    local t = getTickCount()
    if publicCache.data and t - publicCache.at < CACHE_MS then return publicCache.data end
    local s = isRunning("bt_dispatch") and exports.bt_dispatch:getPublicState() or { onDuty = 0, active = 0, completed = 0, units = {} }
    local data = { ok = true, time = now(), onDuty = s.onDuty, active = s.active, completed = s.completed,
        units = s.units, institutions = institutions() }
    publicCache = { at = t, data = data }
    return data
end

function btStock()
    local t = getTickCount()
    if stockCache.data and t - stockCache.at < CACHE_MS * 2 then return stockCache.data end
    local data = { ok = true, stock = isRunning("bt_stock") and exports.bt_stock:getAllStock() or {} }
    stockCache = { at = t, data = data }
    return data
end

---------------------------------------------------------------- admin

local ADMIN_LEVEL = 2
local SESSION_TIMEOUT = 10 * 60
local LEVEL_CACHE = 10
local MAX_FAILS, FAIL_WINDOW = 5, 60
local sessions, fails = {}, {}

local function adminLevelNeeded()
    if isRunning("bt_core") then return exports.bt_core:getConfig().ADMIN_LEVEL or ADMIN_LEVEL end
    return ADMIN_LEVEL
end

local function adminLevelOf(account)
    if isRunning("v_accounts") and isRunning("v_mysql") then
        for _, p in ipairs(getElementsByType("player")) do
            if exports.v_accounts:getName(p) == account then
                return tonumber(exports.v_mysql:getAccData(p, "admin_level")) or 0
            end
        end
        local rows = exports.v_mysql:mysqlQuerySync("SELECT admin_level FROM `accounts` WHERE account_name = ? LIMIT 1", account)
        return rows and rows[1] and tonumber(rows[1].admin_level) or 0
    end
    return 0
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
        tostring(getTickCount()), tostring(now()), account, tostring(math.random(1, 2 ^ 30)), tostring(math.random(1, 2 ^ 30)),
    }, ":"))
end

local function check(token)
    local s = type(token) == "string" and sessions[token]
    if not s then return nil end
    local t = now()
    if t - s.lastSeen > SESSION_TIMEOUT then sessions[token] = nil return nil end
    s.lastSeen = t
    if t - s.levelAt > LEVEL_CACHE then s.level, s.levelAt = adminLevelOf(s.account), t end
    if s.level < adminLevelNeeded() then sessions[token] = nil return nil end
    return s
end

setTimer(function()
    local t = now()
    for token, s in pairs(sessions) do
        if t - s.lastSeen > SESSION_TIMEOUT then sessions[token] = nil end
    end
end, 60000, 0)

function btAdminLogin(_, username, password)
    local id = exports.web_api:getCallerId(hostname)
    fails[id] = fails[id] or {}
    if tooManyFails(id) then return { ok = false, error = "Too many failed attempts. Try again in a minute." } end
    if not isRunning("v_accounts") then return { ok = false, error = "Account system is not available." } end
    local ok, account = exports.v_accounts:httpLogin(username, password)
    local level = ok and adminLevelOf(account) or 0
    local need = adminLevelNeeded()
    if not ok or level < need then
        table.insert(fails[id], now())
        outputServerLog("[bt_web] failed admin login from " .. tostring(id))
        return { ok = false, error = ok and ("You need admin level " .. need .. " or higher.") or account }
    end
    local token = newToken(account)
    sessions[token] = { account = account, lastSeen = now(), level = level, levelAt = now() }
    outputServerLog("[bt_web] admin login: " .. account .. " (" .. tostring(id) .. ")")
    return { ok = true, token = token, account = account, level = level }
end

function btAdminLogout(token)
    sessions[token] = nil
    return { ok = true }
end

-- kind: shifts | shift | tasks | task, params as the in-game /btadmin panel sends them
function btAdminQuery(token, kind, params)
    if not check(token) then return DENIED end
    if not isRunning("bt_dispatch") then return { ok = false, error = "Dispatch is not running." } end
    if kind ~= "shifts" and kind ~= "shift" and kind ~= "tasks" and kind ~= "task" then return { ok = false, error = "Unknown query." } end
    local ok, data = pcall(exports.bt_dispatch.adminQuery, exports.bt_dispatch, kind, type(params) == "table" and params or {})
    if not ok then
        outputDebugString("[bt_web] admin query " .. kind .. ": " .. tostring(data), 1)
        return { ok = false, error = "Query failed." }
    end
    return { ok = true, kind = kind, data = data }
end
