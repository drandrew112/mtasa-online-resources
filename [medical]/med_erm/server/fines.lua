if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Supervisor fines (tablet page "Supervisor"). A SUP unit fines another signed-in unit for one of Config.FINES.
-- Fines are kept only on the unit (u.fines), so they exist while that unit is on shift; at sign-out they are
-- deducted from the pay as separate items (server/payment.lua). No database, no history after the shift.
-- Dispatchers (web console) may issue only the fines marked dispatcher = true (Fines.issueByDispatcher); every
-- unit's fines are shown to them as a penalty log (Units.public -> Fines.publicList).

Fines = {}

local function isSup(u) return u and u.type == "SUP" end

-- Stores the fine on the unit -> true | false, error
function Fines.add(target, fine, by)
    target.fines = target.fines or {}
    if #target.fines >= Config.FINE_MAX_PER_UNIT then return false, L.msg("med_erm.supervisor.too_many") end
    target.fines[#target.fines + 1] = { id = fine.id, amount = fine.amount, at = now(), by = by }
    return true
end

-- Penalty log of a unit for the dispatcher console: oldest first, label already translated.
function Fines.publicList(u)
    local out = {}
    for _, f in ipairs(u.fines or {}) do
        local def = Config.FINE_BY_ID[f.id]
        out[#out + 1] = { id = f.id, label = def and L.msg(def.label) or f.id, amount = f.amount, at = f.at, by = f.by }
    end
    return out
end

-- The fines a dispatcher may issue: { id, label, amount } for the web console unit menu
function Fines.dispatcherList()
    local out = {}
    for _, f in ipairs(Config.FINES) do
        if f.dispatcher then out[#out + 1] = { id = f.id, label = L.msg(f.label), amount = f.amount } end
    end
    return out
end

-- Fine from a dispatcher (web console): only Config.FINES entries with dispatcher = true -> true | false, error
function Fines.issueByDispatcher(targetId, fineId, dispatcher)
    local target = Units.get(targetId)
    if not target then return false, L.msg("med_erm.supervisor.unit_not_found") end
    local fine = Config.FINE_BY_ID[fineId]
    if not fine then return false, L.msg("med_erm.supervisor.unknown_fine") end
    if not fine.dispatcher then return false, L.msg("med_erm.fine.dispatcher_not_allowed") end
    local ok, err = Fines.add(target, fine, dispatcher)
    if not ok then return false, err end

    Units.notify(target, L.msg("med_erm.fine.dispatcher_title"),
        L.msg("med_erm.fine.dispatcher_received", { dispatcher = dispatcher, reason = L.msg(fine.label), amount = fine.amount }))
    Units.sync(target)
    return true
end

-- Issues a fine from the supervisor unit `sup` to unit id `targetId` -> true | false, error
function Fines.issue(sup, targetId, fineId)
    if not isSup(sup) then return false, L.msg("med_erm.supervisor.only_supervisor") end
    local target = Units.get(targetId)
    if not target then return false, L.msg("med_erm.supervisor.unit_not_found") end
    if target.id == sup.id then return false, L.msg("med_erm.supervisor.cannot_self") end
    local fine = Config.FINE_BY_ID[fineId]
    if not fine then return false, L.msg("med_erm.supervisor.unknown_fine") end
    local ok, err = Fines.add(target, fine, sup.callsign)
    if not ok then return false, err end

    Units.notify(target, L.msg("med_erm.supervisor.received_title"),
        L.msg("med_erm.supervisor.received", { supervisor = sup.callsign, reason = L.msg(fine.label), amount = fine.amount }))  -- no alert sound: that is only for incoming tasks
    Units.notify(sup, L.msg("med_erm.supervisor.title"),
        L.msg("med_erm.supervisor.issued", { callsign = target.callsign, reason = L.msg(fine.label), amount = fine.amount }))
    Units.sync(target)
    return true
end

-- Page data: every other signed-in unit with its fines
function Fines.list(sup)
    local out = {}
    for _, u in pairs(Units.list) do
        if u.id ~= sup.id then
            local crew = {}
            for _, p in ipairs(u.members) do
                if isElement(p) then crew[#crew + 1] = ((getElementData(p, "displayName") or getPlayerName(p)):gsub("#%x%x%x%x%x%x", "")) end
            end
            local fines, total = {}, 0
            for _, f in ipairs(u.fines or {}) do
                fines[#fines + 1] = { id = f.id, amount = f.amount, at = f.at, by = f.by }
                total = total + f.amount
            end
            out[#out + 1] = { id = u.id, callsign = u.callsign, type = u.type, plate = u.plate, crew = crew, fines = fines, total = total }
        end
    end
    table.sort(out, function(a, b) return a.callsign < b.callsign end)
    return out
end

function Fines.send(player)
    local u = Units.ofPlayer(player)
    if not isSup(u) then return end
    triggerClientEvent(player, "erm:supUnits", resourceRoot, Fines.list(u))
end

addEvent("erm:supList", true)
addEventHandler("erm:supList", resourceRoot, function()
    if isElement(client) then Fines.send(client) end
end)

addEvent("erm:supFine", true)
addEventHandler("erm:supFine", resourceRoot, function(targetId, fineId)
    if not isElement(client) then return end
    local sup = Units.ofPlayer(client)
    local ok, err = Fines.issue(sup, tonumber(targetId), tostring(fineId))
    if not ok and err then
        triggerClientEvent(client, "erm:notify", resourceRoot, L.msg("med_erm.supervisor.title"), err)
    end
    Fines.send(client)
end)
