--[[
    ui_phone / server/apps/contacts.lua
    Runs (and charges for) the actions offered by Julia and Markus.
]]

PhoneServer.on("contacts:action", function(player, contactKey, actionKey)
    local action = PHONE_CONFIG.contactActionByKey(contactKey, actionKey)
    if not action then return end

    if action.cost and getPlayerMoney(player) < action.cost then
        PhoneServer.toast(player, "Not enough money (need $" .. action.cost .. ").")
        return
    end

    if contactKey == "julia" and actionKey == "heal" then
        takePlayerMoney(player, action.cost)
        setElementHealth(player, 100)
        PhoneServer.toast(player, "Julia patched you up.")

    elseif contactKey == "julia" and actionKey == "armor" then
        takePlayerMoney(player, action.cost)
        setPedArmor(player, 100)
        PhoneServer.toast(player, "Julia refilled your armour.")

    elseif contactKey == "markus" and actionKey == "arena" then
        local ok = getResourceFromName("v_arenawar")
            and pcall(function() exports.v_arenawar:arenawarJoin(player) end)
        if not ok then PhoneServer.toast(player, "Arena War is unavailable right now.") end
        PhoneServer.close(player)

    elseif contactKey == "markus" and actionKey == "job" then
        -- A future job-request flow hooks in here.
        PhoneServer.toast(player, "Markus will get back to you.")
        PhoneServer.close(player)
    end
end)
