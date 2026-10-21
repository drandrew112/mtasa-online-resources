if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Chapter 6: cash, bank, the in-game internet, store robberies.
Intro.module {
    id = "money", order = 60, version = 1, xp = 200,
    essential = true,
    title = L.msg("v_introduce.06_money.money"),
    requires = { "v_bank" },
    scenes = {
        { type = "card",
          title = L.msg("v_introduce.06_money.cash_and_bank"),
          text = L.msg("v_introduce.06_money.your_money_is_kept_in_two") },
        { type = "card", requires = { "ui_browser" },
          title = L.msg("v_introduce.06_money.internet"),
          text = L.msg("v_introduce.06_money.in_game_internet_has_websites_for") },
        { type = "world", requires = { "v_shop_robbery" }, duration = 8,
          camera = { from = { 2290, -1760, 30, 2320, -1718, 14 }, to = { 2355, -1755, 28, 2320, -1718, 14 } },
          point = { 2319.21, -1718.56, 13.55 }, label = "24/7 store", blip = 54,
          text = L.msg("v_introduce.06_money.stores_can_be_robbed_it_pays") },
    },
}
