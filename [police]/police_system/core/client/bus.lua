if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- police_system / core/client/bus.lua
-- Client side of the module registry: POL.module, the internal bus (POL.on / POL.emit), server events
-- (POL.handle "pol:<name>"), requests (POL.send), the state every module needs (right, unit, fonts, scale).

POL = POL or {}
POL.list = {}
local handlers = {}

function POL.module(name, t)
    t = t or {}
    t.name = name
    POL[name] = t
    POL.list[#POL.list + 1] = t
    return t
end

function POL.on(ev, fn)
    local h = handlers[ev]
    if not h then h = {}; handlers[ev] = h end
    h[#h + 1] = fn
end

function POL.emit(ev, ...)
    local h = handlers[ev]
    if not h then return end
    for i = 1, #h do
        local ok, err = pcall(h[i], ...)
        if not ok then outputDebugString("[police_system] " .. ev .. ": " .. tostring(err), 1) end
    end
end

-- server -> client handler for "pol:<name>"
function POL.handle(name, fn)
    addEvent("pol:" .. name, true)
    addEventHandler("pol:" .. name, resourceRoot, fn)
end

function POL.send(name, ...)
    triggerServerEvent("pol:" .. name, resourceRoot, ...)
end

------------------------------------------------------------------------ shared state

POL.unit = false   -- U.state of the server (callsign, status, sub, members ...) or false

function POL.hasRight()
    if not POLICE.REQUIRE_POLICE_RIGHT then return true end
    return getElementData(localPlayer, POLICE.RIGHT_KEY) == true
end

function POL.onDuty() return POL.unit ~= false and POL.unit ~= nil end

function POL.inPoliceVehicle()
    local veh = getPedOccupiedVehicle(localPlayer)
    local ok, def = isPoliceModelVehicle(veh)
    return ok and not def.aiOnly and veh or nil
end

function POL.notify(text)
    if getResourceFromName("ui_core") and getResourceState(getResourceFromName("ui_core")) == "running" then
        exports.ui_core:addNotification(L("police_system.title"), L.resolve(text))
    end
end

POL.handle("notify", function(msg) POL.notify(msg) end)

POL.handle("unit:state", function(state)
    local old = POL.unit
    POL.unit = state or false
    POL.emit("unit", POL.unit, old)
end)

------------------------------------------------------------------------ drawing helpers

local sw, sh = guiGetScreenSize()
POL.sw, POL.sh = sw, sh
POL.scale = math.max(0.65, sh / 1080)
function POL.px(v) return math.floor(v * POL.scale + 0.5) end

local fonts = {}
function POL.font(size, bold)
    local key = (bold and "b" or "r") .. size
    if not fonts[key] then
        fonts[key] = dxCreateFont(bold and "client/fonts/RobotoB.ttf" or "client/fonts/Roboto.ttf", POL.px(size), false, "cleartype")
            or (bold and "default-bold" or "default")
    end
    return fonts[key]
end

POL.colors = {
    bg = tocolor(10, 18, 34, 242), panel = tocolor(16, 28, 52, 250), panel2 = tocolor(22, 38, 68, 255),
    line = tocolor(48, 70, 110, 255), text = tocolor(225, 232, 245, 255), dim = tocolor(140, 158, 190, 255),
    accent = tocolor(70, 140, 255, 255), accentDim = tocolor(40, 80, 150, 255), red = tocolor(235, 64, 64, 255),
    green = tocolor(64, 200, 110, 255), yellow = tocolor(240, 200, 60, 255), orange = tocolor(245, 140, 50, 255),
    white = tocolor(255, 255, 255, 255), black = tocolor(0, 0, 0, 200), hover = tocolor(40, 64, 108, 255),
}

function POL.statusColor(status)
    local s = UNIT_STATUS[status]
    if not s then return POL.colors.dim end
    return tocolor(s.color[1], s.color[2], s.color[3], 255)
end

function POL.money(n) return L.money(n) end
function POL.clock(ts)
    if not ts then return "" end
    local t = getRealTime(ts)
    return ("%02d:%02d"):format(t.hour, t.minute)
end
function POL.date(ts)
    if not ts then return "" end
    local t = getRealTime(ts)
    return ("%04d-%02d-%02d %02d:%02d"):format(t.year + 1900, t.month + 1, t.monthday, t.hour, t.minute)
end
