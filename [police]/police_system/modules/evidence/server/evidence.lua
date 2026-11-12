-- police_system / modules/evidence/server/evidence.lua
-- Evidence (2026-11-12). Every unit gets a police evidence box (v_inventory pol_evidence_box, the blood box model) in
-- the trunk of its unit vehicle at sign-in; the box follows the unit vehicle when the unit changes cars.
-- Seizing: the questionable / illegal items a search found (search.lua S.done) are seized from the stop menu
-- ("Seize evidence": all at once or one by one). Each one becomes a pol_evidence item whose meta says what it is, whom
-- it was taken from, who seized it and when. Where it goes: straight into the unit's box when the unit vehicle is
-- within DIRECT_DIST of the officer, otherwise into a sealed evidence bag (pol_evidence_bag) in the officer's hand
-- ("Store evidence" on the unit vehicle empties the officer's bags into the box). No free hand: nothing is seized.
-- Delivery: a v_inventory port at the station (STATIONS[i].evidence), only for officers in a unit. Dropping an
-- evidence item, a bag or the box itself on it delivers the items: a pol_evidence row each, the delivering officer gets
-- PAY.evidence per item at the end of the duty, the box goes back into the officer's hand. While the unit has
-- undelivered evidence (box, bags of the members) it cannot sign off (units.lua) and a member holding bags cannot
-- leave. Element data pol.unitcs = callsign on the members: trunk / box / port access.

local EV = POL.module("evidence", { boxes = {}, boxUnit = {}, trunks = {}, vehOf = {}, ports = {}, batch = {} })
local C = POLICE.EVIDENCE
local KEY = "pol.unitcs"

local function inv() return POL.running("v_inventory") and exports.v_inventory or nil end

------------------------------------------------------------------------ access data on the members

function EV.syncData()
    local seen = {}
    for _, unit in pairs(POL.units.list) do
        for _, p in ipairs(POL.units.members(unit)) do
            seen[p] = true
            if getElementData(p, KEY) ~= unit.callsign then setElementData(p, KEY, unit.callsign) end
        end
    end
    for _, p in ipairs(getElementsByType("player")) do
        if not seen[p] and getElementData(p, KEY) then removeElementData(p, KEY) end
    end
end

------------------------------------------------------------------------ the box in the unit vehicle

local function boxDisplay(unit)
    return { { label = L.msg("police_system.evidence.box_unit"), value = unit.callsign } }
end

-- the trunk of the unit vehicle (made when the car has none; a trunk of another resource is used as it is)
local function ensureTrunk(veh, unit)
    local i = inv()
    if not i or not isElement(veh) then return false end
    if not i:hasTrunk(veh) then
        if not i:createTrunk(veh, { capacity = C.TRUNK_CAPACITY, dataKey = KEY, dataValue = unit.callsign,
            title = L.msg("police_system.evidence.trunk_title", { callsign = unit.callsign }) }) then return false end
        EV.trunks[veh] = unit
    elseif EV.trunks[veh] then
        EV.trunks[veh] = unit
        i:setTrunkAccess(veh, KEY, unit.callsign)
    end
    return true
end

-- our trunk on an old unit vehicle: whatever is still in it moves along (to the new trunk), then it goes
local function dropTrunk(veh, toVeh)
    local i = inv()
    if not i or not EV.trunks[veh] then return end
    EV.trunks[veh] = nil
    if not isElement(veh) then return end
    for _, uid in ipairs(i:getTrunkItems(veh) or {}) do
        if toVeh and i:hasTrunk(toVeh) then i:addTrunkItem(toVeh, uid) else i:destroyInventoryItem(uid) end
    end
    i:destroyTrunk(veh)
end

function EV.ensureBox(unit)
    local i = inv()
    if not i or not POL.units.list[unit.id] then return end
    local veh = unit.vehicle
    if not isElement(veh) or not ensureTrunk(veh, unit) then return end
    local uid = EV.boxes[unit.id]
    if uid and i:isItem(uid) then
        local it = i:getItem(uid)
        -- in the old car's trunk (or nowhere): into this one; carried by someone: left alone
        if it and it.loc and (it.loc.type == "trunk" or it.loc.type == "none") and it.loc.vehicle ~= veh then
            i:addTrunkItem(veh, uid)
        end
    else
        uid = i:createItem("pol_evidence_box", { unit = unit.callsign, display = boxDisplay(unit) },
            { type = "trunk", vehicle = veh }, { access = { dataKey = KEY, dataValue = unit.callsign } })
        if not uid then
            outputDebugString("[police_system] evidence: no box for " .. tostring(unit.callsign), 2)
            return
        end
        EV.boxes[unit.id] = uid
        EV.boxUnit[uid] = unit
    end
    local old = EV.vehOf[unit.id]
    EV.vehOf[unit.id] = veh
    if old and old ~= veh and EV.trunks[old] == unit then dropTrunk(old, veh) end
end

-- the unit ended: box (with whatever is left, already logged as lost by units.lua's caller) and trunk go
local function removeUnit(unit)
    local i = inv()
    local uid = EV.boxes[unit.id]
    EV.boxes[unit.id] = nil
    if uid then
        EV.boxUnit[uid] = nil
        if i and i:isItem(uid) then i:destroyInventoryItem(uid) end
    end
    local veh = EV.vehOf[unit.id]
    EV.vehOf[unit.id] = nil
    if veh and EV.trunks[veh] == unit then dropTrunk(veh, nil) end
end

------------------------------------------------------------------------ counting what is not delivered

local function heldBags(i, player)
    local out = {}
    for _, uid in pairs(i:getPlayerSlots(player) or {}) do
        local it = i:getItem(uid)
        if it and it.def == "pol_evidence_bag" then out[#out + 1] = uid end
    end
    return out
end

local function contentCount(i, uid)
    local n = 0
    for _, c in ipairs(i:getContainerContents(uid) or {}) do n = n + (c.amount or 1) end
    return n
end

-- undelivered evidence items of a member (bags in the hands)
function EV.pendingOf(player)
    local i = inv()
    if not i or not isElement(player) then return 0 end
    local n = 0
    for _, b in ipairs(heldBags(i, player)) do n = n + math.max(1, contentCount(i, b)) end
    return n
end

-- undelivered evidence items of a unit (its box + the bags of its members)
function EV.pendingCount(unit)
    local i = inv()
    if not i or not unit then return 0 end
    local n = 0
    local uid = EV.boxes[unit.id]
    if uid and i:isItem(uid) then n = n + contentCount(i, uid) end
    for _, p in ipairs(POL.units.members(unit)) do n = n + EV.pendingOf(p) end
    return n
end

------------------------------------------------------------------------ seizing

local function seizedSet(el)
    POL.search.seized[el] = POL.search.seized[el] or {}
    return POL.search.seized[el]
end

-- the questionable / illegal items found on el (searched already) and not seized yet -> { id... }
function EV.seizable(el)
    local out = {}
    local found = isElement(el) and POL.search.done[el]
    if not found or not POL.search.searched[el] then return out end
    local seized = POL.search.seized[el] or {}
    for _, id in ipairs(found) do
        local c = POL.search.classOf(id)
        if (c == "illegal" or c == "questionable") and not seized[id] then out[#out + 1] = id end
    end
    return out
end

-- the unit vehicle close to the officer with the box in its trunk -> box uid
local function boxNear(officer, unit)
    local i = inv()
    local uid = EV.boxes[unit.id]
    local veh = unit.vehicle
    if not i or not uid or not i:isItem(uid) or not isElement(veh) then return nil end
    local it = i:getItem(uid)
    if not (it.loc and it.loc.type == "trunk" and it.loc.vehicle == veh) then return nil end
    if getElementDimension(veh) ~= getElementDimension(officer) or POL.dist(officer, veh) > C.DIRECT_DIST then return nil end
    return uid
end

-- a bag in the officer's hand with room, else a new one in a free hand -> uid | nil
local function bagFor(officer, unit)
    local i = inv()
    for _, b in ipairs(heldBags(i, officer)) do
        local used, cap = i:getContainerWeight(b)
        if used and cap and used + C.ITEM_WEIGHT <= cap then return b end
    end
    local slots = i:getPlayerSlots(officer)
    if slots.left and slots.right then return nil end
    local uid = i:createItem("pol_evidence_bag", { unit = unit.callsign,
        display = { { label = L.msg("police_system.evidence.box_unit"), value = unit.callsign } } },
        { type = "none" }, { access = { dataKey = KEY, dataValue = unit.callsign } })
    if not uid then return nil end
    if not i:giveItemToPlayer(officer, uid) then i:destroyInventoryItem(uid); return nil end
    return uid
end

-- seize ids (nil = every seizable one) found on el; s = the stop
function EV.seize(officer, el, ids, s)
    local i = inv()
    local unit = POL.units.of(officer)
    if not i or not unit or not isElement(el) then return POL.notify(officer, "police_system.evidence.unavailable") end
    local can, want = {}, nil
    for _, id in ipairs(EV.seizable(el)) do can[id] = true end
    if ids then want = {}; for _, id in ipairs(ids) do if can[id] then want[#want + 1] = id end end
    else want = EV.seizable(el) end
    if #want == 0 then return POL.notify(officer, "police_system.evidence.nothing") end
    local isVeh = getElementType(el) == "vehicle"
    local plate = isVeh and getVehiclePlateText(el) or nil
    local person = isVeh and (s and s.person or getVehicleController(el)) or el
    local from = isVeh and (plate .. (isElement(person) and (" · " .. POL.stop.nameOf(person)) or "")) or POL.stop.nameOf(el)
    local cid = s and s.citizenId or (isElement(person) and getElementData(person, "pol.cid")) or nil
    local inc = (s and s.inc) or POL.events.incidentOf(unit, el)
    local box = boxNear(officer, unit)
    local into, where
    if box then into, where = box, "box" else into, where = bagFor(officer, unit), "bag" end
    if not into then return POL.notify(officer, "police_system.evidence.hands_full") end
    local seized, done = seizedSet(el), {}
    local now = POL.now()
    local t = getRealTime(now)
    local stamp = ("%04d-%02d-%02d %02d:%02d"):format(t.year + 1900, t.month + 1, t.monthday, t.hour, t.minute)
    for _, id in ipairs(want) do
        local meta = {
            item = id, class = POL.search.classOf(id), from = from, citizenId = cid, plate = plate,
            officer = POL.nameOf(officer), officerAcc = POL.accountOf(officer), unit = unit.callsign,
            inc = inc and inc.id or nil, at = now,
            display = {
                { label = L.msg("police_system.evidence.meta_item"), value = L.msg("police_system.item." .. id) },
                { label = L.msg("police_system.evidence.meta_from"), value = from },
                { label = L.msg("police_system.evidence.meta_by"), value = POL.nameOf(officer) .. " (" .. unit.callsign .. ")" },
                { label = L.msg("police_system.evidence.meta_at"), value = stamp },
            },
        }
        local uid = i:createItem("pol_evidence", meta, { type = "container", container = into },
            { access = { dataKey = KEY, dataValue = unit.callsign } })
        if not uid and where == "box" then
            -- the box is full: the rest goes into a bag
            local bag = bagFor(officer, unit)
            if bag then
                into, where = bag, "bag"
                uid = i:createItem("pol_evidence", meta, { type = "container", container = into },
                    { access = { dataKey = KEY, dataValue = unit.callsign } })
            end
        end
        if not uid then break end
        seized[id] = true
        done[#done + 1] = id
    end
    if #done == 0 then return POL.notify(officer, "police_system.evidence.hands_full") end
    POL.events.log(unit, officer, "evidence_seized", { name = from, items = done, where = where }, inc)
    POL.notify(officer, where == "box" and "police_system.evidence.seized_box" or "police_system.evidence.seized_bag",
        { count = #done })
    POL.emit("evidence.seized", officer, el, done)
end

-- "Store evidence" on the unit vehicle: the bags in the officer's hands are emptied into the box
function EV.store(officer, veh)
    local i = inv()
    local unit = POL.units.of(officer)
    if not i or not unit then return end
    if veh ~= unit.vehicle then return POL.notify(officer, "police_system.evidence.not_unit_vehicle") end
    local box = boxNear(officer, unit)
    if not box then return POL.notify(officer, "police_system.evidence.no_box") end
    local moved = 0
    for _, bag in ipairs(heldBags(i, officer)) do
        for _, uid in ipairs(i:getContainerItems(bag) or {}) do
            if i:moveInventoryItem(uid, { type = "container", container = box }) then moved = moved + 1 end
        end
        if #(i:getContainerItems(bag) or {}) == 0 then i:destroyInventoryItem(bag) end
    end
    if moved == 0 then return POL.notify(officer, "police_system.evidence.nothing_to_store") end
    POL.events.logFor(officer, "evidence_stored", { count = moved })
    POL.notify(officer, "police_system.evidence.stored", { count = moved })
end

-- sign off refused for evidence: the officer is told and the unit gets the objective of the nearest drop-off
function EV.showDropOff(unit, player)
    local x, y = getElementPosition(player)
    local best, bd
    for _, st in ipairs(POLICE.STATIONS) do
        local e = st.evidence
        if e then
            local d = (e[1] - x) ^ 2 + (e[2] - y) ^ 2
            if not bd or d < bd then best, bd = st, d end
        end
    end
    POL.notify(player, "police_system.evidence.signoff_blocked", { count = EV.pendingCount(unit) })
    if best then
        POL.callouts.setObjective(unit, best.evidence[1], best.evidence[2], best.evidence[3], "police_system.evidence.objective")
        unit.evObjective = true
    end
end

function EV.hasBags(officer)
    local i = inv()
    return i and #heldBags(i, officer) > 0 or false
end

------------------------------------------------------------------------ delivery (station port)

local function stationOfPort(id)
    for _, p in pairs(EV.ports) do if p.id == id then return p.station end end
    return nil
end

local function flushBatch(player)
    local b = EV.batch[player]
    EV.batch[player] = nil
    if not b or not isElement(player) then return end
    POL.notify(player, "police_system.evidence.delivered", { count = b.count, money = b.count * POL.pay.wage("evidence") })
    POL.events.logFor(player, "evidence_delivered", { count = b.count, station = b.station })
end

-- one evidence item delivered: a pol_evidence row, the officer's pay counter
local function deliverItem(i, uid, player, station)
    local it = i:getItem(uid)
    if not it or it.def ~= "pol_evidence" then return 0 end
    local m = type(it.meta) == "table" and it.meta or {}
    local n = math.max(1, tonumber(it.amount) or 1)
    POL.db.create("pol_evidence", {
        citizen_id = tonumber(m.citizenId), item = tostring(m.item or "?"), class = tostring(m.class or "legal"),
        from_name = tostring(m.from or ""):sub(1, 96), plate = m.plate and tostring(m.plate):sub(1, 16) or nil,
        officer_acc = m.officerAcc, officer_name = m.officer, unit = m.unit, incident_id = m.inc and tostring(m.inc) or nil,
        seized_at = tonumber(m.at) or 0, delivered_at = POL.now(), delivered_by = POL.accountOf(player),
        station = station and station.id or nil,
    }, function() end)
    i:destroyInventoryItem(uid)
    return n
end

local function onDelivered(portId, player, uid, dir)
    if dir ~= "in" then return end
    local station = stationOfPort(portId)
    local i = inv()
    if not station or not i or not isElement(player) then return end
    local unit = POL.units.of(player)
    local it = i:getItem(uid)
    if not it then return end
    local count = 0
    if it.def == "pol_evidence" then
        count = deliverItem(i, uid, player, station)
    elseif it.def == "pol_evidence_bag" or it.def == "pol_evidence_box" then
        for _, c in ipairs(i:getContainerItems(uid) or {}) do count = count + deliverItem(i, c, player, station) end
        if it.def == "pol_evidence_bag" then
            i:destroyInventoryItem(uid)
        else
            -- the box goes back to the officer (hand), else into the unit vehicle's trunk
            local owner = EV.boxUnit[uid]
            local ok = i:removePortItem(portId, uid, { type = "none" })
            if ok and not i:giveItemToPlayer(player, uid) then
                if owner and isElement(owner.vehicle) and i:hasTrunk(owner.vehicle) then i:addTrunkItem(owner.vehicle, uid)
                else i:destroyInventoryItem(uid) end
            end
        end
    else
        return
    end
    if count <= 0 then return end
    if unit then
        local acc = POL.accountOf(player)
        if acc then
            unit.evPay = unit.evPay or {}
            unit.evPay[acc] = unit.evPay[acc] or { evidence = 0 }
            unit.evPay[acc].evidence = unit.evPay[acc].evidence + count
        end
    end
    POL.db.stat("evidence", count)
    local b = EV.batch[player]
    if not b then
        b = { count = 0, station = station.name }
        EV.batch[player] = b
        setTimer(function() flushBatch(player) end, 600, 1)
    end
    b.count = b.count + count
    POL.emit("evidence.delivered", player, count)
end

local function createPorts()
    local i = inv()
    if not i then return end
    for _, p in pairs(EV.ports) do i:destroyPort(p.id) end
    EV.ports = {}
    for _, st in ipairs(POLICE.STATIONS) do
        local e = st.evidence
        if e then
            local id = i:createPort({ x = e[1], y = e[2], z = e[3] - 1, dimension = e.dimension or 0, interior = e.interior or 0,
                radius = C.PORT_RADIUS, name = L.msg("police_system.evidence.port_name"),
                title = L.msg("police_system.evidence.port_title", { station = st.name }), icon = "E",
                color = { 70, 140, 255 }, accepts = { "evidence" }, dataKey = KEY })
            if id then EV.ports[#EV.ports + 1] = { id = id, station = st } end
        end
    end
end

addEvent("onPortItemMoved")
addEventHandler("onPortItemMoved", root, function(portId, player, uid, dir)
    local ok, err = pcall(onDelivered, portId, player, uid, dir)
    if not ok then outputDebugString("[police_system] evidence delivery: " .. tostring(err), 1) end
end)

------------------------------------------------------------------------ lifecycle

POL.on("unit.signedIn", function(unit)
    EV.syncData()
    EV.ensureBox(unit)
end)

POL.on("units.member", function() EV.syncData() end)
POL.on("units.changed", function() EV.syncData() end)

POL.on("unit.signedOff", function(unit)
    local left = EV.pendingCount(unit)
    if left > 0 then
        -- a forced end (leader quit, right lost, restart): what was not delivered is lost, logged
        POL.events.log(unit, nil, "evidence_lost", { count = left })
        local i = inv()
        if i then
            for _, p in ipairs(POL.units.members(unit)) do
                for _, b in ipairs(heldBags(i, p)) do i:destroyInventoryItem(b) end
            end
        end
    end
    removeUnit(unit)
    EV.syncData()
end)

-- a member leaving the unit with bags: they are destroyed (units.lua refuses a voluntary leave while holding them)
POL.on("units.member", function(unit, player, joined)
    if joined or not isElement(player) then return end
    local i = inv()
    if not i then return end
    local bags = heldBags(i, player)
    if #bags > 0 then
        POL.events.log(unit, player, "evidence_lost", { count = EV.pendingOf(player) })
        for _, b in ipairs(bags) do i:destroyInventoryItem(b) end
    end
end)

-- the unit vehicle changed (units.lua: the last police car a member drives) / the box was lost: checked every 2 s
local function tick()
    for id, unit in pairs(POL.units.list) do
        -- the drop-off objective (refused sign off) goes once everything is delivered
        if unit.evObjective and EV.pendingCount(unit) == 0 then
            unit.evObjective = nil
            POL.callouts.clearObjective(unit)
        end
        if isElement(unit.vehicle) and (EV.vehOf[id] ~= unit.vehicle or not (EV.boxes[id] and inv() and inv():isItem(EV.boxes[id]))) then
            EV.ensureBox(unit)
        end
    end
end

addEvent("onInventoryReady")
addEventHandler("onInventoryReady", root, function()
    EV.boxes, EV.boxUnit, EV.trunks, EV.vehOf = {}, {}, {}, {}
    createPorts()
    for _, unit in pairs(POL.units.list) do EV.ensureBox(unit) end
end)

addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) == "v_inventory" then EV.ports = {} end
end)

function EV.start()
    createPorts()
    EV.syncData()
    for _, unit in pairs(POL.units.list) do EV.ensureBox(unit) end
    setTimer(function()
        local ok, err = pcall(tick)
        if not ok then outputDebugString("[police_system] evidence: " .. tostring(err), 1) end
    end, 2000, 0)
end

function EV.stop()
    local i = inv()
    if not i then return end
    for _, unit in pairs(POL.units.list) do removeUnit(unit) end
    for _, p in pairs(EV.ports) do i:destroyPort(p.id) end
    EV.ports = {}
    for _, p in ipairs(getElementsByType("player")) do
        for _, b in ipairs(heldBags(i, p)) do i:destroyInventoryItem(b) end
        if getElementData(p, KEY) then removeElementData(p, KEY) end
    end
end
