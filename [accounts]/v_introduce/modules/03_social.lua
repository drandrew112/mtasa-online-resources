if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Chapter 3: chat and the social panel.
Intro.module {
    id = "social", order = 30, version = 1, xp = 150,
    title = L.msg("v_introduce.03_social.talk_friends"),
    requires = { "v_chat" },
    scenes = {
        { type = "task", allow = { "chat" },
          title = L.msg("v_introduce.03_social.chat"),
          text = L.msg("v_introduce.03_social.chat_is_how_you_talk_to"),
          tasks = {
              { text = L.msg("v_introduce.03_social.press_to_open_chat"), check = { data = "showChatInput" } },
          },
          note = L.msg("v_introduce.03_social.enter_sends_your_message_with_empty") },
        { type = "task", allow = { "social" }, requires = { "v_socialpanel" },
          title = L.msg("v_introduce.03_social.social_panel"),
          text = L.msg("v_introduce.03_social.social_panel_holds_your_friends_player"),
          tasks = {
              { text = L.msg("v_introduce.03_social.press_or_num_7_to_open"), check = { data = "socialPanelOpen" } },
          },
          note = L.msg("v_introduce.03_social.esc_closes_it") },
    },
}
