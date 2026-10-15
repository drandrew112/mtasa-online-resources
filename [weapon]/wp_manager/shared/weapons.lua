-- Weapon definitions shared by the server and the client (wp_selector reads them through the
-- client export getWeaponDefs).
--
-- kind:
--   "melee"  no ammo (the ammo is always 1)
--   "gun"    magazine + reserve, manual reload, kept at 0 ammo
--   "tool"   ammo but no reload (spraycan, extinguisher, camera), kept at 0 ammo
--   "thrown" removed from the player when the last one is used
-- Weapons 40 (detonator) and 44-46 (goggles, parachute) are not managed: GTA / other resources
-- own them, and wp_manager never takes them away (GTA slots 11 and 12 are left alone).

WP = {}

WP.MAX_AMMO = 9999
WP.MANAGED_SLOTS = 10   -- GTA slots 0..10 belong to wp_manager

-- Wheel order: bottom first, then clockwise on the screen (left, up, right).
WP.CATEGORIES = { "melee", "shotguns", "heavy", "grenades", "pistols", "smg", "mg", "long" }

-- { id, category, kind } in the order they are listed inside a category
WP.LIST = {
    { 1,  "melee", "melee" },    -- brass knuckles
    { 2,  "melee", "melee" },    -- golf club
    { 3,  "melee", "melee" },    -- nightstick
    { 4,  "melee", "melee" },    -- knife
    { 5,  "melee", "melee" },    -- baseball bat
    { 6,  "melee", "melee" },    -- shovel
    { 7,  "melee", "melee" },    -- pool cue
    { 8,  "melee", "melee" },    -- katana
    { 9,  "melee", "melee" },    -- chainsaw
    { 10, "melee", "melee" },    -- long purple dildo
    { 11, "melee", "melee" },    -- short dildo
    { 12, "melee", "melee" },    -- vibrator
    { 13, "melee", "melee" },    -- silver vibrator
    { 14, "melee", "melee" },    -- flowers
    { 15, "melee", "melee" },    -- cane
    { 41, "melee", "tool" },     -- spraycan
    { 42, "melee", "tool" },     -- fire extinguisher
    { 43, "melee", "tool" },     -- camera
    { 25, "shotguns", "gun" },   -- shotgun
    { 26, "shotguns", "gun" },   -- sawn-off shotgun
    { 27, "shotguns", "gun" },   -- combat shotgun
    { 35, "heavy", "gun" },      -- rocket launcher
    { 36, "heavy", "gun" },      -- heat-seeking RPG
    { 37, "heavy", "gun" },      -- flamethrower
    { 38, "heavy", "gun" },      -- minigun
    { 16, "grenades", "thrown" },-- grenade
    { 17, "grenades", "thrown" },-- tear gas
    { 18, "grenades", "thrown" },-- molotov
    { 39, "grenades", "thrown" },-- satchel charge
    { 22, "pistols", "gun" },    -- colt 45
    { 23, "pistols", "gun" },    -- silenced pistol
    { 24, "pistols", "gun" },    -- desert eagle
    { 28, "smg", "gun" },        -- uzi
    { 29, "smg", "gun" },        -- mp5
    { 32, "smg", "gun" },        -- tec-9
    { 30, "mg", "gun" },         -- ak-47
    { 31, "mg", "gun" },         -- m4
    { 33, "long", "gun" },       -- country rifle
    { 34, "long", "gun" },       -- sniper rifle
}

WP.WEAPONS = {}   -- id -> { id, cat, kind, order }
for order, row in ipairs(WP.LIST) do
    WP.WEAPONS[row[1]] = { id = row[1], cat = row[2], kind = row[3], order = order }
end

function WP.isManaged(id)
    return WP.WEAPONS[tonumber(id)] ~= nil
end

-- Magazine size of a gun, or nil when GTA has no magazine data for it (heavy weapons, tools)
function WP.maxClip(id)
    if id < 22 or id > 34 then return nil end
    local clip = tonumber(getWeaponProperty(id, "pro", "maximum_clip_ammo"))
    return (clip and clip > 0) and clip or nil
end
