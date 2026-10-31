-- police_system / core/client/main.lua
-- One onClientKey handler for every police key, asked in priority order (MDC > radio > query window > surrender >
-- stop > F keys). A handler returns true when it used the key; the key is then cancelled (no GTA control, no other
-- bind: C does not crouch while the radio opens, arrows do not steer while it is open). Keys are only handled with
-- the police right (nothing shows without it, no warning either), except the surrender of a wanted player.

local keyHandlers = {}

-- fn(button, press) -> true when used; prio: higher first
function POL.key(name, fn, prio)
    keyHandlers[#keyHandlers + 1] = { name = name, fn = fn, prio = prio or 0 }
    table.sort(keyHandlers, function(a, b) return a.prio > b.prio end)
end

addEventHandler("onClientKey", root, function(button, press)
    if isConsoleActive() or isChatBoxInputActive() or isMainMenuActive() then return end
    -- MTA reports the function keys upper-case ("F5"); every handler compares lower-case names
    button = button:lower()
    for i = 1, #keyHandlers do
        local h = keyHandlers[i]
        local ok, used = pcall(h.fn, button, press)
        if not ok then
            outputDebugString("[police_system] key " .. h.name .. ": " .. tostring(used), 1)
        elseif used then
            cancelEvent()
            return
        end
    end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, m in ipairs(POL.list) do
        if m.start then
            local ok, err = pcall(m.start)
            if not ok then outputDebugString("[police_system] start " .. m.name .. ": " .. tostring(err), 1) end
        end
    end
end)

-- the right can change (work_police duty): modules rebuild what they show
addEventHandler("onClientElementDataChange", localPlayer, function(key)
    if key == POLICE.RIGHT_KEY then POL.emit("right", POL.hasRight()) end
end)
