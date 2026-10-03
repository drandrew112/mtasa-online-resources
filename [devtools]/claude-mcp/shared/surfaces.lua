-- GTA:SA collision surface materials (data/surfinfo.dat order), as returned in the
-- "material" value of processLineOfSight. Only the first 65 entries are listed;
-- higher ids (procedural "P_*" surfaces) are reported as material_<id> / class "other".
--
-- class is a coarse grouping used by the area / road scanners:
--   road, sidewalk, concrete, grass, dirt, sand, rock, water, structure, vehicle, ped, default, other

SURFACES = {
    [0] = { "DEFAULT", "default" },
    { "TARMAC", "road" }, { "TARMAC_FUCKED", "road" }, { "TARMAC_REALLYFUCKED", "road" },
    { "PAVEMENT", "sidewalk" }, { "PAVEMENT_FUCKED", "sidewalk" },
    { "GRAVEL", "dirt" }, { "FUCKED_CONCRETE", "concrete" }, { "PAINTED_GROUND", "road" },
    { "GRASS_SHORT_LUSH", "grass" }, { "GRASS_MEDIUM_LUSH", "grass" }, { "GRASS_LONG_LUSH", "grass" },
    { "GRASS_SHORT_DRY", "grass" }, { "GRASS_MEDIUM_DRY", "grass" }, { "GRASS_LONG_DRY", "grass" },
    { "GOLFGRASS_ROUGH", "grass" }, { "GOLFGRASS_SMOOTH", "grass" }, { "STEEP_SLIDYGRASS", "grass" },
    { "STEEP_CLIFF", "rock" }, { "FLOWERBED", "grass" }, { "MEADOW", "grass" },
    { "WASTEGROUND", "dirt" }, { "WOODLANDGROUND", "dirt" }, { "VEGETATION", "grass" },
    { "MUD_WET", "dirt" }, { "MUD_DRY", "dirt" }, { "DIRT", "dirt" }, { "DIRTTRACK", "dirt" },
    { "SAND_DEEP", "sand" }, { "SAND_MEDIUM", "sand" }, { "SAND_COMPACT", "sand" },
    { "SAND_ARID", "sand" }, { "SAND_MORE", "sand" }, { "SAND_BEACH", "sand" },
    { "CONCRETE_BEACH", "concrete" }, { "ROCK_DRY", "rock" }, { "ROCK_WET", "rock" },
    { "ROCK_CLIFF", "rock" }, { "WATER_RIVERBED", "water" }, { "WATER_SHALLOW", "water" },
    { "CORNFIELD", "grass" }, { "HEDGE", "grass" }, { "WOOD_CRATES", "structure" },
    { "WOOD_SOLID", "structure" }, { "WOOD_THIN", "structure" }, { "GLASS", "structure" },
    { "GLASS_WINDOWS_LARGE", "structure" }, { "GLASS_WINDOWS_SMALL", "structure" },
    { "EMPTY1", "other" }, { "EMPTY2", "other" }, { "GARAGE_DOOR", "structure" },
    { "THICK_METAL_PLATE", "structure" }, { "SCAFFOLD_POLE", "structure" }, { "LAMP_POST", "structure" },
    { "FIRE_HYDRANT", "structure" }, { "GIANT_TYRE", "structure" }, { "CARDBOARDBOX", "structure" },
    { "PED", "ped" }, { "CAR", "vehicle" }, { "CAR_PANEL", "vehicle" }, { "CAR_MOVINGCOMPONENT", "vehicle" },
    { "TRANSPARENT_CLOTH", "structure" }, { "RUBBER", "structure" }, { "PLASTIC", "structure" },
    { "TRANSPARENT_STONE", "structure" },
}

function surfaceName(id)
    local s = SURFACES[tonumber(id) or -1]
    return s and s[1] or ("material_" .. tostring(id))
end

function surfaceClass(id)
    local s = SURFACES[tonumber(id) or -1]
    return s and s[2] or "other"
end

-- walkable surface classes for peds
WALKABLE = { road = true, sidewalk = true, concrete = true, grass = true, dirt = true, sand = true, default = true, structure = true }

-- world model kind from its dff name (heuristic, reported as such)
local KIND_PATTERNS = {
    { "road", { "road", "rd_", "_rd", "hiway", "hway", "freeway", "frway", "junc", "xing", "crossing", "street", "motorway", "highway", "tunnel" } },
    { "bridge", { "bridge", "brdg", "brig" } },
    { "vegetation", { "tree", "bush", "veg", "plant", "palm", "hedge", "flower", "shrub", "cactus", "pine", "oak", "weed" } },
    { "lighting", { "lamp", "light", "tlight", "traffic" } },
    { "building", { "build", "bldg", "house", "shop", "office", "tower", "apart", "hotel", "church", "warehouse", "hosp", "station", "store", "bank", "casino", "motel", "factory", "hangar", "garage" } },
    { "terrain", { "land", "ground", "hill", "grnd", "cliff", "rock", "beach", "sand", "dirt", "mount", "terrain", "desert" } },
    { "water", { "water", "sea", "river", "lake", "pool" } },
    { "barrier", { "fence", "wall", "barrier", "rail", "gate", "barr" } },
    { "prop", { "bench", "bin", "sign", "cone", "pole", "hydrant", "phone", "post", "crate", "box", "barrel", "table", "chair", "dumpster" } },
}

function modelKind(name)
    if type(name) ~= "string" then return "unknown" end
    local n = name:lower()
    for _, entry in ipairs(KIND_PATTERNS) do
        for _, p in ipairs(entry[2]) do
            if n:find(p, 1, true) then return entry[1] end
        end
    end
    return "unknown"
end
