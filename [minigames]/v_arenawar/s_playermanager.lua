
-- init --
continueMarker,exitMarker = nil
local function init ()
    enterMarker1 = createMarker(2727.3037109375, -1854.26953125, 8.5830879211426, "cylinder", 6, 160,0,240,50, getRootElement())
    setElementData(enterMarker1, "arenawar_marker", true)
    setElementData(enterMarker1, "func", "entermarker")
    createBlipAttachedTo(enterMarker1, 53, 2, 160,0,240,255, 0, 500, getRootElement())
    enterMarker2 = createMarker(2684.4033203125, -1685.0390625, 8.4273843765259, "cylinder", 6, 160,0,240,50, getRootElement())
    setElementData(enterMarker2, "arenawar_marker", true)
    setElementData(enterMarker2, "func", "entermarker")
    createBlipAttachedTo(enterMarker2, 53, 2, 160,0,240,255, 0, 500, getRootElement())
    enterMarker3 = createMarker(2796.1591796875, -1831.0224609375, 8.8687553405762, "cylinder", 6, 160,0,240,50, getRootElement())
    setElementData(enterMarker3, "arenawar_marker", true)
    setElementData(enterMarker3, "func", "entermarker")
    createBlipAttachedTo(enterMarker3, 53, 2, 160,0,240,255, 0, 50, getRootElement())
    enterMarker4 = createMarker(2755.701171875, -1673.15234375, 8.7311372756958, "cylinder", 6, 160,0,240,50, getRootElement())
    setElementData(enterMarker4, "arenawar_marker", true)
    setElementData(enterMarker4, "func", "entermarker")
    createBlipAttachedTo(enterMarker4, 53, 2, 160,0,240,255, 0, 500, getRootElement())

    setAircraftMaxHeight(3000)
end
addEventHandler ("onResourceStart", resourceRoot, init)

-- Marker --
addEventHandler("onPlayerMarkerHit", getRootElement(),
     function (marker)
        if (getElementData(marker, "arenawar_marker")==true) then
            if (getElementData(marker, "func") == "entermarker") then
                triggerClientEvent(source, "markerHit", source, marker)
            elseif (getElementData(marker, "func") == "continue") then
                giveArenaVehicle(source)
            elseif (getElementData(marker, "func") == "leave") then
                exitArena(source, 2)
            end
        end
     end
)

-- enter / exit --

local arenaPlayers = {}

function updateArenaPlayerCount()
    local count = 0
    for _ in pairs(arenaPlayers) do
        count = count + 1
    end
    triggerClientEvent(root, "updateArenaPlayerCount", root, count)
end

function enterArena(player)
    if not arenaPlayers[player] then
        arenaPlayers[player] = true
        updateArenaPlayerCount()

        -- Fekete képernyő ("töltőképernyő" hatás), hogy ne tűnjön random teleportnak.
        -- 1) elsötétítés  2) fekete alatt teleport  3) várunk, míg az aréna betöltődik  4) visszafade
        fadeCamera(player, false, 1.0, 0, 0, 0)
        setTimer(function()
            if not isElement(player) or not arenaPlayers[player] then return end

            setElementInterior(player, 15)
            setElementDimension(player, arena_dim)
            setCameraTarget(player, player)

            giveArenaVehicle(player)

            -- Tartsuk feketén, amíg az új környezet betöltődik, majd lassú visszafade.
            setTimer(function()
                if isElement(player) and arenaPlayers[player] then
                    fadeCamera(player, true, 2.0)
                end
            end, 2000, 1)
        end, 1000, 1)
    end
end
addEvent("enterArena", true)
addEventHandler("enterArena", root, enterArena)

addCommandHandler("fadetrue", function(plr) fadeCamera(plr, true) end)
addCommandHandler("fadefalse", function(plr) fadeCamera(plr, false) end)

function exitArena(player, code)
    local code = code or 0
    --local int,dim = getElementInterior(player), getElementDimension(player)
    --if (int==15 and dim==arena_dim) then

        --[[
            codes
            0 - normal exit (requires player in awTeam)
            1 - vehicle blowed (tp to respawn point)
            2 - teleport player to arenaExit (tp to outside)
        ]]

        if (code == 0) then
            fadeCamera(player, false, 1)
            setTimer(function()
                if arenaPlayers[player] then
                    arenaPlayers[player] = nil
                    updateArenaPlayerCount()
                end

                local x,y,z,rot = arenaExit.x, arenaExit.y, arenaExit.z, arenaExit.rot
                setElementInterior(player, 0)
                setElementDimension(player, 0)
                setElementPosition(player, x,y,z)
                setElementRotation(player, 0,0,rot)
                
                local veh = getPedOccupiedVehicle(player)
                if veh then
                    removePedFromVehicle(player)
                    blowVehicle(veh)
                    setTimer(destroyElement, 60000, 1, veh)
                end

                fadeCamera(player, true)
            end, 1500, 1)
        elseif (code == 1) then
            local veh = getPedOccupiedVehicle(player)
            removePedFromVehicle(player)
            setCameraTarget(player, veh)

            blowVehicle(veh)
            setTimer(function()
                setTimer(destroyElement, 500,1, veh)
            end, (respawnTime*3)*1000, 1)

            local x,y,z,rot = arenaRespawn.x, arenaRespawn.y, arenaRespawn.z, arenaRespawn.rot
            setElementPosition(player, x,y,z)
            setElementRotation(player, 0,0,rot)
            
            setElementData(player, "arenawar_died", true)
            setElementFrozen(player, true)
            setTimer(setCameraMatrix, (respawnTime*1000), 1, player, -1527.908203125,996.4892578125,1047.7312011719, -1368.951171875,996.4892578125,1023.0634765625, 0, 80)

            local c = respawnTime
            setTimer(function()
                c = c-1
                setElementData(player, "arenawar_died_timeleft", c)
                if c==0 then
                    triggerClientEvent(player, "playerEliminated", player)
                end
            end, 1000, respawnTime)
        elseif (code == 2) then
            setElementData(player, "arenawar_died", false)
            fadeCamera(player, false, 1)
            setTimer(function()
                if arenaPlayers[player] then
                    arenaPlayers[player] = nil
                    updateArenaPlayerCount()
                end
                
                if isPedInVehicle(player) then removePedFromVehicle(player) end

                setElementFrozen(player, false)
                setCameraTarget(player, player)

                local x,y,z,rot = arenaExit.x, arenaExit.y, arenaExit.z, arenaExit.rot
                setElementInterior(player, 0)
                setElementDimension(player, 0)
                setElementPosition(player, x,y,z)
                setElementRotation(player, 0,0,rot)

                fadeCamera(player, true)
            end, 1500, 1)
        end
    --end
end
addEvent("exitArena", true)
addEventHandler("exitArena", getRootElement(), exitArena)

-- Közös takarítás: a játékost kivesszük az aréna nyilvántartásából és töröljük
-- a hozzá tartozó aréna-állapotot. Nem teleportál (halott játékosnál nincs értelme),
-- csak "megszünteti a tagságot".
function cleanupArenaPlayer(player)
    if arenaPlayers[player] then
        arenaPlayers[player] = nil
        updateArenaPlayerCount()
    end

    setElementData(player, "arenawar_died", false)
    removeElementData(player, "arenawar_died_timeleft")

    if isElement(player) then
        setElementFrozen(player, false)

        local veh = getPedOccupiedVehicle(player)
        if veh and isElement(veh) then
            removePedFromVehicle(player)
            setTimer(function() if isElement(veh) then destroyElement(veh) end end, 500, 1)
        end
    end
end

-- Ha a játékos meghal az aréna közben, ne tároljuk tovább: úgy kezeljük,
-- mintha kilépett volna az Arena Warból.
addEventHandler("onPlayerWasted", getRootElement(),
    function ()
        if arenaPlayers[source] then
            cleanupArenaPlayer(source)
            setElementInterior(source, 0)
            setElementDimension(source, 0)
        end
    end
)

-- Ha a játékos kilép a szerverről aréna közben, ne maradjon benne ragadva a nyilvántartásban.
addEventHandler("onPlayerQuit", getRootElement(),
    function ()
        if arenaPlayers[source] then
            cleanupArenaPlayer(source)
        end
    end
)

-- continue game
function continueGame(player)
    setElementData(player, "arenawar_died", false)
    fadeCamera(player, false, 0.5)
    setTimer(function()
        setElementFrozen(player, false)
        setCameraTarget(player, player)
        giveArenaVehicle(player)
        setTimer(function() fadeCamera(player, true) end, 750, 1)
    end, 750, 1)
end
addEvent("continueGame", true)
addEventHandler("continueGame", getRootElement(), continueGame)

-- Ne tudj kiszállni a járműből játék közben
addEventHandler("onVehicleStartExit", getRootElement(),
    function (player)
        local int,dim = getElementInterior(player), getElementDimension(player)
        if (int==15 and dim==arena_dim) then
            cancelEvent()
        end
    end
)

-- Export: más resource-ok (pl. a ui_pause "Jobs" menüje) ezen keresztül
-- léptethetnek be egy játékost az Arena Warba, az enterArena logikáján keresztül.
function arenawarJoin(player)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    enterArena(player)
    return true
end
