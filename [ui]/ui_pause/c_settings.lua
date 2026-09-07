-- ui_pause / c_settings.lua
--
-- Client side of pause-menu settings persistence.
--
--   * When the player toggles a setting in the pause menu, c_pausemenu.lua
--     calls pauseSettingsPersist(id, value); the value goes to the server,
--     which stores it on the account.
--   * After login the server sends "uipause:loadSettings" with every saved
--     value; applyAll() walks SETTINGS_TREE (defined in c_pausemenu.lua) and
--     calls each matching item's set() so the saved choice takes effect.
--
-- A value whose owning resource is not ready yet (e.g. v_radar still starting)
-- is remembered and retried on the next onClientResourceStart.

local pending = nil -- { id = value } that could not be applied yet

-- Finds a settings item (with its live get/set closures) by id.
local function findItem(id)
    for _, cat in ipairs(SETTINGS_TREE or {}) do
        for _, item in ipairs(cat.items) do
            if item.id == id then return item end
        end
    end
    return nil
end

-- Applies one stored value to the live setting.
-- Returns false when the setting's resource is unavailable (retry later).
local function applyOne(id, value)
    local item = findItem(id)
    if not item or not item.set then return true end

    if item.available and not item.available() then
        return false
    end
    item.set(value)
    return true
end

-- Applies a whole { id = value } map, keeping any that could not be applied.
local function applyAll(values)
    local deferred, anyDeferred = {}, false
    for id, value in pairs(values) do
        if applyOne(id, value) == false then
            deferred[id] = value
            anyDeferred = true
        end
    end
    pending = anyDeferred and deferred or nil
end

--------------------------------------------------------------------------------
-- server -> client
--------------------------------------------------------------------------------

addEvent("uipause:loadSettings", true)
addEventHandler("uipause:loadSettings", root, function(values)
    if type(values) ~= "table" then return end
    applyAll(values)
end)

-- Another resource just started: retry anything we had to defer.
addEventHandler("onClientResourceStart", root, function()
    if pending then applyAll(pending) end
end)

--------------------------------------------------------------------------------
-- client -> server (called from c_pausemenu.lua on every change)
--------------------------------------------------------------------------------

function pauseSettingsPersist(id, value)
    if not pauseSettingDef(id) then return end
    triggerServerEvent("uipause:saveSetting", localPlayer, id, value)
end
