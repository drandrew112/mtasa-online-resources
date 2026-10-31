-- police_system / modules/warrants/server/warrants.lua
-- Warrants: separate from the GTA wanted level, permanent (pol_warrants). On players and NPCs. Reasons: the BTK
-- items marked "warrant" + unpaid_fines / escape_custody / evading_arrest (several at once). A short description in
-- one language (default the issuer's, any v_locals language; no translation). Issue / edit / revoke on the MDC;
-- every change is kept with the name and time (history JSON lines). Shown red on the query window and profile.
-- Served after the arrest + handover. Public on police_web (the decision).
-- Rank rights: anyone with the right issues; editing / revoking someone else's from Hadnagy (RANKS.WARRANT_EDIT).

local W = POL.module("warrants", {})

local function validReasons(list)
    local ok = {}
    local known = {}
    for _, r in ipairs(POL.btk.warrantReasons()) do known[r.id] = true end
    for _, id in ipairs(type(list) == "table" and list or {}) do
        if known[id] then ok[#ok + 1] = id end
    end
    return ok
end

function W.public(r)
    return {
        id = tonumber(r.id), citizenId = tonumber(r.citizen_id), reasons = POL.db.unjson(r.reasons),
        description = r.description or "", lang = r.lang or "en", status = r.status,
        issuer = r.issued_name, updater = r.updated_name, at = tonumber(r.created_at), updated = tonumber(r.updated_at),
        minutes = W.minutes(POL.db.unjson(r.reasons)),
    }
end

-- jail minutes of a reason list (sum, capped)
function W.minutes(reasons)
    local m = 0
    for _, id in ipairs(reasons or {}) do m = m + POL.btk.reasonMinutes(id) end
    return math.min(m, POLICE.JAIL.WARRANT_MAX_MINUTES)
end

-- issuer: the officer (player) or nil (generated / automatic); silent: no unit log. cb(id | false, err)
function W.create(citizenId, reasons, description, lang, issuer, silent, cb)
    reasons = validReasons(reasons)
    if #reasons == 0 or not tonumber(citizenId) then if cb then cb(false, "bad_reason") end return end
    local now = POL.now()
    local name = issuer and POL.nameOf(issuer) or "SAPD Records"
    POL.db.create("pol_warrants", {
        citizen_id = tonumber(citizenId), reasons = POL.db.json(reasons),
        description = tostring(description or ""):sub(1, 400), lang = tostring(lang or "en"):sub(1, 8), status = "active",
        issued_by = issuer and POL.accountOf(issuer) or "", issued_name = name, updated_by = "", updated_name = "",
        history = toJSON({ at = now, by = name, action = "issued", reasons = reasons }, true) .. "\n",
        created_at = now, updated_at = now,
    }, function(id)
        if id and not silent then
            POL.db.stat("warrants", 1)
            if issuer then POL.events.logFor(issuer, "warrant_issued", { warrant = id, citizen = citizenId }) end
            POL.emit("warrants.changed", citizenId)
        end
        if cb then cb(id) end
    end)
end

local function canEdit(player, row)
    if row.issued_by ~= "" and row.issued_by == POL.accountOf(player) then return true end
    return POL.ranks.has(player, POLICE.RANKS.WARRANT_EDIT)
end

-- changes = { reasons, description, lang }; cb(true | false, err)
function W.update(player, id, changes, cb)
    POL.db.query(function(rows)
        local r = type(rows) == "table" and rows[1]
        if not r or r.status ~= "active" then return cb(false, "not_found") end
        if not canEdit(player, r) then return cb(false, "rank") end
        local reasons = changes.reasons and validReasons(changes.reasons) or POL.db.unjson(r.reasons)
        if #reasons == 0 then return cb(false, "bad_reason") end
        local now, name = POL.now(), POL.nameOf(player)
        POL.db.exec([[UPDATE pol_warrants SET reasons = ?, description = ?, lang = ?, updated_by = ?, updated_name = ?,
            updated_at = ?, history = CONCAT(COALESCE(history, ''), ?) WHERE id = ?]],
            POL.db.json(reasons), tostring(changes.description or r.description or ""):sub(1, 400),
            tostring(changes.lang or r.lang or "en"):sub(1, 8), POL.accountOf(player) or "", name, now,
            toJSON({ at = now, by = name, action = "edited", reasons = reasons }, true) .. "\n", r.id)
        POL.events.logFor(player, "warrant_edited", { warrant = r.id })
        POL.emit("warrants.changed", tonumber(r.citizen_id))
        cb(true)
    end, "SELECT * FROM pol_warrants WHERE id = ? AND is_pool = 0", tonumber(id))
end

function W.revoke(player, id, cb)
    POL.db.query(function(rows)
        local r = type(rows) == "table" and rows[1]
        if not r or r.status ~= "active" then return cb(false, "not_found") end
        if not canEdit(player, r) then return cb(false, "rank") end
        local now, name = POL.now(), POL.nameOf(player)
        POL.db.exec([[UPDATE pol_warrants SET status = 'revoked', updated_by = ?, updated_name = ?, updated_at = ?,
            history = CONCAT(COALESCE(history, ''), ?) WHERE id = ?]], POL.accountOf(player) or "", name, now,
            toJSON({ at = now, by = name, action = "revoked" }, true) .. "\n", r.id)
        POL.events.logFor(player, "warrant_revoked", { warrant = r.id })
        POL.emit("warrants.changed", tonumber(r.citizen_id))
        cb(true)
    end, "SELECT * FROM pol_warrants WHERE id = ? AND is_pool = 0", tonumber(id))
end

-- the active warrants of a citizen: cb(list)
function W.activeFor(citizenId, cb)
    POL.db.query(function(rows)
        local out = {}
        for _, r in ipairs(type(rows) == "table" and rows or {}) do out[#out + 1] = W.public(r) end
        cb(out)
    end, "SELECT * FROM pol_warrants WHERE citizen_id = ? AND status = 'active' AND is_pool = 0", tonumber(citizenId))
end

-- after the arrest + handover: every active warrant of the citizen is served. cb(minutes of the served ones)
function W.serve(citizenId, by, cb)
    W.activeFor(citizenId, function(list)
        local reasons = {}
        for _, w in ipairs(list) do for _, id in ipairs(w.reasons) do reasons[#reasons + 1] = id end end
        if #list > 0 then
            local now, name = POL.now(), by and POL.nameOf(by) or "SAPD"
            POL.db.exec([[UPDATE pol_warrants SET status = 'served', updated_name = ?, updated_at = ?,
                history = CONCAT(COALESCE(history, ''), ?) WHERE citizen_id = ? AND status = 'active' AND is_pool = 0]],
                name, now, toJSON({ at = now, by = name, action = "served" }, true) .. "\n", tonumber(citizenId))
            POL.emit("warrants.changed", tonumber(citizenId))
        end
        if cb then cb(W.minutes(reasons), #list) end
    end)
end

-- MDC list: status "active" (default) | "all"; cb(rows, more)
function W.list(status, page, cb)
    page = math.max(1, math.floor(tonumber(page) or 1))
    local PAGE = POLICE.MDC.PAGE_SIZE
    local where = status == "all" and "w.is_pool = 0" or "w.is_pool = 0 AND w.status = 'active'"
    POL.db.query(function(rows)
        rows = type(rows) == "table" and rows or {}
        local more = #rows > PAGE
        if more then rows[#rows] = nil end
        local out = {}
        for _, r in ipairs(rows) do
            local w = W.public(r)
            w.name = POL.records.nameOf({ kind = r.kind, name = r.name, account_name = r.account_name, dname = r.dname })
            w.kind = r.kind
            out[#out + 1] = w
        end
        cb(out, more)
    end, [[SELECT w.*, c.kind, c.name, c.account_name, a.display_name AS dname FROM pol_warrants w
        LEFT JOIN pol_citizens c ON c.id = w.citizen_id LEFT JOIN accounts a ON a.account_name = c.account_name
        WHERE ]] .. where .. " ORDER BY w.updated_at DESC LIMIT " .. (PAGE + 1) .. " OFFSET " .. ((page - 1) * PAGE))
end

-- automatic warrant (quit cuffed / at wanted 2+): the unit members + leader that chased / held the player are told
function W.automatic(player, reasonId, notifyUnits)
    POL.history.player(player, function(c)
        if not c then return end
        W.create(c.id, { reasonId }, "", "en", nil, false, function(id)
            if not id then return end
            local name = POL.nameOf(player)
            for _, u in ipairs(notifyUnits or {}) do
                POL.notify(POL.units.members(u), "police_system.warrants.auto_warrant", { name = name, id = id })
            end
        end)
    end)
end
