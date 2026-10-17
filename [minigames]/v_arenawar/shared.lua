if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
prefix = "#CC00FFArenaWar #FFFFFF// "
arena_dim = 2

local prevNum = 0
function mathRandom(min, max)
    outputChatBox(L.text("v_arenawar.shared.m", { min = min, max = max }))
    local rand = math.random(tonumber(min), tonumber(max))
    if (rand ~= prevNum) then
        prevNum = rand
        return tonumber(rand)
    else
        mathRandom(min, max)
    end
    outputChatBox(rand.." "..prevNum)
end

function table.random ( theTable )
    return theTable[ random ( 1, #theTable ) ]
end

-- client only (localPlayer is nil on the server): a persistent game setting, set once at start
-- and again after a spawn instead of every frame
if localPlayer then
    setInteriorSoundsEnabled(false)
    addEventHandler("onClientPlayerSpawn", localPlayer, function()
        setInteriorSoundsEnabled(false)
    end)
end

-- better random
local u = 0 -- don't delete
function random(x, y)
    u = u + 1
    math.randomseed(os.time()+u)
    if x ~= nil and y ~= nil then
        return math.floor(x +(math.random()*999999 %y))
    else
        return math.floor((math.random()*100))
    end
end
