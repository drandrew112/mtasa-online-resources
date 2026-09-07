prefix = "#CC00FFArenaWar #FFFFFF// "
arena_dim = 2

local prevNum = 0
function mathRandom(min, max)
    outputChatBox(min.." m "..max)
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

addEventHandler("onClientPreRender", getRootElement(), function()
    setInteriorSoundsEnabled(false)
end)

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
