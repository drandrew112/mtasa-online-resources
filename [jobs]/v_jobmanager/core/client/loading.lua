if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Loading screen of a starting match: shown from matchStarted until the server says the match is ready
-- (job map built for everybody, at least one second). Progress comes from v_jobmaps (client events).

local sw, sh = guiGetScreenSize()
local active = nil   -- { name, hasMap, since, done, total }

addEvent("jobmanager:loadingStart", true)
addEvent("jobmanager:loadingEnd", true)
addEvent("onClientJobMapProgress")

local function render()
    if not active then return end
    local t = getTickCount() - active.since
    dxDrawRectangle(0, 0, sw, sh, tocolor(8, 10, 14, 245), true)
    dxDrawText(active.name or "", 0, sh * 0.36, sw, sh * 0.36 + 60, tocolor(255, 255, 255), 2, "default-bold", "center", "center", false, false, true)
    local dots = string.rep(".", math.floor(t / 400) % 4)
    dxDrawText(L("v_jobmanager.loading.title_loading") .. dots, 0, sh * 0.36 + 60, sw, sh * 0.36 + 100, tocolor(200, 205, 215), 1.4, "default", "center", "center", false, false, true)

    local w, h = math.floor(sw * 0.25), 6
    local x, y = (sw - w) / 2, sh * 0.36 + 120
    dxDrawRectangle(x, y, w, h, tocolor(255, 255, 255, 40), true)
    local fraction
    if active.hasMap and active.total and active.total > 0 then
        fraction = math.min(1, active.done / active.total)
    else
        fraction = math.min(1, t / 1000)
    end
    dxDrawRectangle(x, y, w * fraction, h, tocolor(255, 255, 255, 230), true)
    dxDrawText(L("v_jobmanager.loading.waiting"), 0, y + 16, sw, y + 40, tocolor(150, 155, 165), 1, "default", "center", "center", false, false, true)
end

local function stop()
    if not active then return end
    active = nil
    removeEventHandler("onClientRender", root, render)
end

addEventHandler("jobmanager:loadingStart", resourceRoot, function(name, hasMap)
    stop()
    active = { name = tostring(name), hasMap = hasMap == true, since = getTickCount(), done = 0, total = 0 }
    addEventHandler("onClientRender", root, render)
end)

addEventHandler("jobmanager:loadingEnd", resourceRoot, stop)

addEventHandler("onClientJobMapProgress", root, function(_, done, total)
    if active then active.done, active.total = done, total end
end)

addEventHandler("onClientResourceStop", resourceRoot, stop)
