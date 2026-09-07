local sx, sy = guiGetScreenSize()
local rx, ry = 1360, 768

local isTab = false;
local xp_color = tocolor ( 0, 150, 255,  255 )

local xpLvlDos = 1000
local nextLvlXp = 600
function getNextXp(level)
    if level==0 then return 0 end
    local next_xp = xpLvlDos
    for i=1, level do
        next_xp = next_xp + ( i * nextLvlXp )
    end
    return next_xp
end
