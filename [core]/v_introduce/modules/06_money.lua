-- Chapter 6: cash, bank, the in-game internet, store robberies.
Intro.module {
    id = "money", order = 60, version = 1, xp = 200,
    title = "Money",
    requires = { "v_bank" },
    scenes = {
        { type = "card",
          title = "Cash and bank",
          text = "Your money is kept in two places. Cash is what you carry: you pay with it in shops, and it is "
              .. "at risk. The bank keeps the rest safe. Keep only what you need as cash." },
        { type = "card", requires = { "ui_browser" },
          title = "The internet",
          text = "The in-game internet has websites for shopping, vehicles, property and your bank account. "
              .. "Open it with the Browser app on your phone, or type /browser." },
        { type = "world", requires = { "v_shop_robbery" }, duration = 8,
          camera = { from = { 2290, -1760, 30, 2320, -1718, 14 }, to = { 2355, -1755, 28, 2320, -1718, 14 } },
          point = { 2319.21, -1718.56, 13.55 }, label = "24/7 store", blip = 54,
          text = "Stores can be robbed. It pays well, but it is a crime, the shopkeeper fights back "
              .. "and other players may come after you." },
    },
}
