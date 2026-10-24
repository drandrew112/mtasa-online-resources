if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
uicore = exports.ui_core

addEventHandler('onClientPlayerJoin', root,
	function()
		local name = getPlayerName(source)
		uicore:addNotification(L("v_joinquit.joinquit.player_joined"), name)
	end
)

addEventHandler('onClientPlayerQuit', root,
	function(reason)
		local name = getElementData(source, "displayName") or getPlayerName(source)
		local title = L("v_joinquit.joinquit.player_left")
		if 		reason=="Unknown" then title = L("v_joinquit.joinquit.player_swallowed_by_black_hole")
		elseif	reason=="Quit" then title = L("v_joinquit.joinquit.player_left")
		elseif	reason=="Kicked" then title = L("v_joinquit.joinquit.player_got_kicked")
		elseif	reason=="Banned" then title = L("v_joinquit.joinquit.player_got_banned")
		elseif	reason=="Bad Connection" then title = L("v_joinquit.joinquit.player_should_pay_for_their_internet")
		elseif	reason=="Timed out" then title = L("v_joinquit.joinquit.player_needs_better_computer_or_internet")
		end
		uicore:addNotification(title, name)
	end
)
