-- police_system / modules/test/server/test.lua
-- Admin test commands (admin_level >= POLICE.ADMIN_LEVEL). Moved here from ui_core: the old /wanted only set GTA's
-- wanted level, the police system never heard of it, so no chase and no AI police started.
--
-- /wanted <0-6> [reason]   sets the level through the wanted module (W.add), 0 = clear. A lower level than the
--                          current one clears first (the module only raises). The result is shown as a notification.

local T = POL.module("test", {})

local function isAdmin(p) return (tonumber(getElementData(p, "admin_level")) or 0) >= POLICE.ADMIN_LEVEL end

function T.setWanted(player, level, reason)
    if level <= 0 then
        POL.wanted.clear(player, "admin")
        return true
    end
    local st = POL.wanted.get(player)
    if st and level < st.level then POL.wanted.clear(player, "admin") end
    return POL.wanted.add(player, reason or "public_shooting", level)
end

addCommandHandler("wanted", function(p, _, lv, reason)
    if not isAdmin(p) then return end
    lv = tonumber(lv)
    if not lv or lv < 0 or lv > POLICE.WANTED.MAX then
        POL.notify(p, "police_system.test.wanted_usage", { max = POLICE.WANTED.MAX })
        return
    end
    lv = math.floor(lv)
    local ok, why = T.setWanted(p, lv, reason)
    if ok then
        POL.notify(p, "police_system.test.wanted_set", { level = lv })
    else
        POL.notify(p, "police_system.test.wanted_failed", { reason = tostring(why) })
    end
    outputDebugString(("[police_system] /wanted %d by %s -> %s %s"):format(lv, getPlayerName(p), tostring(ok), tostring(why or "")))
end)
