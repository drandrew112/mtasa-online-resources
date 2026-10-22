-- biz_core tests: minimal MTA server environment (Lua 5.1 through lupa).
-- Elements are tables; events run synchronously; MySQL is answered by
-- TEST.db(sql, ...) which tests replace.

TEST = { events = {}, data = {}, now = 1000000, tick = 0, sent = {}, execs = {}, notifies = {}, bank = {}, timers = {} }

utf8 = utf8 or { len = function(s) return #s end }

local function el(kind, name)
    return { __el = true, kind = kind, name = name }
end
TEST.el = el

resourceRoot = el("root", "resourceRoot")
root = el("root", "root")
resource = el("resource", "biz_core")

function isElement(e) return type(e) == "table" and e.__el == true and not e.destroyed end
function getElementType(e) return e.kind end
function getPlayerName(p) return p.name end
function getPlayerSerial(p) return p.serial or ("S" .. p.name) end
function getPlayerIP(p) return p.ip or ("IP" .. p.name) end
function getElementPosition(e) return e.x or 0, e.y or 0, e.z or 0 end
function getDistanceBetweenPoints3D(a, b, c, d, e, f) return math.sqrt((a - d) ^ 2 + (b - e) ^ 2 + (c - f) ^ 2) end

TEST.players = {}
function getElementsByType(kind)
    if kind == "player" then return TEST.players end
    return {}
end

function setElementData(e, k, v) TEST.data[e] = TEST.data[e] or {}; TEST.data[e][k] = v; return true end
function getElementData(e, k) return TEST.data[e] and TEST.data[e][k] end
function removeElementData(e, k) if TEST.data[e] then TEST.data[e][k] = nil end return true end

function getRealTime() return { timestamp = TEST.now, hour = 12 } end
function getTickCount() return TEST.tick end
function setTimer(fn, ms, times, ...) local t = { fn = fn, ms = ms, times = times, args = { ... } }; TEST.timers[t] = true; return t end
function killTimer(t) TEST.timers[t] = nil return true end
function isTimer(t) return t ~= nil and TEST.timers[t] == true end
function outputDebugString(s) TEST.log = (TEST.log or "") .. tostring(s) .. "\n" end

function addEvent() return true end
function addEventHandler(name, attached, fn) TEST.events[name] = TEST.events[name] or {}; table.insert(TEST.events[name], fn) return true end
function triggerEvent(name, src, ...)
    for _, fn in ipairs(TEST.events[name] or {}) do
        source = src
        fn(...)
    end
    return true
end
function triggerClientEvent(player, name, _, title, msg)
    if name == "biz_core:notify" then table.insert(TEST.notifies, { player = player, msg = msg }) end
    return true
end
function fromJSON() return nil end
function toJSON() return "[]" end

function getResourceFromName(n) return { name = n } end
function getResourceState() return "running" end
function getResourceName(r) return r and r.name or "?" end
function getResourceRootElement(r) return el("root", r.name) end
function call() return 0 end

-- exports.<res>:fn(...)
local EXP = {
    v_locals = { import = function() return "L = setmetatable({}, { __call = function(_, k) return k end }); L.msg = function(k, p) return { t = k, p = p } end; L.text = L.msg" end },
    v_mysql = {
        importAsync = function() return "MYSQL = { query = function(cb, sql, ...) cb(TEST.db(sql, ...)) end, insert = function(cb, sql, ...) cb(TEST.insert(sql, ...)) end }" end,
        mysqlExec = function(sql, ...) table.insert(TEST.execs, { sql = sql, args = { ... } }) return true end,
        getAccData = function() return 0 end, setAccData = function() return true end,
    },
    acc_auth = { getName = function(p) return p.account end },
    v_bank = {
        takeBankMoney = function(p, a) local b = TEST.bank[p] or 0; if b < a then return "not_enough_money" end TEST.bank[p] = b - a return true end,
        giveBankMoney = function(p, a) TEST.bank[p] = (TEST.bank[p] or 0) + a return true end,
    },
    v_stats = { addStat = function() return true end },
    v_achievements = { unlockAchievement = function() return true end, setStat = function() return true end },
}
exports = setmetatable({}, { __index = function(_, res)
    local fns = EXP[res] or {}
    return setmetatable({}, { __index = function(_, fn)
        return function(_, ...) local f = fns[fn]; if f then return f(...) end end
    end })
end })

TEST.db = function() return {} end
local nextId = 100
TEST.insert = function() nextId = nextId + 1 return nextId end

function TEST.player(name, account)
    local p = el("player", name)
    p.account = account
    table.insert(TEST.players, p)
    return p
end

function TEST.quit(p)
    for i, x in ipairs(TEST.players) do if x == p then table.remove(TEST.players, i) end end
    triggerEvent("onPlayerQuit", p)
    p.destroyed = true
end
