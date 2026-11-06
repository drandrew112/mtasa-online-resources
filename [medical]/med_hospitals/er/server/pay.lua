-- ER money (plan: Fizetés és költségek), with staff on duty:
--   * every closed case: its intervention points * health.point_care, paid by the hospital's "care"
--     payer (gov_health, /gov Healthcare); the money disappears (receiver "system")
--   * stock orders: the hospital's "supplies" payer
--   * staff salary: work_hospital -> work_core payWork with the hospital's "salary" payer
--   * Ú9: a payer that cannot cover it -> the system pays, /gov shows a warning (gov_health)
-- Without staff the old gov_health chargeHealthcare runs at the EMS handover (server/handover.lua).

local function gh() return ER.running("gov_health") and exports.gov_health or nil end

local oldClosed = ER.onCaseClosed
ER.onCaseClosed = function(c)
    if oldClosed then oldClosed(c) end
    -- Ú11: a closed, documented case counts for the treating doctor's Physician exam
    if isElement(c.treating) and #(c.diagnoses or {}) > 0 and ER.running("work_hospital") then
        exports.work_hospital:addHospitalTreatedCase(c.treating)
    end
    local points = c.pointsTotal or 0
    if points <= 0 or c.carePaid then return end
    local g = gh()
    if not g then return end
    c.carePaid = true
    local h = Hospitals.byId[c.hospital]
    local ok, amount = g:payHospitalCare(c.hospital, points, { case = c.id, patient = c.name or ("ER #" .. tostring(c.id)), hospital = h and h.name or c.hospital })
    if ok then ER.log(c, "care_paid", tostring(amount or 0)) end
end

-- stock order (er/server/stock.lua ER.orderStock) -> true | false
function ER.paySupplies(hid, cost, player)
    local g = gh()
    if not g then return true end
    local h = Hospitals.byId[hid]
    local ok = g:payHospitalSupplies(hid, cost, { hospital = h and h.name or hid })
    return ok ~= false
end
