if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- HUD tracker of the officers of an unsafe scene's police call (server/safety.lua): ui_core stat tracker rows
-- "Scene not secured", "EMS waiting m:ss", "Active threats n" while they are near the scene.

addEvent("vsm:tracker", true)

local shown = {}   -- [scene id] = { call, emsSince, active }
local timer

local function rowId(id, n) return ("vsm_safe_%d_%d"):format(id, n) end

local function core()
    local res = getResourceFromName("ui_core")
    return res and getResourceState(res) == "running" and exports.ui_core or nil
end

local function mmss(sec)
    sec = math.max(0, math.floor(sec))
    return ("%d:%02d"):format(math.floor(sec / 60), sec % 60)
end

local function remove(id)
    local ui = core()
    if ui then for n = 1, 3 do ui:removeStatTracker(rowId(id, n)) end end
    shown[id] = nil
end

local function draw(id, d)
    local ui = core()
    if not ui then return end
    local red = { 255, 110, 110 }
    if not shown[id] then
        ui:addStatTracker(rowId(id, 1), L("v_scenemanager.safety.tracker_title", { call = d.call }), "", { order = 30, color = red })
        ui:addStatTracker(rowId(id, 2), L("v_scenemanager.safety.tracker_ems"), "-", { order = 31 })
        ui:addStatTracker(rowId(id, 3), L("v_scenemanager.safety.tracker_threats"), tostring(d.active), { order = 32 })
    end
    shown[id] = d
    ui:updateStatTracker(rowId(id, 3), tostring(d.active))
end

local function tick()
    local ui = core()
    if not ui then return end
    local now = getRealTime().timestamp
    for id, d in pairs(shown) do
        ui:updateStatTracker(rowId(id, 2), d.emsSince and mmss(now - d.emsSince) or L("v_scenemanager.safety.tracker_ems_none"))
    end
    if not next(shown) and isTimer(timer) then killTimer(timer); timer = nil end
end

addEventHandler("vsm:tracker", resourceRoot, function(id, data)
    if data then
        draw(id, data)
        if not isTimer(timer) then timer = setTimer(tick, 1000, 0) end
        tick()
    elseif shown[id] then
        remove(id)
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for id in pairs(shown) do remove(id) end
end)
