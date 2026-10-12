if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Chapter 9: jobs (the game modes: races, deathmatches), Arena War, time trials, world attractions.
Intro.module {
    id = "activities", order = 90, version = 1, xp = 250,
    title = L.msg("v_introduce.09_activities.jobs_activities"),
    requires = { "v_jobmanager" },
    scenes = {
        { type = "world", duration = 9,
          camera = { from = { 1000, -1890, 30, 1033, -1847, 14 }, to = { 1070, -1895, 28, 1033, -1847, 14 } },
          point = { 1032.81, -1847.36, 12.51 }, label = L.msg("v_introduce.09_activities.job_ls_beach_motorcycling"), blip = 9,
          text = L.msg("v_introduce.09_activities.jobs_are_game_modes_races_and") },
        { type = "world", requires = { "v_arenawar" }, duration = 8,
          camera = { from = { 2680, -1900, 40, 2727, -1854, 9 }, to = { 2775, -1905, 38, 2727, -1854, 9 } },
          point = { 2727.30, -1854.27, 8.58 }, radius = 6, label = L.msg("v_introduce.09_activities.arena_war"), blip = 53,
          text = L.msg("v_introduce.09_activities.arena_war_vehicle_battles_in_stadium") },
        { type = "camera", duration = 8,
          camera = { from = { 300, -1950, 50, 390, -2028, 20 }, to = { 470, -1960, 45, 390, -2028, 20 } },
          text = L.msg("v_introduce.09_activities.not_everything_is_about_money_take") },
        { type = "card", requires = { "v_timetrial" },
          title = L.msg("v_introduce.09_activities.time_trials"),
          text = L.msg("v_introduce.09_activities.time_trials_are_routes_against_clock") },
    },
}
