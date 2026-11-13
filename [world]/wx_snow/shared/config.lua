-- wx_snow :: shared config (DESIGN.md)

SNOW = {
    -- /snow, /snowbake, /snowtest: account admin_level >= this
    ADMIN_LEVEL = 5,

    -- v_weekly custom key of the week ({ level = 0..5, dynamic = bool })
    WEEK_KEY = "snow",

    -- minutes for the ground coverage to grow from 0 to 1 / to melt from 1 to 0
    ACCUM_MIN = 20,
    MELT_MIN  = 40,

    -- dynamic week: the level moves around the weekly level (-1 / 0 / +1) every SEGMENT_H hours;
    -- the sequence comes from the week start, so every server instance agrees
    DYNAMIC_SEGMENT_H = 3,
    DYNAMIC_STEPS = { -1, 0, 0, 1 },

    -- seconds the snowfall needs to fade in / out (level change, going under a roof / outside)
    PRECIP_FADE = 1.2,

    -- client quality: "off" | "low" | "high" (ui_pause Graphics > Snow quality)
    DEFAULT_QUALITY = "high",

    -- GTA weather while it snows (server, setWeatherBlended); 0 = the weather before the snow
    WEATHER_RESTORE = 1,

    --------------------------------------------------------------------------------------------
    -- levels
    --   cover    ground coverage target 0..1
    --   wet      wet / darker ground where there is no snow 0..1
    --   flakes   snowfall density 0..1 (near flakes + layers)
    --   size     flake size (m)
    --   fall     falling speed (m/s)
    --   wind     wind speed (m/s), gust = extra random part
    --   fog      fog distance (m) through drawdistance:setFogOverride, false = untouched
    --   weather  GTA weather id (server)
    --   grass    GTA procedural grass (tx*): "keep" | "white" | "hide"
    --   windVol  wind loop volume 0..1
    --   grade    shader_colors override (only these keys are touched)
    --------------------------------------------------------------------------------------------
    LEVELS = {
        [0] = { id = "off", cover = 0, wet = 0, flakes = 0, size = 0.06, fall = 1.2, wind = 0, gust = 0,
                fog = false, weather = nil, grass = "keep", windVol = 0, grade = nil },
        [1] = { id = "flurries", cover = 0, wet = 0.45, flakes = 0.18, size = 0.075, fall = 1.0, wind = 0.8, gust = 0.4,
                fog = false, weather = 12, grass = "keep", windVol = 0,
                grade = { temperature = -0.12, saturation = 0.95 } },
        [2] = { id = "light", cover = 0.32, wet = 0.4, flakes = 0.35, size = 0.07, fall = 1.1, wind = 1.0, gust = 0.6,
                fog = false, weather = 12, grass = "white", windVol = 0,
                grade = { temperature = -0.18, saturation = 0.9 } },
        [3] = { id = "snowy", cover = 0.62, wet = 0.3, flakes = 0.55, size = 0.07, fall = 1.2, wind = 1.4, gust = 1.0,
                fog = 900, weather = 15, grass = "white", windVol = 0.15,
                grade = { temperature = -0.25, saturation = 0.85, exposure = 1.04 } },
        [4] = { id = "heavy", cover = 0.85, wet = 0.2, flakes = 0.8, size = 0.065, fall = 1.4, wind = 2.2, gust = 1.6,
                fog = 480, weather = 9, grass = "hide", windVol = 0.35,
                grade = { temperature = -0.3, saturation = 0.78, exposure = 1.06 } },
        [5] = { id = "blizzard", cover = 0.96, wet = 0.1, flakes = 1.0, size = 0.06, fall = 2.0, wind = 7.0, gust = 4.0,
                fog = 170, weather = 9, grass = "hide", windVol = 0.8,
                grade = { temperature = -0.35, saturation = 0.65, exposure = 1.1, contrast = 0.2 } },
    },
    MAX_LEVEL = 5,

    --------------------------------------------------------------------------------------------
    -- ground shader categories (client/ground.lua). The first is the generic "*" one; the others
    -- take their textures away from it (layered shaders: one per texture, never two of ours).
    --   mult   coverage multiplier
    --   upLo / upHi: surface normal z where snow starts / is full (lowered by coverage)
    --   road   1 = slush colour, less snow
    --   debug  colour of /snow debug
    --------------------------------------------------------------------------------------------
    CATEGORIES = {
        -- generic = every texture no other category takes (buildings, roofs, props): each one is drawn a second
        -- time, which is the big fixed cost (/snowtest cost: ground shaders alone were -40 % fps at every
        -- level), so it only reaches maxDist m. The terrain / road / pavement categories stay unlimited.
        { id = "generic", mult = 1.0, upLo = 0.62, upHi = 0.86, road = 0, debug = { 0.2, 0.45, 1.0 },
          maxDist = 250, patterns = { "*" } },
        { id = "soft", mult = 1.15, upLo = 0.45, upHi = 0.75, road = 0, debug = { 0.2, 0.9, 0.25 },
          patterns = { "*grass*", "*dirt*", "*mud*", "*sand*", "desertgryard256", "*gravel*", "*field*",
                       "*forest*", "*rough*", "*hedge*", "*lawn*", "*grssdrt*" } },
        -- road: wheel tracks per lane from the lane map (data/roadmap.png), so the full coverage
        { id = "road", mult = 1.0, upLo = 0.55, upHi = 0.85, road = 1, debug = { 1.0, 0.2, 0.2 },
          patterns = { "*road*", "*tar*", "*asphalt*", "*freeway*", "*hiway*", "*junction*", "*carpark*",
                       "*crossing*", "*snpedtest*", "lan_merge" } },
        -- plain asphalt: the road models use greyground256 for the tarmac itself (the road_* textures are only the
        -- markings / junctions), but plazas and lots use it too, so road = 2: lane tracks only where the lane map has a lane
        { id = "roadplain", mult = 1.0, upLo = 0.55, upHi = 0.85, road = 2, debug = { 1.0, 0.45, 0.45 },
          patterns = { "greyground256" } },
        { id = "pavement", mult = 0.8, upLo = 0.55, upHi = 0.85, road = 0, debug = { 1.0, 0.6, 0.1 },
          patterns = { "*walk*", "*pave*", "sidelatino*", "sjmhoodlawn41", "*kerb*", "*curb*" } },
        -- maxDist: the shader is not applied farther than this (alpha tested leaves = a lot of overdraw,
        -- and trees that far are green in the fog anyway); lowSkip: no foliage snow on Low quality
        { id = "foliage", mult = 0.9, upLo = 0.35, upHi = 0.7, road = 0, debug = { 0.0, 0.6, 0.4 },
          maxDist = 110, lowSkip = true,
          patterns = { "*leave*", "*leaf*", "*tree*", "*branch*", "*bush*", "*pine*", "*fir*", "*foliage*",
                       "*cedar*", "*oak*", "*palm*", "*hedge*" } },
    },

    -- ground shader file: "v2" = fx/snow_world.fx (F1 speed-up), "v1" = fx/snow_world_v1.fx (the old one,
    -- for A/B measuring: /snow shader v1|v2 on the own client)
    SHADER = "v2",

    -- F1 distance tiers of the ground shader (m from the camera); Low quality multiplies them by LOW_SCALE
    --   roof   bilinear roof map up to x, point sample up to y, ignored farther
    --   road   lane map fully on up to x, off from y
    --   noise  finest noise octave up to x, middle octave up to y, sparkle up to z (mip-blurred to the mean after)
    LOD = {
        roof = { 80, 250 }, road = { 70, 110 }, noise = { 100, 300, 30 },
        LOW_SCALE = 0.6,
    },

    -- never snowed on (every category). Mostly the dynamic_lighting removeList + water, glass, lights.
    EXCLUDE = {
        "", "unnamed", "basketball2", "skybox*", "flashlight_*", "muzzle_texture*", "font*", "radar*",
        "sitem16", "snipercrosshair", "siterocket", "cameracrosshair", "fireba*", "wjet6",
        "vehiclegeneric256", "vehicleshatter128", "*shad*", "corona*", "lunar", "tx*", "cj_w_grad",
        "coronaheadlightline", "cloud*", "*water*", "waterclear256", "*glass*", "*window*", "*wndw*",
        "*lights*", "*light_*", "*streetlight*", "*taillight*", "*headlight*", "*lamp*", "*neon*",
        "*smoke*", "*spark*", "*particle*", "*blood*", "*shadow*", "*bullet*", "*explo*",
        "*fire*", "*splash*", "*gunflash*", "*marker*", "*cylinder*", "*vehicle*", "skin*", "*hud*",
    },

    -- GTA procedural grass + plants (white / hidden from level grass = "white" / "hide")
    GRASS_PATTERNS = { "tx*" },

    --------------------------------------------------------------------------------------------
    -- roof map (client/roofmap.lua, /snowbake)
    --------------------------------------------------------------------------------------------
    ROOF = {
        FILE = "data/roofmap.png",
        INFO = "data/roofmap.json",
        -- bake grid: 6144 m square, 4 m cells -> 1536 x 1536
        MIN_X = -3072, MIN_Y = -3072, SIZE = 6144, CELL = 4,
        -- 16 bit height range (m)
        Z_MIN = -60, Z_MAX = 1000,
        -- a pixel is covered when it is this much below the top surface of its cell (m)
        TOLERANCE = 1.6,
        -- bake: tile size (cells), wait after teleport for the collision to stream in (ms),
        -- ray budget per frame (ms), sub samples per cell (min of them = less covered next to walls)
        TILE = 64, WAIT_MS = 1600, BUDGET_MS = 10,
        SUB = { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } },
        RAY_TOP = 900, RAY_BOTTOM = -60,
        -- upload of the baked png to the server (latent event chunks; > ~1 MB gets lost)
        CHUNK = 450000,
    },

    --------------------------------------------------------------------------------------------
    -- snowfall (client/precip.lua)
    --------------------------------------------------------------------------------------------
    PRECIP = {
        BOX = { 36, 36, 22 },        -- near flake box around the camera (m)
        FLAKES = { off = 0, low = 500, high = 1400 },
        -- cylinder layers around the camera: radius (m), texture scale, alpha
        LAYERS = {
            { r = 4,  scale = 2.2, alpha = 0.9 },
            { r = 9,  scale = 1.5, alpha = 0.75 },
            { r = 18, scale = 1.0, alpha = 0.6 },
            { r = 34, scale = 0.6, alpha = 0.5 },
        },
        LAYERS_LOW = 2,              -- low quality draws the first N layers only
        SEGMENTS = 18,               -- cylinder segments
        HEIGHT = { -12, 26 },        -- cylinder bottom / top relative to the camera
    },

    -- maps_loader indoor boxes + clear areas passed to the ground shader (nearest ones)
    INDOOR_BOXES = 4,

    -- always snow free boxes (ground + flakes; the camera is still "outside" there): covered
    -- ramps / bays the roof map would miss or before it is baked. min / max = x, y, z
    CLEAR_AREAS = {
        -- All Saints ambulance bay (med_hospitals hospitals.json bayAreas + ramp)
        { name = "All Saints ambulance bay", min = { 1139.5, -1347.0, 11.5 }, max = { 1150.0, -1314.0, 19.0 } },
    },

    -- maps_loader map -> the boxes wx_snow uses instead of its settings.json "indoor" boxes
    -- ({ minX, minY, minZ, maxX, maxY, maxZ }); the loader box may reach outside the walls
    ZONE_MASKS = {
        -- All Saints: the ER floor (med_hospitals er.zone) instead of the bigger loader box
        ls_allsaints = { { 1150.0, -1384.2, 12.0, 1172.0, -1291.6, 18.5 } },
    },

    -- client state checks (interior, indoor box, under a roof); interior changes are checked at once
    CHECK_MS = 150,

    -- lane map (tools/build_roadmap.py from GTA data/Paths): wheel tracks on roads
    -- the lane map is streamed: a WINDOW x WINDOW cell (4 m) window around the camera, refilled from the chunks
    -- (data/road/c_<cx>_<cy>.png) when the camera comes closer than MARGIN cells to its edge. The shader only uses
    -- the lane map within SNOW.LOD.road[2] m (110 m = 28 cells), so MARGIN 32 cells (128 m) is always enough.
    ROAD = { INFO = "data/roadmap.json", DIR = "data/road/", WINDOW = 128, MARGIN = 32, SNAP = 16,
             CACHE = 4, ROWS_PER_FRAME = 8 },
}

-- level -> params (clamped)
function snowLevelParams(level)
    level = math.max(0, math.min(SNOW.MAX_LEVEL, math.floor(tonumber(level) or 0)))
    return SNOW.LEVELS[level], level
end
