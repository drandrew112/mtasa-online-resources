-- Chapter 2: the HUD - minimap, money and level.
Intro.module {
    id = "hud", order = 20, version = 1, xp = 200,
    title = "Your HUD",
    requires = { "v_radar" },
    scenes = {
        { type = "highlight", target = "minimap",
          title = "Minimap & GPS",
          text = "The minimap shows where you are and what is around you. A purple route leads to your own "
              .. "waypoint, a yellow route to your current objective. The bars under it are your health and armor." },
        { type = "task", requires = { "ui_core" },
          title = "Money and level",
          text = "Your cash, your bank balance and your level are hidden most of the time to keep the screen clean.",
          tasks = {
              { text = "Press {key:hudinfo} to show them", check = { key = "y" } },
          } },
        { type = "card",
          title = "Level and XP",
          text = "You earn XP with jobs (races, deathmatches), work jobs and other activities - and with every "
              .. "chapter of this introduction. "
              .. "Your level shows other players how experienced you are.\n\n"
              .. "Short messages at the top of the screen tell you what just happened. Read them." },
    },
}
