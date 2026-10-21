if not MYSQL then loadstring(exports.v_mysql:importAsync())() end -- v_mysql async lib
-- ============================================================
--  v_admin / server/adminlog.lua
--  Every admin action (adminLog in server/core.lua) also goes into the
--  MySQL table ADMIN.log.table, shown on the Admin log page:
--    ts, admin (account), admin_name, source (game | web), level, action, target
-- ============================================================

ADMINLOG = {}

local TABLE = ADMIN.log.table
local ready = false

local function now() return getRealTime().timestamp end

local function ensure()
    if ready then return true end
    if not resourceRunning("v_mysql") or exports.v_mysql:mysqlIsConnected() ~= true then return false end
    exports.v_mysql:mysqlExec([[CREATE TABLE IF NOT EXISTS `]] .. TABLE .. [[` (
        `id`         INT AUTO_INCREMENT PRIMARY KEY,
        `ts`         INT          NOT NULL DEFAULT 0,
        `admin`      VARCHAR(64)  NOT NULL DEFAULT '',
        `admin_name` VARCHAR(64)  NOT NULL DEFAULT '',
        `source`     VARCHAR(8)   NOT NULL DEFAULT 'game',
        `level`      INT          NOT NULL DEFAULT 0,
        `action`     VARCHAR(255) NOT NULL DEFAULT '',
        `target`     VARCHAR(64)  NULL DEFAULT NULL,
        KEY `idx_ts` (`ts`),
        KEY `idx_admin` (`admin`),
        KEY `idx_target` (`target`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    ready = true
    return true
end

local function strip(s) return (tostring(s or ""):gsub("#%x%x%x%x%x%x", "")) end

local function cut(s, n)
    s = tostring(s or "")
    return utf8.sub(s, 1, n) or s:sub(1, n)
end

--- target = account name, player element or nil
function ADMINLOG.add(actor, text, target)
    if not ensure() then return end
    if isElement(target) then target = actorAccount(target) or strip(getPlayerName(target)) end
    local account = (isElement(actor) or isWebActor(actor)) and actorAccount(actor) or "console"
    local name = strip(isElement(actor) and getPlayerName(actor) or isWebActor(actor) and actor.name or "Console")
    -- no nil among the query arguments: an action without a target stores NULL literally
    local sql = "INSERT INTO `" .. TABLE .. "` (ts, admin, admin_name, source, level, action, target) VALUES (?,?,?,?,?,?,"
        .. (target and "?)" or "NULL)")
    if target then
        MYSQL.query(nil, sql, now(), cut(account, 64), cut(name, 64), isWebActor(actor) and "web" or "game",
            getAdminLevel(actor), cut(text, 255), cut(target, 64))
    else
        MYSQL.query(nil, sql, now(), cut(account, 64), cut(name, 64), isWebActor(actor) and "web" or "game",
            getAdminLevel(actor), cut(text, 255))
    end
end

--------------------------------------------------------------------------------
-- page: adminlog
--   list { page, admin, target, text } -> { rows, more, now }
--------------------------------------------------------------------------------

PAGES.register("adminlog", {
    perm = "adminLog",
    actions = {
        list = function(actor, args, reply)
            if not ensure() then return reply(false, L.msg("v_admin.page.database_error")) end
            local where, params = {}, {}
            for _, k in ipairs({ "admin", "target" }) do
                local v = argText(args[k])
                if v ~= "" then where[#where + 1] = k .. " LIKE ?"; params[#params + 1] = likeText(v) end
            end
            local text = argText(args.text)
            if text ~= "" then where[#where + 1] = "action LIKE ?"; params[#params + 1] = likeText(text) end
            local size = ADMIN.log.pageSize
            local page = math.max(0, math.floor(tonumber(args.page) or 0))
            params[#params + 1] = size + 1
            params[#params + 1] = page * size
            MYSQL.query(function(rows)
                if not rows then return reply(false, L.msg("v_admin.page.database_error")) end
                local out = {}
                for i = 1, math.min(#rows, size) do
                    local r = rows[i]
                    out[i] = { id = tonumber(r.id), ts = tonumber(r.ts), admin = r.admin, adminName = r.admin_name,
                               source = r.source, level = tonumber(r.level), action = r.action, target = r.target or false }
                end
                reply({ rows = out, more = #rows > size, page = page, now = now() })
            end, "SELECT * FROM `" .. TABLE .. "`" .. (#where > 0 and (" WHERE " .. table.concat(where, " AND ")) or "")
                .. " ORDER BY id DESC LIMIT ? OFFSET ?", unpack(params))
        end,
    },
})

addEvent("mysql:connected")
addEventHandler("mysql:connected", root, ensure)
addEventHandler("onResourceStart", resourceRoot, ensure)
