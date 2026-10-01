-- "Examine patient" entry in the ui_interactobject world menu. Every ped / player that carries
-- the medical status element data (= every patient) gets it; picking it opens the panel.

addEvent("onInteractMenuSelect")

local IO_RESOURCE = "ui_interactobject"
local menuIds = {}

local MENU = {
    title = "Patient",
    priority = 10,
    range = MEDIC.INTERACT_RANGE,
    dataKey = MEDIC.DATA_STATUS,
    items = {
        { label = "Examine patient", value = "examine", desc = "Open the examination panel" },
    },
}

-- nil = everyone; with the role requirement only the flagged medics see the menu
local function getVisibleTo()
    if not MEDIC.REQUIRE_MEDIC_ROLE then return nil end
    return getMedicPlayers()
end

local function isIORunning()
    local resource = getResourceFromName(IO_RESOURCE)
    return resource and getResourceState(resource) == "running"
end

local function registerMenus()
    menuIds = {}
    if not isIORunning() then return end
    local visibleTo = getVisibleTo()
    for _, elementType in ipairs({ "ped", "player" }) do
        local id = exports.ui_interactobject:addInteractTypeMenu(elementType, MENU, visibleTo)
        if id then menuIds[id] = true end
    end
end

-- Called when the medic role of a player changes
function updateInteractVisibility()
    if not MEDIC.REQUIRE_MEDIC_ROLE or not isIORunning() then return end
    local visibleTo = getVisibleTo()
    for id in pairs(menuIds) do
        exports.ui_interactobject:setInteractMenuVisibleTo(id, visibleTo)
    end
end

addEventHandler("onInteractMenuSelect", root, function(menuId, value, target)
    if not menuIds[menuId] or value ~= "examine" then return end
    openExamination(source, target)
end)

addEventHandler("onResourceStart", root, function(startedResource)
    if startedResource == resource or getResourceName(startedResource) == IO_RESOURCE then
        registerMenus()
    end
end)

-- ui_interactobject drops our menus itself when either resource stops
addEventHandler("onResourceStop", root, function(stoppedResource)
    if getResourceName(stoppedResource) == IO_RESOURCE then menuIds = {} end
end)
