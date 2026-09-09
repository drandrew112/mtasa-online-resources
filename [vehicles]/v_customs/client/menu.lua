-- v_customs :: temp-menu builder + wiring (client)
--
-- shared/tuning.lua is an alphabetical list of parts / folders. Folders nest one
-- level; every part opens a submenu of its options. Items carry `price` and
-- `checked` (the currently fitted option) which ui_inac renders on the right.

Menu   = Menu or {}
uicore = exports.ui_core

local menuId          = nil
local curVeh          = nil
local previewByPath   = {}   -- option path -> Preview.onHover info
local basePriceByPath = {}   -- option path -> catalogue price
local partOfPath      = {}   -- option path -> owning part's path prefix
local partPaths       = {}   -- part path prefix -> { option path, ... }
local plateToken      = nil

addEvent("ui_inac:tempMenuSelect")
addEvent("ui_inac:tempMenuHover")
addEvent("ui_inac:tempMenuClose")
addEvent("ui_core:textInputResult")
addEvent("v_customs:notify", true)
addEvent("v_customs:buyResult", true)
addEvent("v_customs:promptPlate", true)

--------------------------------------------------------------------------------
-- "currently fitted option" detection
--------------------------------------------------------------------------------

local function extras()
    local t = getElementData(curVeh, "customs:extras")
    return type(t) == "table" and t or {}
end

local function isFlagSet(val, flag) return bitAnd(val, flag) == flag end

local WHEEL_FLAGS = {
    front = { verynarrow = 0x100,  narrow = 0x200,  wide = 0x400,  verywide = 0x800  },
    rear  = { verynarrow = 0x1000, narrow = 0x2000, wide = 0x4000, verywide = 0x8000 },
}

local function nearly(a, b) return math.abs((tonumber(a) or 0) - (tonumber(b) or 0)) < 0.001 end

-- option index currently active for a static part, or nil
local function activeStatic(part)
    local opts = part.options
    local h    = getVehicleHandling(curVeh)
    local orig = getOriginalHandling(getElementModel(curVeh))
    local kind = opts[1].kind

    if kind == "performance" then
        for i, opt in ipairs(opts) do
            local ok = true
            for _, prop in ipairs(opt.data) do
                local target = prop[2] == nil and orig[prop[1]] or (orig[prop[1]] + prop[2])
                if not nearly(h[prop[1]], target) then ok = false break end
            end
            if ok then return i end
        end

    elseif kind == "handlingProp" then
        for i, opt in ipairs(opts) do
            if opt.data == false then
                if h[opt.prop] == orig[opt.prop] or nearly(h[opt.prop], orig[opt.prop]) then return i end
            elseif type(opt.data) == "number" then
                if nearly(h[opt.prop], opt.data) then return i end
            elseif h[opt.prop] == opt.data then
                return i
            end
        end

    elseif kind == "wheelWidth" then
        local flags, side = h.handlingFlags, opts[1].side
        for i, opt in ipairs(opts) do
            local f = WHEEL_FLAGS[side][opt.data]
            if not f then
                local any = false
                for _, ff in pairs(WHEEL_FLAGS[side]) do if isFlagSet(flags, ff) then any = true end end
                if not any then return i end
            elseif isFlagSet(flags, f) then
                return i
            end
        end

    elseif kind == "flagToggle" then
        local on
        if opts[1].flag == "bulletproof" then on = extras().bulletproof and true or false
        else on = getElementData(curVeh, "tuning.lsdDoor") and true or false end
        return on and 2 or 1
    end
    return nil
end

--------------------------------------------------------------------------------
-- option lists
--------------------------------------------------------------------------------

local function priceOf(base) return Customs.price(base or 0) end

local function makeOption(path, name, base, checked, preview)
    basePriceByPath[path] = priceOf(base)
    if preview then previewByPath[path] = preview end
    return {
        label   = name,
        value   = path,
        checked = checked or nil,
        price   = checked and false or priceOf(base),
        closeOnSelect = false,
    }
end

local function opticalOptions(part, prefix)
    local ups = getVehicleCompatibleUpgrades(curVeh, part.slot) or {}
    local cur = getVehicleUpgradeOnSlot(curVeh, part.slot) or 0
    local items, paths = {}, {}

    paths[1] = prefix .. "/1"
    items[1] = makeOption(paths[1], "Default", 0, cur == 0,
        { kind = "optical", slot = part.slot, upgrade = 0 })

    for k, up in ipairs(ups) do
        local p = prefix .. "/" .. (k + 1)
        paths[k + 1] = p
        items[k + 1] = makeOption(p, part.name .. " " .. k, part.price, cur == up,
            { kind = "optical", slot = part.slot, upgrade = up })
    end

    if #ups == 0 then
        return { { label = "(not available for this vehicle)", closeOnSelect = false } }, {}
    end
    return items, paths
end

local function colorOptions(part, prefix)
    local items, paths = {}, {}
    for k, entry in ipairs(Customs.PALETTE) do
        local p = prefix .. "/" .. k
        paths[k] = p
        items[k] = makeOption(p, entry.name, part.price, false,
            { kind = "color", slot = part.slot, rgb = entry.rgb })
    end
    return items, paths
end

local function staticOptions(part, prefix)
    local active = activeStatic(part)
    local items, paths = {}, {}
    for k, opt in ipairs(part.options) do
        local p = prefix .. "/" .. k
        paths[k] = p
        local preview = (opt.kind ~= "horn" and opt.kind ~= "plate") and { kind = opt.kind, opt = opt } or nil
        items[k] = makeOption(p, opt.name, opt.price, active == k, preview)
    end
    return items, paths
end

--------------------------------------------------------------------------------
-- tree build
--------------------------------------------------------------------------------

local function buildPart(part, prefix)
    local opts, paths
    if part.group == "optical" then
        opts, paths = opticalOptions(part, prefix)
    elseif part.group == "color" then
        opts, paths = colorOptions(part, prefix)
    else
        opts, paths = staticOptions(part, prefix)
    end

    partPaths[prefix] = paths
    for _, p in ipairs(paths) do partOfPath[p] = prefix end

    return { label = part.name, title = part.name, items = opts }
end

local function buildLevel(nodes, prefix)
    local items = {}
    for i, node in ipairs(nodes) do
        local p = prefix == "" and tostring(i) or (prefix .. "/" .. i)
        if node.folder then
            items[i] = { label = node.name, title = node.name, items = buildLevel(node.items, p) }
        else
            items[i] = buildPart(node, p)
        end
    end
    return items
end

--------------------------------------------------------------------------------

function Menu.open(veh)
    curVeh          = veh
    previewByPath   = {}
    basePriceByPath = {}
    partOfPath      = {}
    partPaths       = {}
    Preview.init(veh)

    menuId = exports.ui_inac:createTempMenu({
        title = "SA CUSTOMS",
        items = buildLevel(Customs.parts, ""),
    }) or nil
    return menuId ~= nil
end

function Menu.close()
    if menuId and exports.ui_inac:isTempMenuOpen() then
        exports.ui_inac:closeTempMenu()
    end
    menuId = nil
end

--------------------------------------------------------------------------------
-- events
--------------------------------------------------------------------------------

addEventHandler("ui_inac:tempMenuHover", root, function(id, value, path)
    if id ~= menuId then return end
    Preview.onHover(previewByPath[path])
end)

addEventHandler("ui_inac:tempMenuSelect", root, function(id, value)
    if id ~= menuId or type(value) ~= "string" or not isElement(curVeh) then return end
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

    local node    = path and Customs.resolve(path)
    local oneShot = node and (node.kind == "plate" or node.kind == "horn")
    local prefix  = (path and not oneShot) and partOfPath[path]
    if prefix and partPaths[prefix] then
        for _, p in ipairs(partPaths[prefix]) do
            exports.ui_inac:updateTempMenuItem(p, {
                checked = (p == path),
                price   = (p == path) and false or basePriceByPath[p],
            })
        end
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
