if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
--[[
    ui_phone / client/apps/myveh.lua
    Personal vehicles, fed by v_ownveh through server/apps/myveh.lua.

    Root screen  = four category folders (Land / Plane / Helicopter / Boat).
    Opening one  = the vehicles of that category; each row shows the model name
                   and the vehicle id.
    Enter on a vehicle asks the server to summon it. While a personal vehicle is
    already out the request is refused (store it first - interaction menu).
]]

local vehicles = {}   -- { { id, model, modelName, plate, isDestroyed, spawned }, ... }
local sub      = nil  -- nil = category list | "land" | "plane" | "helicopter" | "boat"

local CATEGORIES = {
    { key = "land",       name = L("ui_phone.myveh.land")       },
    { key = "plane",      name = L("ui_phone.myveh.plane")      },
    { key = "helicopter", name = L("ui_phone.myveh.helicopter") },
    { key = "boat",       name = L("ui_phone.myveh.boat")       },
}

local function categoryOf(model)
    local t = getVehicleType(model)
    if     t == "Plane"      then return "plane"
    elseif t == "Helicopter" then return "helicopter"
    elseif t == "Boat"       then return "boat"
    end
    return "land"
end

local function categoryName(key)
    for _, c in ipairs(CATEGORIES) do
        if c.key == key then return c.name end
    end
    return L("ui_phone.myveh.my_vehicles")
end

local function inCategory(key)
    local out = {}
    for _, v in ipairs(vehicles) do
        if categoryOf(v.model) == key then out[#out + 1] = v end
    end
    return out
end

local function anySpawned()
    for _, v in ipairs(vehicles) do
        if v.spawned then return true end
    end
    return false
end

--------------------------------------------------------------------------------

phoneOnServer("myveh:list", function(list)
    vehicles = type(list) == "table" and list or {}
end)

PhoneApp.register({
    id    = "myveh",
    name  = L("ui_phone.myveh.my_vehicles"),
    order = 10,

    open  = function() sub = nil; phonePull() end,
    close = function() sub = nil end,

    headerTitle = function()
        return sub and categoryName(sub) or L("ui_phone.myveh.my_vehicles")
    end,

    hint = function()
        if not sub then return L("ui_phone.myveh.enter_open") end
        if anySpawned() then return L("ui_phone.myveh.store_your_vehicle_first_interaction_menu") end
        return L("ui_phone.myveh.enter_request_vehicle")
    end,

    items = function()
        if not sub then
            local rows = {}
            for _, c in ipairs(CATEGORIES) do
                local n = #inCategory(c.key)
                rows[#rows + 1] = {
                    title    = c.name,
                    subtitle = n == 1 and "1 vehicle" or (L("ui_phone.myveh.vehicles", { n = n })),
                    _cat     = c.key,
                }
            end
            return rows
        end

        local rows = {}
        for _, v in ipairs(inCategory(sub)) do
            local right, rightColor
            if v.spawned then
                right = L("ui_phone.myveh.out")
            elseif v.isDestroyed then
                right, rightColor = L("ui_phone.myveh.destroyed"), PhoneUI.C.bad
            end
            local plate = (v.plate and v.plate ~= "") and ("   -   " .. v.plate) or ""
            rows[#rows + 1] = {
                title      = L("ui_phone.myveh.id", { model_name = v.modelName, id = v.id }),
                subtitle   = L("ui_phone.myveh.model", { model = v.model, plate = plate }),
                right      = right,
                rightColor = rightColor,
                _id        = v.id,
            }
        end
        return rows
    end,
    empty = L("ui_phone.myveh.you_have_no_vehicles_yet"),

    onSelect = function(_, row)
        if row._cat then
            sub = row._cat
            Phone.setSelected(1)
            return
        end
        if row._id then
            phoneRPC("myveh:request", row._id)
        end
    end,

    -- Backspace inside a category returns to the folder list.
    key = function(_, key)
        if sub and key == "backspace" then
            sub = nil
            Phone.setSelected(1)
            PhoneSound.select()
            return true
        end
        return false
    end,
})
