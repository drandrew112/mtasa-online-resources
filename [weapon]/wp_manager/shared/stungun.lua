-- Stun gun module (weapon 23, "Sokkoló / Stun gun"): the hit does no damage at all (cancelled on every
-- client), and a player / ped hit within RANGE lies on the ground for DURATION ms, unable to move.
-- Sold nowhere (wp_shop); work_police lends it on duty (duty_weapons).

WP.STUN = {
    WEAPON   = 23,
    RANGE    = 10,          -- units, shooter -> victim
    DURATION = 30000,       -- ms on the ground
    ANIM     = { "CRACK", "crckdeth2" },   -- lying, twitching (loop)
    REAPPLY_MS = 1000,      -- the victim's client checks that the animation still runs
    SHOT_GAP = 250,         -- ms between two accepted hits of one shooter
    TOLERANCE = 2,          -- extra units the server accepts (lag)
    -- controls the stunned player loses (the camera stays free)
    CONTROLS = { "forwards", "backwards", "left", "right", "jump", "sprint", "walk", "crouch", "fire",
                 "aim_weapon", "enter_exit", "enter_passenger", "action" },
    DATA = "wp.stunned",    -- element data (synced) while stunned: other resources may read it
    -- medsys states that already lie on the ground: no stun animation then
    DOWN_STATUS = { dazed = true, unconscious = true, clinical_death = true, dead = true },
    MEDIC_STATUS = "medic.status",
}
