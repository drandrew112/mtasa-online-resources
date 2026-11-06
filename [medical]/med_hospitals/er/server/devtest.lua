-- /ertest (admin level 5+): a test patient in the player's ER, on a hospital stretcher on a free corridor
-- spot, as if an EMS crew had handed it over (unit "TEST"). For trying the ER without an ambulance.
--   /ertest [injury type] [severity 1-3] [body part] [side]     e.g. /ertest gunshot 3 abdomen left
--   /ertest walk                                                 a walk-in patient at the entrance

local ADMIN_LEVEL = 5
local SKINS = { 7, 9, 10, 11, 12, 14, 15, 17, 19, 20, 21, 22, 23, 24, 25, 26 }

local function adminLevel(player)
    if not ER.running("v_mysql") then return 0 end
    return tonumber(exports.v_mysql:getAccData(player, "admin_level")) or 0
end

addCommandHandler("ertest", function(player, _, injury, severity, part, side)
    if adminLevel(player) < ADMIN_LEVEL then return end
    local hid = getElementData(player, "hosp.staff")
    if not hid then
        for id in pairs(ER.byHospital) do hid = id break end
    end
    local e = hid and ER.byHospital[hid]
    if not e then return outputChatBox("[ertest] no ER", player) end
    if injury == "walk" then
        if ER.spawnWalkIn then ER.spawnWalkIn(e) end
        return
    end
    local m = ER.running("med_equipments") and exports.med_equipments
    local idx, spot = ER.freeCorridorSpot(hid)
    if not m or not spot then return ER.notify(player, "ertest: no free corridor spot", true) end
    local h = e.h
    local obj = m:createHospitalStretcher(hid, spot.x, spot.y, spot.z, spot.rot or 180, h.dimension, h.interior)
    if not obj then return ER.notify(player, "ertest: stretcher limit", true) end
    local ped = createPed(SKINS[math.random(#SKINS)], spot.x + 1, spot.y, spot.z + 1)
    setElementInterior(ped, h.interior) setElementDimension(ped, h.dimension)
    setElementData(ped, "medic.status", "injured")
    exports.medsys:applyInjury(ped, injury or "fracture", tonumber(severity) or 2, part, side)
    setTimer(function()
        if not isElement(ped) or not isElement(obj) then return end
        m:putPatientOnStretcher(obj, ped)
        local c = ER.createCase(ped, hid, { kind = "ems", unit = "TEST", medics = { getPlayerName(player) }, text = "Teszt beteg (/ertest)", at = getRealTime().timestamp })
        c.location = "F" .. idx
        c.anamnesis = "Teszt beteg (/ertest)"
        ER.syncCase(c)
        ER.notifyStaff(hid, function(p) return L.forPlayer(p, "med_hospitals.er.new_ems_patient", { unit = "TEST", spot = "F" .. idx }) end, true)
    end, 400, 1)
end)
