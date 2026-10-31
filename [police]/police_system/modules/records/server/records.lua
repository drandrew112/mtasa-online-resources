-- police_system / modules/records/server/records.lua
-- Citizens and vehicles of the police database: lookups (element -> row), search (name, plate, citizen id, model,
-- owner; LIKE on indexed columns, PAGE_SIZE rows a page), profiles (fines / warnings, warrants, reports, vehicles)
-- and the fines / warnings themselves (pol_records). A player fine is a forced bank deduction (may go negative),
-- an NPC fine is income of the state too (the decision); both go to the BTK fine target (default the treasury).
-- Players: the name is the display name (accounts.display_name at read time), birth date = registration - 18 y.

local R = POL.module("records", { citizens = {}, vehicles = {} })
local PAGE = POLICE.MDC.PAGE_SIZE

function R.cacheCitizen(row) if row and row.id then R.citizens[tonumber(row.id)] = row end end
function R.cacheVehicle(row) if row and row.id then R.vehicles[tonumber(row.id)] = row end end

-- display name of a citizen row (players: the online display name, else accounts.display_name joined as dname)
function R.nameOf(row)
    if not row then return "?" end
    if row.kind == "player" then
        local p = POL.playerByAccount(row.account_name)
        if p then return POL.nameOf(p) end
        local d = row.dname
        return (type(d) == "string" and d ~= "") and d or tostring(row.account_name or "?")
    end
    return tostring(row.name or "?")
end

function R.citizen(id, cb)
    id = tonumber(id)
    if not id then return cb(false) end
    if R.citizens[id] then return cb(R.citizens[id]) end
    POL.db.query(function(rows)
        local r = type(rows) == "table" and rows[1] or false
        if r then R.cacheCitizen(r) end
        cb(r)
    end, [[SELECT c.*, a.display_name AS dname FROM pol_citizens c LEFT JOIN accounts a ON a.account_name = c.account_name
        WHERE c.id = ? AND c.is_pool = 0]], id)
end

function R.vehicle(id, cb)
    id = tonumber(id)
    if not id then return cb(false) end
    if R.vehicles[id] then return cb(R.vehicles[id]) end
    POL.db.query(function(rows)
        local r = type(rows) == "table" and rows[1] or false
        if r then R.cacheVehicle(r) end
        cb(r)
    end, "SELECT * FROM pol_vehicles WHERE id = ? AND is_pool = 0", id)
end

-- citizen row of a player or a ped
function R.citizenOf(el, cb)
    if not isElement(el) then return cb(false) end
    if getElementType(el) == "player" then return POL.history.player(el, cb) end
    return POL.history.npc(el, cb)
end

-- vehicle row of a vehicle element: an owned vehicle by its v_ownveh id, everything else is an NPC vehicle
function R.vehicleOf(veh, cb)
    if not isElement(veh) then return cb(false) end
    local ov = tonumber(getElementData(veh, "ownveh:id"))
    if ov then
        POL.db.query(function(rows)
            local r = type(rows) == "table" and rows[1]
            if r then R.cacheVehicle(r); return cb(r) end
            -- not registered yet (bought just now on another instance): the npc path would be wrong, register it
            POL.db.create("pol_vehicles", { kind = "player", ownveh_id = ov, plate = getVehiclePlateText(veh),
                model = getElementModel(veh), created_at = POL.now() }, function(id)
                if not id then return cb(false) end
                R.vehicle(id, cb)
            end)
        end, "SELECT * FROM pol_vehicles WHERE ownveh_id = ? AND is_pool = 0 LIMIT 1", ov)
        return
    end
    POL.history.npcVehicle(veh, cb)
end

-- the live vehicle element with this plate (NPC vehicles are registered when found)
function R.findVehicleByPlate(plate)
    plate = tostring(plate or ""):upper():gsub("^%s+", ""):gsub("%s+$", "")
    if plate == "" then return nil end
    for _, v in ipairs(getElementsByType("vehicle")) do
        if (getVehiclePlateText(v) or ""):upper():gsub("%s+$", "") == plate then return v end
    end
    return nil
end

------------------------------------------------------------------------ search

local function like(q) return "%" .. tostring(q):gsub("[%%_]", "") .. "%" end

-- kind "citizens": filter "all" | "player" | "npc"; q = name / citizen id / plate. cb(rows, total)
function R.searchCitizens(filter, q, page, cb)
    local where, args = { "c.is_pool = 0" }, {}
    if filter == "player" or filter == "npc" then where[#where + 1] = "c.kind = ?"; args[#args + 1] = filter end
    q = tostring(q or ""):sub(1, 40)
    if q ~= "" then
        local n = tonumber((q:gsub("^#", "")))
        if n then
            where[#where + 1] = "c.id = ?"; args[#args + 1] = n
        else
            where[#where + 1] = [[(c.name LIKE ? OR c.account_name LIKE ? OR a.display_name LIKE ?
                OR c.id IN (SELECT owner_citizen_id FROM pol_vehicles WHERE plate LIKE ? AND is_pool = 0))]]
            local l = like(q)
            args[#args + 1] = l; args[#args + 1] = l; args[#args + 1] = l; args[#args + 1] = l
        end
    end
    page = math.max(1, math.floor(tonumber(page) or 1))
    local sql = [[SELECT c.id, c.kind, c.account_name, c.name, c.gender, c.birth_date, a.display_name AS dname,
            (SELECT COUNT(*) FROM pol_warrants w WHERE w.citizen_id = c.id AND w.status = 'active' AND w.is_pool = 0) AS warrants
        FROM pol_citizens c LEFT JOIN accounts a ON a.account_name = c.account_name
        WHERE ]] .. table.concat(where, " AND ") .. " ORDER BY c.last_seen DESC, c.id DESC LIMIT " .. (PAGE + 1) .. " OFFSET " .. ((page - 1) * PAGE)
    POL.db.query(function(rows)
        rows = type(rows) == "table" and rows or {}
        local more = #rows > PAGE
        if more then rows[#rows] = nil end
        local out = {}
        for _, r in ipairs(rows) do
            local wanted = 0
            local p = r.kind == "player" and POL.playerByAccount(r.account_name)
            if p then wanted = getPlayerWantedLevel(p) end
            out[#out + 1] = { id = r.id, kind = r.kind, name = R.nameOf(r), gender = r.gender, birth = r.birth_date,
                              warrants = tonumber(r.warrants) or 0, wanted = wanted }
        end
        cb(out, more)
    end, sql, unpack(args))
end

function R.searchVehicles(filter, q, page, cb)
    local where, args = { "v.is_pool = 0" }, {}
    if filter == "player" or filter == "npc" then where[#where + 1] = "v.kind = ?"; args[#args + 1] = filter end
    q = tostring(q or ""):sub(1, 40)
    if q ~= "" then
        local n = tonumber(q)
        local l = like(q)
        where[#where + 1] = "(v.plate LIKE ? OR c.name LIKE ? OR a.display_name LIKE ? OR c.account_name LIKE ?" .. (n and " OR v.model = ?" or "") .. ")"
        args[#args + 1] = l; args[#args + 1] = l; args[#args + 1] = l; args[#args + 1] = l
        if n then args[#args + 1] = n end
    end
    page = math.max(1, math.floor(tonumber(page) or 1))
    local sql = [[SELECT v.id, v.kind, v.plate, v.model, v.flags, c.id AS cid, c.kind AS ckind, c.name, c.account_name,
            a.display_name AS dname
        FROM pol_vehicles v LEFT JOIN pol_citizens c ON c.id = v.owner_citizen_id
        LEFT JOIN accounts a ON a.account_name = c.account_name
        WHERE ]] .. table.concat(where, " AND ") .. " ORDER BY v.id DESC LIMIT " .. (PAGE + 1) .. " OFFSET " .. ((page - 1) * PAGE)
    POL.db.query(function(rows)
        rows = type(rows) == "table" and rows or {}
        local more = #rows > PAGE
        if more then rows[#rows] = nil end
        local out = {}
        for _, r in ipairs(rows) do
            local f = POL.db.unjson(r.flags)
            out[#out + 1] = { id = r.id, kind = r.kind, plate = r.plate, model = r.model,
                owner = r.cid and R.nameOf({ kind = r.ckind, name = r.name, account_name = r.account_name, dname = r.dname }) or "-",
                ownerId = r.cid, stolen = f.stolen == true }
        end
        cb(out, more)
    end, sql, unpack(args))
end

------------------------------------------------------------------------ profiles

local function age(birth)
    local y, m, d = tostring(birth or ""):match("^(%d+)-(%d+)-(%d+)")
    if not y then return nil end
    local t = getRealTime()
    local a = t.year + 1900 - tonumber(y)
    if t.month + 1 < tonumber(m) or (t.month + 1 == tonumber(m) and t.monthday < tonumber(d)) then a = a - 1 end
    return a
end

-- citizen profile: cb(profile | false)
function R.profile(id, cb)
    R.citizen(id, function(c)
        if not c then return cb(false) end
        local f = POL.db.unjson(c.flags)
        local prof = {
            id = tonumber(c.id), kind = c.kind, name = R.nameOf(c), gender = c.gender, birth = c.birth_date,
            age = age(c.birth_date), licence = c.kind == "player" and "valid" or (f.licence or "valid"),
            records = {}, warrants = {}, reports = {}, vehicles = {}, wanted = 0, wantedReasons = {},
        }
        if c.kind == "player" then
            local p = POL.playerByAccount(c.account_name)
            if p and POL.wanted then
                local w = POL.wanted.get(p)
                if w then prof.wanted, prof.wantedReasons = w.level, w.reasonList end
            end
        end
        local left = 4
        local function done() left = left - 1; if left == 0 then cb(prof) end end
        POL.db.query(function(rows)
            for _, r in ipairs(type(rows) == "table" and rows or {}) do
                prof.records[#prof.records + 1] = { id = r.id, type = r.type, btk = r.btk_id, amount = tonumber(r.amount) or 0,
                    refunded = tonumber(r.refunded) == 1, officer = r.officer_name, unit = r.unit, at = tonumber(r.created_at) }
            end
            done()
        end, "SELECT * FROM pol_records WHERE citizen_id = ? AND is_pool = 0 ORDER BY created_at DESC LIMIT 50", c.id)
        POL.db.query(function(rows)
            for _, r in ipairs(type(rows) == "table" and rows or {}) do
                prof.warrants[#prof.warrants + 1] = POL.warrants.public(r)
            end
            done()
        end, "SELECT * FROM pol_warrants WHERE citizen_id = ? AND is_pool = 0 ORDER BY created_at DESC LIMIT 20", c.id)
        POL.db.query(function(rows)
            for _, r in ipairs(type(rows) == "table" and rows or {}) do
                prof.reports[#prof.reports + 1] = { id = r.id, type = r.type, title = r.title, author = r.author_name,
                    unit = r.unit, at = tonumber(r.submitted_at) or tonumber(r.created_at), lang = r.lang }
            end
            done()
        end, [[SELECT id, type, title, author_name, unit, created_at, submitted_at, lang FROM pol_reports
            WHERE status = 'submitted' AND is_pool = 0 AND subjects LIKE ? ORDER BY id DESC LIMIT 20]], '%"c' .. c.id .. '"%')
        POL.db.query(function(rows)
            for _, r in ipairs(type(rows) == "table" and rows or {}) do
                prof.vehicles[#prof.vehicles + 1] = { id = r.id, plate = r.plate, model = r.model }
            end
            done()
        end, "SELECT id, plate, model FROM pol_vehicles WHERE owner_citizen_id = ? AND is_pool = 0 ORDER BY id DESC LIMIT 20", c.id)
    end)
end

function R.vehicleProfile(id, cb)
    R.vehicle(id, function(v)
        if not v then return cb(false) end
        local f = POL.db.unjson(v.flags)
        local prof = { id = tonumber(v.id), kind = v.kind, plate = v.plate, model = tonumber(v.model), color = v.color,
            registration = v.kind == "player" and "valid" or (f.registration or "valid"),
            inspection = v.kind == "player" and "valid" or (f.inspection or "valid"),
            stolen = f.stolen == true, records = {}, owner = false }
        local left = 2
        local function done() left = left - 1; if left == 0 then cb(prof) end end
        if v.owner_citizen_id then
            R.citizen(v.owner_citizen_id, function(c)
                if c then
                    local wc = 0
                    prof.owner = { id = tonumber(c.id), name = R.nameOf(c), kind = c.kind }
                    POL.db.query(function(rows)
                        wc = type(rows) == "table" and rows[1] and tonumber(rows[1].n) or 0
                        prof.owner.warrants = wc
                        done()
                    end, "SELECT COUNT(*) AS n FROM pol_warrants WHERE citizen_id = ? AND status = 'active' AND is_pool = 0", c.id)
                else
                    done()
                end
            end)
        else
            done()
        end
        POL.db.query(function(rows)
            for _, r in ipairs(type(rows) == "table" and rows or {}) do
                prof.records[#prof.records + 1] = { id = r.id, type = r.type, btk = r.btk_id, amount = tonumber(r.amount) or 0,
                    officer = r.officer_name, unit = r.unit, at = tonumber(r.created_at) }
            end
            done()
        end, "SELECT * FROM pol_records WHERE vehicle_id = ? AND is_pool = 0 ORDER BY created_at DESC LIMIT 30", v.id)
    end)
end

------------------------------------------------------------------------ fines and warnings

-- subject = { el = player | ped, citizenId, vehicleId }; officer = player; kind = "fine" | "warning"
-- cb(true, amount | false, err)
function R.issue(officer, subject, kind, btkId, cb)
    cb = cb or function() end
    local e = POL.btk.get(btkId)
    if not e then return cb(false, "bad_item") end
    if kind == "warning" and not e.warning then return cb(false, "bad_item") end
    if kind == "fine" and e.warning then return cb(false, "bad_item") end
    local amount = kind == "fine" and POL.btk.amount(btkId) or 0
    local unit = POL.units.of(officer)
    local target = POL.btk.fineTarget()
    local paid = 0
    local el = subject.el
    if kind == "fine" and amount > 0 and POL.running("v_bank") then
        if isElement(el) and getElementType(el) == "player" then
            local ok = exports.v_bank:forceTakeMoney(el, amount, "fine.police", { item = btkId }, target)
            if ok ~= true then return cb(false, "bank") end
            paid = 1
        else
            -- NPC fine: state income too (the decision)
            local ok = target and exports.v_bank:credit(target, amount, "fine.police_npc", { item = btkId })
            paid = ok and 1 or 0
        end
    end
    POL.db.create("pol_records", {
        type = kind, btk_id = btkId, amount = amount, paid = paid, citizen_id = subject.citizenId,
        vehicle_id = subject.vehicleId, officer = POL.accountOf(officer), officer_name = POL.nameOf(officer),
        unit = unit and unit.callsign or "", shift_id = unit and unit.shiftId or nil, created_at = POL.now(),
    }, function(id)
        if kind == "fine" then
            POL.db.stat("fines", 1)
            POL.db.stat("fine_amount", amount)
            triggerEvent("onPoliceFineIssued", resourceRoot, { citizenId = subject.citizenId, element = el }, btkId, amount, officer)
        else
            POL.db.stat("warnings", 1)
        end
        if isElement(el) and getElementType(el) == "player" then
            POL.notify(el, kind == "fine" and "police_system.records.you_were_fined" or "police_system.records.you_were_warned",
                { item = L.msg(btkKey(btkId)), amount = amount })
        end
        cb(true, amount, id)
    end)
end

-- Százados+: a fine is refunded to the player (forced from the fine target back) and marked refunded
function R.refund(officer, recordId, cb)
    POL.db.query(function(rows)
        local r = type(rows) == "table" and rows[1]
        if not r or r.type ~= "fine" or tonumber(r.refunded) == 1 then return cb(false, "bad_record") end
        R.citizen(r.citizen_id, function(c)
            local amount = tonumber(r.amount) or 0
            if c and c.kind == "player" and amount > 0 and POL.running("v_bank") then
                local p = POL.playerByAccount(c.account_name)
                -- the bank account of an online player only (v_bank keeps the personal account per player)
                local acc = p and exports.v_bank:getPlayerAccount(p)
                if not acc then return cb(false, "offline") end
                local ok = exports.v_bank:transfer(POL.btk.fineTarget(), acc, amount, "fine.police_refund", { item = r.btk_id },
                    POL.accountOf(officer))
                if ok ~= true then return cb(false, "bank") end
                if p then POL.notify(p, "police_system.records.fine_refunded", { amount = amount, item = L.msg(btkKey(r.btk_id)) }) end
            end
            POL.db.exec("UPDATE pol_records SET refunded = 1 WHERE id = ?", r.id)
            POL.events.logFor(officer, "fine_refund", { record = r.id, amount = amount })
            cb(true)
        end)
    end, "SELECT * FROM pol_records WHERE id = ? AND is_pool = 0", tonumber(recordId))
end
