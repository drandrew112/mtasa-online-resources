UIState = {
    active = false,
    panel = nil -- login | register | forgot | banned
}

-- name = nil hides every panel. handoff = true: another screen (v_mainmenu, the
-- loading screen) takes over right away, so cursor / HUD / binds / camera stay
-- as they are instead of being handed back to the game.
function setPanel(name, handoff)
    UIState.active = (name ~= nil)
    UIState.panel = name

    for panelName, panel in pairs(Panels) do
        panel:setVisible(UIState.panel == panelName)
    end
    if setPanelRendering then setPanelRendering(UIState.active) end
    if Music then Music.update() end

    -- the cursor is per resource: ours stays on (and blocks the controls) until
    -- we hide it ourselves, even when another screen takes over
    showCursor(UIState.active)

    if handoff and not UIState.active then return end

    setElementData(localPlayer, "hideHUD", UIState.active)
    uicore:toggleMoveControls(not UIState.active)
    guiSetInputMode(UIState.active and "no_binds" or "allow_binds")

    -- A banned player must not be able to move or act at all.
    if UIState.panel == "banned" then
        toggleAllControls(false, true, false)
    else
        toggleAllControls(true, true, true)
    end

    if not UIState.active then
        setCameraTarget(localPlayer)
        setElementData(localPlayer, "hideHUD", false)
    end
end
