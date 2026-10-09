-- On foot, every editor element gets a ui_interactobject menu (Q/E focus, X open,
-- number keys). In freecam the cursor shows, which hides these menus; clicking
-- an element opens the ui_inac item menu instead.

Interact = { ids = {} }

local DEF = {
    title = "Editor",
    range = 6,
    lineOfSight = false,
    allowInVehicle = false,
    dataKey = "jobcreator.item",
    items = {
        { label = "Move", value = "move" },
        { label = "Duplicate", value = "dup" },
        { label = "Options...", value = "options" },
        { label = "Delete", value = "delete" },
    },
}

function Interact.register()
    Interact.unregister()
    for _, elementType in ipairs({ "object", "vehicle", "ped" }) do
        local id = iobj:addInteractTypeMenu(elementType, DEF)
        if id then Interact.ids[id] = true end
    end
end

function Interact.unregister()
    for id in pairs(Interact.ids) do iobj:removeInteractMenu(id) end
    Interact.ids = {}
end

addEventHandler("onClientInteractMenuSelect", root, function(menuId, value, target)
    if not Interact.ids[menuId] or not Editor.active or Editor.testing then return end
    local item = View.byElement[target]
    if not item then return end
    Editor.selected = item
    if value == "move" then
        if Kinds[item.kind].fixed then return Menus.openItem(item) end
        Tools.move(item)
    elseif value == "dup" then
        if item.kind == "object" or item.kind == "spawn" then Ops.duplicate(item) else notify("This cannot be duplicated.") end
    elseif value == "options" then
        Menus.openItem(item)
    elseif value == "delete" then
        Ops.delete(item)
    end
end)

-- ui_interactobject restarted: register again
addEventHandler("onClientResourceStart", root, function(res)
    if getResourceName(res) == "ui_interactobject" and Editor.active then Interact.register() end
end)
