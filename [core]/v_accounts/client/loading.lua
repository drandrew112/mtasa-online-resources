if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Account System - client loading screen
--
-- A plain black screen with the ui_core loading spinner, shown between a
-- successful login/registration and the moment the server spawns the player
-- (while account data is being pulled from the shared MySQL store).

local active = false
local screenW, screenH = guiGetScreenSize()

addEvent("acc:loadingScreen", true)
addEvent("onClientPlayerLoaded") -- local; fired when the server finished loading the player (arg 1 = account name)
addEvent("acc:playerLoaded", true)
addEventHandler("acc:playerLoaded", root, function(accName)
    triggerEvent("onClientPlayerLoaded", localPlayer, accName)
end)
addEvent("onClientLoadingStarted") -- local; fired when the loading screen appears
addEventHandler("acc:loadingScreen", root, function(show)
    active = show and true or false

    if active then
        triggerEvent("onClientLoadingStarted", localPlayer)
        setElementData(localPlayer, "hideHUD", true)
        showCursor(false)
        fadeCamera(true)
        toggleAllControls(localPlayer, false, true, false)
    end
    -- When it turns off, acc:setPanel(nil) follows immediately and restores
    -- controls / HUD, so there is nothing to undo here.
end)

addEventHandler("onClientRender", root, function()
    if not active then return end
    dxDrawRectangle(0, 0, screenW, screenH, tocolor(0, 0, 0, 255))
    exports.ui_core:drawLoadingText(L("v_accounts.loading.loading"))
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if active then
        toggleAllControls(localPlayer, true, true, true)
    end
end)

-- Exported (client only). A required resource calls
-- exports.v_accounts:resourceReady() once it is fully set up; the name comes
-- from sourceResource. When the server asks (acc:checkReady) and every required
-- resource has reported, the client answers acc:clientReady and loading goes on.
-- A listed resource that is not running on this client is not waited for.
local REQUIRED = {
    "ui_inac", "ui_pause", "ui_phone", "v_admin", "v_introduce", "v_weekly",
    "v_socialpanel", "v_jobmanager", "v_jobcreator", "v_arenawar",
    "med_erm", "work_ems", "rw_loco", "shader_colors",
    "world_clothes-shop", "world_ferriswheel",
    -- resources whose shared configs / tables hold texts (v_locals L.config or own gate)
    "v_stats", "v_radar", "v_nametags", "v_customs", "v_els",
    "medsys", "medsys_effects", "medsys_events", "med_bag", "med_hospitals",
    "mg_airway", "mg_cpr", "mg_intravenous",
    "rw_core", "rw_customtracks", "rw_signals", "rw_timetable",
    "work_atc", "work_traindriver", "world_elevators", "map_int_sacontrol",
}
local ready = {}
local checking = false
local warnTimer

local function missingResources()
    local missing = {}
    for _, name in ipairs(REQUIRED) do
        if not ready[name] then
            local res = getResourceFromName(name)
            if res and getResourceState(res) == "running" then missing[#missing + 1] = name end
        end
    end
    return missing
end

local function tryReport()
    if not checking then return end
    if #missingResources() > 0 then return end
    checking = false
    if isTimer(warnTimer) then killTimer(warnTimer) end
    triggerServerEvent("acc:clientReady", localPlayer)
end

function resourceReady()
    if not sourceResource then return end
    ready[getResourceName(sourceResource)] = true
    tryReport()
end

addEvent("acc:checkReady", true)
addEventHandler("acc:checkReady", root, function()
    checking = true
    if isTimer(warnTimer) then killTimer(warnTimer) end
    warnTimer = setTimer(function()
        local missing = missingResources()
        if checking and #missing > 0 then
            outputDebugString("[v_accounts] still waiting for resourceReady from: " .. table.concat(missing, ", "), 2)
        end
    end, 10000, 0)
    tryReport()
end)
