addEvent("executeCommand", true)
addEventHandler("executeCommand", getRootElement(), function(cmd, ...)
	executeCommandHandler(cmd, client, ...)
end)