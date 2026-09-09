-- v_customs :: purchase + apply (server, authoritative)
--
-- The client only ever sends the *path* of the chosen item. This file looks the
-- item up in the shared catalogue, checks the session / money / compatibility,
-- applies the effect and charges cash.

Customs = Customs or {}

addEvent("v_customs:buy", true)
addEvent("v_customs:setCustomPlate", true)

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

-- ui_core:addNotification / showMoney are client exports, so everything the
-- player sees is pushed as an event and drawn client-side (client/menu.lua).
local function notify(player, title, text)
    triggerClientEvent(player, "v_customs:notify", player, title, text)
end

local WHEEL_SIZE = { verynarrow = 1, narrow = 2, default = 0, wide = 4, verywide = 8 }
local OFFROAD    = { default = 0, dirt = 1, sand = 2 }

-- Byte-addressable handlingFlags editor (ported verbatim from old/sourceS.lua).
local function setVehicleHandlingFlags(veh, byte, value)
    local handlingFlags  = string.format("%X", getVehicleHandling(veh)["handlingFlags"])
    local reversedFlags  = string.reverse(handlingFlags) .. string.rep("0", 8 - string.len(handlingFlags))
    local currentByte, flags = 1, ""

    for values in string.gmatch(reversedFlags, ".") do
        if type(byte) == "table" then
            for _, v in ipairs(byte) do
                if currentByte == v then values = string.format("%X", tonumber(value)) end
            end
        elseif currentByte == byte then
            values = string.format("%X", tonumber(value))
        end
        flags = flags .. values
        currentByte = currentByte + 1
    end

    setVehicleHandling(veh, "handlingFlags", tonumber("0x" .. string.reverse(flags)), false)
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

-- keeps nitro / hydraulics upgrades alive after a handling write (old bug fix)
local function reapplySlotUpgrades(veh)
    if getVehicleUpgradeOnSlot(veh, 8) ~= 0 then addVehicleUpgrade(veh, 1010) end
    if getVehicleUpgradeOnSlot(veh, 9) ~= 0 then addVehicleUpgrade(veh, 1087) end
end

--------------------------------------------------------------------------------
-- Air-ride (used by persist.lua too)
--------------------------------------------------------------------------------

local AIRRIDE_DROP = { [1] = 0.01, [2] = -0.1, [3] = -0.2, [4] = -0.3, [5] = -0.45 }

function Customs.applyAirRide(veh, level)
    level = tonumber(level) or 0
    if level <= 0 then
        setVehicleHandling(veh, "suspensionLowerLimit",
            getOriginalHandling(getElementModel(veh))["suspensionLowerLimit"])
    else
        setVehicleHandling(veh, "suspensionLowerLimit", AIRRIDE_DROP[level] or -0.2)
    end
end

--------------------------------------------------------------------------------
-- Effect application per kind
--------------------------------------------------------------------------------

-- Returns true on success. `optIdx` is the trailing option index for groups.
local function applyItem(player, veh, node, optIdx)
    local kind = node.kind
    local model = getElementModel(veh)

    if kind == "performance" then
        for _, prop in ipairs(node.data) do
            if prop[2] == nil then
                setVehicleHandling(veh, prop[1], nil, false)
            else
                local def = getOriginalHandling(model)[prop[1]]
                setVehicleHandling(veh, prop[1], def + prop[2], false)
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
        local byte = node.side == "front" and 3 or 4
        setVehicleHandlingFlags(veh, byte, WHEEL_SIZE[node.data] or 0)
        return true

    elseif kind == "offroad" then
        setVehicleHandlingFlags(veh, 6, OFFROAD[node.data] or 0)
        return true

    elseif kind == "opticalGroup" then
        local compatible = getVehicleCompatibleUpgrades(veh, node.slot) or {}
        -- option 1 = Default (remove whatever is on the slot)
        local current = getVehicleUpgradeOnSlot(veh, node.slot)
        if current and current ~= 0 then removeVehicleUpgrade(veh, current) end
        if optIdx and optIdx > 1 then
            local up = compatible[optIdx - 1]
            if not up then
                notify(player, "Customs", "That part does not fit this vehicle.")
                return false
            end
            addVehicleUpgrade(veh, up)
        end
        return true

    elseif kind == "colorGroup" then
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

    elseif kind == "neonGroup" then
        if optIdx == 1 then
            Customs.setExtra(veh, "neon", nil)
            triggerClientEvent(root, "v_customs:neon", root, veh, false)
        else
            local entry = Customs.NEONS[(optIdx or 0) - 1]
            if not entry then return false end
            Customs.setExtra(veh, "neon", entry.id)
            triggerClientEvent(root, "v_customs:neon", root, veh, entry.id)
        end
        return true

    elseif kind == "nitro" then
        local level = tonumber(node.data) or 0
        if level <= 0 then
            removeVehicleUpgrade(veh, 1010)
            Customs.setExtra(veh, "nitro", nil)
        else
            addVehicleUpgrade(veh, 1010)
            Customs.setExtra(veh, "nitro", level)
        end
        triggerClientEvent(root, "v_customs:nitroLevel", root, veh, level)
        return true

    elseif kind == "airride" then
        local level = tonumber(node.data) or 0
        Customs.applyAirRide(veh, level)
        Customs.setExtra(veh, "airride", level > 0 and level or nil)
        return true

    elseif kind == "flagToggle" then
        if node.flag == "bulletproof" then
            Customs.setExtra(veh, "bulletproof", node.data or nil)
            setElementData(veh, "tuning.bulletProofTires", node.data and true or nil)
        elseif node.flag == "lsdDoor" then
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
-- Buy entry point
--------------------------------------------------------------------------------

addEventHandler("v_customs:buy", root, function(veh, path)
    local player = client
    if not isElement(player) then return end

    if Customs.sessionVehicle(player) ~= veh or not isElement(veh) then
        return
    end

    local node, optIdx = Customs.resolve(path)
    if not node or not node.kind then return end

    -- the first option of a group ("Default" / "Remove") is always free
    local isGroupReset = (node.kind == "opticalGroup" or node.kind == "neonGroup") and optIdx == 1
    local price = isGroupReset and 0 or Customs.price(node.price or 0)
    if price > 0 and getPlayerMoney(player) < price then
        notify(player, "Customs", "You don't have enough money.")
        triggerClientEvent(player, "v_customs:buyResult", player, false)
        return
    end

    if not applyItem(player, veh, node, optIdx) then
        triggerClientEvent(player, "v_customs:buyResult", player, false)
        return
    end

    -- "custom plate" is charged only once the text comes back
    local charged = 0
    if not (node.kind == "plate" and node.data == "custom") and price > 0 then
        takePlayerMoney(player, price)
        charged = price
    end

    if node.kind ~= "horn" then
        notify(player, "Customs", node.name .. " installed.")
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
