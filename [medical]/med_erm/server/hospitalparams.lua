-- EMS -> hospital: one-button parameter card and the hospital status on the tablet (med_hospitals ER).
--   erm:paramsRequest  -> erm:paramsData { items = { { key, value, measured, default } }, hospitals, target }
--   erm:paramsSend (hospitalId, keys) -> med_hospitals:receiveParams
-- Only measured values can be sent: the monitor gives pulse / BP / SpO2 / rhythm, the glucometer the
-- glucose (med_docs care log), the injuries and drugs come from the patient's medsys state.

local STATUS_INTERVAL = 20000
local function running(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function patientOf(player, u)
    if running("med_equipments") and isElement(u.vehicle) then
        local st = exports.med_equipments:getVehicleStretcher(u.vehicle)
        local ped = st and exports.med_equipments:getStretcherPatient(st)
        if isElement(ped) then return ped end
    end
    local pushed = getElementData(player, "stretcher.pushing")
    if isElement(pushed) and running("med_equipments") then
        local ped = exports.med_equipments:getStretcherPatient(pushed)
        if isElement(ped) then return ped end
    end
    local px, py, pz = getElementPosition(player)
    local best, bestD
    for _, ped in ipairs(getElementsWithinRange(px, py, pz, 25, "ped")) do
        if getElementData(ped, "medic.status") then
            local x, y, z = getElementPosition(ped)
            local d = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
            if not bestD or d < bestD then best, bestD = ped, d end
        end
    end
    return best
end

local function itemsOf(ped)
    local snap = running("medsys") and exports.medsys:getMedicalState(ped) or {}
    local log = running("med_docs") and exports.med_docs:getPatientCareLog(ped) or {}
    local did = {}
    for _, e in ipairs(log) do did[e.action] = true end
    local monitor = snap.monitor ~= nil or did.monitor
    local items = {}
    local function add(key, value, measured, default) items[#items + 1] = { key = key, value = value, measured = measured, default = default } end
    add("hr", snap.heartRate and (snap.heartRate .. "/min") or "-", monitor, true)
    add("spo2", snap.spo2 and (snap.spo2 .. "%") or "-", monitor, true)
    add("bp", snap.bloodPressure or "-", monitor, true)
    add("glucose", snap.glucose and string.format("%.1f mmol/l", snap.glucose / 18) or "-", did.glucometer == true, false)
    add("rhythm", snap.rhythm or "-", monitor, false)
    add("consciousness", snap.consciousness or "-", true, false)
    add("breathing", snap.breathing or "-", true, false)
    local inj = {}
    for _, i in ipairs(snap.injuries or {}) do inj[#inj + 1] = i.type .. (i.severity and (" " .. i.severity) or "") end
    add("injuries", #inj > 0 and table.concat(inj, ", ") or "-", true, false)
    local drugs = {}
    for _, d in ipairs(snap.drugs or {}) do drugs[#drugs + 1] = tostring(d.id) .. (d.dose and (" " .. d.dose) or "") end
    add("drugs", #drugs > 0 and table.concat(drugs, ", ") or "-", true, false)
    return items
end

local function hospitals()
    return running("med_hospitals") and exports.med_hospitals:getHospitalStatus() or {}
end

local function nearestHospital(player, list)
    local px, py = getElementPosition(player)
    local best, bestD
    for _, h in ipairs(list) do
        local d = getDistanceBetweenPoints2D(px, py, h.x, h.y)
        if not bestD or d < bestD then best, bestD = h, d end
    end
    return best and best.id or false
end

addEvent("erm:paramsRequest", true)
addEventHandler("erm:paramsRequest", resourceRoot, function()
    local player = client
    local u = Units.ofPlayer(player)
    if not u then return end
    local ped = patientOf(player, u)
    local list = hospitals()
    triggerClientEvent(player, "erm:paramsData", resourceRoot, { items = ped and itemsOf(ped) or {}, hospitals = list,
        target = nearestHospital(player, list), patient = ped ~= nil })
end)

addEvent("erm:paramsSend", true)
addEventHandler("erm:paramsSend", resourceRoot, function(hospitalId, keys)
    local player = client
    local u = Units.ofPlayer(player)
    if not u or type(keys) ~= "table" or not running("med_hospitals") then return end
    local ped = patientOf(player, u)
    if not ped then return end
    local want = {}
    for _, k in ipairs(keys) do want[k] = true end
    local items = {}
    for _, it in ipairs(itemsOf(ped)) do
        if want[it.key] and it.measured then items[#items + 1] = { key = it.key, value = it.value } end
    end
    if #items == 0 then return end
    exports.med_hospitals:receiveParams(hospitalId, { unit = u.callsign, medic = (getElementData(player, "displayName") or getPlayerName(player)), items = items, taskId = u.task ~= 0 and u.task or nil })
    triggerClientEvent(player, "erm:notify", resourceRoot, "ERM", L.forPlayer(player, "med_erm.hospital.params_sent"), false)
end)

-- the hospital status of every unit member's tablet (case page line)
setTimer(function()
    if not running("med_hospitals") then return end
    local list = hospitals()
    for _, p in ipairs(getElementsByType("player")) do
        if Units.ofPlayer(p) then triggerClientEvent(p, "erm:hospitalStatus", resourceRoot, list) end
    end
end, STATUS_INTERVAL, 0)

---------------------------------------------------------------- "Kórház" tab: messages with the hospital (med_hospitals er/server/comms.lua)

local function crewOf(u)
    local out = {}
    for p, unit in pairs(Units.byPlayer) do if unit == u and isElement(p) then out[#out + 1] = p end end
    return out
end

local function threadOf(hid, u)
    local th = running("med_hospitals") and exports.med_hospitals:getHospitalThreads(hid, u.callsign) or false
    return type(th) == "table" and th.msgs or {}
end

addEvent("erm:hospThread", true)
addEventHandler("erm:hospThread", resourceRoot, function(hid)
    local u = Units.ofPlayer(client)
    if not u or type(hid) ~= "string" then return end
    triggerClientEvent(client, "erm:hospThread", resourceRoot, hid, threadOf(hid, u))
end)

addEvent("erm:hospMessage", true)
addEventHandler("erm:hospMessage", resourceRoot, function(hid, text)
    local player = client
    local u = Units.ofPlayer(player)
    if not u or type(hid) ~= "string" or type(text) ~= "string" or not running("med_hospitals") then return end
    local name = getElementData(player, "displayName") or getPlayerName(player)
    if not exports.med_hospitals:sendHospitalMessage(hid, { unit = u.callsign, taskId = u.task ~= 0 and u.task or nil, name = name }, text) then
        triggerClientEvent(player, "erm:notify", resourceRoot, "ERM", L.forPlayer(player, "med_erm.hospital.no_er"), true)
    end
end)

-- a new message in a unit's thread: the crew's tablets get the thread again
addEvent("onHospitalMessage")
addEventHandler("onHospitalMessage", root, function(hid, key, msg)
    local unit = tostring(key):match("^unit:(.+)$")
    if not unit then return end
    for _, u in pairs(Units.byPlayer) do
        if u.callsign == unit then
            for _, p in ipairs(crewOf(u)) do
                triggerClientEvent(p, "erm:hospThread", resourceRoot, hid, threadOf(hid, u))
                if msg.side == "hospital" then
                    triggerClientEvent(p, "erm:notify", resourceRoot, "ERM", L.forPlayer(p, "med_erm.hospital.new_message", { from = msg.from or "?", text = msg.text or "" }), false)
                end
            end
            break
        end
    end
end)
