if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Organizations (biz_core) inside the interaction menu.
--
-- "My organization" is the first item of the main menu (above Fast Travel),
-- only while the player is the founder of an organization: biz_core sets the
-- local element data "biz:company" = { id, name, clean, dirty, associates,
-- maxAssociates, ... } on him. The item is inserted / removed whenever that
-- data changes. Associates are managed in the phone (Organization app).

local ITEM_KEY = "_biz"
local renameToken

local function company()
    local c = getElementData(localPlayer, "biz:company")
    return type(c) == "table" and c or nil
end

local function balanceText()
    local c = company()
    if not c then return "—" end
    return L("ui_inac.business.money", { amount = (tonumber(c.clean) or 0) + (tonumber(c.dirty) or 0) })
end

local function associatesText()
    local c = company()
    if not c then return "—" end
    return L("ui_inac.business.associates_value", { count = c.associates or 0, max = c.maxAssociates or 3 })
end

local function mainItem()
    return {
        [ITEM_KEY] = true,
        label = L("ui_inac.business.my_organization"),
        type = "submenu",
        target = "biz_org",
        desc = L("ui_inac.business.my_organization_desc"),
    }
end

--- puts the item on top of the main menu when the player has an organization
local function syncMainItem()
    local main = MenuRegistry:get("main")
    if not main then return end
    local has = company() ~= nil
    local present = main.items[1] and main.items[1][ITEM_KEY]
    if has and not present then
        table.insert(main.items, 1, mainItem())
        if MenuState.current == "main" and MenuState.open then MenuState.selected = MenuState.selected + 1 end
    elseif not has and present then
        table.remove(main.items, 1)
        if MenuState.current == "main" then MenuState.selected = math.max(1, MenuState.selected - 1) end
        if MenuState.current == "biz_org" or MenuState.current == "biz_props" then
            MenuState.current = "main"
            MenuState:resetSelection()
        end
    end
    local org = MenuRegistry:get("biz_org")
    if org then org.title = company() and company().name or L("ui_inac.business.my_organization") end
end

local function setPropertyItems(items)
    local menu = MenuRegistry:get("biz_props")
    if not menu then return end
    menu.items = items
    if MenuState.current == "biz_props" then
        MenuState.selected = math.max(1, math.min(MenuState.selected, #items))
    end
end

-- called from registerMenus() (main.lua) once the player is loaded
function registerBusinessMenu()
    registerMenu({
        id    = "biz_org",
        title = L("ui_inac.business.my_organization"),
        back  = "main",
        items = {
            {
                label = L("ui_inac.business.rename"),
                type = "action",
                desc = function()
                    local c = company()
                    return L("ui_inac.business.rename_desc", { amount = c and tonumber(c.renameCost) or 0 })
                end,
                action = function()
                    local c = company()
                    if not c then return end
                    renameToken = exports.ui_core:openTextInput(L("ui_inac.business.rename_title"), 32, c.name, L("ui_inac.business.rename_placeholder"))
                end,
            },
            {
                label = L("ui_inac.business.balance"),
                type = "data",
                source = localPlayer,
                key = "biz:company",
                format = balanceText,
                desc = L("ui_inac.business.balance_desc"),
            },
            {
                label = L("ui_inac.business.properties"),
                type = "submenu",
                target = "biz_props",
                desc = L("ui_inac.business.properties_desc"),
                onOpen = function()
                    setPropertyItems({ { label = L("common.loading"), type = "action", action = function() end } })
                    triggerServerEvent("ui_inac:bizProperties", localPlayer)
                end,
            },
            {
                label = L("ui_inac.business.associates"),
                type = "data",
                source = localPlayer,
                key = "biz:company",
                format = associatesText,
                desc = L("ui_inac.business.associates_desc"),
            },
        },
    })
    registerMenu({
        id    = "biz_props",
        title = L("ui_inac.business.properties"),
        back  = "biz_org",
        items = { { label = L("common.loading"), type = "action", action = function() end } },
    })
    syncMainItem()
end

addEventHandler("onClientElementDataChange", localPlayer, function(key)
    if key == "biz:company" then syncMainItem() end
end)

addEvent("ui_inac:bizPropertyList", true)
addEventHandler("ui_inac:bizPropertyList", root, function(list)
    local items = {}
    for _, p in ipairs(list or {}) do
        items[#items + 1] = {
            label = p.name,
            desc = L("ui_inac.business.set_gps_desc", { city = p.city or "" }),
            type = "action",
            action = function()
                setElementData(localPlayer, "gpsDestination", { p.x, p.y })
                uicore:addNotification(L("ui_inac.business.my_organization"), L("ui_inac.business.gps_set", { name = p.name }))
            end,
        }
    end
    if #items == 0 then items[1] = { label = L("ui_inac.business.no_properties"), type = "action", action = function() end } end
    setPropertyItems(items)
end)

addEvent("ui_core:textInputResult")
addEventHandler("ui_core:textInputResult", root, function(token, text)
    if token ~= renameToken then return end
    renameToken = nil
    if type(text) == "string" and text ~= "" then
        triggerServerEvent("ui_inac:bizRename", localPlayer, text)
    end
end)
