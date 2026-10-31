-- police_system / modules/mdc/client/terminals.lua
-- MDC computers (server/terminals.lua): the list from the server, the nearest one checked every TERMINALS.CHECK ms
-- (on foot, with the police right); the "J  MDC" hint layer is on only next to one. J asks the server, which opens
-- the full MDC without a unit (mdc:terminalOpen). Placing them: /mdcpc (terminal_editor.lua).

local MDC = POL.mdc
local C = POLICE.TERMINALS
local TM = POL.module("terminals", { list = {}, near = nil })

local function distTo(e)
    local x, y, z = getElementPosition(localPlayer)
    return math.sqrt((e.x - x) ^ 2 + (e.y - y) ^ 2 + (e.z - z) ^ 2)
end

local function sameWorld(e)
    return getElementInterior(localPlayer) == (tonumber(e.interior) or 0)
       and getElementDimension(localPlayer) == (tonumber(e.dimension) or 0)
end

local function byId(id)
    for _, e in ipairs(TM.list) do if e.id == id then return e end end
    return nil
end

-- id of the computer within reach, or nil
function MDC.nearestTerminal()
    if getPedOccupiedVehicle(localPlayer) then return nil end
    local best, bd
    for _, e in ipairs(TM.list) do
        if sameWorld(e) then
            local d = distTo(e)
            if d <= C.RANGE and (not bd or d < bd) then best, bd = e, d end
        end
    end
    return best and best.id or nil
end

-- the open terminal MDC stays open this close
function MDC.nearTerminal(id)
    local e = byId(id)
    return e and sameWorld(e) and not getPedOccupiedVehicle(localPlayer) and distTo(e) <= C.CLOSE_DIST or false
end

local function hint()
    local e = TM.near and byId(TM.near)
    if not e or MDC.isOpen() then return end
    local sx, sy = getScreenFromWorldPosition(e.x, e.y, e.z + 0.45)
    if not sx then return end
    local text = L("police_system.terminals.hint")
    local font = POL.font(10, true)
    local w = dxGetTextWidth(text, 1, font) + POL.px(20)
    local h = POL.px(28)
    dxDrawRectangle(sx - w / 2, sy - h / 2, w, h, POL.colors.panel)
    dxDrawRectangle(sx - w / 2, sy + h / 2 - POL.px(2), w, POL.px(2), POL.colors.accent)
    dxDrawText(text, sx - w / 2, sy - h / 2, sx + w / 2, sy + h / 2, POL.colors.white, 1, font, "center", "center")
end
POL.layers.add("terminal_hint", hint, 40)

local function check()
    local id = (#TM.list > 0 and POL.hasRight()) and MDC.nearestTerminal() or nil
    if id ~= TM.near then
        TM.near = id
        POL.layers.set("terminal_hint", id ~= nil)
    end
end

POL.handle("terminals", function(list)
    TM.list = {}
    for _, e in ipairs(type(list) == "table" and list or {}) do
        e.id, e.x, e.y, e.z = tonumber(e.id), tonumber(e.x), tonumber(e.y), tonumber(e.z)
        if e.id and e.x and e.y and e.z then TM.list[#TM.list + 1] = e end
    end
    check()
end)

POL.handle("mdc:terminalOpen", function(id)
    if POL.hasRight() and MDC.nearTerminal(id) then MDC.openMdc(id) end
end)

function TM.start()
    POL.send("terminals:ready")
    setTimer(check, C.CHECK, 0)
end
