if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Chapter 8: work jobs (work_core). The player only learns that they exist: every work job has
-- its own tutorial the first time they go on duty. "Jobs" alone are the game modes
-- (races, deathmatches), see 09_activities.lua.
Intro.module {
    id = "work", order = 80, version = 2, xp = 150,
    title = L.msg("v_introduce.08_work.work_jobs"),
    requires = { "work_core" },
    scenes = {
        { type = "card",
          title = L.msg("v_introduce.08_work.work_jobs"),
          text = L.msg("v_introduce.08_work.work_jobs_pay_and_give_you") },
        { type = "world", requires = { "work_ems" }, duration = 8,
          camera = { from = { 1140, -1380, 40, 1183, -1325, 14 }, to = { 1230, -1385, 38, 1183, -1325, 14 } },
          point = { 1182.82, -1330.80, 12.58 }, label = L.msg("v_introduce.08_work.ems_all_saints"), blip = 22,
          text = L.msg("v_introduce.08_work.paramedics_answer_emergency_calls_treat_patients") },
        { type = "world", requires = { "work_bloodtransport" }, duration = 8,
          camera = { from = { 896, -1466, 28, 926.0, -1436.0, 12.0 }, to = { 956, -1466, 26, 926.0, -1436.0, 12.0 } },
          point = { 926.17, -1435.77, 12.33 }, radius = 4, label = L.msg("v_introduce.08_work.blood_transport"),
          text = L.msg("v_introduce.08_work.blood_transporters_carry_blood_products_and_lab") },
        { type = "world", requires = { "work_atc" }, duration = 8,
          camera = { from = { -2207, 209, 56, -2169.0, 247.0, 34.0 }, to = { -2131, 209, 54, -2169.0, 247.0, 34.0 } },
          point = { -2169.14, 247.03, 34.32 }, label = "SA Control", blip = 13,
          text = L.msg("v_introduce.08_work.air_traffic_controllers_run_the_flights_of") },
        { type = "world", requires = { "work_traindriver" }, duration = 8,
          camera = { from = { 1730, -1973, 31, 1764.0, -1939.0, 13.0 }, to = { 1798, -1973, 29, 1764.0, -1939.0, 13.0 } },
          point = { 1764.42, -1938.68, 12.58 }, radius = 4, label = "Unity Station",
          text = L.msg("v_introduce.08_work.train_drivers_run_the_railways_of_san") },
    },
}
