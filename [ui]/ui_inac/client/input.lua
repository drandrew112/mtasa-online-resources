local function playSelect()
    playSound("sounds/select.wav")
end

local function playClick()
    playSound("sounds/click.wav")
end

setElementData(localPlayer, "interactionMenuOpen", false)

-- A jatekos egy job-lobbyban var (v_jobmanager varo-panel) -> nincs INAC menu.
local function inJobLobby()
    local res = getResourceFromName("v_jobmanager")
    if not res or getResourceState(res) ~= "running" then return false end
    return exports.v_jobmanager:jobmanagerInLobby() and true or false
end

-- Panelek kozotti osszeferhetetlenseg: az INAC menu nem nyilhat meg, ha mar
-- egy masik panel (social panel, telefon) vagy a chat input aktiv, ha a jatekos
-- a pause menuben van, vagy ha egy job-lobbyban var. (Zarni mindig lehet.)
local function otherPanelOpen()
    return getElementData(localPlayer, "paused")
        or getElementData(localPlayer, "socialPanelOpen")
        or getElementData(localPlayer, "phoneOpen")
        or getElementData(localPlayer, "browserOpen")
        or getElementData(localPlayer, "showChatInput")
        or getElementData(localPlayer, "reportPanelOpen")
        or inJobLobby()
end

bindKey("m", "down", function()
    if isTempMenuOpen() then return end
    if not MenuState.open and otherPanelOpen() then return end
    MenuState.open = not MenuState.open
    setElementData(localPlayer, "interactionMenuOpen", MenuState.open)
    uicore:toggleMoveControls(not MenuState.open)
    playSelect()
end)

bindKey("arrow_u", "down", function()
    if not MenuState.open then return end
    local items = MenuState:getMenu().items
    MenuState.selected = MenuState.selected > 1 and MenuState.selected - 1 or #items
    playSelect()
end)

bindKey("arrow_d", "down", function()
    if not MenuState.open then return end
    local items = MenuState:getMenu().items
    MenuState.selected = MenuState.selected < #items and MenuState.selected + 1 or 1
    playSelect()
end)

bindKey("arrow_l", "down", function()
    if not MenuState.open then return end
    local item = MenuState:getMenu().items[MenuState.selected]
    if item.type == "select" then
        item.value = item.value > 1 and item.value - 1 or #item.options
        playSelect()
    end
end)

bindKey("arrow_r", "down", function()
    if not MenuState.open then return end
    local item = MenuState:getMenu().items[MenuState.selected]
    if item.type == "select" then
        item.value = item.value < #item.options and item.value + 1 or 1
        playSelect()
    end
end)

bindKey("enter", "down", function()
    if not MenuState.open then return end
    local item = MenuState:getMenu().items[MenuState.selected]

    if item.type == "submenu" then
        MenuState.current = item.target
        MenuState:resetSelection()
        if item.onOpen then item.onOpen() end
        playClick()

    elseif item.type == "select" then
        item.options[item.value].action()
        playClick()

    elseif item.type == "action" and item.action then
        item.action()
        playClick()
        if item.closeOnSelect and isTempMenuOpen() then closeTempMenu() end

    elseif item.type == "spawnvehicle" then
        triggerServerEvent("ui_inac:spawnVehicle", localPlayer, item.model)
        playClick()
    end
end)

bindKey("backspace", "down", function()
    if not MenuState.open then return end

    if isTempMenuOpen() then
        closeTempMenu()
        playSelect()
        return
    end

    local menu = MenuState:getMenu()

    if menu.back then
        MenuState.current = menu.back
        MenuState:resetSelection()
    else
        MenuState.open = false
        setElementData(localPlayer, "interactionMenuOpen", false)
        uicore:toggleMoveControls(not MenuState.open)
    end
    playSelect()
end)
