if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Organizations (biz_core) inside the interaction menu: the server side of
-- client/business.lua. Rename goes through biz_core:renameCompany (cost and
-- rules there); the property list carries the positions for the GPS.

local function bizRunning()
    local r = getResourceFromName("biz_core")
    return r and getResourceState(r) == "running"
end

local ERRORS = {
    name_short = "ui_inac.business.err_name_short",
    name_long = "ui_inac.business.err_name_long",
    name_invalid = "ui_inac.business.err_name_invalid",
    name_taken = "ui_inac.business.err_name_taken",
    name_same = "ui_inac.business.err_name_same",
    rename_cooldown = "ui_inac.business.err_rename_cooldown",
    not_enough_money = "ui_inac.business.err_not_enough_money",
}

addEvent("ui_inac:bizRename", true)
addEventHandler("ui_inac:bizRename", root, function(name)
    local player = client
    if not player or not bizRunning() or type(name) ~= "string" then return end
    local r = exports.biz_core:renameCompany(player, name)
    if type(r) == "table" and not r.ok then
        triggerClientEvent(player, "ui_inac:notify", resourceRoot, L.msg("ui_inac.business.my_organization"),
            L.msg(ERRORS[r.error] or "ui_inac.business.err_failed"))
    end
end)

addEvent("ui_inac:bizProperties", true)
addEventHandler("ui_inac:bizProperties", root, function()
    local player = client
    if not player then return end
    local list = {}
    if bizRunning() then
        local c = exports.biz_core:getPlayerCompany(player)
        for _, u in ipairs(c and c.units or {}) do
            local p = exports.biz_core:getProperty(u.propertyId)
            if p and p.x then
                list[#list + 1] = { name = u.name, city = p.city, x = p.x, y = p.y }
            end
        end
    end
    triggerClientEvent(player, "ui_inac:bizPropertyList", resourceRoot, list)
end)
