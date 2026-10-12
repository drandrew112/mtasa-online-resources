if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
--[[
    ui_phone / client/apps/browser.lua
    Opens the virtual browser (ui_browser) as its own full-screen panel. The
    phone closes itself first; ui_browser then owns the foreground.
]]

PhoneApp.register({
    id    = "browser",
    name  = L("ui_phone.browser.browser"),
    order = 40,

    open = function()
        local res = getResourceFromName("ui_browser")
        if res and getResourceState(res) == "running" then
            if Phone and Phone.close then Phone.close() end
            exports.ui_browser:openBrowser()
        else
            outputChatBox(L("ui_phone.browser.phone_browser_is_not_available_right"), 255, 255, 255, true)
        end
        -- Return false so the phone home grid stays put (we handled entry ourselves).
        return false
    end,
})
