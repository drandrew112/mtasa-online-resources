if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- world_interiors / client/admin.lua — /interiors + /intwatch browsers (ui_inac temp menu)

addEvent("world_interiors:adminList", true)

local menuId

local function fmtPoint(p, dim)
    return L("world_interiors.admin.int_dim", { x = p.x, y = p.y, z = p.z, interior = p.interior, dimension = dim or p.dimension or 0 })
end

local function buildRegistered(list)
    local items = {}
    for _, it in ipairs(list) do
        items[#items + 1] = {
            label = it.name, title = it.name,
            desc = L("world_interiors.admin.dim_int_by", { id = it.id, dimension = it.dimension, interior = it.exit.interior, resource = it.resource }),
            items = {
                { label = L("world_interiors.admin.go_to_entrance"), desc = fmtPoint(it.enter), value = { mode = "registered", act = "tp", id = it.id, where = "enter" }, closeOnSelect = false },
                { label = L("world_interiors.admin.go_inside"), desc = fmtPoint(it.exit, it.dimension), value = { mode = "registered", act = "tp", id = it.id, where = "exit" }, closeOnSelect = false },
            },
        }
    end
    if #list == 0 then
        items[#items + 1] = { label = L("world_interiors.admin.no_interiors_registered"), desc = L("world_interiors.admin.resources_register_them_via_exports_world"), value = { act = "none" } }
    end
    return items
end

local function buildStock(list)
    local items = {}
    for i, g in ipairs(list) do
        local sub = {
            { label = L("world_interiors.admin.go_inside"), desc = fmtPoint(g.inside), value = { mode = "stock", act = "tp", id = i, where = "inside" }, closeOnSelect = false },
        }
        for j, e in ipairs(g.entrances) do
            sub[#sub + 1] = {
                label = L("world_interiors.admin.entrance", { id = e.id }), desc = fmtPoint(e),
                value = { mode = "stock", act = "tp", id = i, where = j }, closeOnSelect = false,
            }
        end
        local desc = #g.entrances > 0 and L("world_interiors.admin.int_entrance_s", { interior = g.inside.interior, entrances = #g.entrances })
            or L("world_interiors.admin.int_no_stock_entrance_wiki", { interior = g.inside.interior })
        if g.aliases and #g.aliases > 0 then desc = L("world_interiors.admin.also", { desc = desc, aliases = table.concat(g.aliases, ", ") }) end
        local label = g.name
        if g.label and g.label ~= "" and g.label ~= g.name then label = g.label .. " [" .. g.name .. "]" end
        items[#items + 1] = { label = label, title = label, desc = desc, items = sub }
    end
    return items
end

addEventHandler("world_interiors:adminList", resourceRoot, function(mode, list, canGoBack)
    local items = mode == "stock" and buildStock(list) or buildRegistered(list)
    if canGoBack then
        table.insert(items, 1, { label = L("world_interiors.admin.back_to_previous_position"), desc = L("world_interiors.admin.return_to_where_you_were_before"), value = { act = "back" } })
    end
    local title = (mode == "stock" and L("world_interiors.admin.stock_interiors") or L("world_interiors.admin.interiors")) .. #list .. ")"
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
