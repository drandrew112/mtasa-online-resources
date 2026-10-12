if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Chapter 8: work jobs (work_core) with EMS as the example. "Jobs" alone are the game modes
-- (races, deathmatches), see 09_activities.lua.
Intro.module {
    id = "work", order = 80, version = 1, xp = 200,
    title = L.msg("v_introduce.08_work.work_jobs"),
    requires = { "work_core" },
    scenes = {
        { type = "card",
          title = L.msg("v_introduce.08_work.work_jobs"),
          text = L.msg("v_introduce.08_work.work_jobs_pay_and_give_you") },
        { type = "world", requires = { "work_ems" }, duration = 9,
          camera = { from = { 1140, -1380, 40, 1183, -1325, 14 }, to = { 1230, -1385, 38, 1183, -1325, 14 } },
          point = { 1182.82, -1330.80, 12.58 }, label = L.msg("v_introduce.08_work.ems_all_saints"), blip = 22,
          text = L.msg("v_introduce.08_work.paramedics_answer_emergency_calls_treat_patients") },
    },
}
