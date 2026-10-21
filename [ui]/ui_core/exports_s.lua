
-- Penzmozgas kijelzese egy jatekosnak (a kliens oldali showMoney parja):
--   kind = "add" | "take", change = pozitiv osszeg, moneyType = "cash" | "bank"
-- Mindegyik kotelezo; rossz ertekre error + false.
-- Csak kijelzes - a penzt a hivo valtoztatja (givePlayerMoney, v_bank exportok).
function showMoney(player, kind, change, moneyType)
    local who = sourceResource and getResourceName(sourceResource) or "?"
    if not isElement(player) or getElementType(player) ~= "player" then
        outputDebugString(("[ui_core] showMoney (%s): invalid player"):format(who), 1)
        return false
    end
    if kind ~= "add" and kind ~= "take" then
        outputDebugString(("[ui_core] showMoney (%s): kind must be \"add\" or \"take\" (got %s)"):format(who, tostring(kind)), 1)
        return false
    end
    if moneyType ~= "cash" and moneyType ~= "bank" then
        outputDebugString(("[ui_core] showMoney (%s): moneyType must be \"cash\" or \"bank\" (got %s)"):format(who, tostring(moneyType)), 1)
        return false
    end
    change = tonumber(change)
    if not change or change <= 0 then
        outputDebugString(("[ui_core] showMoney (%s): change must be a positive number (got %s)"):format(who, tostring(change)), 1)
        return false
    end
    return triggerClientEvent(player, "ui_core:showMoney", resourceRoot, kind, change, moneyType)
end

function toggleMoveControls_s(player, v)
    toggleControl(player, "forwards", v)
    toggleControl(player, "backwards", v)
    toggleControl(player, "left", v)
    toggleControl(player, "right", v)
    toggleControl(player, "change_camera", v)
    toggleControl(player, "jump", v)
    toggleControl(player, "sprint", v)
    toggleControl(player, "look_behind", v)
    toggleControl(player, "crouch", v)
    toggleControl(player, "fire", v)
    toggleControl(player, "aim_weapon", v)
    toggleControl(player, "next_weapon", v)
    toggleControl(player, "previous_weapon", v)
    toggleControl(player, "action", v)
    toggleControl(player, "walk", v)
    toggleControl(player, "group_control_forwards", v)
    toggleControl(player, "group_control_back", v)
    toggleControl(player, "enter_exit", v)
    toggleControl(player, "vehicle_fire", v)
    toggleControl(player, "vehicle_secondary_fire", v)
    toggleControl(player, "steer_forward", v)
    toggleControl(player, "steer_back", v)
    toggleControl(player, "accelerate", v)
    toggleControl(player, "brake_reverse", v)
    toggleControl(player, "horn", v)
    toggleControl(player, "handbrake", v)
    toggleControl(player, "vehicle_left", v)
    toggleControl(player, "vehicle_right", v)
end
