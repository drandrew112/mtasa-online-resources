-- Timers

local sx, sy = guiGetScreenSize()

function UI:drawTimer(time_left)
    -- calc
    local text = "Time left: "..time_left
    -- calc ui
    local h = 25*ui(1.7)
    local w = dxGetTextWidth(text, ui(1.7), "default", true)+10
    -- background
    dxDrawRectangle(UI.slots.bottomRight.x-w, UI.slots.bottomRight.y-h, w, h, tocolor(0,0,0,160))
    -- text
    dxDrawText( text, UI.slots.bottomRight.x-w+5, UI.slots.bottomRight.y-(h/2), _,_, tocolor(255,255,255), ui(1.7), "default", "left", "center", false,false,false,true)    
end
