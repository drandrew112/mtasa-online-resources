-- police_system / modules/db/server/pool.lua
-- Id pools (the med_erm pattern): every table with an id keeps 2 placeholder rows per server instance
-- (is_pool = 1, server = instance). A new row = the lowest own pool id filled with an UPDATE (non-blocking, the id is
-- known at once), then a new placeholder is inserted asynchronously. An empty pool falls back to an async INSERT
-- (the id arrives in the callback). Rows left in a pool at a stop are taken back at the next start.

local P = { size = 2, pools = {} }
POL.db.pool = P

local function pool(tbl)
    local p = P.pools[tbl]
    if not p then p = { ids = {}, inflight = 0 }; P.pools[tbl] = p end
    return p
end

local function refill(tbl)
    local p = pool(tbl)
    for _ = 1, P.size - #p.ids - p.inflight do
        p.inflight = p.inflight + 1
        MYSQL.insert(function(id)
            p.inflight = p.inflight - 1
            if type(id) == "number" then
                p.ids[#p.ids + 1] = id
                table.sort(p.ids)
            end
        end, POL_POOL_TABLES[tbl], POL.db.instance())
    end
end

-- loads the existing pool rows of this instance, then tops every pool up; cb() when the loads answered
function P.load(cb)
    local left = 0
    for _ in pairs(POL_POOL_TABLES) do left = left + 1 end
    for tbl in pairs(POL_POOL_TABLES) do
        MYSQL.query(function(rows)
            local p = pool(tbl)
            p.ids = {}
            for _, r in ipairs(type(rows) == "table" and rows or {}) do p.ids[#p.ids + 1] = tonumber(r.id) end
            table.sort(p.ids)
            refill(tbl)
            left = left - 1
            if left == 0 and cb then cb() end
        end, "SELECT id FROM " .. tbl .. " WHERE is_pool = 1 AND server = ? ORDER BY id", POL.db.instance())
    end
end

-- new row: fields = { column = value, ... }; cb(id | false). With a pool id cb runs at once.
function P.create(tbl, fields, cb)
    local cols, vals = {}, {}
    for k, v in pairs(fields) do
        cols[#cols + 1] = k
        vals[#vals + 1] = v
    end
    local p = pool(tbl)
    local id = POL.db.ready and table.remove(p.ids, 1) or nil   -- sorted: the lowest
    refill(tbl)
    if id then
        local set = {}
        for i, c in ipairs(cols) do set[i] = "`" .. c .. "` = ?" end
        vals[#vals + 1] = id
        POL.db.exec("UPDATE " .. tbl .. " SET " .. table.concat(set, ", ") .. ", is_pool = 0 WHERE id = ?", unpack(vals))
        if cb then cb(id) end
        return id
    end
    local marks = {}
    for i, c in ipairs(cols) do cols[i] = "`" .. c .. "`"; marks[i] = "?" end
    cols[#cols + 1] = "server"
    marks[#marks + 1] = "?"
    vals[#vals + 1] = POL.db.instance()
    MYSQL.insert(function(newId)
        if cb then cb(type(newId) == "number" and newId or false) end
    end, "INSERT INTO " .. tbl .. " (" .. table.concat(cols, ", ") .. ") VALUES (" .. table.concat(marks, ", ") .. ")", unpack(vals))
    return nil
end

POL.db.create = P.create
