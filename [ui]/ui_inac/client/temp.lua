-- Temporary, on-the-fly menus for other resources.
--
-- A temporary menu is registered, opened and drawn through the same render /
-- input pipeline as the built-in interaction menu, but it carries no "FREE V"
-- header and is discarded the moment it closes. It may contain nested submenus
-- (arbitrary depth) - needed e.g. by the tuning menu.
--
-- IMPORTANT: MTA cannot pass Lua functions across a resource boundary, so the
-- caller passes DATA ONLY, no callbacks. ui_inac fires client events that any
-- resource can listen for:
--
--   "ui_inac:tempMenuHover"   (source localPlayer)  rootMenuId, value, path
--       fired every time the highlighted item changes (arrows, open, submenu
--       nav) - use it for live previews, e.g. recolouring a vehicle while the
--       player scrolls a colour list.
--   "ui_inac:tempMenuSelect"  (source localPlayer)  rootMenuId, value, path
--       fired when the player presses Enter on a leaf item.
--   "ui_inac:tempMenuClose"   (source localPlayer)  rootMenuId
--
-- See world_elevators for a reference consumer.

local tempIds   = {}    -- set: every menu id that belongs to the live temp menu
local rootId    = nil   -- id of the live temp menu's root (nil = none)
local idCounter = 0

addEvent("ui_inac:tempMenuHover")
addEvent("ui_inac:tempMenuSelect")
addEvent("ui_inac:tempMenuClose")

-- True while some part of a temporary menu is the menu currently on screen.
function isTempMenuOpen()
    return rootId ~= nil and MenuState.open and tempIds[MenuState.current] == true
end

local function teardown(fireOnClose)
    if not rootId then return end

    local closingId  = rootId
    local wasCurrent = tempIds[MenuState.current] == true

    for id in pairs(tempIds) do
        MenuRegistry.menus[id] = nil
        tempIds[id] = nil
    end
    rootId = nil

    if wasCurrent then
        MenuState.open = false
        MenuState.current = "main"
        MenuState:resetSelection()
        setElementData(localPlayer, "interactionMenuOpen", false)
        uicore:toggleMoveControls(true)
    end

    if fireOnClose then
        triggerEvent("ui_inac:tempMenuClose", localPlayer, closingId)
    end
end

-- Recursively registers `node` (and every nested submenu) as a menu.
--   node       = { title, items }
--   id         = menu id to register under
--   backId     = parent menu id (nil for the root)
--   pathPrefix = "" for the root, "2/1/..." for nested levels
local function registerNode(node, id, backId, pathPrefix)
    local rid   = rootId
    local items = {}

    for idx, src in ipairs(node.items or {}) do
        local itemPath = pathPrefix == "" and tostring(idx) or (pathPrefix .. "/" .. idx)
        local label    = tostring(src.label or "")
        local desc     = src.desc ~= nil and tostring(src.desc) or nil

        if type(src.items) == "table" then
            -- submenu
            local subId = id .. "/" .. idx
            registerNode({ title = src.title or src.label, items = src.items }, subId, id, itemPath)
            items[idx] = {
                label = label, desc = desc, type = "submenu", target = subId,
                path = itemPath,   -- value stays nil for submenu rows
            }
        else
            -- leaf: selecting it fires the select event with this item's value
            local value = src.value
            items[idx] = {
                label         = label,
                desc          = desc,
                type          = "action",
                closeOnSelect = src.closeOnSelect ~= false,
                value         = value,     -- also handed out on hover
                path          = itemPath,
                -- right-hand indicators (rendered like a select value):
                --   checked -> a tick (wins over everything)
                --   owned   -> a small ring
                --   price   -> "$1,234" / "Free"  (number)
                price         = src.price,
                checked       = src.checked,
                owned         = src.owned,
                action        = function()
                    triggerEvent("ui_inac:tempMenuSelect", localPlayer, rid, value, itemPath)
                end,
            }
        end
    end

    if #items == 0 then
        items[1] = { label = "—", type = "action", action = function() end, closeOnSelect = false }
    end

    MenuRegistry:register({
        id        = id,
        title     = tostring(node.title or "MENU"),
        back      = backId,
        header    = false,
        temporary = true,
        items     = items,
    })
    tempIds[id] = true
end

-- exports.ui_inac:createTempMenu(config)
--
--   config.title  - title bar text of the root menu (default "MENU")
--   config.items  - ordered array of item tables. Each item is either:
--       leaf     { label, desc, value, closeOnSelect }
--                  value        - serialisable payload handed back with the
--                                 select event (number/string/table of those,
--                                 NO functions)
--                  closeOnSelect - default true; closes the whole temp menu
--                                 right after the select event fired
--       submenu  { label, desc, title, items = { ...more items... } }
--                  presence of `items` makes it a submenu; `title` defaults to
--                  the item's label. Nesting depth is unlimited.
--
-- On Enter over a leaf, ui_inac triggers "ui_inac:tempMenuSelect" with
-- (rootMenuId, value, path) where path is like "2/1". Backspace walks back up
-- one level, or closes the menu at the root. On close ui_inac triggers
-- "ui_inac:tempMenuClose" with (rootMenuId).
--
-- Returns the root menu id (string) on success, false otherwise. Any menu
-- previously created through this export is dropped first (no close event).
function createTempMenu(config)
    if type(config) ~= "table" then return false end

    -- Don't open over the normal interaction menu (or another caller's temp menu).
    if MenuState.open and not isTempMenuOpen() then return false end

    teardown(false)

    idCounter = idCounter + 1
    rootId = "__temp_" .. idCounter

    registerNode({ title = config.title, items = config.items }, rootId, nil, "")

    MenuState.open = true
    MenuState.current = rootId
    MenuState:resetSelection()
    setElementData(localPlayer, "interactionMenuOpen", true)
    uicore:toggleMoveControls(false)

    return rootId
end

-- exports.ui_inac:closeTempMenu()  -  close the whole temp menu (fires the close event).
function closeTempMenu()
    if not rootId then return false end
    teardown(true)
    return true
end

-- exports.ui_inac:updateTempMenuItem(path, meta)
--   Patches the right-hand indicators of one already-registered leaf without
--   rebuilding the menu. `path` is the "2/1"-style path from the select / hover
--   events; `meta` may carry any of { price, checked, owned } (pass false to
--   clear checked/owned, a number for price).
function updateTempMenuItem(path, meta)
    if not rootId or type(meta) ~= "table" then return false end

    local segs = {}
    for s in tostring(path):gmatch("[^/]+") do segs[#segs + 1] = tonumber(s) end
    if #segs < 1 then return false end

    local menuId = rootId
    for i = 1, #segs - 1 do
        menuId = menuId .. "/" .. segs[i]
    end

    local menu = MenuRegistry.menus[menuId]
    local item = menu and menu.items[segs[#segs]]
    if not item then return false end

    if meta.price   ~= nil then item.price   = meta.price   end
    if meta.checked ~= nil then item.checked = meta.checked or nil end
    if meta.owned   ~= nil then item.owned   = meta.owned or nil end
    return true
end

-- Fire "ui_inac:tempMenuHover" whenever the highlighted item changes.
local lastHoverKey = nil
addEventHandler("onClientRender", root, function()
    if not isTempMenuOpen() then
        lastHoverKey = nil
        return
    end

    local menu = MenuState:getMenu()
    local item = menu and menu.items[MenuState.selected]
    if not item then return end

    local key = MenuState.current .. "#" .. MenuState.selected
    if key == lastHoverKey then return end
    lastHoverKey = key

    triggerEvent("ui_inac:tempMenuHover", localPlayer, rootId, item.value, item.path)
end)
