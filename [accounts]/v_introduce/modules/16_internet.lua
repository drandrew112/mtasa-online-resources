if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Chapter 16: the in-game internet (ui_browser) and the server's own web pages (web_manager).
local scenes = {
    { type = "card",
      title = L.msg("v_introduce.16_internet.the_in_game_internet"),
      text = L.msg("v_introduce.16_internet.the_browser_app_of_your_phone_opens") },
    { type = "task", allow = { "phone", "browser" },
      title = L.msg("v_introduce.16_internet.try_the_browser"),
      text = L.msg("v_introduce.16_internet.open_your_phone_and_start_the_browser"),
      tasks = {
          { text = L.msg("v_introduce.16_internet.open_the_browser_app_on_your_phone"), check = { data = "browserOpen" } },
      },
      note = L.msg("v_introduce.16_internet.right_click_goes_back_close_the_browser") },
    { type = "card", requires = { "avi_web" },
      title = "San Andreas Control",
      text = L.msg("v_introduce.16_internet.the_site_of_the_air_traffic") },
    { type = "card", requires = { "bt_web" },
      title = "Blood Transport",
      text = L.msg("v_introduce.16_internet.the_blood_transport_site_blood_transport_eu") },
}

-- only with a configured address (INTRO.WEB_URL)
if INTRO.WEB_URL ~= "" then
    scenes[#scenes + 1] = { type = "card",
      title = L.msg("v_introduce.16_internet.on_the_web"),
      text = L.msg("v_introduce.16_internet.many_services_also_have_a_normal") }
end

Intro.module {
    id = "internet", order = 65, version = 1, xp = 200,
    title = L.msg("v_introduce.16_internet.internet"),
    requires = { "ui_browser" },
    scenes = scenes,
}
