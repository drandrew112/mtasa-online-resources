local function buildSlots()
    return {
    topLeft = {
        x = UI.safe.x,
        y = UI.safe.y,
    },
    topCenter = {
        x = UI.sw / 2,
        y = UI.safe.y,
    },
    topRight = {
        x = UI.sw - UI.safe.x,
        y = UI.safe.y,
    },

    alert = {
        x = UI.sw / 2,
        y = UI.sh * 0.1, -- képernyő közepén, felülről sh*0.1
    },

    leftCenter = {
        x = UI.safe.x,
        y = UI.sh / 2,
        minY = UI.sh - ui(200), -- radar hely
        w = ui(420),
    },

    bottomLeft = {
        x = UI.safe.x,
        y = UI.sh - UI.safe.y,
    },
    bottomCenter = {
        x = UI.sw / 2,
        y = UI.sh - UI.safe.y,
    },
    bottomRight = {
        x = UI.sw - UI.safe.x,
        y = UI.sh - UI.safe.y,
    },
}
end

-- UI.slots is changed in place when the safe zone level changes
UI.slots = {}
function UI.updateSlots()
    for name, slot in pairs(buildSlots()) do
        local cur = UI.slots[name]
        if not cur then UI.slots[name] = slot
        else for k, v in pairs(slot) do cur[k] = v end end
    end
    if UI.relayoutWanted then UI.relayoutWanted() end
end
UI.updateSlots()
