-- v_customs :: temp-menu builder + wiring (client)
--
-- Turns shared/tuning.lua into a ui_inac temp menu. The whole tree is built once
-- per session (the vehicle is frozen, so dynamic lists - compatible optical
-- upgrades - are stable). Item `value` is the catalogue path; the server
-- resolves and charges it.

Menu   = Menu or {}
uicore = exports.ui_core

local menuId        = nil
local curVeh        = nil
local cameraByPath  = {}   -- path -> camera preset key
local previewByPath = {}   -- path -> Preview.onHover info
local plateToken    = nil

addEvent("ui_inac:tempMenuSelect")
addEvent("ui_inac:tempMenuHover")
addEvent("ui_inac:tempMenuClose")
addEvent("ui_core:textInputResult")
addEvent("v_customs:notify", true)
addEvent("v_customs:buyResult", true)
addEvent("v_customs:promptPlate", true)

--------------------------------------------------------------------------------
-- formatting
--------------------------------------------------------------------------------

local function commas(n)
    local s = tostring(math.floor(n))
    return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local function priceStr(base)
    local p = Customs.price(base or 0)
    return p <= 0 and "Free" or ("$" .. commas(p))
end

--------------------------------------------------------------------------------
-- tree -> temp menu items
--------------------------------------------------------------------------------

local function opticalOptions(child, path, cam)
    local ups  = getVehicleCompatibleUpgrades(curVeh, child.slot) or {}
    local opts = {}

    local defPath = path .. "/1"
    opts[1] = { label = "Default", desc = "Free", value = defPath, closeOnSelect = false }
    previewByPath[defPath] = { kind = "optical", slot = child.slot, upgrade = 0 }
    cameraByPath[defPath]  = child.camera or cam

    for k, up in ipairs(ups) do
        local p = path .. "/" .. (k + 1)
        opts[k + 1] = { label = child.name .. " " .. k, desc = priceStr(child.price),
                        value = p, closeOnSelect = false }
        previewByPath[p] = { kind = "optical", slot = child.slot, upgrade = up }
        cameraByPath[p]  = child.camera or cam
    end

    if #ups == 0 then
        opts = { { label = "(not available for this vehicle)", closeOnSelect = false } }
    end
    return opts
end

local function colorOptions(child, path, cam)
    local opts = {}
    for k, entry in ipairs(Customs.PALETTE) do
        local p = path .. "/" .. k
        opts[k] = { label = entry.name, desc = priceStr(child.price), value = p, closeOnSelect = false }
        previewByPath[p] = { kind = "color", slot = child.slot, rgb = entry.rgb }
        cameraByPath[p]  = child.camera or cam
    end
    return opts
end

local function neonOptions(child, path, cam)
    cameraByPath[path .. "/1"] = child.camera or cam
    local opts = { { label = "Remove", desc = "Free", value = path .. "/1", closeOnSelect = false } }
    for k, entry in ipairs(Customs.NEONS) do
        local p = path .. "/" .. (k + 1)
        opts[k + 1] = { label = entry.name, desc = priceStr(child.price), value = p, closeOnSelect = false }
        cameraByPath[p] = child.camera or cam
    end
    return opts
end

local function buildItems(node, prefix, inheritedCam)
    local items = {}
    for i, child in ipairs(node.items or {}) do
        local path = prefix == "" and tostring(i) or (prefix .. "/" .. i)
        local cam  = child.camera or inheritedCam
        cameraByPath[path] = cam

        if child.kind == "opticalGroup" then
            items[i] = { label = child.name, desc = child.name, title = child.name,
                         items = opticalOptions(child, path, cam) }
        elseif child.kind == "colorGroup" then
            items[i] = { label = child.name, desc = child.name, title = child.name,
                         items = colorOptions(child, path, cam) }
        elseif child.kind == "neonGroup" then
            items[i] = { label = child.name, desc = child.name, title = child.name,
                         items = neonOptions(child, path, cam) }
        elseif child.items then
            items[i] = { label = child.name, desc = child.name, title = child.name,
                         items = buildItems(child, path, cam) }
        else
            items[i] = { label = child.name, desc = priceStr(child.price),
                         value = path, closeOnSelect = false }
        end
    end
    return items
end

--------------------------------------------------------------------------------
-- open / close
--------------------------------------------------------------------------------

function Menu.open(veh)
    curVeh        = veh
    cameraByPath  = {}
    previewByPath = {}
    Preview.init(veh)

    local items = buildItems(Customs.root, "", "front")
    menuId = exports.ui_inac:createTempMenu({ title = "SA CUSTOMS", items = items }) or nil
    return menuId ~= nil
end

function Menu.close()
    if menuId and exports.ui_inac:isTempMenuOpen() then
        exports.ui_inac:closeTempMenu()
    end
    menuId = nil
end

function Menu.isOpen()
    return menuId ~= nil
end

--------------------------------------------------------------------------------
-- events
--------------------------------------------------------------------------------

addEventHandler("ui_inac:tempMenuHover", root, function(id, value, path)
    if id ~= menuId then return end
    CustomsCam.to(cameraByPath[path] or "front")
    Preview.onHover(previewByPath[path])
end)

addEventHandler("ui_inac:tempMenuSelect", root, function(id, value)
    if id ~= menuId then return end
    if type(value) ~= "string" then return end
    if not isElement(curVeh) then return end
    triggerServerEvent("v_customs:buy", localPlayer, curVeh, value)
end)

addEventHandler("ui_inac:tempMenuClose", root, function(id)
    if id ~= menuId then return end
    menuId = nil
    if Shop and Shop.onMenuClosed then Shop.onMenuClosed() end
end)

addEventHandler("v_customs:notify", root, function(title, text)
    uicore:addNotification(tostring(title), tostring(text))
end)

addEventHandler("v_customs:buyResult", root, function(ok, path, charged)
    if not ok then return end
    if path and previewByPath[path] then Preview.commit(previewByPath[path]) end
    if tonumber(charged) and tonumber(charged) > 0 then
        uicore:showMoney("take", tonumber(charged))
    end
end)

addEventHandler("v_customs:promptPlate", root, function()
    plateToken = exports.ui_core:openTextInput("Custom license plate", 8)
end)

addEventHandler("ui_core:textInputResult", root, function(token, text)
    if token ~= plateToken then return end
    plateToken = nil
    if type(text) == "string" and text ~= "" then
        triggerServerEvent("v_customs:setCustomPlate", localPlayer, text)
    end
end)
