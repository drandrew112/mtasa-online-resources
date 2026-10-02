-- Chapter 3: chat and the social panel.
Intro.module {
    id = "social", order = 30, version = 1, xp = 200,
    title = "Talk & friends",
    requires = { "v_chat" },
    scenes = {
        { type = "task", allow = { "chat" },
          title = "Chat",
          text = "The chat is how you talk to everyone on the server. Be friendly - new players are welcome "
              .. "to ask questions.",
          tasks = {
              { text = "Press {key:chat} to open the chat", check = { data = "showChatInput" } },
          },
          note = "ENTER sends your message. With an empty line it just closes the chat." },
        { type = "task", allow = { "social" }, requires = { "v_socialpanel" },
          title = "Social panel",
          text = "The social panel holds your friends, player profiles, crews and private messages. "
              .. "A crew is a group of players with its own tag.",
          tasks = {
              { text = "Press {key:social} (or NUM 7) to open the social panel", check = { data = "socialPanelOpen" } },
          },
          note = "ESC closes it." },
    },
}
