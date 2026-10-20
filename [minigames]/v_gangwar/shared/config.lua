-- v_gangwar settings (shared). Gang wars themselves live in the MySQL `gangwars` table (server/db.lua) and are made
-- with /gangwareditor.

GW = {
    ADMIN_LEVEL = 5,                -- /gangwareditor
    EDITOR_DIMENSION = 46000,       -- + slot: every editor works in a private dimension (preview + test run peds too)
    EDITOR_SLOTS = 999,

    COOLDOWN = 3 * 86400,           -- s: a gang war comes back this long after its last completed run (global)
    RESERVE_TIMEOUT = 5 * 60000,    -- ms: a reservation whose starter never entered the zone expires
    TICK = 1000,                    -- ms: reservation / zone / distance checks
    CLEANUP_TICK = 2000,            -- ms: removing peds of a closed gang war (only while no camera sees them)
    CLEANUP_SEE_DIST = 300,         -- m: cameras farther than this do not keep a ped alive
    RELOAD_INTERVAL = 5 * 60000,    -- ms: last_run re-read from the database (other servers sharing it)
    HUD_RADIUS_FACTOR = 1.2,        -- helpers within zone_radius x this see the stat rows
    END_HUD_TIME = 8000,            -- ms: stat rows stay this long after the end

    KILL_MONEY = 1500,              -- per kill, paid to whoever killed (starter or helper), at once
    KILL_XP = 500,

    CIRCLE_COLOR = { 220, 30, 30, 90 },

    -- new gang war / new attacker values in the editor
    DEFAULTS = {
        name = "Gang war", gang = "gang", enabled = true,
        trigger_radius = 150, zone_radius = 60, release_radius = 250,
        reward_money = 10000, reward_xp = 2000,
        days = "1234567", hour_from = 0, hour_to = 24,
    },
    ATTACKER = {
        skin = 102, weapon = 30, ammo = 300, health = 100, armor = 0, accuracy = 0.5, aggro = 35,
        task = "guard", wait = { 2000, 6000 }, speed = "walk",
    },

    LIMITS = {
        name = 48, gang = 24,
        radius = { 5, 1000 },
        money = { 0, 10000000 }, xp = { 0, 10000000 },
        attackers = 40, patrol = 20,
        health = { 1, 1000 }, armor = { 0, 100 }, ammo = { 1, 9999 }, aggro = { 5, 200 },
        wait = { 0, 120000 },
    },

    -- editor keys (client)
    KEY_MENU = "r",                 -- open the editor menu
    KEY_POINT = "1",                -- patrol recording: add a point at your position
    KEY_UNDO = "2",                 -- patrol recording: remove the last point
    KEY_DONE = "3",                 -- patrol recording: finish
    KEY_DRAG_PLACE = "1",           -- dragging an attacker: put it down (left click works too)
    KEY_DRAG_CANCEL = "2",          -- dragging an attacker: cancel (right click works too)
    DRAG_ROTATE_STEP = 15,          -- degrees per mouse wheel tick while dragging
    DRAG_MAX_DIST = 30,             -- m: farthest an attacker can be dragged from you
    ATTACKER_MENU_RANGE = 6,        -- m: ui_interactobject menu on the preview peds

    -- skin presets in the attacker interact menu (label = locale key suffix)
    SKIN_PRESETS = {
        { "grove", { 105, 106, 107 } }, { "ballas", { 102, 103, 104 } }, { "vagos", { 108, 109, 110 } },
        { "aztecas", { 114, 115, 116 } }, { "rifa", { 173, 174, 175 } }, { "danang", { 121, 122, 123 } },
        { "triads", { 117, 118, 120 } }, { "mafia", { 111, 112, 113 } }, { "bikers", { 247, 248, 254 } },
    },
}

-- firearms count as "armed" (melee, thrown weapons and tools do not)
function GW.isFirearm(id)
    id = tonumber(id)
    return id ~= nil and id >= 22 and id <= 38
end

-- valid attacker weapons (melee allowed for peds too)
function GW.isPedWeapon(id)
    id = tonumber(id)
    return id ~= nil and ((id >= 1 and id <= 9) or (id >= 22 and id <= 38))
end

-- days: "1234567", 1 = Monday ... 7 = Sunday. getRealTime().weekday: 0 = Sunday.
function GW.isDayAllowed(days, weekday)
    local d = weekday == 0 and 7 or weekday
    return tostring(days or ""):find(tostring(d), 1, true) ~= nil
end

-- hour window [from, to): from == to or 0..24 = all day; from > to wraps past midnight
function GW.isHourAllowed(from, to, hour)
    from, to = tonumber(from) or 0, tonumber(to) or 24
    if from == to or (from <= 0 and to >= 24) then return true end
    if from < to then return hour >= from and hour < to end
    return hour >= from or hour < to
end

function GW.clamp(v, range)
    v = tonumber(v)
    if not v then return nil end
    return math.max(range[1], math.min(range[2], v))
end
