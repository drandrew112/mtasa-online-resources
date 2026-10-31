-- police_system / modules/rights/server/ranks.lua
-- Ranks = work_police levels (work_core). The rights tied to them (the decision): anyone with the police right
-- issues warrants; editing / revoking someone else's warrant from Hadnagy (level 7); reviewing / refunding fines
-- from Százados (level 9). Admins (POLICE.ADMIN_LEVEL) count as the highest rank.

local K = POL.module("ranks", {})

function K.level(player)
    if not isElement(player) then return 0 end
    if (tonumber(getElementData(player, "admin_level")) or 0) >= POLICE.ADMIN_LEVEL then return 99 end
    if not POL.running("work_core") then return 1 end
    local ok, lv = pcall(function() return exports.work_core:getPlayerWorkLevel(player, POLICE.WORK_ID) end)
    return ok and tonumber(lv) or 1
end

function K.has(player, level) return K.level(player) >= level end
