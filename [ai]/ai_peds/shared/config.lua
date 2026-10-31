-- ai_peds settings (shared). Distances in metres, speeds in m/s, times in ms unless noted.
-- Every limit of the ped traffic is here so the server load can be tried out (/aipeds shows the counts).

AIPEDS = {
    TICK = 250,                 -- server brain step (all peds)
    SYNC_CHECK = 1000,          -- syncer re-check (MTA picks the syncer: nearest player within ped_syncer_distance, 100 m default)

    -- ped traffic (sidewalk walkers): only around players in dimension 0 / interior 0, only in built-up areas
    TRAFFIC_ENABLED = true,
    MAX_TRAFFIC = 30,           -- walkers on the whole server (adopted drivers not counted)
    MAX_PER_PLAYER = 8,         -- walkers within SPAWN_MAX_DIST of one player; hard cap for EVERY player near a spawn point
    AREA_RADIUS = 45,           -- regional limit: no new walker where this circle already holds...
    AREA_MAX = 4,               -- ...this many peds (walkers, drivers, scripted)
    SIDEWALK_PER_PED = 90,      -- metres of sidewalk around the player per walker (density) before the cap
    SETTLEMENT_RADIUS = 90,     -- built-up area test: sidewalk length within this radius of the player...
    SETTLEMENT_MIN = 260,       -- ...must reach this many metres, else no walkers (country roads, lone footpaths)
    WALK_KINDS = { "sidewalk", "crossing", "crossing_light" },  -- navmesh ped edge kinds walkers use (no park / hiking paths)
    SPAWN_INTERVAL = 1000,
    SPAWN_PER_PLAYER = 1,       -- spawn attempts per player per SPAWN_INTERVAL
    SPAWN_MIN_DIST = 45,        -- spawn at least this far from every player...
    SPAWN_MAX_DIST = 90,        -- ...and at most this far from the spawning player (stay inside the ped syncer distance)
    SPAWN_VISIBLE_MIN = 75,     -- a spawn point a camera looks at must be at least this far from it
    EDGE_CACHE_MOVE = 25,       -- sidewalk list around a player is re-read after moving this far...
    EDGE_CACHE_AGE = 15000,     -- ...or after this long
    DESPAWN_DIST = 120,         -- walkers / adopted drivers farther than this from every player are removed
    CULL_MIN_DIST = 35,         -- unseen (no camera looks at them) for CULL_AFTER and farther than this: removed
    CULL_AFTER = 5000,
    NIGHT_FACTOR = 0.5,         -- density factor between NIGHT_FROM and NIGHT_TO (game hours)
    NIGHT_FROM = 22,
    NIGHT_TO = 6,
    WALK_LENGTH = 140,          -- random walk length asked from navmesh, continued before the end
    WALK_SIDE = 0.35,           -- walkers keep this fraction of the path width right of the centre line (+-jitter)
    WALK_SKINS = nil,           -- nil = the civilian skin list below

    -- crossings
    CROSSING_WAIT_DIST = 2.5,   -- stop this close to the kerb when the crossing is closed
    CROSSING_CAR_RANGE = 30,    -- unlit crossing: wait while a vehicle closer than this...
    CROSSING_CAR_SPEED = 3,     -- ...drives faster than this towards it
    CROSSING_MAX_WAIT = 45000,  -- give up waiting (broken light data): cross anyway

    -- cameras (clients report): spawning out of sight, culling unseen walkers
    VIEW_SEND = 500,
    VIEW_STALE = 3000,          -- a player without a fresh report counts as seeing everything
    VIEW_HALF_ANGLE = 70,
    VIEW_NEAR = 12,

    -- perception
    SHOT_REPORT_GAP = 600,      -- a client reports its own gunshots at most this often
    SHOT_SCARE_RADIUS = 40,     -- civilians this close to a shot (shooter or impact) get scared
    SHOT_ALERT_RADIUS = 60,     -- enemies this close to a shot by a hostile engage the shooter
    ATTACK_SCARE_RADIUS = 25,   -- civilians this close to an attacked / killed ped get scared
    CIVILIAN_FIGHT_BACK = 0.15, -- chance an attacked civilian (unarmed) fights back instead of fleeing
    GRUDGE_TIME = 60000,        -- an enemy stays hostile to its attacker this long
    GROUP_ALERT_RADIUS = 40,    -- an attacked enemy calls the members of its group this close

    -- scared / fleeing
    FLEE_DIST = 60,             -- flee point this far away from the threat
    FLEE_SAFE = 55,             -- calms down once the threat is farther than this...
    FLEE_CALM = 10000,          -- ...and nothing scared it for this long
    FLEE_ROUTE = true,          -- navmesh route to the flee point (async); false: straight line only
    COWER_DIST = 8,             -- no way out and the threat this close: cowers

    -- enemies
    AGGRO_RADIUS = 30,          -- default: hostiles closer than this are attacked (scripted peds can set their own)
    LEASH = 90,                 -- default: a ped with a home does not chase farther than this from it
    LOSE_DIST = 110,            -- target farther than this: lost
    REPATH_MIN = 1500,          -- route to the target at most this often...
    REPATH_MOVE = 5,            -- ...when it moved this far since the last route
    VEH_TASK_TIMEOUT = 9000,    -- aiPedEnterVehicle / aiPedExitVehicle: placed in / out after this (synced ped)
    VEH_TASK_UNSYNCED = 2500,   -- ...or this long without a syncer
    DIRECT_DIST = 12,           -- closer than this: straight at the target, no route
    ACCURACY = 0.55,            -- default 0..1 (aim spread on the client)
    MELEE_RANGE = 1.5,
    -- unarmed enemy vs a target sitting in a vehicle: pulls it out first (GTA jack), armed ones shoot
    JACK_DIST = 9,              -- starts the jack closer than this (setPedEnterVehicle: 10 m with a driver)...
    JACK_MAX_SPEED = 3,         -- ...while the vehicle is slower than this (m/s)
    JACK_TIMEOUT = 7000,        -- target still inside after this long: gives up for JACK_RETRY (fists)
    JACK_RETRY = 3000,
    SCAN_INTERVAL = 500,        -- hostile scan of calm enemies
    -- weapon ranges / firing pattern (ms): weapon id -> { range, burst = {min, max}, pause = {min, max} }
    WEAPONS = {
        [22] = { range = 30, burst = { 200, 500 }, pause = { 500, 1200 } },   -- colt
        [23] = { range = 30, burst = { 200, 500 }, pause = { 500, 1200 } },   -- silenced
        [24] = { range = 32, burst = { 150, 300 }, pause = { 800, 1500 } },   -- deagle
        [25] = { range = 18, burst = { 150, 250 }, pause = { 1000, 1600 } },  -- shotgun
        [26] = { range = 14, burst = { 150, 300 }, pause = { 600, 1200 } },   -- sawn-off
        [27] = { range = 20, burst = { 150, 300 }, pause = { 500, 1000 } },   -- combat shotgun
        [28] = { range = 26, burst = { 400, 900 }, pause = { 600, 1300 } },   -- uzi
        [29] = { range = 32, burst = { 400, 900 }, pause = { 600, 1300 } },   -- mp5
        [30] = { range = 45, burst = { 300, 800 }, pause = { 700, 1400 } },   -- ak
        [31] = { range = 50, burst = { 300, 800 }, pause = { 700, 1400 } },   -- m4
        [32] = { range = 26, burst = { 400, 900 }, pause = { 600, 1300 } },   -- tec-9
        [33] = { range = 70, burst = { 150, 250 }, pause = { 1500, 2500 } },  -- rifle
        [34] = { range = 90, burst = { 150, 250 }, pause = { 2000, 3000 } },  -- sniper
    },
    MELEE_WEAPONS = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true,
                      [7] = true, [8] = true, [9] = true, [10] = true, [11] = true, [12] = true, [15] = true },

    -- drivers taken over from ai_land_traffic (crash, damage, jacked, player got in)
    DRIVER_ENEMY_CHANCE = 0.15,         -- after a crash / damage
    DRIVER_ENEMY_CHANCE_JACKED = 0.35,  -- pulled out by a player / a player got in
    DRIVER_ARMED_CHANCE = 0.35,         -- an enemy driver has a weapon (else fists)
    DRIVER_WEAPONS = { { 22, 60, 4 }, { 24, 21, 1 }, { 5, 1, 3 }, { 4, 1, 1 }, { 28, 100, 1 } },  -- { weapon, ammo, weight }
    DRIVER_EXIT_SPEED = 2.5,    -- the driver gets out once the vehicle is slower than this
    DRIVER_EXIT_DELAY = 1200,   -- after a crash: shock before getting out
    DRIVER_JACK_WAIT = 6000,    -- jacked: GTA pulls the ped out; still inside after this long -> it gets out itself
    DRIVER_EXIT_RETRY = 4000,   -- exit order repeated after this long
    DRIVER_EXIT_GIVEUP = 25000, -- still inside: left alone in the vehicle (never teleported out)
    DRIVER_CULL_GRACE = 20000,  -- a driver that just got out is never culled for this long

    -- bodies
    BODY_LIFE = 30000,          -- dead traffic / driver peds are removed after this (when nobody is near)
    BODY_NEAR = 25,

    -- medical status (medsys, server/medical.lua): every ped is a persistent medsys patient (examinable, gets
    -- injuries, a lethal hit puts it down instead of killing it); a downed ped is never culled near a player
    MEDICAL = true,
    MEDICAL_CHECK = 1000,       -- downed / up re-check of every ped

    ADMIN_LEVEL = 4,            -- /aipeds (elementData admin_level)
    DEBUG = false,
}

-- civilian skins (walkers, scripted default)
AIPEDS_SKINS = {
    7, 9, 10, 11, 12, 13, 14, 15, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 29, 31, 32, 33, 34, 35, 36, 37,
    38, 39, 40, 41, 43, 44, 46, 47, 48, 49, 54, 55, 56, 57, 58, 59, 60, 61, 62, 68, 69, 72, 73, 76, 78, 79,
    88, 89, 91, 93, 94, 95, 98, 100, 101, 128, 129, 130, 131, 132, 133, 141, 142, 143, 147, 148, 150, 151,
    153, 157, 158, 159, 160, 161, 170, 171, 172, 176, 177, 179, 182, 183, 184, 185, 186, 187, 188, 189, 190,
    191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 206, 210, 211, 212, 213, 214, 215, 216, 217,
    218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 231, 232, 233, 234, 235, 236, 239, 240, 241,
    242, 250, 258, 259, 260, 261, 262,
}

-- events
EV_READY = "ai_peds:ready"      -- client -> server: scripts loaded
EV_CMD = "ai_peds:cmd"          -- server -> syncer: ped, command
EV_DROP = "ai_peds:drop"        -- server -> client: ped, stop driving it
EV_REPORT = "ai_peds:report"    -- syncer -> server: ped, kind ("arrived" | "stuck" | "exited"), data
EV_THREAT = "ai_peds:threat"    -- client -> server: kind ("shot" | "damage"), ...
EV_VIEW = "ai_peds:view"        -- client -> server: camera
EV_NOTIFY = "ai_peds:notify"    -- server -> client: admin text
EV_DEBUG = "ai_peds:debug"      -- server -> client: toggle the debug view

-- element data (set by the server): the syncer's move state ("walk" | "run" | "sprint" | false), the other clients
-- play the walk with it (control states are not synced, without it they see the ped slide)
DATA_MOVE = "ai_peds.mv"
-- the same for fighting: { t = target, me = melee, r = range, acc, burst, pause } while the syncer aims + fires / hits,
-- else false. Each client's own shots only hurt its own player (the others are hit on their own clients)
DATA_FIGHT = "ai_peds.fight"
-- medsys consciousness element data (stable | confused | dazed | unconscious | clinical_death | dead)
MEDICAL_STATUS = "medic.status"
