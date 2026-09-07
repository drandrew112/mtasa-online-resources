--[[
    v_phone / client/apps/myveh.lua
    Owned-vehicle list. A dedicated resource will feed this later; for now it is
    intentionally empty.
]]

PhoneApp.register({
    id    = "myveh",
    name  = "My Vehicles",
    order = 10,

    items = function() return {} end,
    empty = "You have no vehicles yet",
})
