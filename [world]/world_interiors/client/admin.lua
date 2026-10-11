-- world_interiors / client/admin.lua — /interiors + /intwatch browsers (ui_inac temp menu)

addEvent("world_interiors:adminList", true)

local menuId

local function fmtPoint(p, dim)
    return ("%.1f, %.1f, %.1f (int %d, dim %d)"):format(p.x, p.y, p.z, p.interior, dim or p.dimension or 0)
end

local function buildRegistered(list)
    local items = {}
    for _, it in ipairs(list) do
        items[#items + 1] = {
            label = it.name, title = it.name,
            desc = ("%s | dim %d | int %d | by %s"):format(it.id, it.dimension, it.exit.interior, it.resource),
            items = {
                { label = "Go to entrance", desc = fmtPoint(it.enter), value = { mode = "registered", act = "tp", id = it.id, where = "enter" }, closeOnSelect = false },
                { label = "Go inside", desc = fmtPoint(it.exit, it.dimension), value = { mode = "registered", act = "tp", id = it.id, where = "exit" }, closeOnSelect = false },
            },
        }
    end
    if #list == 0 then
        items[#items + 1] = { label = "No interiors registered", desc = "Resources register them via exports.world_interiors:registerInterior", value = { act = "none" } }
    end
    return items
end

local function buildStock(list)
    local items = {}
    for i, g in ipairs(list) do
        local sub = {
            { label = "Go inside", desc = fmtPoint(g.inside), value = { mode = "stock", act = "tp", id = i, where = "inside" }, closeOnSelect = false },
        }
        for j, e in ipairs(g.entrances) do
            sub[#sub + 1] = {
                label = "Entrance: " .. e.id, desc = fmtPoint(e),
                value = { mode = "stock", act = "tp", id = i, where = j }, closeOnSelect = false,
            }
        end
        local desc = #g.entrances > 0 and ("int %d | %d entrance(s)"):format(g.inside.interior, #g.entrances)
            or ("int %d | no stock entrance (wiki)"):format(g.inside.interior)
        if g.aliases and #g.aliases > 0 then desc = desc .. " | also: " .. table.concat(g.aliases, ", ") end
        local label = g.name
        if g.label and g.label ~= "" and g.label ~= g.name then label = g.label .. " [" .. g.name .. "]" end
        items[#items + 1] = { label = label, title = label, desc = desc, items = sub }
    end
    return items
end

addEventHandler("world_interiors:adminList", resourceRoot, function(mode, list, canGoBack)
    local items = mode == "stock" and buildStock(list) or buildRegistered(list)
    if canGoBack then
        table.insert(items, 1, { label = "<< Back to previous position", desc = "Return to where you were before browsing", value = { act = "back" } })
    end
    local title = (mode == "stock" and "Stock interiors (" or "Interiors (") .. #list .. ")"
    if exports.ui_inac:isTempMenuOpen() then exports.ui_inac:closeTempMenu() end
    menuId = exports.ui_inac:createTempMenu({ title = title, items = items })
end)

addEventHandler("ui_inac:tempMenuSelect", root, function(id, value)
    if id ~= menuId or type(value) ~= "table" then return end
    if value.act == "tp" then
        triggerServerEvent("world_interiors:adminTeleport", resourceRoot, value.mode, value.id, value.where)
    elseif value.act == "back" then
        triggerServerEvent("world_interiors:adminBack", resourceRoot)
    end
end)

addEventHandler("ui_inac:tempMenuClose", root, function(id)
    if id == menuId then menuId = nil end
end)
