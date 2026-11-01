if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Crew competencies on the tablet (work_core client exports, ranks of Config.COMPETENCY_WORK):
-- the badge + short code of a player, and which unit types the sign-in crew may choose
-- (Config.UNIT_COMPETENCY; the server checks it again).

Competency = {}

local s = Gfx.s

local function running(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function defs()
    if not running("work_core") then return nil end
    local d = exports.work_core:getCompetencyDefs(Config.COMPETENCY_WORK)
    return type(d) == "table" and d or nil
end

local textures = {}
local function texture(path)
    if not path then return nil end
    if textures[path] == nil then textures[path] = dxCreateTexture(path, "argb", true, "clamp") or false end
    return textures[path] or nil
end

-- -> { short, badge, certs = { short... } } | nil
function Competency.of(player)
    local d = defs()
    if not d or not isElement(player) then return nil end
    local id, _, def = exports.work_core:getPlayerCompetency(player, Config.COMPETENCY_WORK)
    if not id then return nil end
    local certs = {}
    for _, c in ipairs(d.certs or {}) do
        if exports.work_core:hasCompetency(player, Config.COMPETENCY_WORK, c.id) then certs[#certs + 1] = c.short end
    end
    return { short = def and def.short or id, badge = def and def.badge, certs = certs }
end

local function nameOf(id)
    local d = defs()
    for _, list in ipairs({ d and d.ranks or {}, d and d.certs or {} }) do
        for _, x in ipairs(list) do if x.id == id then return x.name end end
    end
    return tostring(id)
end

-- -> true | false, needed competency name
function Competency.crewAllows(members, unitType)
    local need = Config.UNIT_COMPETENCY[unitType]
    -- the work_ems tutorial demo signs in locally: no competency needed there
    if not need or not defs() or (TabletTutorial and TabletTutorial.active) then return true end
    for _, p in ipairs(members) do
        if isElement(p) and exports.work_core:hasCompetency(p, Config.COMPETENCY_WORK, need) then return true end
    end
    return false, nameOf(need)
end

-- Draws the badge, the short code and the cert codes right-aligned to x + w -> width used
function Competency.draw(player, x, y, w, h)
    local c = Competency.of(player)
    if not c then return 0 end
    local font = Gfx.font(8, true)
    local parts = { c.short }
    for _, cert in ipairs(c.certs) do parts[#parts + 1] = cert end
    local label = table.concat(parts, " · ")
    local tw = L.width(label, 1, font) + s(10)
    local tex = texture(c.badge)
    local bh = h - s(8)
    local bw = 0
    if tex then
        local mw, mh = dxGetMaterialSize(tex)
        bw = bh * mw / mh
    end
    local total = tw + (bw > 0 and bw + s(6) or 0)
    local cx = x + w - total
    if tex then dxDrawImage(cx, y + s(4), bw, bh, tex) end
    local lx = cx + (bw > 0 and bw + s(6) or 0)
    Gfx.round(lx, y + (h - s(18)) / 2, tw, s(18), s(9), Theme.panel2)
    Gfx.text(label, lx, y + (h - s(18)) / 2, tw, s(18), Theme.text, font, "center")
    return total
end
