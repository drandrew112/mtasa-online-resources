if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Chapter 14: weapons (wp_manager / wp_selector). A practice pistol (a temporary wp_manager
-- loadout, never saved) and a target; the pistol is taken back when the chapter ends.
Intro.module {
    id = "weapons", order = 95, version = 1, xp = 200,
    title = L.msg("v_introduce.14_weapons.weapons"),
    requires = { "wp_manager", "wp_selector" },
    scenes = {
        { type = "card",
          title = L.msg("v_introduce.14_weapons.your_weapons"),
          text = L.msg("v_introduce.14_weapons.weapons_work_differently_here_hold_to") },
        { type = "task", weapon = true, camera = "player",
          title = L.msg("v_introduce.14_weapons.target_practice"),
          text = L.msg("v_introduce.14_weapons.here_is_a_practice_pistol_and"),
          tasks = {
              { text = L.msg("v_introduce.14_weapons.hold_and_choose_the_pistol"), check = { weapon = 22 } },
              { text = L.msg("v_introduce.14_weapons.hold_to_aim_and_press_to_hit"), check = { targetHit = true } },
          },
          note = L.msg("v_introduce.14_weapons.move_the_mouse_to_aim_at_the") },
    },
}
