addEventHandler("onClientRender", root, function()
    if not UIState.active then return end

    -- Keep the HUD/minimap hidden for as long as a panel is up, even if another
    -- resource (e.g. ui_download after a mid-session file transfer) flips the
    -- flag back. setElementData is a no-op when the value is unchanged.
    setElementData(localPlayer, "hideHUD", true)

    dxDrawImage(0, 0, sw, sh, bg_img)
    dxDrawRectangle(0, 0, sw, sh, tocolor(0, 0, 0, 130)) -- darken the backdrop for contrast

    for name, panel in pairs(Panels) do
        if UIState.panel == name then
            panel:draw()
        end
    end

    -- Drawn last so it sits on top of the background image.
    if Music then
        Music.drawToggle()
    end
end)
