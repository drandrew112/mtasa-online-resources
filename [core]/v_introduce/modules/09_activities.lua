-- Chapter 9: jobs (the game modes: races, deathmatches), Arena War, time trials, world attractions.
Intro.module {
    id = "activities", order = 90, version = 1, xp = 250,
    title = "Jobs & activities",
    requires = { "v_jobmanager" },
    scenes = {
        { type = "world", duration = 9,
          camera = { from = { 1000, -1890, 30, 1033, -1847, 14 }, to = { 1070, -1895, 28, 1033, -1847, 14 } },
          point = { 1032.81, -1847.36, 12.51 }, label = "Job: LS Beach Motorcycling", blip = 9,
          text = "Jobs are game modes: races and deathmatches played in lobbies. Step into the marker of a job "
              .. "to start one, or accept an invite from another player on your phone." },
        { type = "world", requires = { "v_arenawar" }, duration = 8,
          camera = { from = { 2680, -1900, 40, 2727, -1854, 9 }, to = { 2775, -1905, 38, 2727, -1854, 9 } },
          point = { 2727.30, -1854.27, 8.58 }, radius = 6, label = "Arena War", blip = 53,
          text = "Arena War: vehicle battles in the stadium." },
        { type = "camera", duration = 8,
          camera = { from = { 300, -1950, 50, 390, -2028, 20 }, to = { 470, -1960, 45, 390, -2028, 20 } },
          text = "Not everything is about money: take a ride on the pier, the cable car up Mount Chiliad, "
              .. "or jump with a parachute from somewhere high." },
        { type = "card", requires = { "v_timetrial" },
          title = "Time Trials",
          text = "Time Trials are routes against the clock. They never stay in one place: every now and then "
              .. "the Time Trial moves somewhere else with a new route. Find its start marker on the map, "
              .. "drive the route and beat the best time." },
    },
}
