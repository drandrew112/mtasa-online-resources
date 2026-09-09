-- Minden export-hivas, ami a kepernyore ir valamit, itt egy sorral a konzolba
-- (log) is bekerul, hogy kesobb visszakovetheto legyen mit mutatott a UI.
local function uiLog(fmt, ...)
    outputConsole("[ui_core] " .. fmt:format(...))
end

-- A folyamatosan (onClientRender-bol) hivott exportoknal csak akkor logolunk,
-- ha valtozott a szoveg, kulonben elarasztana a konzolt.
local lastLoadingText = nil
local lastTimerValue  = nil

function setBanner(title, text, r,g,b)
    uiLog("setBanner: %s | %s (r=%s g=%s b=%s)",
        tostring(title), tostring(text), tostring(r), tostring(g), tostring(b))
    UI.banner:set(title, text, r,g,b)
end

function setInfobox(text, r, g, b)
    uiLog("setInfobox: %s (r=%s g=%s b=%s)",
        tostring(text), tostring(r), tostring(g), tostring(b))
    UI.infobox:set(text, r, g, b)
end

function drawSubtitle(text, duration)
    uiLog("subtitle: %s (duration=%s)", tostring(text), tostring(duration))
    UI.subtitle:set(text, duration)
end

function setAlert(text, r, g, b, duration)
    uiLog("setAlert: %s (r=%s g=%s b=%s duration=%s)",
        tostring(text), tostring(r), tostring(g), tostring(b), tostring(duration))
    UI.alert:set(text, r, g, b, duration)
end

function addNotification(title, text)
    uiLog("addNotification: %s | %s", tostring(title), tostring(text))
    UI:addNotification(title, text)
end

function drawLoadingText(text)
    if text ~= lastLoadingText then
        lastLoadingText = text
        uiLog("drawLoadingText: %s", tostring(text))
    end
    UI:drawLoading(text)
end

function drawTimer(time_left)
    if time_left ~= lastTimerValue then
        lastTimerValue = time_left
        uiLog("drawTimer: %s", tostring(time_left))
    end
    UI:drawTimer(time_left)
end

-- 3 masodpercre megmutatja a kepernyon a szint / XP savot (a teljes Y overlay
-- nelkul). A v_levelsys hivja meg minden alkalommal amikor a jatekos XP-t kap.
function showLevelOverlay()
    uiLog("showLevelOverlay")
    UI.yOverlay:showLevelOnly()
end

-- Rovid ideig megmutatja a cash-t es alatta a valtozast:
-- kind = "add"  -> + $ <change>  (zold)
-- kind = "take" -> - $ <change>  (piros)
function showMoney(kind, change)
    uiLog("showMoney: %s | %s", tostring(kind), tostring(change))
    UI.yOverlay:showMoney(kind, change)
end

-- textInput.lua defines openTextInput / closeTextInput / isTextInputOpen; wrap
-- the opener so the console keeps a trace of what asked for input.
local _openTextInput = openTextInput
function openTextInput(title, maxLength, defaultText)
    uiLog("openTextInput: %s (max=%s)", tostring(title), tostring(maxLength))
    return _openTextInput(title, maxLength, defaultText)
end

function getScreenWH()
    return UI.sw, UI.sh
end

function getSafeZone()
    return UI.safe.x, UI.safe.y
end

function toggleMoveControls(v)
    toggleControl("forwards", v)
    toggleControl("backwards", v)
    toggleControl("left", v)
    toggleControl("right", v)
    toggleControl("change_camera", v)
    toggleControl("jump", v)
    toggleControl("sprint", v)
    toggleControl("look_behind", v)
    toggleControl("crouch", v)
    toggleControl("fire", v)
    toggleControl("aim_weapon", v)
    toggleControl("next_weapon", v)
    toggleControl("previous_weapon", v)
    toggleControl("action", v)
    toggleControl("walk", v)
    toggleControl("group_control_forwards", v)
    toggleControl("group_control_back", v)
    toggleControl("enter_exit", v)
    toggleControl("vehicle_fire", v)
    toggleControl("vehicle_secondary_fire", v)
    toggleControl("steer_forward", v)
    toggleControl("steer_back", v)
    toggleControl("accelerate", v)
    toggleControl("brake_reverse", v)
    toggleControl("horn", v)
    toggleControl("handbrake", v)
    toggleControl("vehicle_left", v)
    toggleControl("vehicle_right", v)
end
