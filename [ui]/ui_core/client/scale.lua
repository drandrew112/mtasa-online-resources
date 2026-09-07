UI = {}
UI.sw, UI.sh = guiGetScreenSize()

UI.baseW, UI.baseH = 1920, 1080
UI.scale = math.min(UI.sw / UI.baseW, UI.sh / UI.baseH)

-- safe area (behúzás)
UI.safe = {
    x = 50 * UI.scale,
    y = 50 * UI.scale,
}

function ui(px) return px * UI.scale end
