-- Chapter 10: the medical system, hospitals, death.
Intro.module {
    id = "health", order = 100, version = 1, xp = 200,
    title = "Health",
    requires = { "medsys" },
    scenes = {
        { type = "card",
          title = "Injuries",
          text = "Injuries are realistic here. A fall, a crash or a bullet can cause bleeding, broken bones or "
              .. "unconsciousness, and they do not heal by themselves. A blurred, pale screen and a loud "
              .. "heartbeat mean you are hurt." },
        { type = "world", requires = { "med_hospitals" }, duration = 9,
          camera = { from = { 1140, -1360, 35, 1180, -1308, 14 }, to = { 1225, -1360, 33, 1180, -1308, 14 } },
          point = { 1179.3, -1308.6, 13.0 }, radius = 4, label = "All Saints General Hospital", blip = 22,
          text = "Paramedics can treat you on the spot and take you to a hospital. If your heart stops and "
              .. "nobody saves you, you die and respawn." },
    },
}
