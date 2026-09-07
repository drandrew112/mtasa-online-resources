-- Builds the "Spawn vehicle" menu tree from vehicles.xml.
--
-- Every <group> becomes a submenu, every <vehicle> becomes an item that
-- spawns the vehicle (model + name taken from the XML) when Enter is pressed.

local ROOT_MENU_ID  = "spawn_vehicle" -- target of the "Spawn vehicle" item in the "vehicle" menu
local ROOT_MENU_BACK = "vehicle"      -- menu to return to from the tree root

-- Registers a menu for one XML node and, recursively, for all of its sub-groups.
local function buildMenu(node, menuId, title, backId)
    local items = {}

    for _, child in ipairs(xmlNodeGetChildren(node)) do
        local nodeType = xmlNodeGetName(child)

        if nodeType == "group" then
            local name    = xmlNodeGetAttribute(child, "name") or "Group"
            local childId = menuId .. "/" .. name

            buildMenu(child, childId, name, menuId)
            items[#items + 1] = { label = name, type = "submenu", target = childId }

        elseif nodeType == "vehicle" then
            local model = tonumber(xmlNodeGetAttribute(child, "id"))
            local name  = xmlNodeGetAttribute(child, "name")

            if model then
                items[#items + 1] = {
                    label = name or ("Vehicle " .. model),
                    type  = "spawnvehicle",
                    model = model
                }
            end
        end
    end

    registerMenu({
        id    = menuId,
        title = title,
        back  = backId,
        items = items
    })
end

local xml = xmlLoadFile("vehicles.xml")
if xml then
    buildMenu(xml, ROOT_MENU_ID, "Spawn vehicle", ROOT_MENU_BACK)
    xmlUnloadFile(xml)
else
    outputDebugString("ui_inac: could not load vehicles.xml", 1)
end
