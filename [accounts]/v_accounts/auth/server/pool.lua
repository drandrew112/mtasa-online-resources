if not MYSQL then loadstring(exports.v_mysql:importAsync())() end -- v_mysql async lib
-- Account pool: registrations take an `accounts` row reserved in advance
-- instead of inserting one, so the AUTO_INCREMENT ids stay without gaps.
--
-- A failed INSERT (duplicate name or email, a race between two servers) still
-- burns an id in InnoDB; a failed UPDATE does not. So every server instance keeps
-- POOL_SIZE (at most 2) empty rows named "#<instance id>.<slot>", loads them at
-- start and fills a slot again as soon as a registration used it. Filling is a
-- plain INSERT of a name only this instance uses, so it never fails on a
-- duplicate and never wastes an id.
--
-- Pool rows have no password (no login can match) and no email; names starting
-- with "#" are not valid account names (register.lua), and the account lists
-- (getAllAccountNames, v_admin, v_socialpanel) leave them out.

local TABLE  = "accounts"
local SIZE   = math.max(0, math.min(2, math.floor(tonumber(AUTH.POOL_SIZE) or 2)))
local RETRY  = 10000 -- ms between two start attempts while v_main / MySQL are not up
local TRIES  = 60

local slots    = {}  -- [i] = { name, id = row id | false, busy = bool, gen }
local poolGen  = 0   -- bumped on every (re)load: answers of an older load are dropped
local retryTimer

-- The pool row names: "#" .. instance id .. "." .. slot
function isPoolAccountName(name)
    return type(name) == "string" and name:sub(1, 1) == "#"
end

-- Looks up (or creates) the reserved row of a slot. The slot is busy meanwhile.
local function fillSlot(s)
    s.id, s.busy = false, true
    MYSQL.query(function(rows)
        if s.gen ~= poolGen then return end
        if rows == false then
            s.busy = false
            return outputServerLog(("[v_accounts] pool: could not read slot %s"):format(s.name))
        end
        if rows[1] then
            s.id, s.busy = tonumber(rows[1].id) or false, false
            return
        end
        MYSQL.insert(function(id, err)
            if s.gen ~= poolGen then return end
            s.busy = false
            if type(id) == "number" then
                s.id = id
            else
                outputServerLog(("[v_accounts] pool: could not reserve slot %s: %s"):format(s.name, tostring(err)))
            end
        end, "INSERT INTO `" .. TABLE .. "` "
            .. "(account_name, password, email, display_name, admin_level, account_data, created_at, updated_at) "
            .. "VALUES (?, NULL, NULL, NULL, 0, '{}', 0, 0)", s.name)
    end, "SELECT id FROM `" .. TABLE .. "` WHERE account_name = ? LIMIT 1", s.name)
end

local function loadPool(tries)
    if isTimer(retryTimer) then killTimer(retryTimer) end
    retryTimer = nil
    poolGen = poolGen + 1
    slots = {}
    if SIZE == 0 then return end

    local inst = serverInstanceId()
    local ready = inst > 0 and resourceRunning("v_mysql") and exports.v_mysql:mysqlIsConnected() == true
    if not ready then
        tries = (tries or 0) + 1
        if tries < TRIES then
            retryTimer = setTimer(function() loadPool(tries) end, RETRY, 1)
        else
            outputServerLog("[v_accounts] pool: no server instance id or MySQL, registrations insert directly")
        end
        return
    end

    for i = 1, SIZE do
        slots[i] = { name = ("#%d.%d"):format(inst, i), id = false, busy = false, gen = poolGen }
        fillSlot(slots[i])
    end
end

addEventHandler("onResourceStart", resourceRoot, function() loadPool() end)

-- v_main gives the instance id, v_mysql the rows: start again when either restarts
addEventHandler("onResourceStart", root, function(res)
    local name = getResourceName(res)
    if name == "v_main" or name == "v_mysql" then loadPool() end
end)

-- Same contract as createAccountRowAsync (db.lua): the answer is
--   triggerEvent(eventName, resourceRoot, requestId, id | false, err)
-- Takes a free pool row when there is one, else inserts a new row.
-- -> true if the answer is coming
function createAccountRowPooled(name, pwHash, email, eventName, requestId)
    local s
    for _, slot in ipairs(slots) do
        if slot.id and not slot.busy then s = slot break end
    end
    if not s then return createAccountRowAsync(name, pwHash, email, eventName, requestId) end

    s.busy = true
    local rowId, gen, ts = s.id, s.gen, getRealTime().timestamp
    local function answer(id, err) triggerEvent(eventName, resourceRoot, requestId, id, err) end
    local function refill() if gen == poolGen then fillSlot(s) end end

    -- id = LAST_INSERT_ID(id) makes MySQL report the claimed row's id; no match = no id
    MYSQL.insert(function(res, err)
        if res == false then
            -- duplicate name / email: the pool row is untouched and stays free
            if gen == poolGen then s.busy = false end
            return answer(false, err)
        end
        if type(res) == "number" then
            refill()
            return answer(res)
        end
        -- no id reported: either the pool row was gone, or the driver did not pass
        -- the id on - the account row decides
        MYSQL.query(function(rows)
            refill()
            local id = type(rows) == "table" and rows[1] and tonumber(rows[1].id)
            if id then return answer(id) end
            if not createAccountRowAsync(name, pwHash, email, eventName, requestId) then
                answer(false, "registration failed")
            end
        end, "SELECT id FROM `" .. TABLE .. "` WHERE id = ? AND account_name = ? LIMIT 1", rowId, name)
    end, "UPDATE `" .. TABLE .. "` SET id = LAST_INSERT_ID(id), account_name = ?, password = ?, email = ?, "
        .. "display_name = ?, admin_level = 0, account_data = '{}', created_at = ?, updated_at = ? "
        .. "WHERE id = ? AND account_name = ?",
        name, pwHash, email, name, ts, ts, rowId, s.name)
    return true
end
