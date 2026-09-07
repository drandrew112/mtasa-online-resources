local prefix = "#00ffffSzint Rendszer #ff0000// #ffffff"

local xpLvlDos = 1000
local nextLvlXp = 600

local showTimer

function getNextXp(level)
    local next_xp = xpLvlDos
    for i=1, level do
        next_xp = next_xp + ( i * nextLvlXp )
    end
    return next_xp
end

addEventHandler ( "onResourceStart" , resourceRoot ,
    function ( )
        for index , player in ipairs ( getElementsByType ( "player" ) ) do
            local pAccount = getPlayerAccount ( player )
            if not isGuestAccount ( pAccount ) then
                local level = getAccountData ( pAccount , "level" )
                local xp = getAccountData ( pAccount , "xp" )

		if level then
		    setElementData(player , "level" , level )
		else
        	    setAccountData ( pAccount , "level" , 1 )
		    setElementData(player , "level" , 1 )
        	end
		if xp then
		    setElementData(player , "xp" , xp )
		else
        	    setAccountData ( pAccount , "xp" , 0 )
		    setElementData(player , "xp" , 0 )
        	end
		local next_xp = getNextXp(level or 1)
		setAccountData ( pAccount , "next_xp" , next_xp )
		setElementData ( player   , "next_xp" , next_xp )
            else
                setElementData(player , "level", "n/a")
                setElementData(player , "xp", "n/a")
                setElementData(player , "next_xp", "n/a")
            end
            setElementData(player, "levelsys:show", false)
        end
    end
)
 
addEventHandler ( "onPlayerLogin" , root ,
    function ( _ , pAccount )
        local level = getAccountData ( pAccount , "level" )
        local xp = getAccountData ( pAccount , "xp" )

	if level then
	    setElementData(source , "level" , level )
	else
        setAccountData ( pAccount , "level" , 1 )
	    setElementData(source , "level" , 1 )
        end
	if xp then
	    setElementData(source , "xp" , xp )
	else
        setAccountData ( pAccount , "xp" , 0 )
	    setElementData(source , "xp" , 0 )
        end
	local next_xp = getNextXp(level or 1)
	setAccountData ( pAccount , "next_xp" , next_xp )
	setElementData ( source   , "next_xp" , next_xp )
    end
)

addEventHandler ( "onPlayerJoin" , root ,
    function ( )
        setElementData ( source , "xp"          , 0 )
        setElementData ( source , "level"       , 0 )
        setElementData ( source , "next_xp"     , 0 )
        setElementData ( source , "lvlsys:show" , false )
    end
)

function saveLvl ( player, level, xp )
    local pAccount = getPlayerAccount ( player )
    --local level = getAccountData ( pAccount , "level" )
    --local xp    = getAccountData ( pAccount , "xp" )

    setAccountData ( pAccount , "level"   , tonumber ( level ) )
    setAccountData ( pAccount , "xp"      , tonumber ( xp ) )

    setElementData ( player , "level"   , level )
    setElementData ( player , "xp"      , xp )

    -- Next_xp
    local next_xp = getNextXp(level)
    setAccountData ( pAccount , "next_xp" , next_xp )
    setElementData ( player   , "next_xp" , next_xp )

    -- Show level
    setElementData(player, "lvlsys:show", true)
    if (showTimer) then killTimer(showTimer) end
    showTimer = setTimer(function()
        setElementData(player, "lvlsys:show", false)
    end, 5*1000, 1)
end

function giveXp (player, add_xp)
    --local pAccount = getPlayerAccount ( player )
    local level   = getElementData ( player , "level" )
    local xp      = getElementData ( player , "xp" )
    local next_xp = getElementData ( player , "next_xp" )

    -- XP Hozzáadása
    for i=1, 10000 do
        if ( (xp + add_xp) > (next_xp - 1) ) then -- level up
            level = level + 1
            next_xp = getNextXp(level)
            outputChatBox(prefix.."Elérted a "..level..". szintet!", player, 255,255,255, true)
        else -- Level up vége, folytatás
            xp = (xp + add_xp)
            saveLvl(player, level, xp)
            break
        end
    end
end
addCommandHandler("givexp", function(playerSource, cmd, targetName, add_xp)
    local player = playerSource
    if ( getElementData(player, "acc:adminLevel") > 2 ) then
	local target = getPlayerFromName(targetName)
	if target then
	    giveXp(target, add_xp)
	    outputChatBox(prefix.."#ffffffKaptal #00ffff"..add_xp.."#ffffff XP-t, #00ffff"..getPlayerName(player).."#ffffff-tol/tol", target, 255,255,255, true)
	    outputChatBox(prefix.."#ffffffAdtal #00ffff"..add_xp.."#ffffff XP-t "..targetName.."#ffffff jatekosnak", player, 255,255,255, true)
	end
    else
        outputChatBox(prefix.."Ehhez nincs jogod!",player,255,50,50,true)
        return
    end
end)

addCommandHandler("resetlvl",
    function (playerSource, cmd, targetName)
        local player = playerSource
        if ( getElementData(player, "acc:adminLevel") > 2 ) then
            if (targetName) then
                local target = getPlayerFromName(targetName)
                if (target) then
                    local level, xp = 1, 0
                    saveLvl(target, level, xp)
                else
                    outputChatBox(prefix.."A játékos nem található", player, 255,50,50, true)
                end
            else
                outputChatBox(prefix.."Add meg annak a játékosnak a nevét akinek", player, 255,50,50, true)
            end
        else
            outputChatBox(prefix.."Ehhez nincs jogod!",player,255,50,50,true)
            return
        end
    end
)
