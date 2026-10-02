-- Chapter 5: the interaction menu (M) and the 3D menus (X).
Intro.module {
    id = "interaction", order = 50, version = 1, xp = 200,
    title = "Interaction",
    requires = { "ui_inac" },
    scenes = {
        { type = "task", allow = { "interaction" },
          title = "Interaction menu",
          text = "The interaction menu holds what you can do right now: things about you, your vehicle and "
              .. "your surroundings.",
          tasks = {
              { text = "Press {key:interaction} to open the menu", check = { data = "interactionMenuOpen" } },
          },
          note = "Arrow keys move, ENTER selects, BACKSPACE goes back. {key:interaction} closes the menu." },
        { type = "card", requires = { "ui_interactobject" },
          title = "Menus in the world",
          text = "Some objects, vehicles and people have a menu of their own. When you look at one, a small "
              .. "prompt appears: press {key:interact3d} to open it and pick an option with the number keys 1-9." },
    },
}
