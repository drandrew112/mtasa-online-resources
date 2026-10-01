-- The "Examine patient" prompt comes from ui_interactobject (server/interaction.lua). Here the
-- world menus are only switched off while the local player cannot / should not use them:
-- during a procedure (the minigames use keys like E) or while the player is down.
-- The examination panel shows the cursor, which hides the world menus on its own.

addEvent("medic:busy", true)

local busy = false
local disabled = false

local function refresh()
    local down = medicIsDown(getElementData(localPlayer, MEDIC.DATA_STATUS))
    local wanted = busy or down
    if wanted == disabled then return end

    local io = getResourceFromName("ui_interactobject")
    if not io or not getResourceRootElement(io) then return end
    disabled = wanted
    exports.ui_interactobject:setInteractionDisabled(wanted)
end

addEventHandler("medic:busy", resourceRoot, function(state)
    busy = state == true
    refresh()
end)

addEventHandler("onClientElementDataChange", localPlayer, function(key)
    if key == MEDIC.DATA_STATUS then refresh() end
end, false)

-- a restarted ui_interactobject forgets the disabled flag
addEventHandler("onClientResourceStart", root, function(startedResource)
    if getResourceName(startedResource) == "ui_interactobject" then
        disabled = false
        refresh()
    end
end)
