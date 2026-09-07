-- ui_pause / s_settings.lua
--
-- Server side of pause-menu settings persistence.
--
--   * The client changes a setting        -> "uipause:saveSetting" -> written
--     to the player's accountData.
--   * The client side starts and sends "uipause:clientReady" (or the player
--     logs in) -> every saved value is pushed back with "uipause:loadSettings"
--     so the client can apply it.
--
-- Valid setting ids and their types are declared in settings_shared.lua.

local PUSH_DELAY = 1500 -- ms after login before pushing, so client-side
                        -- dependencies (v_radar) are surely running

local function accountOf(player)
    local acc = player and getPlayerAccount(player)
    if not acc or isGuestAccount(acc) then return nil end
    return acc
end

-- Reads every saved setting for a player into a { id = value } map.
local function collectSaved(player)
    local acc = accountOf(player)
    if not acc then return {} end

    local out = {}
    for _, def in ipairs(PAUSE_SETTINGS) do
        local value = pauseSettingDecode(def.id, getAccountData(acc, PAUSE_SETTING_KEY .. def.id))
        if value ~= nil then
            out[def.id] = value
        end
    end
    return out
end

-- Pushes the saved settings to a client so it can apply them.
local function sendSaved(player)
    if not isElement(player) then return end
    triggerClientEvent(player, "uipause:loadSettings", player, collectSaved(player))
end

--------------------------------------------------------------------------------
-- client -> server: persist one changed setting
--------------------------------------------------------------------------------

addEvent("uipause:saveSetting", true)
addEventHandler("uipause:saveSetting", root, function(id, value)
    local player = client
    if not isElement(player) then return end
    if not pauseSettingDef(id) then return end

    local acc = accountOf(player)
    if not acc then return end -- guest: kept for the session only, never saved

    local encoded = pauseSettingEncode(id, value)
    if encoded == nil then return end
    setAccountData(acc, PAUSE_SETTING_KEY .. id, encoded)
end)

--------------------------------------------------------------------------------
-- push saved settings back to the client
--------------------------------------------------------------------------------

-- Client side is up and has added "uipause:loadSettings": safe to push now.
-- This also covers a resource restart with players already connected.
addEvent("uipause:clientReady", true)
addEventHandler("uipause:clientReady", root, function()
    if isElement(client) then
        sendSaved(client)
    end
end)

-- Login after the client side is already running: the event handler is added,
-- but a dependency (v_radar) may still be starting, so keep the cushion. The
-- client re-applies any deferred value on the next onClientResourceStart.
addEventHandler("onPlayerLogin", root, function()
    setTimer(sendSaved, PUSH_DELAY, 1, source)
end)
