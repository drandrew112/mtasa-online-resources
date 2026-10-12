if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Chapter 11: the pause menu and the settings.
Intro.module {
    id = "settings", order = 110, version = 1, xp = 150,
    title = L.msg("v_introduce.11_settings.settings"),
    requires = { "ui_pause" },
    scenes = {
        { type = "task", allow = { "pause" },
          title = L.msg("v_introduce.11_settings.pause_menu"),
          text = L.msg("v_introduce.11_settings.pause_menu_has_big_map_jobs"),
          tasks = {
              { text = L.msg("v_introduce.11_settings.press_to_open_pause_menu"), check = { data = "paused" } },
          },
          note = L.msg("v_introduce.11_settings.closes_it_again") },
    },
}
