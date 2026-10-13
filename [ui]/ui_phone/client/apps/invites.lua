if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
--[[
    ui_phone / client/apps/invites.lua
    Pending lobby invites (fed by the server, e.g. from v_jobmanager).
    Selecting one joins the lobby and closes the phone.
]]

local invites = {}   -- { { id, title, subtitle }, ... }

phoneOnServer("invites:list", function(list)
    invites = type(list) == "table" and list or {}
end)

PhoneApp.defer(function()
PhoneApp.register({
    id    = "invites",
    name  = L("ui_phone.invites.invites"),
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
    empty = L("ui_phone.invites.no_pending_invites"),
    hint  = L("ui_phone.invites.enter_join_backspace_back"),

    onSelect = function(_, row)
        phoneRPC("invites:accept", row._id)
    end,
})
end)
