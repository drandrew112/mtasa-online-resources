if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Chapter 10: the medical system, hospitals, death.
Intro.module {
    id = "health", order = 100, version = 1, xp = 200,
    title = L.msg("v_introduce.10_health.health"),
    requires = { "medsys" },
    scenes = {
        { type = "card",
          title = L.msg("v_introduce.10_health.injuries"),
          text = L.msg("v_introduce.10_health.injuries_are_realistic_here_fall_crash") },
        { type = "world", requires = { "med_hospitals" }, duration = 9,
          camera = { from = { 1140, -1360, 35, 1180, -1308, 14 }, to = { 1225, -1360, 33, 1180, -1308, 14 } },
          point = { 1179.3, -1308.6, 13.0 }, radius = 4, label = L.msg("v_introduce.10_health.all_saints_general_hospital"), blip = 22,
          text = L.msg("v_introduce.10_health.paramedics_can_treat_you_on_spot") },
    },
}
