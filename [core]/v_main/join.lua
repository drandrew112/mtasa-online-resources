
local WELCOME_COLOR = "#4DA6FF" -- Világoskék
local STATUS_COLOR  = "#A0E7E5" -- Lágy türkiz
local DEFAULT_COLOR = "#FFFFFF" -- Fehér

addEventHandler("onPlayerJoin", root,
    function()
        local player = source
        local serverName = getServerInstanceName()

        local message = table.concat({
            "Welcome to FreeV!",
            "You are on " .. WELCOME_COLOR .. serverName .. DEFAULT_COLOR .. "!",
            STATUS_COLOR .. "Loading... Please wait!" .. DEFAULT_COLOR
        }, "\n")

        outputChatBox(
            message,
            player,
            255, 255, 255,
            true
        )
    end
)
