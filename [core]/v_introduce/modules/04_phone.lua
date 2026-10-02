-- Chapter 4: the phone and its apps.
Intro.module {
    id = "phone", order = 40, version = 1, xp = 250,
    title = "Phone",
    requires = { "ui_phone" },
    scenes = {
        { type = "task", allow = { "phone" },
          title = "Your phone",
          text = "Your phone is the remote control of your life here: your vehicles, invites from other players, "
              .. "people who can help you and the in-game internet.",
          tasks = {
              { text = "Open your phone with {key:phone}", check = { data = "phoneOpen" } },
              { text = "Open the MyVeh app (arrow keys, then ENTER)", check = { phoneApp = "myveh" } },
          },
          note = "BACKSPACE goes back. On the home screen it closes the phone." },
        { type = "card",
          title = "The apps",
          text = "MyVeh - call your own vehicles to you.\n"
              .. "Invites - races, deathmatches and other activities other players invite you to.\n"
              .. "Contacts - call people of the city who help you: patch you up, get you into an "
              .. "activity, handle your vehicle insurance and more.\n"
              .. "Browser - the in-game internet: shops, vehicles, property and your bank.\n"
              .. "Settings - wallpaper and phone options." },
    },
}
