if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
prefix = "#CC00FFArenaWar #FFFFFF// "
arena_dim = 2

-- MTA seeds math.random itself at startup; reseeding per call only made values correlated
function table.random ( theTable )
    return theTable[ math.random ( 1, #theTable ) ]
end

-- client only (localPlayer is nil on the server): a persistent game setting, set once at start
-- and again after a spawn instead of every frame
if localPlayer then
    setInteriorSoundsEnabled(false)
    addEventHandler("onClientPlayerSpawn", localPlayer, function()
        setInteriorSoundsEnabled(false)
    end)
end
