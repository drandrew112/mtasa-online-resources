-- Chapter 8: work jobs (work_core) with EMS as the example. "Jobs" alone are the game modes
-- (races, deathmatches), see 09_activities.lua.
Intro.module {
    id = "work", order = 80, version = 1, xp = 200,
    title = "Work jobs",
    requires = { "work_core" },
    scenes = {
        { type = "card",
          title = "Work jobs",
          text = "Work jobs pay and give you a role on the server. Go to a workplace, step into its marker and "
              .. "press {key:work} to go on duty: you get the uniform and can take a work vehicle. "
              .. "You can have one work job at a time." },
        { type = "world", requires = { "work_ems" }, duration = 9,
          camera = { from = { 1140, -1380, 40, 1183, -1325, 14 }, to = { 1230, -1385, 38, 1183, -1325, 14 } },
          point = { 1182.82, -1330.80, 12.58 }, label = "EMS - All Saints", blip = 22,
          text = "Paramedics answer emergency calls, treat patients and take them to hospital. The first time "
              .. "you go on duty as EMS, a separate tutorial teaches you the work." },
    },
}
