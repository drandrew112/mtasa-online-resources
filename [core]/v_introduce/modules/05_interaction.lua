if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Chapter 5: the interaction menu (M) and the 3D menus (X).
Intro.module {
    id = "interaction", order = 50, version = 1, xp = 200,
    title = L.msg("v_introduce.05_interaction.interaction"),
    requires = { "ui_inac" },
    scenes = {
        { type = "task", allow = { "interaction" },
          title = L.msg("v_introduce.05_interaction.interaction_menu"),
          text = L.msg("v_introduce.05_interaction.interaction_menu_holds_what_you_can"),
          tasks = {
              { text = L.msg("v_introduce.05_interaction.press_to_open_menu"), check = { data = "interactionMenuOpen" } },
          },
          note = L.msg("v_introduce.05_interaction.arrow_keys_move_enter_selects_backspace") },
        { type = "card", requires = { "ui_interactobject" },
          title = L.msg("v_introduce.05_interaction.menus_in_world"),
          text = L.msg("v_introduce.05_interaction.some_objects_vehicles_and_people_have") },
    },
}
