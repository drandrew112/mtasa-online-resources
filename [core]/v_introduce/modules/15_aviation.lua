if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Chapter 15: air traffic control (the [aviation] suite), in a few seconds.
Intro.module {
    id = "aviation", order = 105, version = 1, xp = 100,
    title = L.msg("v_introduce.15_aviation.air_traffic"),
    requires = { "avi_core" },
    scenes = {
        { type = "world", duration = 9,
          camera = { from = { -2262, 128, 112, -2169, 247, 38 }, to = { -2246, 110, 122, -2169, 247, 38 } },
          point = { -2169.14, 247.03, 34.32 }, label = "SA Control", blip = 13,
          text = L.msg("v_introduce.15_aviation.the_skies_of_san_andreas_are_busy") },
        { type = "card",
          title = L.msg("v_introduce.15_aviation.air_traffic_control"),
          text = L.msg("v_introduce.15_aviation.go_on_duty_as_an_air_traffic") },
    },
}
