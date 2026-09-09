-- v_customs :: persistence bridge (server)
--
-- The handling / colours / plate / GTA upgrades a player buys are read straight
-- back off the vehicle by v_ownveh (OwnVeh.captureState), so those persist for
-- free. The element-data-only extras do not - this file keeps them on a single
-- "customs:extras" table which v_ownveh serialises into its `customs` column,
-- and re-applies them when v_ownveh restores a stored vehicle.

Customs = Customs or {}

addEvent("v_customs:applyExtras")   -- fired by v_ownveh/state.lua on applyState

--------------------------------------------------------------------------------
-- Extras table helpers
--------------------------------------------------------------------------------

function Customs.getExtras(veh)
    local t = getElementData(veh, "customs:extras")
    return (type(t) == "table") and t or {}
end

function Customs.setExtra(veh, key, value)
    local t = Customs.getExtras(veh)
    if value == nil then
        t[key] = nil
    else
        t[key] = value
    end
    setElementData(veh, "customs:extras", t)   -- synced -> clients + captured by v_ownveh
    return t
end

--------------------------------------------------------------------------------
-- Re-apply on restore
--------------------------------------------------------------------------------

addEventHandler("v_customs:applyExtras", root, function(extras)
    local veh = source
    if not isElement(veh) then return end
    extras = (type(extras) == "table") and extras or Customs.getExtras(veh)

    -- LSD doors / bulletproof tyres are element-data flags the client modules
    -- react to. v_ownveh already setElementData("customs:extras"); mirror the two
    -- flags the modules key on so a mid-life resource restart still works.
    if extras.lsdDoor then
        setElementData(veh, "tuning.lsdDoor", true)
    end
    if extras.bulletproof then
        setElementData(veh, "tuning.bulletProofTires", true)
    end
end)
