-- Screenshot preparation on the probe client: hide the custom UI (minimap, ui_core
-- overlays) through the shared "hideHUD" element data and the chat, optional
-- daylight (client-side time + weather only); everything is restored after the
-- capture. The GTA HUD is never touched: the gamemode keeps it hidden all the time.

local saved

local function restore()
    if not saved then return end
    if saved.ui then
        -- local only: the value is restored exactly as it was, nothing is synced
        setElementData(localPlayer, "hideHUD", saved.hideHUD, false)
        showChat(saved.chat)
    end
    if saved.time then
        if isTimer(saved.holdTimer) then killTimer(saved.holdTimer) end
        setTime(saved.time[1], saved.time[2])
        setWeather(saved.weather)
    end
    if isTimer(saved.safety) then killTimer(saved.safety) end
    saved = nil
end

addEvent("cmcp:captureRestore", true)
addEventHandler("cmcp:captureRestore", resourceRoot, restore)

-- capturePrepare: { hideHud, daylight }
CMCPC.ops.capturePrepare = function(a)
    restore()
    saved = {}
    if a.hideHud then
        saved.ui = true
        saved.hideHUD = getElementData(localPlayer, "hideHUD")
        saved.chat = isChatVisible()
        -- v_radar skips the minimap and ui_core its overlays while hideHUD is true
        setElementData(localPlayer, "hideHUD", true, false)
        showChat(false)
    end
    if a.daylight then
        local h, m = getTime()
        saved.time = { h, m }
        saved.weather = getWeather()
        local function hold()
            setTime(12, 0)
            setWeather(1)
        end
        hold()
        saved.holdTimer = setTimer(hold, 100, 0)
    end
    -- safety: never leave the UI hidden if the restore event is lost
    saved.safety = setTimer(restore, 20000, 1)
    return { prepared = true }
end
