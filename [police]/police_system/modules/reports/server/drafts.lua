-- police_system / modules/reports/server/drafts.lua
-- Reports. A closed incident makes a draft from its log (templates/<lang>.lua) in the language of the unit leader
-- (any v_locals language can be picked in the editor; the language is always shown; no translation). The officer
-- edits / completes it and submits it. A manual report (type Other) can be written too, it pays nothing. Any member
-- of the unit can submit; the leader sees what is left. Signing off needs every draft of the shift submitted (leaving
-- the unit: the drafts the member is in). Drafts can be submitted off duty too (MDC sign-in screen, MDC computers):
-- a report of an ended shift is paid when it is submitted (pay.lua PAY.report).

local R = POL.module("reports", { pending = {} })   -- pending[shiftId] = number of drafts

local function MODEL_NAME(model) return exports.veh_manager:getModelName(model) end

local function tpl(lang) return REPORT_TEMPLATES[lang] or REPORT_TEMPLATES.en end

local function fill(text, p)
    return (tostring(text):gsub("{(%w+)}", function(k) local v = p[k]; return v ~= nil and tostring(v) or "" end))
end

local function subjectName(inc)
    for _, s in ipairs(inc.subjects) do if s.name then return s.name end end
    return "?"
end

local function subjectVehicle(inc)
    for _, s in ipairs(inc.subjects) do if s.plate then return s end end
    return {}
end

-- the draft text of an incident in `lang`: title, body
function R.build(inc, lang)
    local T = tpl(lang)
    local names = {}
    for _, n in pairs(inc.members) do names[#names + 1] = n end
    table.sort(names)
    local v = subjectVehicle(inc)
    local zone = inc.zone or "San Andreas"
    local title = ("%s · %s · %s–%s · %s"):format(T.types[inc.type] or T.types.other, inc.unit.callsign,
        POL.fmtTime(inc.startedAt), POL.clock(inc.closedAt or POL.now()), lang:upper())
    local intro = fill(T.intro, {
        time = POL.clock(inc.startedAt), unit = inc.unit.callsign, members = table.concat(names, ", "),
        what = fill(T.what[inc.type] or T.what.other, {
            color = v.color and (v.color .. " ") or "", model = v.model and MODEL_NAME(v.model) or "?",
            plate = v.plate or "?", zone = zone, name = subjectName(inc), ["for"] = inc.backupFor or "?",
        }),
    })
    local body = { intro }
    for _, l in ipairs(inc.lines) do
        local f = T.lines[l.k]
        if f then
            local d = l.d or {}
            local p = { time = POL.clock(l.t), o = l.o, name = d.name or subjectName(inc), plate = d.plate or v.plate or "?",
                model = d.model and MODEL_NAME(d.model) or (v.model and MODEL_NAME(v.model)) or "?", value = d.value,
                result = d.result and T.drug.pos or T.drug.neg, amount = d.amount and L.money(d.amount, lang) or "",
                item = d.item and L.forLang(lang, btkKey(d.item)) or "", station = d.station or "", level = d.level,
                count = d.count, warrant = d.warrant and T.lines.warrant_found or "",
                flags = (d.stolen and T.lines.flag_stolen or "") .. (d.inspection and fill(T.lines.flag_inspection, { value = d.inspection }) or "") }
            body[#body + 1] = fill(f, p)
        end
    end
    return title, table.concat(body, "\n")
end

local function subjectKeys(inc)
    local out = {}
    for _, s in ipairs(inc.subjects) do
        if s.citizenId then out[#out + 1] = "c" .. s.citizenId end
        if s.vehicleId then out[#out + 1] = "v" .. s.vehicleId end
    end
    return out
end

function R.draft(inc)
    local unit = inc.unit
    local leader = unit.leader
    local lang = isElement(leader) and POL.lang(leader) or "en"
    local title, body = R.build(inc, lang)
    local members = {}
    for acc in pairs(inc.members) do members[#members + 1] = acc end
    local sid = unit.shiftId
    if sid then R.pending[sid] = (R.pending[sid] or 0) + 1 end
    POL.db.create("pol_reports", {
        shift_id = sid, incident_id = inc.id, type = inc.type, pay_type = inc.payType, level = inc.level or 0, lang = lang,
        author = isElement(leader) and POL.accountOf(leader) or "", author_name = isElement(leader) and POL.nameOf(leader) or "",
        unit = unit.callsign, members = POL.db.json(members), title = title, body = body,
        subjects = POL.db.json(subjectKeys(inc)), status = "draft", created_at = POL.now(),
    }, function(id)
        if not id then return end
        local typeKey = "police_system.reports.type_" .. tostring(inc.type)
        POL.notify(POL.units.members(unit), "police_system.reports.required", { type = L.msg(typeKey), num = inc.num })
        POL.send(POL.units.members(unit), "mdc:refresh", "reports")
    end)
end

function R.pendingCount(unit)
    return unit and unit.shiftId and (R.pending[unit.shiftId] or 0) or 0
end

-- drafts of an account (author or member), only of shift `shiftId` when given; cb(n)
function R.draftCount(acc, shiftId, cb)
    if not acc or not POL.db.ready then return cb(0) end
    local sql = "SELECT COUNT(*) AS n FROM pol_reports WHERE is_pool = 0 AND status = 'draft' AND (author = ? OR members LIKE ?)"
    local args = { acc, '%"' .. acc .. '"%' }
    if shiftId then sql = sql .. " AND shift_id = ?"; args[3] = shiftId end
    POL.db.query(function(rows)
        cb(type(rows) == "table" and rows[1] and tonumber(rows[1].n) or 0)
    end, sql, unpack(args))
end

local function canSee(player, r)
    local acc = POL.accountOf(player)
    if not acc then return false end
    if r.author == acc then return true end
    for _, a in ipairs(POL.db.unjson(r.members)) do if a == acc then return true end end
    return POL.ranks.has(player, POLICE.RANKS.FINE_REVIEW)
end

-- MDC list: scope "mine" (drafts first, then my submitted) | "unit" (the current shift); cb(rows)
function R.list(player, scope, cb)
    local acc = POL.accountOf(player) or ""
    local unit = POL.units.of(player)
    local sql, args
    if scope == "unit" and unit and unit.shiftId then
        sql, args = "SELECT id, type, title, status, unit, author_name, lang, created_at, submitted_at FROM pol_reports WHERE shift_id = ? AND is_pool = 0 ORDER BY id DESC LIMIT 50", { unit.shiftId }
    else
        sql, args = [[SELECT id, type, title, status, unit, author_name, lang, created_at, submitted_at FROM pol_reports
            WHERE is_pool = 0 AND (author = ? OR members LIKE ?) ORDER BY (status = 'draft') DESC, id DESC LIMIT 50]],
            { acc, '%"' .. acc .. '"%' }
    end
    POL.db.query(function(rows)
        local out = {}
        for _, r in ipairs(type(rows) == "table" and rows or {}) do
            out[#out + 1] = { id = r.id, type = r.type, title = r.title, status = r.status, unit = r.unit, author = r.author_name,
                lang = r.lang, at = tonumber(r.submitted_at) ~= 0 and tonumber(r.submitted_at) or tonumber(r.created_at) }
        end
        cb(out)
    end, sql, unpack(args))
end

function R.get(player, id, cb)
    POL.db.query(function(rows)
        local r = type(rows) == "table" and rows[1]
        if not r or not canSee(player, r) then return cb(false) end
        cb({ id = r.id, type = r.type, title = r.title, body = r.body, status = r.status, unit = r.unit, lang = r.lang,
             author = r.author_name, at = tonumber(r.created_at), submitted = tonumber(r.submitted_at) })
    end, "SELECT * FROM pol_reports WHERE id = ? AND is_pool = 0", tonumber(id))
end

-- save a draft (submit = true: submitted). cb(true | false, err)
function R.save(player, id, title, body, lang, submit, cb)
    POL.db.query(function(rows)
        local r = type(rows) == "table" and rows[1]
        if not r or not canSee(player, r) then return cb(false, "not_found") end
        if r.status ~= "draft" then return cb(false, "submitted") end
        title = tostring(title or r.title):sub(1, 160)
        body = tostring(body or r.body):sub(1, 8000)
        lang = tostring(lang or r.lang):sub(1, 8)
        if submit then
            local sid = tonumber(r.shift_id)
            POL.db.query(function(ok)
                if ok == false or not sid then return end
                -- the shift may have ended already (forced end): this report is paid now (after the row is submitted)
                local live = false
                for _, u in pairs(POL.units.list) do if u.shiftId == sid then live = u end end
                if not live then POL.pay.report(sid, r.id) end
            end, "UPDATE pol_reports SET title = ?, body = ?, lang = ?, status = 'submitted', submitted_at = ? WHERE id = ?",
                title, body, lang, POL.now(), r.id)
            POL.db.stat("reports", 1)
            if sid then
                R.pending[sid] = math.max(0, (R.pending[sid] or 1) - 1)
                for _, u in pairs(POL.units.list) do if u.shiftId == sid then POL.units.push(u) end end
            end
            POL.events.logFor(player, "report_submitted", { report = r.id })
        else
            POL.db.exec("UPDATE pol_reports SET title = ?, body = ?, lang = ? WHERE id = ?", title, body, lang, r.id)
        end
        cb(true)
    end, "SELECT * FROM pol_reports WHERE id = ? AND is_pool = 0", tonumber(id))
end

-- manual report (Other): submitted at once, no pay
function R.manual(player, title, body, lang, cb)
    local unit = POL.units.of(player)
    POL.db.create("pol_reports", {
        shift_id = unit and unit.shiftId or nil, type = "other", lang = tostring(lang or POL.lang(player)):sub(1, 8),
        author = POL.accountOf(player) or "", author_name = POL.nameOf(player), unit = unit and unit.callsign or "",
        members = POL.db.json({ POL.accountOf(player) }), title = tostring(title or ""):sub(1, 160),
        body = tostring(body or ""):sub(1, 8000), subjects = "[]", status = "submitted", created_at = POL.now(),
        submitted_at = POL.now(),
    }, function(id) cb(id and true or false) end)
end
