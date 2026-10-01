-- Client side of the medic role (server/treatment.lua owns it), for client scripts of other
-- resources, e.g. the EMS tablet. Only for UI decisions: the server checks the role itself.

-- Is the medic role checked at all (fixed while the resource runs, query it once)
function isMedicRoleRequired()
    return MEDIC.REQUIRE_MEDIC_ROLE == true
end

-- Does the player hold the medic role (the bare flag)
function isPlayerMedic(player)
    player = player or localPlayer
    return isElement(player) and getElementData(player, MEDIC.DATA_ROLE) == true
end

-- May the player work as a medic: always when the role is not required, otherwise with the role
function hasMedicAccess(player)
    return not MEDIC.REQUIRE_MEDIC_ROLE or isPlayerMedic(player)
end
