if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Backup request from the tablet's Active Case page: the crew picks the unit type it needs
-- (Config.BACKUP_OPTIONS) and the nearest free unit of that type is assigned to the case.
-- SOLO / DOC units call an ambulance for transport, BLS calls ALS / DOC for advanced care.

Backup = {}

local lastRequest = {}   -- [unit id] = getTickCount() of the last successful request

local function option(id)
    for _, o in ipairs(Config.BACKUP_OPTIONS) do
        if o.id == id then return o end
    end
end

-- Nearest unit of the option's types that can take the case -> unit, distance | nil, counts
-- counts: why the others cannot (busy = on another case, handover, unqualified)
local function findUnit(t, types, requester)
    local best, bestDist
    local counts = { total = 0, busy = 0, handover = 0, unqualified = 0 }
    for _, o in pairs(Units.list) do
        if o ~= requester and hasValue(types, o.type) then
            counts.total = counts.total + 1
            if o.status == "handover" then
                counts.handover = counts.handover + 1
            elseif o.task then
                counts.busy = counts.busy + 1
            elseif o.unqualified then
                counts.unqualified = counts.unqualified + 1
            elseif o.status == "available" then
                local x, y = Units.position(o)
                local d = getDistanceBetweenPoints2D(x, y, t.x, t.y)
                if not bestDist or d < bestDist then best, bestDist = o, d end
            else
                counts.busy = counts.busy + 1
            end
        end
    end
    return best, bestDist, counts
end

local function distanceText(d)
    if d >= 1000 then return string.format("%.1f km", d / 1000) end
    return string.format("%d m", d)
end

-- -> true | false, error
function Backup.request(u, optionId)
    if not u.task then return false, L.msg("med_erm.tablet.no_active_case") end
    local t = Tasks.get(u.task)
    if not t then return false, L.msg("med_erm.tablet.no_active_case") end
    if u.status == "handover" then return false, L.msg("med_erm.tasks.handover_in_progress") end
    local opt = option(optionId)
    if not opt then return false, L.msg("med_erm.backup.select_unit_type") end

    local last = lastRequest[u.id]
    if last and getTickCount() - last < Config.BACKUP_COOLDOWN then
        return false, L.msg("med_erm.backup.wait", { seconds = math.ceil((Config.BACKUP_COOLDOWN - (getTickCount() - last)) / 1000) })
    end

    local types = table.concat(opt.types, "/")
    local best, dist, counts = findUnit(t, opt.types, u)
    if not best then
        if counts.total == 0 then
            return false, L.msg("med_erm.backup.none_on_duty", { types = types })
        end
        return false, L.msg("med_erm.backup.none_free", {
            types = types, busy = counts.busy, handover = counts.handover, unqualified = counts.unqualified,
        })
    end

    local ok, err = Tasks.assign(t.id, best.id)
    if not ok then return false, err end
    lastRequest[u.id] = getTickCount()

    Units.notify(best, L.msg("med_erm.backup.requested_title"),
        L.msg("med_erm.backup.requested_by", { callsign = u.callsign, id = t.id }))
    for _, otherId in ipairs(t.units) do
        local o = Units.get(otherId)
        if o and o ~= best then
            Units.notify(o, L.msg("med_erm.backup.assigned_title"),
                L.msg("med_erm.backup.assigned", { callsign = best.callsign, type = best.type, distance = distanceText(dist) }))
        end
    end
    Events.fire("onErmBackupRequested", t.id, u.id, best.id, opt.id)
    return true
end
