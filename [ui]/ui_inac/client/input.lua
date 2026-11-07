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
-- v_introduce: a szerver bemutato alatt csak az a panel nyilhat, amit eppen tanit
local function introBlocks(id)
    local allow = getElementData(localPlayer, "intro.allow")
    return type(allow) == "table" and not allow[id]
end

local function otherPanelOpen()
    return introBlocks("interaction")
        or getElementData(localPlayer, "paused")
        or getElementData(localPlayer, "socialPanelOpen")
        or getElementData(localPlayer, "phoneOpen")
        or getElementData(localPlayer, "browserOpen")
        or getElementData(localPlayer, "showChatInput")
        or getElementData(localPlayer, "reportPanelOpen")
        or getElementData(localPlayer, "adminPanelOpen")
        or getElementData(localPlayer, "textInputOpen")
        or getElementData(localPlayer, "inventoryOpen")
        or inJobLobby()
end

--------------------------------------------------------------------------------
-- navigation actions, shared by the keyboard (below) and the mouse (mouse.lua)
--------------------------------------------------------------------------------

InacNav = { playSelect = playSelect }

function InacNav.move(delta)
    if not MenuState.open then return end
    local items = MenuState:getMenu().items
    local n = #items
    if n == 0 then return end
    MenuState.selected = (MenuState.selected - 1 + delta) % n + 1
    playSelect()
end

function InacNav.step(delta)
    if not MenuState.open then return end
    local item = MenuState:getMenu().items[MenuState.selected]
    if item and item.type == "select" and #item.options > 0 then
        item.value = (item.value - 1 + delta) % #item.options + 1
        playSelect()
    end
end

function InacNav.enter()
    if not MenuState.open then return end
    local item = MenuState:getMenu().items[MenuState.selected]
    if not item then return end

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
        if item.closeOnSelect and isTempMenuOpen() and tempMenuMayClose() then closeTempMenu() end

    elseif item.type == "spawnvehicle" then
        triggerServerEvent("ui_inac:spawnVehicle", localPlayer, item.model)
        playClick()
    end
end

function InacNav.back()
    if not MenuState.open then return end

    local menu = MenuState:getMenu()

    -- Ideiglenes menu: submenubol egy szintet vissza, a gyokerrol bezar.
    if menu and menu.temporary then
        if menu.back then
            MenuState.current = menu.back
            MenuState:resetSelection()
        elseif tempMenuMayClose() then
            closeTempMenu()
        end
        playSelect()
        return
    end

    if menu.back then
        MenuState.current = menu.back
        MenuState:resetSelection()
    else
        MenuState.open = false
        syncMenuRender()
        setElementData(localPlayer, "interactionMenuOpen", false)
        uicore:toggleMoveControls(not MenuState.open)
    end
    playSelect()
end

-- a keyboard step: the row window follows the selection again (render.lua)
local function kb(fn)
    return function()
        if not MenuState.open then return end
        MenuState.mouseScroll = false
        fn()
    end
end

function bindAllKeys()
    bindKey("m", "down", function()
        if isTempMenuOpen() then return end
        if not MenuState.open and otherPanelOpen() then return end
        MenuState.open = not MenuState.open
        MenuState.mouse = true -- the interaction menu always takes the mouse
        syncMenuRender()
        setElementData(localPlayer, "interactionMenuOpen", MenuState.open)
        uicore:toggleMoveControls(not MenuState.open)
        playSelect()
    end)

    bindKey("arrow_u", "down", kb(function() InacNav.move(-1) end))
    bindKey("arrow_d", "down", kb(function() InacNav.move(1) end))
    bindKey("arrow_l", "down", kb(function() InacNav.step(-1) end))
    bindKey("arrow_r", "down", kb(function() InacNav.step(1) end))
    bindKey("enter", "down", kb(InacNav.enter))
    bindKey("backspace", "down", kb(InacNav.back))
end
addEvent("onClientPlayerLoaded", true)
addEventHandler("onClientPlayerLoaded", localPlayer, bindAllKeys)
addEventHandler("onClientResourceStart", resourceRoot, function()
    if getElementData(localPlayer, "loaded") then
        bindAllKeys()
    end
end)
