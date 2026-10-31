-- police_system / modules/mdc/server/api.lua
-- MDC requests: client "pol:mdc:call" (reqId, action, args) -> API[action](player, args, reply) -> "pol:mdc:reply"
-- (reqId, result, err). Paged data (PAGE_SIZE rows), server side checks for everything (the right, the unit, ranks).

local M = POL.module("mdc", { open = {} })
local API = {}
M.API = API

local function needUnit(player, reply)
    if POL.units.of(player) then return true end
    reply(false, "not_in_unit")
    return false
end

------------------------------------------------------------------------ overview / lists

local function zoneOf(el) local x, y, z = getElementPosition(el); return getZoneName(x, y, z) end

function M.overview(player)
    local unit = POL.units.of(player)
    local units = {}
    for _, u in pairs(POL.units.list) do
        local names = {}
        for _, p in ipairs(POL.units.members(u)) do names[#names + 1] = POL.nameOf(p) end
        local lead = isElement(u.leader) and u.leader or POL.units.members(u)[1]
        units[#units + 1] = { callsign = u.callsign, members = names, status = u.status, sub = u.sub or false,
                              zone = lead and zoneOf(lead) or "" }
    end
    table.sort(units, function(a, b) return a.callsign < b.callsign end)
    local wanted = {}
    for p, st in pairs(POL.wanted.list) do
        if isElement(p) then
            wanted[#wanted + 1] = { name = POL.nameOf(p), level = st.level, reason = st.reasonList[#st.reasonList] or false,
                                    phase = st.phase }
        end
    end
    table.sort(wanted, function(a, b) return a.level > b.level end)
    return {
        unit = POL.units.state(unit), pending = POL.reports.pendingCount(unit), units = units,
        pursuits = POL.chase.publicList(), wanted = wanted, calls = POL.dispatch.list(),
        arrestsToday = POL.web and POL.web.today("arrests") or 0,
        tail = unit and unit.tail or {}, tows = unit and POL.tow.forUnit(unit) or {},
    }
end

function API.overview(p, a, reply) reply(M.overview(p)) end
function API.calls(p, a, reply) reply(POL.dispatch.list()) end
function API.callRespond(p, a, reply) if needUnit(p, reply) then reply(POL.dispatch.respond(p, a.id)) end end
function API.callClose(p, a, reply) if needUnit(p, reply) then reply(POL.dispatch.closeCall(p, a.id)) end end
function API.pursuits(p, a, reply) reply(POL.chase.publicList()) end
function API.pursuitJoin(p, a, reply)
    if not needUnit(p, reply) then return end
    reply(POL.chase.join(p, POL.chase.byId(a.id)))
end

function API.wanted(p, a, reply)
    local out = {}
    for pl, st in pairs(POL.wanted.list) do
        if isElement(pl) then
            out[#out + 1] = { name = POL.nameOf(pl), level = st.level, reasons = st.reasonList, phase = st.phase,
                              zone = st.phase == "evading" and getZoneName(st.lx, st.ly, st.lz) or zoneOf(pl) }
        end
    end
    table.sort(out, function(x, y) return x.level > y.level end)
    reply(out)
end

------------------------------------------------------------------------ warrants

function API.warrants(p, a, reply)
    POL.warrants.list(a.status, a.page, function(rows, more) reply({ rows = rows, more = more }) end)
end

function API.warrantReasons(p, a, reply)
    local langs = {}
    if POL.running("v_locals") then
        local ok, l = pcall(function() return exports.v_locals:getLanguages() end)
        if ok and type(l) == "table" then langs = l end
    end
    reply({ reasons = POL.btk.warrantReasons(), languages = langs, lang = POL.lang(p),
            canEditAll = POL.ranks.has(p, POLICE.RANKS.WARRANT_EDIT) })
end

function API.warrantCreate(p, a, reply)
    if not POL.rights.has(p) then return reply(false, "no_right") end
    POL.warrants.create(a.citizenId, a.reasons, a.description, a.lang, p, false, function(id, err)
        reply(id and { id = id } or false, err)
    end)
end

function API.warrantUpdate(p, a, reply)
    POL.warrants.update(p, a.id, { reasons = a.reasons, description = a.description, lang = a.lang }, function(ok, err)
        reply(ok, err)
    end)
end

function API.warrantRevoke(p, a, reply) POL.warrants.revoke(p, a.id, function(ok, err) reply(ok, err) end) end

------------------------------------------------------------------------ citizens / vehicles

function API.citizens(p, a, reply)
    POL.records.searchCitizens(a.filter, a.q, a.page, function(rows, more) reply({ rows = rows, more = more }) end)
end

function API.citizen(p, a, reply)
    POL.records.profile(a.id, function(prof)
        if prof then prof.canRefund = POL.ranks.has(p, POLICE.RANKS.FINE_REVIEW) end
        reply(prof or false, prof and nil or "not_found")
    end)
end

function API.vehicles(p, a, reply)
    POL.records.searchVehicles(a.filter, a.q, a.page, function(rows, more)
        if #rows == 0 and a.q and #tostring(a.q) >= 3 then
            -- a live NPC vehicle with this plate: registered now (History)
            local veh = POL.records.findVehicleByPlate(a.q)
            if veh then
                return POL.records.vehicleOf(veh, function()
                    POL.records.searchVehicles(a.filter, a.q, a.page, function(r2, m2) reply({ rows = r2, more = m2 }) end)
                end)
            end
        end
        reply({ rows = rows, more = more })
    end)
end

function API.vehicle(p, a, reply)
    POL.records.vehicleProfile(a.id, function(prof) reply(prof or false, prof and nil or "not_found") end)
end

function API.refund(p, a, reply)
    if not POL.ranks.has(p, POLICE.RANKS.FINE_REVIEW) then return reply(false, "rank") end
    POL.records.refund(p, a.id, function(ok, err) reply(ok, err) end)
end

------------------------------------------------------------------------ reports

function API.reports(p, a, reply) POL.reports.list(p, a.scope, reply) end
function API.report(p, a, reply) POL.reports.get(p, a.id, function(r) reply(r or false, r and nil or "not_found") end) end
function API.reportSave(p, a, reply)
    POL.reports.save(p, a.id, a.title, a.body, a.lang, a.submit == true, function(ok, err) reply(ok, err) end)
end
function API.reportManual(p, a, reply)
    POL.reports.manual(p, a.title, a.body, a.lang, function(ok) reply(ok) end)
end

function API.penal(p, a, reply) reply(POL.btk.list()) end
function API.queries(p, a, reply)
    local u = POL.units.of(p)
    reply(u and u.queries or {})
end

------------------------------------------------------------------------ units

function API.signin(p, a, reply) POL.units.formState(p, reply) end
function API.signinSet(p, a, reply)
    POL.units.setForm(p, a.type, a.number)
    POL.units.formState(p, reply)
end
function API.invite(p, a, reply)
    local ok, err = POL.units.invite(p, a.target)
    reply(ok, err)
end
function API.signinGo(p, a, reply) POL.units.signIn(p, function(ok, err) reply(ok, err) end) end
function API.signOff(p, a, reply)
    POL.units.signOff(p, function(ok, err, n) reply(ok, err, n) end)
end
function API.status(p, a, reply)
    local u = POL.units.of(p)
    if not u then return reply(false, "not_in_unit") end
    reply(POL.radio.handle(p, (UNIT_STATUS[a.status] or {}).radio or "", {}))
end

POL.net("mdc:call", function(player, reqId, action, args)
    local fn = API[action]
    local function reply(result, err, extra)
        if isElement(player) then triggerClientEvent(player, "pol:mdc:reply", resourceRoot, reqId, result, err, extra) end
    end
    if not fn then return reply(false, "unknown") end
    if not POL.rights.has(player) then return reply(false, "no_right") end
    local ok, e = pcall(fn, player, type(args) == "table" and args or {}, reply)
    if not ok then
        outputDebugString("[police_system] mdc " .. tostring(action) .. ": " .. tostring(e), 1)
        reply(false, "error")
    end
end)

-- the Overview feed only goes to open MDCs, every FEED_INTERVAL, only when it changed
POL.net("mdc:open", function(player, open)
    M.open[player] = open and { last = "" } or nil
end)

addEventHandler("onPlayerQuit", root, function() M.open[source] = nil end)

function M.start()
    setTimer(function()
        for p, o in pairs(M.open) do
            if isElement(p) and POL.rights.has(p) then
                local data = M.overview(p)
                local s = toJSON(data)
                if s ~= o.last then
                    o.last = s
                    triggerClientEvent(p, "pol:mdc:feed", resourceRoot, data)
                end
            else
                M.open[p] = nil
            end
        end
    end, POLICE.MDC.FEED_INTERVAL, 0)
end
