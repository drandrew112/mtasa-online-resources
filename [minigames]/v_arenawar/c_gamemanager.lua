-- Ne tudj kiszállni a járműből játék közben
addEventHandler("onClientPlayerDamage", getRootElement(),
    function ()
        local int,dim = getElementInterior(source), getElementDimension(source)
        if (int==15 and dim==arena_dim) then
            cancelEvent()
        end
    end
)

addEventHandler("onClientResourceStop", getRootElement(),
     function (res)
            if (res == getThisResource()) then
                local int,dim = getElementInterior(localPlayer), getElementDimension(localPlayer)
                if (int==15 and dim==arena_dim) then
                    outputChatBox("Az aréna háború script leáll vagy újraindul.", 255,50,50, true)
                    triggerServerEvent("exitArena", localPlayer, localPlayer, 2)
                end
            end
     end
)
