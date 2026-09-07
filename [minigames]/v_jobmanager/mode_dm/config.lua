-- Self-contained temporary DM arena. Replace this configuration when a custom map is ready.
registerJob({
    id = "ls_airport_dm", name = "Los Santos Airport Deathmatch", type = JOB_TYPE_DM,
    minPlayers = 2, maxPlayers = 8, marker = {1941.3, -1778.4, 13.39},
    image = "assets/jobs/ls_airport_dm.jpg",
    description = "Last player standing wins. Fight it out across the Los Santos airport apron with deagles and full armour.",
    weapon = 24, ammo = 120, armour = 100,
    spawns = {
        {1955.3,-1776.0,13.39,90}, {1938.3,-1758.0,13.39,180}, {1917.0,-1774.0,13.39,270}, {1940.0,-1800.0,13.39,0},
        {1973.0,-1786.0,13.39,90}, {1925.0,-1811.0,13.39,0}, {1904.0,-1793.0,13.39,270}, {1961.0,-1743.0,13.39,180},
    },
})
