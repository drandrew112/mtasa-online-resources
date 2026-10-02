-- Chapter 12: the rules (rules.txt). Raising INTRO.RULES_VERSION shows this chapter to everybody
-- again on their next login.
Intro.module {
    id = "rules", order = 120, version = INTRO.RULES_VERSION, xp = 200,
    title = "Rules",
    rules = true,
    scenes = {
        { type = "card",
          title = "Fair play",
          text = "One more thing before you start: the rules. They keep the server fun for everyone. "
              .. "If someone breaks them, type /report and an admin will look at it." },
        { type = "accept", title = "Server rules" },
    },
}
