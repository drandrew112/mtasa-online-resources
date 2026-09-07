
lobby_menus = {
    {
        name = "MAIN",
        back = 0,
        btns = {
            {
                text="Players",
                desc = "Check players",
                options = false,
                value = false,
                set_menu = 3,
                action = false,
                hostOnly = false,
            },
            {
                text="Game settings",
                desc = "Settings for this game",
                options = false,
                value = false,
                set_menu = 2,
                action = false,
                hostOnly = true,
            },
            {
                text="Start",
                desc = "Start the game",
                options = false,
                value = false,
                set_menu = false,
                action = function() triggerServerEvent("startJob", localPlayer, lobby_id) end,
                hostOnly = true, -- Only the host can start
                bg = tocolor(0,70,120, 255),
            },
        },
    },
    {
        name = "GAME SETTINGS",
        back = 1,
        btns = {
            {
                text="Nothing here",
                desc = "",
                options = false,
                value = false,
                set_menu = false,
                action = false,
                hostOnly = false,
            },
        },
    },
    {
        name = "PLAYERS",
        back = 1,
        btns = {
            {
                text="Nothing here",
                desc = "",
                options = false,
                value = false,
                set_menu = false,
                action = false,
                hostOnly = false,
            },
        },
    },
}

