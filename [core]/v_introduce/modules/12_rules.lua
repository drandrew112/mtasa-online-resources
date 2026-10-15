if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Chapter 12: the rules (rules.txt). Raising INTRO.RULES_VERSION shows this chapter to everybody
-- again on their next login.
Intro.module {
    id = "rules", order = 120, version = INTRO.RULES_VERSION, xp = 200,
    skippable = false, essential = true,
    title = L.msg("v_introduce.12_rules.rules"),
    rules = true,
    scenes = {
        { type = "card",
          title = L.msg("v_introduce.12_rules.fair_play"),
          text = L.msg("v_introduce.12_rules.one_more_thing_before_you_start") },
        { type = "accept", title = L.msg("v_introduce.rules.server_rules") },
    },
}
