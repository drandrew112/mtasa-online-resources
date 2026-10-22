if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Minden export-hivas, ami a kepernyore ir valamit, itt egy sorral a konzolba
-- (log) is bekerul, hogy kesobb visszakovetheto legyen mit mutatott a UI.
local function uiLog(fmt, ...)
    outputConsole("[ui_core] " .. fmt:format(...))
end

-- A folyamatosan (onClientRender-bol) hivott exportoknal csak akkor logolunk,
-- ha valtozott a szoveg, kulonben elarasztana a konzolt.
local lastLoadingText = nil
local lastTimerValue  = nil

-- Every text argument may be a plain string or a v_locals message object
-- { t = key, p = params } (DESIGN.md 4.5): messages become text in the player's
-- language here, strings pass through unchanged.
local function txt(x)
    if type(x) == "table" then return L.resolve(x) end
    return x
end

function setBanner(title, text, r,g,b)
    title, text = txt(title), txt(text)
    uiLog("setBanner: %s | %s (r=%s g=%s b=%s)",
        tostring(title), tostring(text), tostring(r), tostring(g), tostring(b))
    UI.banner:set(title, text, r,g,b)
end

function setInfobox(text, r, g, b)
    text = txt(text)
    uiLog("setInfobox: %s (r=%s g=%s b=%s)",
        tostring(text), tostring(r), tostring(g), tostring(b))
    UI.infobox:set(text, r, g, b)
end

function drawSubtitle(text, duration)
    text = txt(text)
    uiLog("subtitle: %s (duration=%s)", tostring(text), tostring(duration))
    UI.subtitle:set(text, duration)
end

function setAlert(text, r, g, b, duration)
    text = txt(text)
    uiLog("setAlert: %s (r=%s g=%s b=%s duration=%s)",
        tostring(text), tostring(r), tostring(g), tostring(b), tostring(duration))
    UI.alert:set(text, r, g, b, duration)
end

function addNotification(title, text, silent)
    title, text = txt(title), txt(text)
    uiLog("addNotification: %s | %s", tostring(title), tostring(text))
    UI:addNotification(title, text, silent == true)
end

function drawLoadingText(text)
    text = txt(text)
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

-- Stat trackers in the bottom-right corner, above the timer (client/stats.lua).
--   addStatTracker(id, label, value [, { order = n, color = {r,g,b}, progress = 0..1, barColor = {r,g,b} }])
--       - adds or replaces a row; `progress` draws a bar under the row (nil = no bar)
--   updateStatTracker(id, value [, label [, progress]])  - progress false removes the bar
--   removeStatTracker(id)
--   clearStatTrackers()  - every row of the calling resource
-- The rows of a resource are removed when it stops.
function addStatTracker(id, label, value, opts)
    if id == nil then return false end
    return UI.stats:set(tostring(id), txt(label), txt(value), opts, sourceResource or resource)
end

function updateStatTracker(id, value, label, progress)
    if id == nil then return false end
    return UI.stats:update(tostring(id), txt(value), txt(label), progress)
end

function removeStatTracker(id)
    if id == nil then return false end
    return UI.stats:remove(tostring(id))
end

function clearStatTrackers()
    return UI.stats:clearOwner(sourceResource or resource)
end

-- Rovid ideig megmutatja az egyenleget es alatta a valtozast:
--   kind      = "add"  -> + € <change>  (zold)
--               "take" -> - € <change>  (piros)
--   change    = pozitiv osszeg
--   moneyType = "cash" -> keszpenz blokk (zold egyenleg)
--               "bank" -> bankszamla blokk (kek egyenleg)
-- Mindharom kotelezo; rossz ertekre error + false, nem jelenik meg semmi.
-- Szerver oldalrol: exports.ui_core:showMoney(player, kind, change, moneyType).
function showMoney(kind, change, moneyType)
    uiLog("showMoney: %s | %s | %s", tostring(kind), tostring(change), tostring(moneyType))
    local who = sourceResource and getResourceName(sourceResource) or "?"
    if kind ~= "add" and kind ~= "take" then
        outputDebugString(("[ui_core] showMoney (%s): kind must be \"add\" or \"take\" (got %s)"):format(who, tostring(kind)), 1)
        return false
    end
    if moneyType ~= "cash" and moneyType ~= "bank" then
        outputDebugString(("[ui_core] showMoney (%s): moneyType must be \"cash\" or \"bank\" (got %s)"):format(who, tostring(moneyType)), 1)
        return false
    end
    change = tonumber(change)
    if not change or change <= 0 then
        outputDebugString(("[ui_core] showMoney (%s): change must be a positive number (got %s)"):format(who, tostring(change)), 1)
        return false
    end
    return UI.yOverlay:showMoney(kind, change, moneyType)
end

-- exports_s.lua showMoney(player, ...) -> ide
addEvent("ui_core:showMoney", true)
addEventHandler("ui_core:showMoney", resourceRoot, function(kind, change, moneyType)
    showMoney(kind, change, moneyType)
end)

-- textInput.lua defines openTextInput / closeTextInput / isTextInputOpen; wrap
-- the opener so the console keeps a trace of what asked for input.
local _openTextInput = openTextInput
function openTextInput(title, maxLength, defaultText, placeholder)
    title, placeholder = txt(title), txt(placeholder)
    uiLog("openTextInput: %s (max=%s)", tostring(title), tostring(maxLength))
    return _openTextInput(title, maxLength, defaultText, placeholder)
end

function getScreenWH()
    return UI.sw, UI.sh
end

function getSafeZone()
    return UI.safe.x, UI.safe.y
end

-- Az enter_exit-et csak a gomb (pl. Enter, F) felengedése után kapcsoljuk vissza:
-- ha egy menü Enterre zárul, a még lenyomott gombot a GTA új kiszállásnak venné.
local enterExitPending = false

local function isEnterExitHeld()
    for key in pairs(getBoundKeys("enter_exit") or {}) do
        if getKeyState(key) then return true end
    end
    return false
end

local function enableEnterExitOnRelease()
    if isEnterExitHeld() then return end
    removeEventHandler("onClientRender", root, enableEnterExitOnRelease)
    enterExitPending = false
    toggleControl("enter_exit", true)
end

local function setEnterExit(v)
    if v and isEnterExitHeld() then
        if not enterExitPending then
            enterExitPending = true
            addEventHandler("onClientRender", root, enableEnterExitOnRelease)
        end
        return
    end
    if enterExitPending then
        removeEventHandler("onClientRender", root, enableEnterExitOnRelease)
        enterExitPending = false
    end
    toggleControl("enter_exit", v)
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
    setEnterExit(v)
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
