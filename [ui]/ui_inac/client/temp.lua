-- Temporary, on-the-fly menus for other resources.
--
-- A temporary menu is registered, opened and drawn through the same render /
-- input pipeline as the built-in interaction menu, but it carries no "FREE V"
-- header and is discarded the moment it closes. Other resources build one via
-- the createTempMenu / closeTempMenu exports instead of shipping their own dx
-- menu code (see world_elevators).

local activeId  = nil   -- id of the temp menu currently registered (nil = none)
local idCounter = 0

-- True while a temporary menu is the menu currently on screen.
function isTempMenuOpen()
    return activeId ~= nil and MenuState.open and MenuState.current == activeId
end

local function teardown(fireOnClose)
    if not activeId then return end

    local menu       = MenuRegistry:get(activeId)
    local wasCurrent  = (MenuState.current == activeId)

    MenuRegistry.menus[activeId] = nil
    activeId = nil

    if wasCurrent then
        MenuState.open = false
        MenuState.current = "main"
        MenuState:resetSelection()
        setElementData(localPlayer, "interactionMenuOpen", false)
        uicore:toggleMoveControls(true)
    end

    if fireOnClose and menu and menu.onClose then
        menu.onClose()
    end
end

-- exports.ui_inac:createTempMenu(config)
--
--   config.title   - text shown in the menu title bar (default "MENU")
--   config.items   - array of { label, desc, action, closeOnSelect }
--                    action  is called on Enter.
--                    closeOnSelect (default true) closes the menu right after
--                    the action has run.
--   config.onClose - called once when the menu closes for any reason
--                    (Enter on a closeOnSelect item, Backspace, or an explicit
--                    closeTempMenu()).
--
-- Returns the menu id on success, false otherwise. Any menu previously created
-- through this export is dropped first, without firing its onClose.
function createTempMenu(config)
    if type(config) ~= "table" then return false end

    -- Ne nyiljon ideiglenes menu, ha eppen a rendes interaction menu (vagy egy
    -- masik ideiglenes menu masik hivotol) van a kepernyon.
    if MenuState.open and not isTempMenuOpen() then return false end

    teardown(false)

    idCounter = idCounter + 1
    local id = "__temp_" .. idCounter

    local items = {}
    for _, src in ipairs(config.items or {}) do
        items[#items + 1] = {
            label         = src.label or "",
            desc          = src.desc,
            type          = "action",
            action        = src.action,
            closeOnSelect = src.closeOnSelect ~= false,
        }
    end
    if #items == 0 then
        items[1] = { label = "—", type = "action", action = function() end, closeOnSelect = false }
    end

    MenuRegistry:register({
        id        = id,
        title     = config.title or "MENU",
        back      = nil,
        header    = false,
        temporary = true,
        onClose   = config.onClose,
        items     = items,
    })

    activeId = id
    MenuState.open = true
    MenuState.current = id
    MenuState:resetSelection()
    setElementData(localPlayer, "interactionMenuOpen", true)
    uicore:toggleMoveControls(false)

    return id
end

-- exports.ui_inac:closeTempMenu()  -  close the current temp menu (fires onClose).
function closeTempMenu()
    if not activeId then return false end
    teardown(true)
    return true
end
