-- /aipeds debug (client): the commands of the peds this client syncs (route lines, mode) and a label on every AI ped.
-- The render handler is attached only while the view is on.

local on = false
local COLORS = { move = tocolor(80, 220, 255), combat = tocolor(255, 70, 70), wait = tocolor(255, 220, 60),
                 idle = tocolor(200, 200, 200), exit = tocolor(255, 140, 0) }

local function render()
    local cx, cy, cz = getCameraMatrix()
    for _, ped in ipairs(getElementsByType("ped", root, true)) do
        local kind = getElementData(ped, "ai_peds")
        if kind then
            local x, y, z = getElementPosition(ped)
            if (x - cx) ^ 2 + (y - cy) ^ 2 < 90 * 90 then
                local st = Motor.debugInfo(ped)
                local cmd = st and st.cmd
                local col = cmd and COLORS[cmd.m] or tocolor(150, 150, 150)
                if cmd and cmd.pts and isElementSyncer(ped) then
                    local px, py, pz = x, y, z
                    for i = st.i or 1, #cmd.pts do
                        local pt = cmd.pts[i]
                        dxDrawLine3D(px, py, pz, pt[1], pt[2], pz, col, 2)
                        px, py = pt[1], pt[2]
                    end
                end
                if cmd and cmd.m == "combat" and isElement(cmd.t) then
                    local tx, ty, tz = getElementPosition(cmd.t)
                    dxDrawLine3D(x, y, z + 0.6, tx, ty, tz + 0.5, tocolor(255, 0, 0, 120), 1)
                end
                local sx, sy = getScreenFromWorldPosition(x, y, z + 1.2)
                if sx then
                    local text = kind .. (cmd and (" " .. cmd.m) or "") .. (isElementSyncer(ped) and " *" or "")
                    dxDrawText(text, sx + 1, sy + 1, sx + 1, sy + 1, tocolor(0, 0, 0), 1, "default-bold", "center")
                    dxDrawText(text, sx, sy, sx, sy, col, 1, "default-bold", "center")
                end
            end
        end
    end
end

addEvent(EV_DEBUG, true)
addEventHandler(EV_DEBUG, resourceRoot, function()
    on = not on
    if on then addEventHandler("onClientRender", root, render) else removeEventHandler("onClientRender", root, render) end
end)
