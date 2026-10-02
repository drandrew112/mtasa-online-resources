-- v_introduce - shared configuration. The chapters themselves are in modules/*.lua.
-- Camera positions of the chapters are first guesses: /introcam (admin) prints the current
-- camera matrix in the module format, use it to fine-tune them in-game.

INTRO = {
    -- true: the introduction runs on EVERY login, no matter what the player has already seen.
    -- XP is still given only once per module (account data intro.rewarded).
    DEBUG = false,

    -- Resources that never appear in the introduction. A module that requires one of them,
    -- or that is registered by one of them through registerModule, is refused.
    BLOCKED_RESOURCES = { "v_modmenu" },

    -- account data (v_mysql)
    ACC_SEEN = "intro.seen",           -- JSON { moduleId = version }
    ACC_REWARDED = "intro.rewarded",   -- JSON { moduleId = xp }
    ACC_DONE = "intro.done",           -- true once the full introduction was finished
    ACC_RULES = "intro.rules",         -- the accepted RULES_VERSION

    -- Raise it when rules.txt changes: everybody has to accept the new rules on the next login.
    RULES_VERSION = 1,

    -- Reward: the XP of each module (modules/*.lua, field xp) is given when the module is
    -- finished the first time. The last chapter tops it up to REWARD_TOTAL_XP, so a new
    -- player (level 1, 0 XP) reaches level 3 with v_levelsys' curve (level 3 = 2800 XP).
    REWARD_TOTAL_XP = 2800,

    -- New players are spawned here at the end (LS airport, terminal). Players who already had
    -- a saved position go back to where they were.
    SPAWN = { 1685.6845703125, -2330.2578125, -1.6796875, 0, interior = 0, dimension = 0 },

    -- During the introduction the player stands here, frozen, in their own dimension. The camera
    -- never shows them: scenes without a camera of their own show BACKDROP.
    STAGE = { 1683.09, -2286.06, 13.5, 180 },
    DIMENSION_BASE = 43000,
    BACKDROP = { 1255, -870, 110, 1500, -1350, 50 },   -- fixed camera { x, y, z, lookX, lookY, lookZ }

    -- Objects and peds of dimension 0 (maps, script objects) do not exist in the player's
    -- dimension: the client copies the ones within this radius of the camera's target into it
    -- for as long as the scene shows them (client/mirror.lua).
    MIRROR_RADIUS = 300,

    -- "On the road" practice vehicle: an ELS vehicle (v_els sirenVehicles) so the emergency
    -- lights can be tried too. The camera looks at it from the vehicle-local CAMERA offset.
    VEHICLE = {
        model = 416,
        position = { 1489.33948, -1872.05774, 13.57774, 90 },
        camera = { -5.5, 7.5, 1.8 },               -- right, forward, up of the vehicle
    },

    FADE_TIME = 1.0,                   -- seconds of a camera fade
    CLIENT_WAIT = 180,                 -- seconds to wait for a client still downloading the
                                       -- resources; then the player is released, next login retries
    -- Continue is locked on a scene for: text length / READ_CHARS_PER_SEC, or CAMERA_LOCK_SHARE of
    -- a camera ride's duration - at least MIN_SCENE_TIME, at most MAX_SCENE_TIME seconds.
    -- Task and accept scenes have no waiting time: Continue unlocks as soon as they are done.
    READ_CHARS_PER_SEC = 45,
    CAMERA_LOCK_SHARE = 0.2,
    MIN_SCENE_TIME = 0.5,
    MAX_SCENE_TIME = 3,
    MIN_MODULE_SHARE = 0.6,            -- server check: a module may not finish faster than this
                                       -- share of the sum of its scenes' minimum times

    CONTINUE_KEY = "space",            -- Continue (only once the scene allows it)
    ADMIN_LEVEL = 3,                   -- /intro, /introcam

    -- Key labels used in the texts as {key:name}. Keep them in sync with the resources.
    KEYS = {
        chat = "T",
        social = "HOME",
        phone = "B",
        interaction = "M",
        interact3d = "X",
        pause = "P",
        hudinfo = "Y",
        headlights = "L",
        radio = "Q",
        elsLights = "0",
        elsSiren = "1",
        elsPattern = "5",
        work = "E",
        continue = "SPACE",
        back = "BACKSPACE",
    },
}

-- Seconds a scene stays on screen at least: reading time of its texts, or its camera ride.
-- Used by the client (Continue lock) and the server (a module may not finish faster).
function INTRO.sceneMinTime(scene)
    -- task-type scenes have no waiting time: the task itself is the lock
    if scene.type == "task" or scene.type == "accept" then return 0 end
    local chars = #(scene.title or "") + #(scene.text or "")
    for _, task in ipairs(scene.tasks or {}) do chars = chars + #(task.text or "") end
    for _, callout in ipairs(scene.callouts or {}) do chars = chars + #(callout.text or "") end
    local t = math.max(chars / INTRO.READ_CHARS_PER_SEC, (tonumber(scene.duration) or 0) * INTRO.CAMERA_LOCK_SHARE)
    return math.min(INTRO.MAX_SCENE_TIME, math.max(INTRO.MIN_SCENE_TIME, t))
end

function INTRO.isBlocked(resourceName)
    for _, name in ipairs(INTRO.BLOCKED_RESOURCES) do
        if name == resourceName then return true end
    end
    return false
end
