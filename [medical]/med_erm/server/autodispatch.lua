-- Bridge to the optional med_erm_auto resource (automatic dispatcher).
-- The switch lives in med_erm_auto; erm only shows it (web console, /ermadmin)
-- and toggles it from the admin panel.

AutoDispatch = {}

local AUTO = "med_erm_auto"

local function running()
    local res = getResourceFromName(AUTO)
    return res and getResourceState(res) == "running"
end

-- -> { available = bool (resource running), enabled = bool }
function AutoDispatch.state()
    if not running() then return { available = false, enabled = false } end
    local ok, on = pcall(function() return exports[AUTO]:getAutoDispatch() end)
    return { available = true, enabled = ok and on == true }
end

function AutoDispatch.set(on, by)
    if not running() then return false, AUTO .. " is not running" end
    return exports[AUTO]:setAutoDispatch(on, by)
end
