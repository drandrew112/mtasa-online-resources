if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Chapter 2: the HUD - minimap, money and level.
Intro.module {
    id = "hud", order = 20, version = 1, xp = 200,
    essential = true,
    title = L.msg("v_introduce.02_hud.your_hud"),
    requires = { "v_radar" },
    scenes = {
        { type = "highlight", target = "minimap",
          title = L.msg("v_introduce.02_hud.minimap_gps"),
          text = L.msg("v_introduce.02_hud.minimap_shows_where_you_are_and") },
        { type = "task", requires = { "ui_core" },
          title = L.msg("v_introduce.02_hud.money_and_level"),
          text = L.msg("v_introduce.02_hud.your_cash_your_bank_balance_and"),
          tasks = {
              { text = L.msg("v_introduce.02_hud.press_to_show_them"), check = { key = "y" } },
          } },
        { type = "card",
          title = L.msg("v_introduce.02_hud.level_and_xp"),
          text = L.msg("v_introduce.02_hud.you_earn_xp_with_jobs_races") },
    },
}
