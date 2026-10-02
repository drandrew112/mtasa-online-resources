-- Chapter 13: the end. Gives the XP top-up (INTRO.REWARD_TOTAL_XP), then the player is free.
Intro.module {
    id = "finish", order = 1000, version = 1, xp = 0,
    title = "Ready",
    final = true,
    scenes = {
        -- downtown skyscrapers, from low to high: the camera rises along the towers
        { type = "camera", duration = 10,
          camera = { from = { 1390, -1470, 40, 1545, -1260, 90 }, to = { 1700, -1480, 110, 1560, -1250, 130 } },
          bigTitle = { "You are ready", "Los Santos awaits" },
          text = "The city is yours. Go wherever you like and find your own way - have fun, "
              .. "and see you on the streets!" },
    },
}
