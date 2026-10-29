if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- On foot, every editor element gets a ui_interactobject menu (Q/E focus, X open,
-- number keys). In freecam the cursor shows, which hides these menus; clicking
-- an element opens the ui_inac item menu instead.

Interact = { ids = {} }

local function buildDef() return {
    title = L("v_jobcreator.interact.editor"),
    range = 6,
    lineOfSight = false,
    allowInVehicle = false,
    dataKey = "jobcreator.item",
    items = {
        { label = L("v_jobcreator.interact.move"), value = "move" },
        { label = L("v_jobcreator.interact.duplicate"), value = "dup" },
        { label = L("v_jobcreator.interact.options"), value = "options" },
        { label = L("v_jobcreator.interact.delete"), value = "delete" },
    },
} end

function Interact.register()
    Interact.unregister()
    for _, elementType in ipairs({ "object", "vehicle", "ped" }) do
        local id = iobj:addInteractTypeMenu(elementType, buildDef())
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
        if Ops.canDuplicate(item) then Ops.duplicate(item) else notify(L("v_jobcreator.interact.this_cannot_be_duplicated")) end
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
