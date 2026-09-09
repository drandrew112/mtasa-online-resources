-- v_customs :: live preview (client)
--
-- While the player scrolls the Respray / Optical lists the vehicle updates in
-- real time. Anything not actually bought is rolled back to the committed
-- baseline when the highlight moves away or the menu closes. Purchases move the
-- baseline forward (server has already applied them for real / for everyone).

Preview = { veh = nil }

local origColors  = nil    -- committed vehicle colour set
local origHead    = nil    -- committed headlight colour
local opticalBase = {}     -- [slot] = committed upgrade id (0 = none)
local active      = nil    -- the preview currently shown, so we can undo it

local function applyColors()
    setVehicleColor(Preview.veh, unpack(origColors))
    setVehicleHeadLightColor(Preview.veh, origHead[1], origHead[2], origHead[3])
end

local function restoreSlot(slot)
    local veh = Preview.veh
    local cur = getVehicleUpgradeOnSlot(veh, slot)
    if cur and cur ~= 0 then removeVehicleUpgrade(veh, cur) end
    if (opticalBase[slot] or 0) ~= 0 then addVehicleUpgrade(veh, opticalBase[slot]) end
end

local function undoActive()
    if not active or not isElement(Preview.veh) then return end
    if active.kind == "color" then
        applyColors()
    elseif active.kind == "optical" then
        restoreSlot(active.slot)
    end
    active = nil
end

function Preview.init(veh)
    Preview.veh = veh
    origColors  = { getVehicleColor(veh, true) }
    origHead    = { getVehicleHeadLightColor(veh) }
    opticalBase = {}
    active      = nil
end

-- info: nil, or { kind = "color", slot, rgb } / { kind = "optical", slot, upgrade }
function Preview.onHover(info)
    if not isElement(Preview.veh) then return end
    undoActive()
    if type(info) ~= "table" then return end

    if info.kind == "color" then
        local r, g, b = info.rgb[1], info.rgb[2], info.rgb[3]
        if info.slot == "headlight" then
            setVehicleHeadLightColor(Preview.veh, r, g, b)
        else
            local c = { getVehicleColor(Preview.veh, true) }
            local base = info.slot == "primary" and 0 or 3
            c[base + 1], c[base + 2], c[base + 3] = r, g, b
            setVehicleColor(Preview.veh, unpack(c))
        end
        active = info

    elseif info.kind == "optical" then
        if opticalBase[info.slot] == nil then
            opticalBase[info.slot] = getVehicleUpgradeOnSlot(Preview.veh, info.slot) or 0
        end
        local cur = getVehicleUpgradeOnSlot(Preview.veh, info.slot)
        if cur and cur ~= 0 then removeVehicleUpgrade(Preview.veh, cur) end
        if (info.upgrade or 0) ~= 0 then addVehicleUpgrade(Preview.veh, info.upgrade) end
        active = info
    end
end

-- The item at this preview info was actually purchased: bank the current look.
function Preview.commit(info)
    if type(info) ~= "table" or not isElement(Preview.veh) then return end
    if info.kind == "color" then
        origColors = { getVehicleColor(Preview.veh, true) }
        origHead   = { getVehicleHeadLightColor(Preview.veh) }
        active = nil
    elseif info.kind == "optical" then
        opticalBase[info.slot] = info.upgrade or 0
        active = nil
    end
end

function Preview.restore()
    undoActive()
    if isElement(Preview.veh) then
        applyColors()
        for slot in pairs(opticalBase) do restoreSlot(slot) end
    end
    Preview.veh = nil
end
