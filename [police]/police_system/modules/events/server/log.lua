-- police_system / modules/events/server/log.lua
-- The event log and the incidents. Every line: time, unit, officer, kind, data (+ subject). Lines go to
-- pol_shifts.events as JSON lines, batched every LOG_FLUSH ms with CONCAT (no read-modify-write), and to the open
-- incidents of the unit. An incident is opened by a stop, a pursuit, an arrest or a backup call, closed by Code 4,
-- Release or the handover; closing makes the report draft (reports.lua) and tells the unit "Report required".
--
-- incident = { id = "<shift>-<n>", num, type ("traffic_stop" | "ped_stop" | "pursuit" | "arrest" | "backup" | "other"),
--              unit, startedAt, closedAt, lines, subjects = { { kind, citizenId, vehicleId, name, plate, model } },
--              fines = { { btk, amount, kind } }, members = { [acc] = name }, level, outcome, arrested, payType }

local E = POL.module("events", { buffers = {} })

local function line(unit, officer, kind, data)
    return { t = POL.now(), u = unit and unit.callsign or "", o = isElement(officer) and POL.nameOf(officer) or "",
             k = kind, d = data or {} }
end

function E.log(unit, officer, kind, data, only)
    local l = line(unit, officer, kind, data)
    if unit then
        if unit.shiftId then
            local b = E.buffers[unit.shiftId]
            if not b then b = {}; E.buffers[unit.shiftId] = b end
            b[#b + 1] = l
        end
        unit.tail[#unit.tail + 1] = l
        if #unit.tail > 40 then table.remove(unit.tail, 1) end
        for inc in pairs(unit.incidents) do
            if not only or inc == only then inc.lines[#inc.lines + 1] = l end
        end
    end
    return l
end

-- log for an officer's unit (nothing when not on duty)
function E.logFor(officer, kind, data, only)
    local unit = POL.units.of(officer)
    if unit then return E.log(unit, officer, kind, data, only) end
end

function E.flush(shiftId)
    local function one(id, lines)
        if #lines == 0 then return end
        local parts = {}
        for i, l in ipairs(lines) do parts[i] = toJSON(l, true) end
        POL.db.exec("UPDATE pol_shifts SET events = CONCAT(COALESCE(events, ''), ?) WHERE id = ?",
            table.concat(parts, "\n") .. "\n", id)
    end
    if shiftId then
        one(shiftId, E.buffers[shiftId] or {})
        E.buffers[shiftId] = nil
        return
    end
    for id, lines in pairs(E.buffers) do one(id, lines) end
    E.buffers = {}
end

------------------------------------------------------------------------ incidents

local function memberMap(unit)
    local m = {}
    for _, p in ipairs(POL.units.members(unit)) do m[POL.accountOf(p) or getPlayerName(p)] = POL.nameOf(p) end
    return m
end

function E.open(unit, itype, subject)
    if not unit then return nil end
    unit.incSeq = unit.incSeq + 1
    local inc = { id = tostring(unit.shiftId or 0) .. "-" .. unit.incSeq, num = unit.incSeq, type = itype, unit = unit,
                  startedAt = POL.now(), lines = {}, subjects = {}, fines = {}, members = memberMap(unit), level = 0 }
    unit.incidents[inc] = true
    if subject then E.addSubject(inc, subject) end
    E.log(unit, nil, "incident_open", { incident = inc.num, type = itype }, inc)
    POL.emit("incident.opened", inc)
    return inc
end

function E.addSubject(inc, s)
    for _, x in ipairs(inc.subjects) do
        if (s.citizenId and x.citizenId == s.citizenId) or (s.vehicleId and x.vehicleId == s.vehicleId) then
            for k, v in pairs(s) do x[k] = v end
            return
        end
    end
    inc.subjects[#inc.subjects + 1] = s
end

-- officers who join later are part of the incident too
POL.on("units.member", function(unit, player, joined)
    if not joined then return end
    for inc in pairs(unit.incidents) do inc.members[POL.accountOf(player) or getPlayerName(player)] = POL.nameOf(player) end
end)

local function payTypeOf(inc)
    if inc.arrested then
        if inc.type == "pursuit" then return "pursuit_caught" end
        return inc.arrested == "player" and "arrest_player" or "arrest_npc"
    end
    if inc.type == "backup" then return inc.arrived and "backup" or nil end
    local fines, warnings = 0, 0
    for _, f in ipairs(inc.fines) do if f.kind == "fine" then fines = fines + 1 else warnings = warnings + 1 end end
    if fines > 0 then return "traffic_fine" end
    if warnings > 0 then return "traffic_warning" end
    return nil
end

function E.close(inc, outcome, by)
    local unit = inc.unit
    if not unit or not unit.incidents[inc] then return end
    unit.incidents[inc] = nil
    inc.closedAt = POL.now()
    inc.outcome = outcome
    inc.payType = payTypeOf(inc)
    E.log(unit, by, "incident_close", { incident = inc.num, outcome = outcome })
    inc.lines[#inc.lines + 1] = line(unit, by, "incident_close", { incident = inc.num, outcome = outcome })
    if unit.sub and not next(unit.incidents) then POL.units.setSub(unit, nil) end
    POL.reports.draft(inc)
    POL.emit("incident.closed", inc)
end

-- the open incident of a unit about a subject element (stop / arrest), or the newest one
function E.incidentOf(unit, el)
    if not unit then return nil end
    local newest
    for inc in pairs(unit.incidents) do
        if el and inc.el == el then return inc end
        if not newest or inc.num > newest.num then newest = inc end
    end
    if el then return nil end
    return newest
end

------------------------------------------------------------------------ weapon draw / use of on-duty officers

local shots = {}   -- [player] = { n, from, weapon }

POL.net("evt:weapon", function(player, weapon)
    if not POL.units.of(player) then return end
    weapon = tonumber(weapon) or 0
    if weapon > 0 then E.logFor(player, "weapon_drawn", { weapon = weapon }) end
end)

POL.net("evt:shots", function(player, weapon, count)
    if not POL.units.of(player) then return end
    E.logFor(player, "weapon_fired", { weapon = tonumber(weapon) or 0, count = math.min(500, tonumber(count) or 1) })
end)

function E.start()
    setTimer(E.flush, POLICE.LOG_FLUSH, 0)
end

function E.stop() E.flush() end
