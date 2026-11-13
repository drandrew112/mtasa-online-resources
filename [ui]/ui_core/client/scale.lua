UI = {}
UI.sw, UI.sh = guiGetScreenSize()

UI.baseW, UI.baseH = 1920, 1080
UI.scale = math.min(UI.sw / UI.baseW, UI.sh / UI.baseH)

-- safe area (behúzás); 6 levels, the table is changed in place so every
-- UI.safe reader follows a level change
UI.safeLevels = { 20, 35, 50, 65, 80, 95 } -- px at 1920x1080
UI.safeDefaultLevel = 3
UI.safeLevel = UI.safeDefaultLevel
UI.safe = {
    x = UI.safeLevels[UI.safeLevel] * UI.scale,
    y = UI.safeLevels[UI.safeLevel] * UI.scale,
}

function UI.setSafeLevel(level)
    level = math.floor(tonumber(level) or UI.safeDefaultLevel)
    level = math.max(1, math.min(#UI.safeLevels, level))
    UI.safeLevel = level
    UI.safe.x = UI.safeLevels[level] * UI.scale
    UI.safe.y = UI.safeLevels[level] * UI.scale
    if UI.updateSlots then UI.updateSlots() end
    return level
end

function ui(px) return px * UI.scale end
