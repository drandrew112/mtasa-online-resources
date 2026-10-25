-- gov_perms / client/notify.lua
-- The salary notification of a position (server/salary.lua).

addEvent("gov_perms:salary", true)
addEventHandler("gov_perms:salary", resourceRoot, function(position, gross, tax)
    local text = L.has("gov_perms.salary_paid") and L.text("gov_perms.salary_paid",
        { position = tostring(position), gross = tostring(gross), tax = tostring(tax) }) or tostring(position)
    pcall(function() exports.ui_core:addNotification(L.text("gov_perms.salary_title"), text) end)
end)
