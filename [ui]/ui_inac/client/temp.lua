-- Temporary, on-the-fly menus for other resources.
--
-- A temporary menu is registered, opened and drawn through the same render /
-- input pipeline as the built-in interaction menu, but it carries no "FREE V"
-- header and is discarded the moment it closes.
--
-- IMPORTANT: MTA cannot pass Lua functions across a resource boundary, so the
-- caller does NOT hand in callbacks. Instead ui_inac fires client events that
-- any resource can listen for:
--
--   "ui_inac:tempMenuSelect"  (source localPlayer)  menuId, index, value
--   "ui_inac:tempMenuClose"   (source localPlayer)  menuId
--
-- See world_elevators for a reference consumer.

local activeId  = nil   -- id of the temp menu currently registered (nil = none)
local idCounter = 0

addEvent("ui_inac:tempMenuSelect")
addEvent("ui_inac:tempMenuClose")

-- True while a temporary menu is the menu currently on screen.
function isTempMenuOpen()
    return activeId ~= nil and MenuState.open and MenuState.current == activeId
end

local function teardown(fireOnClose)
    if not activeId then return end

    local id         = activeId
    local wasCurrent = (MenuState.current == id)

    MenuRegistry.menus[id] = nil
    activeId = nil

    if wasCurrent then
        MenuState.open = false
        MenuState.current = "main"
        MenuState:resetSelection()
        setElementData(localPlayer, "interactionMenuOpen", false)
        uicore:toggleMoveControls(true)
    end

    if fireOnClose then
        triggerEvent("ui_inac:tempMenuClose", localPlayer, id)
    end
end

-- exports.ui_inac:createTempMenu(config)
--
--   config.title  - text shown in the menu title bar (default "MENU")
--   config.items  - ordered array of { label, desc, value, closeOnSelect }
--                   * label / desc  - display strings
--                   * value         - arbitrary serialisable payload handed
--                                     back with the select event (number,
--                                     string, or table of those - NO functions)
--                   * closeOnSelect - default true; closes the menu right after
--                                     the select event has been fired.
--
-- On Enter, ui_inac triggers "ui_inac:tempMenuSelect" with (menuId, itemIndex,
-- value). On close it triggers "ui_inac:tempMenuClose" with (menuId).
--
-- Returns the menu id (string) on success, false otherwise. Any menu previously
-- created through this export is dropped first (no close event).
function createTempMenu(config)
    if type(config) ~= "table" then return false end

    -- Don't open over the normal interaction menu (or another caller's temp menu).
    if MenuState.open and not isTempMenuOpen() then return false end

    teardown(false)

    idCounter = idCounter + 1
    local id = "__temp_" .. idCounter

    local items = {}
    for idx, src in ipairs(config.items or {}) do
        local index = idx
        local value = src.value
        items[idx] = {
            label         = tostring(src.label or ""),
            desc          = src.desc ~= nil and tostring(src.desc) or nil,
            type          = "action",
            closeOnSelect = src.closeOnSelect ~= false,
            action        = function()
                triggerEvent("ui_inac:tempMenuSelect", localPlayer, id, index, value)
            end,
        }
    end
    if #items == 0 then
        items[1] = { label = "—", type = "action", action = function() end, closeOnSelect = false }
    end

    MenuRegistry:register({
        id        = id,
        title     = tostring(config.title or "MENU"),
        back      = nil,
        header    = false,
        temporary = true,
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

-- exports.ui_inac:closeTempMenu()  -  close the current temp menu (fires the close event).
function closeTempMenu()
    if not activeId then return false end
    teardown(true)
    return true
end
