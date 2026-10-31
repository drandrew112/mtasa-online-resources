if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
L.config(function()  -- texts are refreshed once the player is loaded (v_locals L.config)
-- Configuration of the medsys events module: which in-game events hurt a player and how.
--
-- Every rule is a list of tiers. The highest tier whose `min` is at or below the measured value
-- (health loss, crash speed, accumulated damage ...) is used. A tier can contain:
--   injuries = { { type, part, chance, severity = { min, max } }, ... }  -- each one rolled separately
--       type: a medsys injury type ("gunshot" | "fracture" | "burn" | "suffocation")
--       part: "hit" (the body part that was hit), "leg" / "arm" (a random side that was not used
--             yet in this event), or an exact part ("head", "torso", "pelvis", "left_arm", ...)
--   bleeding = 1-3          -- bleeding that is not tied to an injury (cuts, abrasions)
--   pain     = 0-100        -- pain spike, fades on its own
--   spo2     = 0-100        -- SpO2 drops to at most this value (recovers on its own)
--   knockout = { unconscious = chance, dazed = chance }  -- the worse one is rolled first
--   health   = hp           -- extra health loss (only where GTA itself does not hurt, e.g. crashes)

MEDEV = {
    APPLY_TO_PLAYERS = false,   -- false: players get no injuries / medical state at all
    APPLY_TO_PEDS = true,       -- true: peds get injured the same way
    DEFER = 50,                 -- ms after the damage event before the rules run (the death check)

    -- Peds with a medical status (every ai_peds ped) do not die from GTA damage: a hit that would kill is
    -- cancelled on the clients, the ped keeps PED_DOWN_HEALTH and goes down in medsys instead (unconscious,
    -- or cardiac arrest by PED_LETHAL_ARREST), so an arriving medic has a patient to treat. medsys decides
    -- about the death from then on (biological death kills the ped).
    PED_SAVE_LETHAL = true,
    PED_DOWN_HEALTH = 10,       -- health a downed ped is kept at (police "injured" check: below 60)
    PED_LETHAL_ARREST = { gun_head = 0.6, gun = 0.25, explosion = 0.4, default = 0.1 }, -- chance of clinical death
    PED_LETHAL_REPORT_GAP = 200, -- ms, one client report per ped

    -- Players have no clinical death: their death is final, so there is nothing to resuscitate.
    -- A player whose heart stops in medsys dies after this many ms.
    PLAYER_DEATH_IS_FINAL = true,
    PLAYER_ARREST_DEATH_DELAY = 0,

    MAX_INJURIES = 12,          -- no new injury beyond this many on one element

    -- Bare-fisted punch into a vehicle (client detects it, server validates)
    PUNCH_REACH = 1.1,          -- metres in front of the chest
    PUNCH_HIT_DELAY = 220,      -- ms after the fire key, when the fist lands
    PUNCH_COOLDOWN = 450,       -- ms between two counted punches
    PUNCH_MAX_DISTANCE = 7.0,   -- server: max distance from the vehicle centre (long vehicles too)
    PUNCH_WORLD = false,        -- true: punching walls / objects counts too (with WORLD_FACTOR)

    -- Vehicle crashes: the client measures the speed change of its vehicle
    CRASH_MIN_SPEED = 25,       -- km/h speed change, below this nothing is reported
    CRASH_MEASURE_DELAY = 120,  -- ms after the collision when the speed after the impact is read
    CRASH_COOLDOWN = 1500,      -- ms per vehicle
    CRASH_MAX_SPEED = 400,      -- server: reports above this are ignored
    CRASH_OPEN_FACTOR = 1.35,   -- bikes / BMX / quads: the rider is not protected
}

-- GTA body part ids (onPlayerDamage) -> body part names
MEDEV_BODYPARTS = { [3] = "torso", [4] = "pelvis", [5] = "left_arm", [6] = "right_arm",
    [7] = "left_leg", [8] = "right_leg", [9] = "head" }

MEDEV_BODYPART_LABELS = { head = L.text("medsys_events.config.head"), torso = L.text("medsys_events.config.torso"), pelvis = L.text("medsys_events.config.pelvis"), left_arm = L.text("medsys_events.config.left_arm"),
    right_arm = L.text("medsys_events.config.right_arm"), left_leg = L.text("medsys_events.config.left_leg"), right_leg = L.text("medsys_events.config.right_leg") }

-- Body part -> group used by the rules (head / torso / pelvis / arm / leg)
MEDEV_PART_GROUP = { head = "head", torso = "torso", pelvis = "pelvis", left_arm = "arm",
    right_arm = "arm", left_leg = "leg", right_leg = "leg" }

MEDEV_CAUSE_LABELS = { fall = L.text("medsys_events.config.fall"), gun = L.text("medsys_events.config.gunshot"), fist = L.text("medsys_events.config.punch"), blunt = L.text("medsys_events.config.blunt_trauma"),
    sharp = L.text("medsys_events.config.cut_stab_wound"), explosion = L.text("medsys_events.config.explosion"), fire = L.text("medsys_events.config.fire"), drown = L.text("medsys_events.config.drowning"),
    gas = L.text("medsys_events.config.tear_gas"), vehicle_hit = L.text("medsys_events.config.hit_by_vehicle"), crash = L.text("medsys_events.config.vehicle_crash"), punch = L.text("medsys_events.config.punched_hard_surface") }

-- Weapon id -> cause
MEDEV_WEAPONS = {
    [0] = "fist", [1] = "fist",
    [2] = "blunt", [3] = "blunt", [5] = "blunt", [6] = "blunt", [7] = "blunt",
    [10] = "blunt", [11] = "blunt", [12] = "blunt", [13] = "blunt", [14] = "blunt", [15] = "blunt",
    [4] = "sharp", [8] = "sharp", [9] = "sharp",
    [22] = "gun", [23] = "gun", [24] = "gun", [25] = "gun", [26] = "gun", [27] = "gun",
    [28] = "gun", [29] = "gun", [30] = "gun", [31] = "gun", [32] = "gun", [33] = "gun",
    [34] = "gun", [38] = "gun",
    [16] = "explosion", [19] = "explosion", [35] = "explosion", [36] = "explosion",
    [39] = "explosion", [51] = "explosion",
    [37] = "fire", [18] = "fire",
    [17] = "gas",
    [53] = "drown",
    [49] = "vehicle_hit", [50] = "vehicle_hit",
    [54] = "fall",
}

-- Minimum ms between two rule runs of the same cause on the same element (on the same body
-- part for gun / melee), so a minigun burst does not make 40 wounds
MEDEV_COOLDOWN = { fall = 800, gun = 300, fist = 600, blunt = 500, sharp = 500, explosion = 1000,
    vehicle_hit = 1000 }

-- Damage that comes in many small ticks is summed up into one episode, and the rule runs when
-- the damage stops for `gap` ms (the tiers are by the total health loss of the episode)
MEDEV_EPISODES = { fire = { gap = 3000 }, drown = { gap = 2500 }, gas = { gap = 4000 } }

MEDEV_RULES = {
    -- by health loss of the single fall
    fall = {
        { min = 6, pain = 25,
            injuries = { { type = "fracture", part = "leg", chance = 0.20, severity = { 1, 1 } } } },
        { min = 18, pain = 45, knockout = { dazed = 0.05 },
            injuries = { { type = "fracture", part = "leg", chance = 0.55, severity = { 1, 2 } },
                { type = "fracture", part = "arm", chance = 0.10, severity = { 1, 1 } } } },
        { min = 35, pain = 65, knockout = { dazed = 0.25 },
            injuries = { { type = "fracture", part = "leg", chance = 0.85, severity = { 2, 2 } },
                { type = "fracture", part = "leg", chance = 0.30, severity = { 1, 2 } },
                { type = "fracture", part = "arm", chance = 0.25, severity = { 1, 2 } } } },
        { min = 55, pain = 85, knockout = { unconscious = 0.35, dazed = 0.5 },
            injuries = { { type = "fracture", part = "leg", chance = 1.0, severity = { 2, 3 } },
                { type = "fracture", part = "leg", chance = 0.50, severity = { 2, 3 } },
                { type = "fracture", part = "arm", chance = 0.35, severity = { 1, 2 } },
                { type = "fracture", part = "pelvis", chance = 0.25, severity = { 2, 3 } } } },
    },

    -- per hit body part group, by health loss of the hit
    gun = {
        head = { { min = 0, pain = 80, knockout = { unconscious = 0.6 },
            injuries = { { type = "gunshot", part = "hit", chance = 1, severity = { 3, 3 } } } } },
        torso = {
            { min = 0, pain = 55, injuries = { { type = "gunshot", part = "hit", chance = 1, severity = { 2, 2 } },
                { type = "fracture", part = "hit", chance = 0.10, severity = { 1, 1 } } } },
            { min = 30, pain = 75, knockout = { dazed = 0.3 },
                injuries = { { type = "gunshot", part = "hit", chance = 1, severity = { 3, 3 } },
                    { type = "fracture", part = "hit", chance = 0.20, severity = { 1, 2 } } } },
        },
        pelvis = { { min = 0, pain = 60, injuries = { { type = "gunshot", part = "hit", chance = 1, severity = { 2, 2 } },
            { type = "fracture", part = "hit", chance = 0.15, severity = { 2, 2 } } } } },
        arm = {
            { min = 0, pain = 40, injuries = { { type = "gunshot", part = "hit", chance = 1, severity = { 1, 1 } },
                { type = "fracture", part = "hit", chance = 0.20, severity = { 2, 2 } } } },
            { min = 25, pain = 55, injuries = { { type = "gunshot", part = "hit", chance = 1, severity = { 2, 2 } },
                { type = "fracture", part = "hit", chance = 0.35, severity = { 2, 3 } } } },
        },
        leg = {
            { min = 0, pain = 45, injuries = { { type = "gunshot", part = "hit", chance = 1, severity = { 1, 1 } },
                { type = "fracture", part = "hit", chance = 0.20, severity = { 2, 2 } } } },
            { min = 25, pain = 60, injuries = { { type = "gunshot", part = "hit", chance = 1, severity = { 2, 2 } },
                { type = "fracture", part = "hit", chance = 0.35, severity = { 2, 3 } } } },
        },
    },
    -- torso hit while the player wears armor: the vest stops the bullet, blunt trauma only
    gunArmored = { { min = 0, pain = 35,
        injuries = { { type = "fracture", part = "torso", chance = 0.08, severity = { 1, 1 } } } } },

    fist = {
        head = { { min = 0, pain = 15, knockout = { dazed = 0.04 } } },
    },
    blunt = {
        head = { { min = 0, pain = 45, knockout = { unconscious = 0.08, dazed = 0.30 }, bleeding = 1 } },
        torso = { { min = 0, pain = 35, injuries = { { type = "fracture", part = "hit", chance = 0.06, severity = { 1, 1 } } } } },
        pelvis = { { min = 0, pain = 30 } },
        arm = { { min = 0, pain = 40, injuries = { { type = "fracture", part = "hit", chance = 0.12, severity = { 1, 2 } } } } },
        leg = { { min = 0, pain = 40, injuries = { { type = "fracture", part = "hit", chance = 0.10, severity = { 1, 2 } } } } },
    },
    -- cuts bleed (bandage stops them), tiers by health loss of the hit
    sharp = {
        head = { { min = 0, pain = 50, bleeding = 2, knockout = { dazed = 0.15 } } },
        torso = { { min = 0, pain = 50, bleeding = 2 }, { min = 30, pain = 70, bleeding = 3 } },
        pelvis = { { min = 0, pain = 45, bleeding = 2 } },
        arm = { { min = 0, pain = 40, bleeding = 1 }, { min = 25, pain = 55, bleeding = 2 } },
        leg = { { min = 0, pain = 40, bleeding = 1 }, { min = 25, pain = 55, bleeding = 2 } },
    },

    explosion = {
        { min = 5, pain = 40, knockout = { dazed = 0.4 },
            injuries = { { type = "burn", part = "torso", chance = 0.6, severity = { 1, 1 } } } },
        { min = 20, pain = 65, knockout = { unconscious = 0.15, dazed = 0.6 },
            injuries = { { type = "burn", part = "torso", chance = 1, severity = { 1, 2 } },
                { type = "fracture", part = "leg", chance = 0.25, severity = { 1, 2 } },
                { type = "fracture", part = "arm", chance = 0.20, severity = { 1, 2 } } } },
        { min = 45, pain = 85, knockout = { unconscious = 0.5, dazed = 1 },
            injuries = { { type = "burn", part = "torso", chance = 1, severity = { 2, 3 } },
                { type = "fracture", part = "leg", chance = 0.50, severity = { 2, 3 } },
                { type = "fracture", part = "arm", chance = 0.35, severity = { 1, 2 } },
                { type = "gunshot", part = "torso", chance = 0.30, severity = { 1, 2 } } } }, -- shrapnel
    },

    -- episodes: tiers by the total health loss of the whole episode
    fire = {
        { min = 8, pain = 35, injuries = { { type = "burn", part = "torso", chance = 1, severity = { 1, 1 } } } },
        { min = 30, pain = 65, injuries = { { type = "burn", part = "torso", chance = 1, severity = { 2, 2 } } } },
        { min = 60, pain = 90, knockout = { dazed = 0.5 },
            injuries = { { type = "burn", part = "torso", chance = 1, severity = { 3, 3 } } } },
    },
    drown = {
        { min = 5, spo2 = 90 },
        { min = 20, spo2 = 80, knockout = { dazed = 0.5 },
            injuries = { { type = "suffocation", part = "torso", chance = 1, severity = { 1, 1 } } } },
        { min = 45, spo2 = 68, knockout = { unconscious = 0.6, dazed = 1 },
            injuries = { { type = "suffocation", part = "torso", chance = 1, severity = { 2, 2 } } } },
    },
    gas = {
        { min = 3, spo2 = 92, pain = 20 },
        { min = 15, spo2 = 86, pain = 30, knockout = { dazed = 0.4 } },
    },

    vehicle_hit = {
        { min = 5, pain = 35, injuries = { { type = "fracture", part = "leg", chance = 0.25, severity = { 1, 1 } } } },
        { min = 20, pain = 60, knockout = { unconscious = 0.1, dazed = 0.35 }, bleeding = 1,
            injuries = { { type = "fracture", part = "leg", chance = 0.6, severity = { 1, 2 } },
                { type = "fracture", part = "arm", chance = 0.2, severity = { 1, 1 } },
                { type = "fracture", part = "torso", chance = 0.15, severity = { 1, 2 } } } },
        { min = 45, pain = 85, knockout = { unconscious = 0.4, dazed = 1 }, bleeding = 2,
            injuries = { { type = "fracture", part = "leg", chance = 0.9, severity = { 2, 3 } },
                { type = "fracture", part = "pelvis", chance = 0.35, severity = { 2, 3 } },
                { type = "fracture", part = "torso", chance = 0.35, severity = { 2, 2 } },
                { type = "fracture", part = "arm", chance = 0.3, severity = { 1, 2 } } } },
    },

    -- by the speed change of the vehicle in km/h (every occupant rolls separately)
    crash = {
        { min = 30, pain = 25, health = 5, knockout = { dazed = 0.15 } },
        { min = 50, pain = 50, health = 15, knockout = { dazed = 0.5, unconscious = 0.05 },
            injuries = { { type = "fracture", part = "arm", chance = 0.15, severity = { 1, 1 } },
                { type = "fracture", part = "torso", chance = 0.15, severity = { 1, 1 } } }, bleeding = 1 },
        { min = 75, pain = 75, health = 30, knockout = { unconscious = 0.3, dazed = 1 }, bleeding = 2,
            injuries = { { type = "fracture", part = "leg", chance = 0.45, severity = { 1, 2 } },
                { type = "fracture", part = "arm", chance = 0.35, severity = { 1, 2 } },
                { type = "fracture", part = "torso", chance = 0.35, severity = { 1, 2 } } } },
        { min = 110, pain = 90, health = 50, knockout = { unconscious = 0.7, dazed = 1 }, bleeding = 3,
            injuries = { { type = "fracture", part = "leg", chance = 0.8, severity = { 2, 3 } },
                { type = "fracture", part = "pelvis", chance = 0.4, severity = { 2, 3 } },
                { type = "fracture", part = "torso", chance = 0.6, severity = { 2, 3 } },
                { type = "fracture", part = "arm", chance = 0.5, severity = { 1, 2 } } } },
    },
}

-- Bare-fisted punch into a vehicle: the chance rises with every punch in a row
MEDEV_PUNCH = {
    chance = 0.06,              -- first punch
    streakBonus = 0.04,         -- + this per punch in the streak
    maxChance = 0.45,
    streakWindow = 4000,        -- ms, the streak resets after this long without a punch
    pain = 20,                  -- every punch hurts a little
    severity = { 1, 1 },        -- hand / forearm fracture
    WORLD_FACTOR = 0.6,         -- chance multiplier for walls / objects (MEDEV.PUNCH_WORLD)
}
end)
