if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- biz_missions / client/hud.lua
-- Mission HUD: the time left (ui_core timer, bottom right) and the stat rows
-- the server sends. The render handler only runs while a mission is shown.

local endTick, rows = nil, {}

local function fmt(sec)
    sec = math.max(0, math.floor(sec))
    return ("%02d:%02d"):format(math.floor(sec / 60), sec % 60)
end

local function render()
    if not endTick then return end
    exports.ui_core:drawTimer(fmt((endTick - getTickCount()) / 1000))
end

local function clearRows()
    for id in pairs(rows) do exports.ui_core:removeStatTracker("bizmis_" .. id) end
    rows = {}
end

addEvent("bizmis:hud", true)
addEventHandler("bizmis:hud", resourceRoot, function(d)
    if not d then
        if endTick then removeEventHandler("onClientRender", root, render) end
        endTick = nil
        clearRows()
        return
    end
    if not endTick then addEventHandler("onClientRender", root, render) end
    endTick = getTickCount() + (tonumber(d.left) or 0) * 1000
    local seen = {}
    for i, r in ipairs(d.rows or {}) do
        local id = tostring(r.id)
        seen[id] = true
        local label, value = L.resolve(r.label), L.resolve(r.value)
        if rows[id] then
            exports.ui_core:updateStatTracker("bizmis_" .. id, value, label)
        else
            exports.ui_core:addStatTracker("bizmis_" .. id, label, value, { order = 10 + i })
        end
        rows[id] = true
    end
    for id in pairs(rows) do
        if not seen[id] then
            exports.ui_core:removeStatTracker("bizmis_" .. id)
            rows[id] = nil
        end
    end
end)
