-- Lookup tables built from shared/database.lua (generated) + settings shared by both sides.
--
-- Animation id = "<group command>_<n>", e.g. "sit_1". /sit plays sit_1, /sit 3 plays sit_3.
-- Group labels: v_locals "v_anims.group.<cmd>", category labels "v_anims.cat.<id>".

ANIMS = {
    MAX_FAVS     = 8,
    ACC_KEY      = "anims.favourites", -- accData: JSON array of animation ids (wheel order)
    DATA_CURRENT = "v_anims.cur",      -- element data (synced): id of the playing animation
    BLEND        = 250,                -- ms blend between animations
    -- element data of other systems that forbid animations while true / set
    BLOCK_DATA   = { "pol.cuffed", "wp.stunned", "medfx.anim" },

    byId   = {},  -- id -> anim
    groups = {},  -- cmd -> group
    order  = {},  -- every anim in database order
    cats   = {},  -- category id -> { group, ... }
}

for gi, g in ipairs(ANIM_GROUPS) do
    local group = { cmd = g.cmd, cat = g.cat, index = gi, anims = {} }
    ANIMS.groups[g.cmd] = group
    ANIMS.cats[g.cat] = ANIMS.cats[g.cat] or {}
    table.insert(ANIMS.cats[g.cat], group)
    for n, e in ipairs(g.anims) do
        local a = {
            id = g.cmd .. "_" .. n, cmd = g.cmd, n = n, cat = g.cat,
            block = e[1], name = e[2],
            loop = e[3]:find("l") ~= nil, hold = e[3]:find("h") ~= nil, move = e[3]:find("m") ~= nil,
            intro = e[4] or nil, outro = e[5] or nil, ms = e[6],
        }
        group.anims[n] = a
        ANIMS.byId[a.id] = a
        ANIMS.order[#ANIMS.order + 1] = a
    end
end

-- /sit 2 -> "sit_2"; "sit" -> "sit_1"; "sit_2" -> "sit_2"
function ANIMS.resolve(cmdOrId, n)
    if type(cmdOrId) ~= "string" then return nil end
    cmdOrId = cmdOrId:lower()
    if ANIMS.byId[cmdOrId] then return ANIMS.byId[cmdOrId] end
    local g = ANIMS.groups[cmdOrId]
    if not g then return nil end
    return g.anims[math.floor(tonumber(n) or 1)]
end

-- the ped plays one of the animation's parts (intro / main / outro)
function ANIMS.matches(a, block, name)
    if not (a and block and name) then return false end
    block, name = block:lower(), name:lower()
    local function eq(b, n) return b:lower() == block and n:lower() == name end
    return eq(a.block, a.name) or (a.intro and eq(a.intro[1], a.intro[2])) or (a.outro and eq(a.outro[1], a.outro[2])) or false
end

-- favourites list check: known ids, no duplicates, at most MAX_FAVS
function ANIMS.cleanFavs(list)
    local out, seen = {}, {}
    if type(list) ~= "table" then return out end
    for _, id in ipairs(list) do
        if type(id) == "string" and ANIMS.byId[id] and not seen[id] and #out < ANIMS.MAX_FAVS then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    return out
end
