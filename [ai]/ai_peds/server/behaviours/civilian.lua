-- Behaviour "civilian": does its task (sidewalk walker: wander). Shots, attacks and deaths nearby scare it; an
-- attacked civilian sometimes fights back with its fists.
--
-- args: task, taskOpts (replace the task), fightBack (chance, AIPEDS.CIVILIAN_FIGHT_BACK default)

Behaviours = Behaviours or {}

Behaviours.civilian = {
    enter = function(p, args)
        if args.fightBack then p.fightBack = args.fightBack end
        Tasks.run(p, args.task, args.taskOpts)
    end,

    update = function(p, now)
        Tasks.update(p, now)
    end,

    report = function(p, kind)
        if kind == "stuck" then Tasks.stuck(p) end
    end,

    -- kind: "shot" | "attacked" | "death" | "explosion"; src = element (shooter, attacker, killer) or nil
    threat = function(p, kind, src, x, y, z)
        if kind == "attacked" and src and Peds.alive(src) and math.random() < (p.fightBack or AIPEDS.CIVILIAN_FIGHT_BACK) then
            Groups.grudge(p, src)
            Peds.setBehaviour(p, "enemy", { target = src, calmTo = "civilian" })
            return
        end
        Peds.setBehaviour(p, "scared", { threat = src, x = x, y = y, z = z, calmTo = "civilian" })
    end,
}
