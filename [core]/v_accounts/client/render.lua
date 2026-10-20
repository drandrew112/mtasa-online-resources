local function renderPanels()

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

    local panel = Panels[UIState.panel]
    local form = UIState.panel == "login" or UIState.panel == "register"

    -- Logo + welcome above, weekly updates card right of the login/register panel
    if form and Header then Header.draw(panel) end
    if form and Weekly then Weekly.draw(panel) end

    -- Settings card (music + language) left of the panel; last, so the
    -- language list opens over everything else.
    if Settings then Settings.draw(panel) end
end

-- attached only while a panel is up (setPanel calls this)
local rendering = false
function setPanelRendering(on)
    on = on and true or false
    if on == rendering then return end
    rendering = on
    if on then
        addEventHandler("onClientRender", root, renderPanels)
    else
        removeEventHandler("onClientRender", root, renderPanels)
    end
end
setPanelRendering(UIState.active)
