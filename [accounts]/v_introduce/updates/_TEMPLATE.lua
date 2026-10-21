-- TEMPLATE of an update module - this file is NOT loaded (it is not in meta.xml).
--
-- An update module shows players who already finished the introduction what is new on the
-- server. New players never get it: they learn the feature from the main line (put the
-- important things there too), and finishing the main line marks every current update as seen.
--
-- To add one:
--   1. Copy this file to updates/YYYY_MM_DD_<name>.lua and fill it in.
--   2. Add it to meta.xml in the "update modules" block (server script).
--   3. Restart v_introduce. Players who finished the introduction get it on their next login,
--      players online right now 3 s after the restart. Test it: /intro start <player> <id>
--
-- id       unique, keep the date in it: "update_2026_10_15_garages"
-- order    the date as a number (20261015): several pending updates run oldest first
-- version  raise it only to show the same update again to everybody who saw it
-- expires  optional "YYYY-MM-DD": from that day on nobody gets it (a player coming back after
--          months does not have to sit through old news)
-- xp       optional reward (default 0); it does not count into the main-line XP top-up
-- requires the resources of the new feature: while one is not running, the update is left out
-- scenes   the same scene types as the main line (client/scenes.lua, client/rules.lua)

Intro.module {
    id = "update_2026_10_15_example", order = 20261015, version = 1,
    update = true,
    expires = "2027-01-15",
    xp = 0,
    title = "Example feature",
    requires = { "v_example" },
    scenes = {
        { type = "camera", duration = 8,
          camera = { from = { 1100, -1600, 160, 1550, -1300, 80 }, to = { 1850, -1600, 150, 1550, -1250, 70 } },
          bigTitle = { "New on the server", "Example feature" },
          text = "One or two sentences: what is new and why it is worth trying." },
        { type = "world", duration = 8,
          camera = { from = { 1140, -1380, 40, 1183, -1325, 14 }, to = { 1230, -1385, 38, 1183, -1325, 14 } },
          point = { 1182.8, -1330.8, 12.6 }, label = "Where to find it", blip = 22,
          text = "Where it is and how to start it." },
        { type = "card",
          title = "How it works",
          text = "The short version of the rules of the new feature. Keys: {key:phone}, {key:interaction}." },
    },
}
