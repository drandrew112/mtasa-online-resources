if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Chapter 4: the phone and its apps.
Intro.module {
    id = "phone", order = 40, version = 1, xp = 200,
    essential = true,
    title = L.msg("v_introduce.04_phone.phone"),
    requires = { "ui_phone" },
    scenes = {
        { type = "task", allow = { "phone" },
          title = L.msg("v_introduce.04_phone.your_phone"),
          text = L.msg("v_introduce.04_phone.your_phone_is_remote_control_of"),
          tasks = {
              { text = L.msg("v_introduce.04_phone.open_your_phone_with"), check = { data = "phoneOpen" } },
              { text = L.msg("v_introduce.04_phone.open_myveh_app_arrow_keys_then"), check = { phoneApp = "myveh" } },
          },
          note = L.msg("v_introduce.04_phone.backspace_goes_back_on_home_screen") },
        { type = "card",
          title = L.msg("v_introduce.04_phone.apps"),
          text = L.msg("v_introduce.04_phone.myveh_call_your_own_vehicles_to") },
    },
}
