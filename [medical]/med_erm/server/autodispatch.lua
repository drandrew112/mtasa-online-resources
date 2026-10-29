if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Bridge to the auto dispatch module (auto/server/main.lua).
-- The switch lives in the module; erm shows it (web console, /ermadmin)
-- and toggles it from the admin panel.

AutoDispatch = {}

-- -> { available = bool (always true: the module is part of med_erm), enabled = bool }
function AutoDispatch.state()
    return { available = true, enabled = getAutoDispatch() == true }
end

function AutoDispatch.set(on, by)
    return setAutoDispatch(on, by)
end
