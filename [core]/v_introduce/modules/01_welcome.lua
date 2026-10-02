-- Chapter 1: what this server is. Camera rides over Los Santos.
Intro.module {
    id = "welcome", order = 10, version = 1, xp = 150,
    title = "Welcome",
    scenes = {
        { type = "camera", duration = 10,
          camera = { from = { 1100, -1600, 160, 1550, -1300, 80 }, to = { 1850, -1600, 150, 1550, -1250, 70 } },
          bigTitle = { "Welcome to", "FreeV" },
          text = "Los Santos runs on its own rules here. In the next few minutes you will see what you can do, "
              .. "where to find it and how to get started." },
        { type = "camera", duration = 9,
          camera = { from = { 250, -1850, 45, 380, -2040, 15 }, to = { 520, -1880, 40, 390, -2030, 15 } },
          text = "This is not GTA Online. The jobs, the economy and the activities are our own, built for this "
              .. "server - and the other players live here with you." },
        { type = "camera", duration = 9,
          camera = { from = { 1500, -2550, 70, 1700, -2300, 15 }, to = { 1950, -2550, 60, 1700, -2300, 15 } },
          text = "Read the texts, do the small tasks and press {key:continue} when the button lights up. "
              .. "Every chapter you finish gives you XP." },
    },
}
