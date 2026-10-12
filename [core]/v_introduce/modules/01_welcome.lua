if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Chapter 1: what this server is. Camera rides over Los Santos.
Intro.module {
    id = "welcome", order = 10, version = 1, xp = 150,
    title = L.msg("v_introduce.01_welcome.welcome"),
    scenes = {
        { type = "camera", duration = 10,
          camera = { from = { 1100, -1600, 160, 1550, -1300, 80 }, to = { 1850, -1600, 150, 1550, -1250, 70 } },
          bigTitle = { L.msg("v_introduce.01_welcome.welcome_to"), "FreeV" },
          text = L.msg("v_introduce.01_welcome.los_santos_runs_on_its_own") },
        { type = "camera", duration = 9,
          camera = { from = { 250, -1850, 45, 380, -2040, 15 }, to = { 520, -1880, 40, 390, -2030, 15 } },
          text = L.msg("v_introduce.01_welcome.this_is_not_gta_online_jobs") },
        { type = "camera", duration = 9,
          camera = { from = { 1500, -2550, 70, 1700, -2300, 15 }, to = { 1950, -2550, 60, 1700, -2300, 15 } },
          text = L.msg("v_introduce.01_welcome.read_texts_do_small_tasks_and") },
    },
}
