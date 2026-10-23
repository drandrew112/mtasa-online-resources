-- v_bank tests: minimal MTA server environment (Lua 5.1 through lupa).
-- Elements are tables; events run synchronously; MySQL answers through TEST.db(sql, ...),
-- every write is recorded in TEST.execs.

TEST = { events = {}, data = {}, now = 1000000, tick = 0, execs = {}, timers = {}, shown = {} }

local function el(kind, name) return { __el = true, kind = kind, name = name } end
TEST.el = el

resourceRoot = el("root", "resourceRoot")
root = el("root", "root")

function isElement(e) return type(e) == "table" and e.__el == true end
function getElementType(e) return e.kind end
function getPlayerName(p) return p.name end
TEST.players = {}
function getElementsByType(kind) return kind == "player" and TEST.players or {} end
function setElementData(e, k, v) TEST.data[e] = TEST.data[e] or {}; TEST.data[e][k] = v; return true end
function getElementData(e, k) return TEST.data[e] and TEST.data[e][k] end
function removeElementData(e, k) if TEST.data[e] then TEST.data[e][k] = nil end return true end
function getRealTime() return { timestamp = TEST.now } end
function getTickCount() return TEST.tick end
function setTimer() return {} end
function outputDebugString(s) TEST.log = (TEST.log or "") .. tostring(s) .. "\n" end
function outputServerLog() end
function addEvent() return true end
function addEventHandler(name, _, fn) TEST.events[name] = TEST.events[name] or {}; table.insert(TEST.events[name], fn) return true end
function triggerEvent(name, src, ...)
    for _, fn in ipairs(TEST.events[name] or {}) do source = src; fn(...) end
    return true
end
function triggerClientEvent() return true end
function getResourceFromName(n) return { name = n } end
function getResourceState() return "running" end
function getResourceName(r) return r and r.name or "?" end
function getPlayerMoney(p) return p.cash or 0 end
function takePlayerMoney(p, a) p.cash = (p.cash or 0) - a return true end
function givePlayerMoney(p, a) p.cash = (p.cash or 0) + a return true end

-- JSON: enough for the params of a ledger row
function toJSON(t)
    local parts = {}
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do parts[#parts + 1] = ('"%s": "%s"'):format(k, tostring(t[k])) end
    return "[ { " .. table.concat(parts, ", ") .. " } ]"
end
function fromJSON() return nil end

local EXP = {
    v_mysql = {
        importAsync = function() return "MYSQL = { query = function(cb, sql, ...) cb(TEST.db(sql, ...)) end }" end,
        mysqlExec = function(sql, ...) table.insert(TEST.execs, { sql = sql, args = { ... } }) return true end,
    },
    v_main = { getServerInstanceId = function() return 1 end },
    ui_core = { showMoney = function(p, kind, amount) table.insert(TEST.shown, { p = p, kind = kind, amount = amount }) end },
}
exports = setmetatable({}, { __index = function(_, res)
    local fns = EXP[res] or {}
    return setmetatable({}, { __index = function(_, fn)
        return function(_, ...) local f = fns[fn]; if f then return f(...) end end
    end })
end })

TEST.db = function() return {} end

function TEST.player(name)
    local p = el("player", name)
    setElementData(p, "isLogged", true)
    setElementData(p, "accName", name)
    table.insert(TEST.players, p)
    return p
end
