local sw,sh = guiGetScreenSize()

local function lerp(a,b,t) return a + (b - a) * t end

-- red -> yellow -> green depending on remaining health ratio
local function healthColor(ratio)
    ratio = math.max(0, math.min(1, ratio))
    if ratio > 0.5 then
        local t = (ratio - 0.5) / 0.5
        return tocolor(lerp(230,40,t), lerp(190,200,t), lerp(60,130,t), 255)
    else
        local t = ratio / 0.5
        return tocolor(lerp(210,230,t), lerp(60,190,t), lerp(60,60,t), 255)
    end
end

function renderHud()
    local veh = getPedOccupiedVehicle(localPlayer)
    local int,dim = getElementInterior(localPlayer), getElementDimension(localPlayer)
    if (int==15 and dim==arena_dim) then
        if (veh) then
            local veh_hp = math.ceil(getElementHealth(veh))-421
            local maxHp = 1000-421
            local ratio = veh_hp/maxHp

            local w, h = 320, 34
            local x, y = sw/2-w/2, sh*0.1

            -- vehicle health
            dxDrawRectangle(x+2, y+3, w, h, tocolor(0,0,0,120))
            dxDrawRectangle(x-1, y-1, w+2, h+2, tocolor(255,255,255,25))
            dxDrawRectangle(x, y, w, h, tocolor(10,10,14,200))
            dxDrawRectangle(x+2, y+2, (w-4)*math.max(0, math.min(1, ratio)), h-4, healthColor(ratio))

            local text = ("Your vehicle")
            dxDrawText(text, sw/2+1, y+h/2+1, _,_, tocolor(0,0,0,180), 1.1, "default-bold", "center", "center")
            dxDrawText(text, sw/2, y+h/2, _,_, tocolor(255,255,255,255), 1.1, "default-bold", "center", "center")
        end
    end
end
addEventHandler("onClientRender", getRootElement(), renderHud)
