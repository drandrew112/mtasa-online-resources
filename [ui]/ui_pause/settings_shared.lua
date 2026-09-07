-- ui_pause / settings_shared.lua
--
-- Shared registry of the pause-menu settings that are persisted per account.
-- Both sides read this list so they always agree on:
--   * which setting ids may be saved,
--   * what Lua type each one is,
--   * how a value is written to / read back from accountData.
--
-- The actual behaviour of each setting (what get()/set() do) lives with the
-- SETTINGS_TREE in c_pausemenu.lua. This file only cares about storage.

-- Every id here must match an item id in SETTINGS_TREE (c_pausemenu.lua).
PAUSE_SETTINGS = {
    { id = "show3dblips",        type = "boolean" },
    { id = "enable3dnavigation", type = "boolean" },
}

-- accountData key prefix; the final key is e.g. "uipause.setting.show3dblips".
PAUSE_SETTING_KEY = "uipause.setting."

-- Returns the definition table for a setting id, or nil if it is not persisted.
function pauseSettingDef(id)
    for _, def in ipairs(PAUSE_SETTINGS) do
        if def.id == id then return def end
    end
    return nil
end

-- Lua value -> accountData storage form.
--
-- Booleans are stored as the numbers 1 / 0 (not as a Lua boolean) so that a
-- saved "false" stays distinguishable from "never saved": getAccountData
-- returns the boolean false for a missing key, which would otherwise collide
-- with a genuinely stored false.
function pauseSettingEncode(id, value)
    local def = pauseSettingDef(id)
    if not def then return nil end
    if def.type == "boolean" then
        return (value == true or value == 1 or value == "1") and 1 or 0
    elseif def.type == "number" then
        return tonumber(value)
    end
    return tostring(value)
end

-- accountData storage form -> Lua value. Returns nil when nothing is stored.
function pauseSettingDecode(id, raw)
    local def = pauseSettingDef(id)
    if not def then return nil end
    if raw == nil or raw == false then return nil end -- missing key
    if def.type == "boolean" then
        return raw == 1 or raw == "1" or raw == true
    elseif def.type == "number" then
        return tonumber(raw)
    end
    return tostring(raw)
end
