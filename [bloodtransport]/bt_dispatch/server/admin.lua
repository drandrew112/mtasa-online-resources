if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- /btadmin queries (shift and task history from bt_shifts / bt_tasks, v_mysql). Used by the in-game panel
-- (client/admin.lua, every call re-checks the admin level) and by the web admin of bt_web
-- (exports.bt_dispatch:adminQuery, the web side checks the level).

local PAGE = BTD.ADMIN_PAGE

local function like(s)
    return "%" .. tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("[%%_]", "") .. "%"
end

local function toSeconds(s)
    local Y, M, D, h, m, sec = tostring(s or ""):match("^(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
    if not Y then return nil end
    Y, M, D = tonumber(Y), tonumber(M), tonumber(D)
    if M <= 2 then Y = Y - 1 end
    local era = math.floor(Y / 400)
    local yoe = Y - era * 400
    local doy = math.floor((153 * ((M + 9) % 12) + 2) / 5) + D - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return (era * 146097 + doe - 719468) * 86400 + tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(sec)
end

local function duration(from, to)
    local a, b = toSeconds(from), toSeconds(to or DB.nowText())
    return (a and b) and math.max(0, b - a) or 0
end

local function paged(countSql, selectSql, where, args, page)
    local w = #where > 0 and (" WHERE " .. table.concat(where, " AND ")) or ""
    local countRows = DB.query(countSql .. w, unpack(args)) or {}
    local total = countRows[1] and tonumber(countRows[1].n) or 0
    local pages = math.max(1, math.ceil(total / PAGE))
    page = math.min(math.max(1, page), pages)
    local qa = { unpack(args) }
    qa[#qa + 1] = PAGE
    qa[#qa + 1] = (page - 1) * PAGE
    local rows = DB.query(selectSql .. w .. " ORDER BY id DESC LIMIT ? OFFSET ?", unpack(qa)) or {}
    return rows, total, page, pages
end

local SHIFT_COLS = "id, account, player, unit, started_at, ended_at, end_reason, delivered, in_transit, cancelled, pay, task_count"
local TASK_COLS = [[id, type, urgency, source, product, grp, units, from_inst, to_inst, status, shift_id, created_at, assigned_at,
    picked_at, delivered_at, cancelled_at, cancel_reason]]

-- "?,?,?" for n values
local function marks(n)
    return string.rep("?,", n - 1) .. "?"
end

local function taskRow(r)
    return {
        id = r.id, type = r.type, urgency = r.urgency or "", status = r.status, product = r.product or "", group = r.grp or "",
        units = tonumber(r.units) or 0, from = r.from_inst, to = r.to_inst, fromName = instName(r.from_inst), toName = instName(r.to_inst),
        source = r.source or "", createdAt = r.created_at or "", pickedAt = r.picked_at or "", deliveredAt = r.delivered_at or "",
        cancelledAt = r.cancelled_at or "", cancelReason = r.cancel_reason or "", shiftId = r.shift_id,
    }
end

local H = {}
AdminHandlers = H

-- pool rows (placeholders for new tasks / shifts, server/db.lua) are never listed
function H.shifts(p)
    local where, args = { "COALESCE(end_reason, '') != 'pool'" }, {}
    local search = tostring(p.search or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if search ~= "" then
        local l = like(search)
        where[#where + 1] = "(unit LIKE ? OR player LIKE ? OR account LIKE ?)"
        args = { l, l, l }
    end
    if p.filter == "active" then where[#where + 1] = "ended_at IS NULL"
    elseif p.filter == "ended" then where[#where + 1] = "ended_at IS NOT NULL" end
    local rows, total, page, pages = paged("SELECT COUNT(*) AS n FROM bt_shifts",
        "SELECT " .. SHIFT_COLS .. " FROM bt_shifts",
        where, args, tonumber(p.page) or 1)
    local list = {}
    for _, r in ipairs(rows) do
        list[#list + 1] = {
            id = r.id, unit = r.unit or "?", player = r.player or "?", account = r.account or "", startedAt = r.started_at or "",
            endedAt = r.ended_at or "", duration = duration(r.started_at, r.ended_at), tasks = tonumber(r.task_count) or 0,
            delivered = tonumber(r.delivered) or 0, inTransit = tonumber(r.in_transit) or 0, cancelled = tonumber(r.cancelled) or 0,
            pay = tonumber(r.pay) or 0, reason = r.end_reason or "", live = r.ended_at == nil,
        }
    end
    return { list = list, total = total, page = page, pages = pages }
end

function H.shift(p)
    local id = tonumber(p.id)
    local r = id and (DB.query("SELECT * FROM bt_shifts WHERE id = ? AND COALESCE(end_reason, '') != 'pool'", id) or {})[1]
    if not r then return { error = "not_found" } end
    local given, ids, byId = DB.assignments(r.tasks, "task"), {}, {}
    for _, a in ipairs(given) do
        if not byId[a.id] then ids[#ids + 1], byId[a.id] = a.id, {} end
    end
    if #ids > 0 then
        for _, t in ipairs(DB.query("SELECT id, type, urgency, status, product, grp, units, from_inst, to_inst FROM bt_tasks WHERE id IN ("
            .. marks(#ids) .. ")", unpack(ids)) or {}) do
            byId[tonumber(t.id)] = t
        end
    end
    local tasks = {}
    for _, a in ipairs(given) do
        local l = byId[a.id]
        tasks[#tasks + 1] = {
            id = a.id, type = l.type or "?", urgency = l.urgency or "", status = l.status or "?", product = l.product or "",
            group = l.grp or "", units = tonumber(l.units) or 0, fromName = instName(l.from_inst), toName = instName(l.to_inst),
            assignedAt = a.assignedAt or "", releasedAt = a.releasedAt or "", outcome = a.outcome or "",
        }
    end
    return {
        id = r.id, unit = r.unit or "?", player = r.player or "?", account = r.account or "", startedAt = r.started_at or "",
        endedAt = r.ended_at or "", duration = duration(r.started_at, r.ended_at), delivered = tonumber(r.delivered) or 0,
        inTransit = tonumber(r.in_transit) or 0, cancelled = tonumber(r.cancelled) or 0, pay = tonumber(r.pay) or 0,
        reason = r.end_reason or "", payItems = DB.unjson(r.pay_items), live = r.ended_at == nil, tasks = tasks,
    }
end

function H.tasks(p)
    local where, args = { "status != 'pool'" }, {}
    local search = tostring(p.search or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if search ~= "" then
        local l = like(search)
        local num = tonumber((search:gsub("^[Tt]%-", "")))
        where[#where + 1] = "(id = ? OR type LIKE ? OR product LIKE ? OR grp LIKE ? OR from_inst LIKE ? OR to_inst LIKE ? OR shift_id IN (SELECT id FROM bt_shifts WHERE unit LIKE ? OR player LIKE ?))"
        args = { num or -1, l, l, l, l, l, l, l }
    end
    if p.filter == "open" then where[#where + 1] = "status IN ('waiting','transit')"
    elseif p.filter == "closed" then where[#where + 1] = "status IN ('delivered','cancelled')" end
    local rows, total, page, pages = paged("SELECT COUNT(*) AS n FROM bt_tasks",
        "SELECT " .. TASK_COLS .. ", (SELECT unit FROM bt_shifts s WHERE s.id = bt_tasks.shift_id) AS unit, "
            .. "(SELECT player FROM bt_shifts s WHERE s.id = bt_tasks.shift_id) AS driver FROM bt_tasks",
        where, args, tonumber(p.page) or 1)
    local list = {}
    for _, r in ipairs(rows) do
        local t = taskRow(r)
        t.unit, t.driver = r.unit or "", r.driver or ""
        list[#list + 1] = t
    end
    return { list = list, total = total, page = page, pages = pages }
end

function H.task(p)
    local id = tonumber(p.id)
    local r = id and (DB.query("SELECT * FROM bt_tasks WHERE id = ? AND status != 'pool'", id) or {})[1]
    if not r then return { error = "not_found" } end
    local t = taskRow(r)
    t.log = {}
    for _, l in ipairs(DB.lines(r.log)) do
        t.log[#t.log + 1] = { at = l.at or "", event = l.event or "", info = l.info or "" }
    end
    local given, ids, byId = DB.assignments(r.shifts, "shift"), {}, {}
    for _, a in ipairs(given) do
        if not byId[a.id] then ids[#ids + 1], byId[a.id] = a.id, {} end
    end
    if #ids > 0 then
        for _, s in ipairs(DB.query("SELECT id, unit, player FROM bt_shifts WHERE id IN (" .. marks(#ids) .. ")", unpack(ids)) or {}) do
            byId[tonumber(s.id)] = s
        end
    end
    t.shifts = {}
    for _, a in ipairs(given) do
        local s = byId[a.id]
        t.shifts[#t.shifts + 1] = { shiftId = a.id, unit = s.unit or "?", player = s.player or "?",
            assignedAt = a.assignedAt or "", releasedAt = a.releasedAt or "", outcome = a.outcome or "" }
    end
    return t
end

-- Exported to bt_web: the caller has checked the admin level
function adminQuery(kind, params)
    local fn = H[kind]
    if not fn then return { error = "unknown query" } end
    return fn(type(params) == "table" and params or {})
end

-- ---------------------------------------------------------------------------------------------
-- In game: /btadmin
-- ---------------------------------------------------------------------------------------------

addEvent("btd:admin:query", true)
addEvent("btd:admin:open", true)

local function adminLevel(player)
    local res = getResourceFromName("v_mysql")
    if res and getResourceState(res) == "running" then
        return tonumber(exports.v_mysql:getAccData(player, "admin_level")) or 0
    end
    return tonumber(getElementData(player, "admin_level")) or 0
end

local function isAdmin(player)
    local c = BTC()
    return adminLevel(player) >= (c and c.ADMIN_LEVEL or 2)
end

addCommandHandler("btadmin", function(player)
    if not isAdmin(player) then
        return notify(player, L.msg("bt_dispatch.notify.title"), L.msg("bt_dispatch.err.no_admin"))
    end
    triggerClientEvent(player, "btd:admin:toggle", resourceRoot)
end)

addEventHandler("btd:admin:query", root, function(kind, params)
    local player = client
    if not isAdmin(player) then return end
    local fn = H[kind]
    if not fn then return end
    local data = fn(type(params) == "table" and params or {})
    triggerClientEvent(player, "btd:admin:result", resourceRoot, kind, data)
end)
