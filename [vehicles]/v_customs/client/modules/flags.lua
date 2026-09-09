-- v_customs :: misc flag effects (client)

-- Bulletproof tyres: cancel wheel damage on vehicles carrying the synced flag.
addEventHandler("onClientVehicleDamage", root, function(_, _, _, _, _, _, tyre)
    if not getElementData(source, "tuning.bulletProofTires") then return end
    if tyre and tyre >= 0 and tyre <= 3 then
        cancelEvent()
    end
end)
