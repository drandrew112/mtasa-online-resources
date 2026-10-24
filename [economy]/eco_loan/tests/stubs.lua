-- eco_loan tests: minimal MTA server environment (Lua 5.1 through lupa).
-- MySQL answers through TEST.db(sql, ...) / TEST.insertId; every write is recorded in TEST.execs,
-- every v_bank transfer in TEST.transfers (answer: TEST.bankAnswer(from, to, amount, key)).

TEST = { events = {}, fired = {}, data = {}, now = 1000000, execs = {}, transfers = {}, notes = {} }

local function el(kind, name) return { __el = true, kind = kind, name = name } end

resourceRoot = el("root", "resourceRoot")
root = el("root", "root")

function isElement(e) return type(e) == "table" and e.__el == true end
function getElementType(e) return e.kind end
TEST.players = {}
function getElementsByType(kind) return kind == "player" and TEST.players or {} end
function setElementData(e, k, v) TEST.data[e] = TEST.data[e] or {}; TEST.data[e][k] = v; return true end
function getElementData(e, k) return TEST.data[e] and TEST.data[e][k] end
function getRealTime() return { timestamp = TEST.now } end
function getTickCount() return 0 end
function setTimer() return {} end
function outputDebugString(s) TEST.log = (TEST.log or "") .. tostring(s) .. "\n" end
function addEvent() return true end
function addEventHandler(name, _, fn) TEST.events[name] = TEST.events[name] or {}; table.insert(TEST.events[name], fn) return true end
function triggerEvent(name, src, ...)
    table.insert(TEST.fired, { name = name, args = { ... } })
    for _, fn in ipairs(TEST.events[name] or {}) do source = src; fn(...) end
    return true
end
function triggerClientEvent(player, name, _, title, msg) table.insert(TEST.notes, { player = player, msg = msg }) return true end
function getResourceFromName(n) return { name = n } end
function getResourceState() return "running" end
function getResourceName(r) return r and r.name or "?" end

L = { msg = function(key, params) return { key = key, params = params } end }

TEST.bankAnswer = function() return true, "ref1" end
TEST.accounts = {}   -- id -> info

local EXP = {
    v_mysql = {
        importAsync = function()
            return "MYSQL = { query = function(cb, sql, ...) cb(TEST.db(sql, ...)) end, "
                .. "insert = function(cb, sql, ...) table.insert(TEST.execs, { sql = sql, args = { ... } }) cb(TEST.insertId) end }"
        end,
        mysqlExec = function(sql, ...) table.insert(TEST.execs, { sql = sql, args = { ... } }) return true end,
    },
    v_bank = {
        isBankReady = function() return true end,
        getPlayerAccount = function(p) return p.acc or false end,
        getCompanyAccount = function(id) return id == 3 and 30 or false end,
        getStateAccount = function(code) return code == "treasury" and 90 or false end,
        getAccountInfo = function(id) return TEST.accounts[id] or false end,
        transfer = function(from, to, amount, key, params)
            table.insert(TEST.transfers, { from = from, to = to, amount = amount, key = key, params = params })
            return TEST.bankAnswer(from, to, amount, key)
        end,
    },
    biz_core = {
        getCompany = function(id) return id == 3 and { name = "Acme" } or false end,
        isCompanyActive = function(id) return id == 3 end,
        getCompanyFounder = function() return false end,
    },
}
exports = setmetatable({}, { __index = function(_, res)
    local fns = EXP[res] or {}
    return setmetatable({}, { __index = function(_, fn)
        return function(_, ...) local f = fns[fn]; if f then return f(...) end end
    end })
end })

TEST.db = function() return {} end
TEST.insertId = 42

function TEST.player(name, acc)
    local p = el("player", name)
    p.acc = acc
    setElementData(p, "isLogged", true)
    setElementData(p, "accName", name)
    table.insert(TEST.players, p)
    return p
end

function TEST.reset()
    TEST.execs, TEST.transfers, TEST.fired, TEST.notes = {}, {}, {}, {}
    TEST.db = function() return {} end
    TEST.bankAnswer = function() return true, "ref1" end
end

--- the first recorded exec whose SQL contains the text
function TEST.exec(text)
    for _, e in ipairs(TEST.execs) do
        if e.sql:find(text, 1, true) then return e end
    end
    return nil
end

function TEST.firedEvent(name)
    for _, f in ipairs(TEST.fired) do if f.name == name then return f end end
    return nil
end

-- tiny assert lib
TEST.result = { pass = 0, fail = 0, lines = {} }
function TEST.check(name, cond, info)
    if cond then
        TEST.result.pass = TEST.result.pass + 1
    else
        TEST.result.fail = TEST.result.fail + 1
        table.insert(TEST.result.lines, "FAIL " .. name .. (info and (": " .. tostring(info)) or ""))
    end
end
