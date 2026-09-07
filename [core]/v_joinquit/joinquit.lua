uicore = exports.ui_core

addEventHandler('onClientPlayerJoin', root,
	function()
		local name = getPlayerName(source)
		uicore:addNotification("Player joined", name)
	end
)

addEventHandler('onClientPlayerQuit', root,
	function(reason)
		local name = getPlayerName(source)
		local title = "Player left"
		if 		reason=="Unknown" then title = "Player swallowed by a black hole"
		elseif	reason=="Quit" then title = "Player left"
		elseif	reason=="Kicked" then title = "Player got kicked"
		elseif	reason=="Banned" then title = "Player got banned"
		elseif	reason=="Bad Connection" then title = "Buy internet"
		elseif	reason=="Timed out" then title = "Player crashed"
		end
		uicore:addNotification(title, name)
	end
)
