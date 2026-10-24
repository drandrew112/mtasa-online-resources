-- world_clothes-shop / shared/config.lua
if not VAT then loadstring(exports.v_gov:importVat())() end -- VAT lib of v_gov (shared/vat.lua)
-- Clothes shops: interiors registered through world_interiors, a radar blip on every entrance,
-- and skin changer markers inside. Every outfit costs the same (CLOTHES.price, cash).

CLOTHES = {
    price      = 500,                    -- every outfit (net; VAT "clothing" on top), taken from cash
    key        = "e",                    -- open the outfit list in a changer marker
    blip       = 12,                     -- v_radar blip icon on the entrances
    blipRange  = 300,                    -- blip visible distance (radar)
    markerSize = 1.2,
    markerColor = { 255, 200, 60, 140 },
    statusMs   = 3500,                   -- purchase result shown on the marker label

    -- Marker UI (3D label above the changer markers)
    label = {
        color        = { 255, 200, 60 },
        distance     = 15,
        fullDistance = 5,
        minScale     = 0.6,
        height       = 1.6,              -- above the marker base
    },

    -- Camera while the outfit list is open: in front of the player, looking at them.
    -- side = degrees off the player's facing (turns the camera a little to the side).
    -- The player's position is about hip height (feet ~1 m lower, head ~0.8 m higher), so a
    -- camera ~3.6 m away at hip height with fov 60 frames the whole body.
    camera = {
        distance   = 3.6,
        height     = 0.1,                -- above the player's position
        lookHeight = -0.1,               -- aim slightly under the hips = body centred on screen
        side       = 15,
        fov        = 60,
    },

    -- Shop interiors (template). inside = where the player lands / the exit marker,
    -- changers = skin changer markers (player standing position).
    -- Coordinates from world_interiors/data/stock_interiors.json (CSCHP) + GTA wiki.
    -- changer rot (optional) = the player is turned this way when the outfit list opens.
    -- NOTE: the changer position is not yet verified in-game; check it with /interiors.
    interiors = {
        binco = {
            name     = "Binco",
            inside   = { x = 207.74, y = -111.42, z = 1005.13, rot = 357, interior = 15 },
            changers = {
                -- mirror on the east wall: the player stands with the back to it (faces west)
                { x = 217.80, y = -98.60, z = 1005.26, rot = 90 },
            },
        },
    },

    -- Shop entrances. Each one gets its own fixed inside dimension (world_interiors).
    -- rot = the facing when the player comes back out.
    shops = {
        { id = "binco_ganton",   interior = "binco", dimension = 2101, x = 2244.47,  y = -1665, z = 15.484, rot = 180 },
        { id = "binco_sf",       interior = "binco", dimension = 2102, x = -2375.32, y = 910.293,  z = 45.458, rot = 90 },
        { id = "binco_lv_south", interior = "binco", dimension = 2103, x = 1656.13, y = 1733.25, z = 10.83, rot = 90 },
        { id = "binco_lv_north", interior = "binco", dimension = 2104, x = 2103.19, y = 2257.55, z = 11.02, rot = 270 },
    },

    -- Outfits for sale (civilian ped models; uniforms / work outfits are left out)
    skins = {
        male = {
            7, 14, 15, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 28, 29, 30, 32, 33, 34, 35, 36, 37,
            43, 44, 45, 46, 47, 48, 49, 51, 52, 57, 58, 59, 60, 62, 66, 67, 68, 72, 73, 78, 79, 80,
            81, 82, 83, 84, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109,
            110, 111, 112, 113, 114, 115, 116, 117, 118, 120, 121, 122, 123, 124, 125, 126, 127, 128,
            132, 133, 134, 135, 136, 137, 142, 143, 144, 146, 147, 153, 154, 156, 158, 159, 160, 161,
            162, 168, 170, 173, 174, 175, 176, 177, 180, 181, 182, 183, 184, 185, 186, 187, 188, 200,
            202, 203, 204, 206, 210, 212, 213, 220, 221, 222, 223, 227, 228, 229, 230, 234, 235, 236,
            239, 240, 241, 242, 247, 248, 249, 250, 254, 258, 259, 261, 262, 269, 270, 271, 272, 290,
            291, 292, 293, 294, 296, 297, 299,
        },
        female = {
            9, 10, 11, 12, 13, 31, 38, 39, 40, 41, 53, 54, 55, 56, 63, 64, 69, 75, 76, 77, 85, 87,
            88, 89, 90, 91, 92, 93, 129, 130, 131, 138, 139, 140, 141, 145, 148, 150, 151, 152, 157,
            169, 172, 178, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 201, 207, 214, 215, 216,
            218, 219, 224, 225, 226, 231, 232, 233, 237, 238, 243, 244, 245, 246, 251, 256, 257, 263,
            298,
        },
    },
}

-- shop id -> shop
CLOTHES.shopById = {}
for _, shop in ipairs(CLOTHES.shops) do CLOTHES.shopById[shop.id] = shop end

-- skin -> true lookup of everything for sale
CLOTHES.forSale = {}
for _, list in pairs(CLOTHES.skins) do
    for _, s in ipairs(list) do CLOTHES.forSale[s] = true end
end

--- what an outfit costs with VAT (shown and charged)
function CLOTHES.gross() return VAT.gross("clothing", CLOTHES.price) end
