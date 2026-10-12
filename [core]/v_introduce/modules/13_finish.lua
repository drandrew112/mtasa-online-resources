if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Chapter 13: the end. Gives the XP top-up (INTRO.REWARD_TOTAL_XP), then the player is free.
Intro.module {
    id = "finish", order = 1000, version = 1, xp = 0,
    title = L.msg("v_introduce.13_finish.ready"),
    final = true,
    scenes = {
        -- downtown skyscrapers, from low to high: the camera rises along the towers
        { type = "camera", duration = 10,
          camera = { from = { 1390, -1470, 40, 1545, -1260, 90 }, to = { 1700, -1480, 110, 1560, -1250, 130 } },
          bigTitle = { L.msg("v_introduce.13_finish.you_are_ready"), L.msg("v_introduce.13_finish.los_santos_awaits") },
          text = L.msg("v_introduce.13_finish.city_is_yours_go_wherever_you") },
    },
}
