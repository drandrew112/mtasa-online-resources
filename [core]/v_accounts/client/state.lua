UIState = {
    active = false,
    panel = nil -- login | register | banned
}

function setPanel(name)
    UIState.active = (name ~= nil)
    UIState.panel = name

    for panelName, panel in pairs(Panels) do
        panel:setVisible(UIState.panel == panelName)
    end

    setElementData(localPlayer, "hideHUD", UIState.active)
    showCursor(UIState.active)
    uicore:toggleMoveControls(not UIState.active)
    guiSetInputMode(UIState.active and "no_binds" or "allow_binds")

    -- A banned player must not be able to move or act at all.
    toggleAllControls(localPlayer, not (UIState.panel == "banned"))

    -- Menu music follows panel visibility.
    if Music then
        Music.update()
    end

    if not UIState.active then
        setCameraTarget(localPlayer)
        setElementData(localPlayer, "hideHUD", false)
    end
end
