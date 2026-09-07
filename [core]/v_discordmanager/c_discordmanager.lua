
local roles = {
   [0]="PLAYER",
	[1]="MOD",
	[2]="A1",
	[3]="A2",
	[4]="A3",
	[5]="A4",
	[6]="A5",
	[7]="SA",
	[8]="CM",
	[9]="WEBDEV",
	[10]='DEV',
	[11]="OWNER",
}

local app_id = "998373153950670999"

function updateRPC()
   local name = getElementData(localPlayer, "accName")
   local playedTime = getElementData(localPlayer, "Játékidő")
   setDiscordRichPresenceDetails(name.." | lvl "..getElementData(localPlayer, "level"))
   setDiscordRichPresenceState(roles[getElementData(localPlayer, "admin_level")].." | "..playedTime)
   --setDiscordRichPresencePartySize(#getElementsByType("player"), 8)
end

function ConnectRPC()
   setDiscordApplicationID(app_id)
   if isDiscordRichPresenceConnected() then
      local name = getElementData(localPlayer, "accName")
      local playedTime = getElementData(localPlayer, "Játékidő")
      outputConsole("RPC: Discord RPC is now connected")
      setDiscordRichPresenceAsset("freev", "MTA:SA")
      setDiscordRichPresenceDetails(name.." | lvl "..getElementData(localPlayer, "level"))
      setDiscordRichPresenceState(roles[getElementData(localPlayer, "admin_level")].." | "..playedTime)
      --setDiscordRichPresencePartySize(#getElementsByType("player"), 8)
      setTimer(updateRPC, 120000, 0)
   else
      outputConsole("RPC: Discord RPC failed to connect")
   end
end
addEventHandler("onClientResourceStart", resourceRoot, ConnectRPC)

--// Now, we reset the rpc details so the status will not be bugged
addEventHandler("onClientResourceStop", resourceRoot, function()
    resetDiscordRichPresenceData()
end)