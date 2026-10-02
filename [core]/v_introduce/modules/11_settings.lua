-- Chapter 11: the pause menu and the settings.
Intro.module {
    id = "settings", order = 110, version = 1, xp = 150,
    title = "Settings",
    requires = { "ui_pause" },
    scenes = {
        { type = "task", allow = { "pause" },
          title = "Pause menu",
          text = "The pause menu has the big map, the jobs (races, deathmatches) and the settings. Your settings - graphics, view "
              .. "distance and the rest - are saved to your account.",
          tasks = {
              { text = "Press {key:pause} to open the pause menu", check = { data = "paused" } },
          },
          note = "{key:pause} closes it again." },
    },
}
