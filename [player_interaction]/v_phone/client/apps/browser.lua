--[[
    v_phone / client/apps/browser.lua
    Placeholder. The Browser will be its own full-screen panel opened from here;
    for now selecting it does nothing.
]]

PhoneApp.register({
    id    = "browser",
    name  = "Browser",
    order = 40,

    open = function()
        -- Nothing yet - refuse entry so the home grid stays put.
        return false
    end,
})
