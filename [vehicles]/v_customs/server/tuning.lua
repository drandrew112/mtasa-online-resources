-- v_customs :: purchase + apply (server, authoritative)
--
-- The client sends only the catalogue path. This file resolves it, checks the
-- session / money / compatibility, applies the effect and charges cash.

Customs = Customs or {}

addEvent("v_customs:buy", true)
addEvent("v_customs:setCustomPlate", true)

local function notify(player, title, text)
    triggerClientEvent(player, "v_customs:notify", player, title, text)
end

local function generatePlate()
    local out = {}
    for i = 1, 8 do
        if i == 4 then
            out[i] = " "
        elseif math.random(2) == 1 then
            out[i] = string.char(math.random(48, 57))
        else
            out[i] = string.char(math.random(65, 90))
        end
    end
    return table.concat(out)
end

local function reapplySlotUpgrades(veh)
    if getVehicleUpgradeOnSlot(veh, 9) ~= 0 then addVehicleUpgrade(veh, 1087) end
end

--------------------------------------------------------------------------------
-- Effect application
--------------------------------------------------------------------------------

-- node = catalogue option leaf, or a group part (+ optIdx). Returns true on success.
local function applyItem(player, veh, node, optIdx)
    local model = getElementModel(veh)

    -- ---- groups -----------------------------------------------------------
    if node.group == "optical" then
        local compatible = getVehicleCompatibleUpgrades(veh, node.slot) or {}
        local cur = getVehicleUpgradeOnSlot(veh, node.slot)
        if cur and cur ~= 0 then removeVehicleUpgrade(veh, cur) end
        if optIdx and optIdx > 1 then
            local up = compatible[optIdx - 1]
            if not up then
                notify(player, "Customs", "That part does not fit this vehicle.")
                return false
            end
            addVehicleUpgrade(veh, up)
        end
        return true

    elseif node.group == "color" then
        local entry = Customs.PALETTE[optIdx or 0]
        if not entry then return false end
        local r, g, b = entry.rgb[1], entry.rgb[2], entry.rgb[3]
        if node.slot == "headlight" then
            setVehicleHeadLightColor(veh, r, g, b)
        else
            local c = { getVehicleColor(veh, true) }
            local base = node.slot == "primary" and 0 or 3
            c[base + 1], c[base + 2], c[base + 3] = r, g, b
            setVehicleColor(veh, unpack(c))
        end
        return true
    end

    -- ---- option leaves --------------------------------------------------
    local kind = node.kind

    if kind == "performance" then
        for _, prop in ipairs(node.data) do
            if prop[2] == nil then
                setVehicleHandling(veh, prop[1], nil, false)
            else
                setVehicleHandling(veh, prop[1], getOriginalHandling(model)[prop[1]] + prop[2], false)
            end
        end
        reapplySlotUpgrades(veh)
        return true

    elseif kind == "handlingProp" then
        if node.data == false then
            setVehicleHandling(veh, node.prop, getOriginalHandling(model)[node.prop], false)
        else
            setVehicleHandling(veh, node.prop, node.data, false)
        end
        reapplySlotUpgrades(veh)
        return true

    elseif kind == "wheelWidth" then
        Customs.setHandlingFlagByte(veh, node.side == "front" and 3 or 4, Customs.WHEEL_SIZE[node.data] or 0)
        return true

    elseif kind == "flagToggle" then
        if node.flag == "bulletproof" then
            Customs.setExtra(veh, "bulletproof", node.data or nil)
            setElementData(veh, "tuning.bulletProofTires", node.data and true or nil)
        else
            Customs.setExtra(veh, "lsdDoor", node.data or nil)
            setElementData(veh, "tuning.lsdDoor", node.data and true or nil)
        end
        return true

    elseif kind == "plate" then
        if node.data == "random" then
            setVehiclePlateText(veh, generatePlate())
        elseif node.data == "default" then
            local s = Customs.session(player)
            setVehiclePlateText(veh, (s and s.origPlate) or generatePlate())
        elseif node.data == "custom" then
            triggerClientEvent(player, "v_customs:promptPlate", player)
        end
        return true

    elseif kind == "horn" then
        notify(player, "Horn", "Horns are coming soon.")
        return true
    end

    return false
end

--------------------------------------------------------------------------------
-- Buy
--------------------------------------------------------------------------------

addEventHandler("v_customs:buy", root, function(veh, path)
    local player = client
    if not isElement(player) then return end
    if Customs.sessionVehicle(player) ~= veh or not isElement(veh) then return end

    local node, optIdx = Customs.resolve(path)
    if not node then return end
    if not node.group and not node.kind then return end

    -- first option of an optical group ("Default") is free
    local freeReset = node.group == "optical" and optIdx == 1
    local price = freeReset and 0 or Customs.price(node.price or 0)

    if price > 0 and getPlayerMoney(player) < price then
        notify(player, "Customs", "You don't have enough money.")
        triggerClientEvent(player, "v_customs:buyResult", player, false)
        return
    end

    if not applyItem(player, veh, node, optIdx) then
        triggerClientEvent(player, "v_customs:buyResult", player, false)
        return
    end

    local custom  = (node.kind == "plate" and node.data == "custom")
    local charged = 0
    if not custom and price > 0 then
        takePlayerMoney(player, price)
        charged = price
    end

    if node.kind ~= "horn" then
        notify(player, "Customs", (node.name or "Part") .. " installed.")
    end
    triggerClientEvent(player, "v_customs:buyResult", player, true, path, charged)
end)

addEventHandler("v_customs:setCustomPlate", root, function(text)
    local player = client
    local veh = Customs.sessionVehicle(player)
    if not veh then return end

    text = tostring(text or ""):upper():gsub("[^%w %-]", ""):sub(1, 8)
    if text == "" then return end

    local price = Customs.price(15000)
    if getPlayerMoney(player) < price then
        notify(player, "Customs", "You don't have enough money.")
        return
    end

    setVehiclePlateText(veh, text)
    takePlayerMoney(player, price)
    triggerClientEvent(player, "v_customs:buyResult", player, true, nil, price)
    notify(player, "Customs", "Custom plate installed.")
end)
