--[[
    v_phone / client/apps/invites.lua
    Pending lobby invites (fed by the server, e.g. from v_jobmanager).
    Selecting one joins the lobby and closes the phone.
]]

local invites = {}   -- { { id, title, subtitle }, ... }

phoneOnServer("invites:list", function(list)
    invites = type(list) == "table" and list or {}
end)

PhoneApp.register({
    id    = "invites",
    name  = "Invites",
    order = 20,

    badge = function() return #invites end,

    open = function() phonePull() end,

    items = function()
        local rows = {}
        for _, inv in ipairs(invites) do
            rows[#rows + 1] = { title = inv.title, subtitle = inv.subtitle, _id = inv.id }
        end
        return rows
    end,
    empty = "No pending invites",
    hint  = "[Enter] join    [Backspace] back",

    onSelect = function(_, row)
        phoneRPC("invites:accept", row._id)
    end,
})
