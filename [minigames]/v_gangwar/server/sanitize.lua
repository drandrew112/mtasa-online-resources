-- Validation of what the editor sends (and of rows read from the database). Never trusts the client:
-- unknown fields are dropped, numbers clamped, strings cut.

Sanitize = {}

local LIM = GW.LIMITS

local function num(v, default)
    v = tonumber(v)
    if not v or v ~= v or v == math.huge or v == -math.huge then return default end
    return v
end

local function int(v, default, range)
    v = num(v, default)
    if v == nil then return nil end
    v = math.floor(v + 0.5)
    if range then v = math.max(range[1], math.min(range[2], v)) end
    return v
end

local function str(v, max, default)
    v = type(v) == "string" and v:gsub("[%c]", ""):gsub("^%s+", ""):gsub("%s+$", "") or ""
    if v == "" then return default end
    return v:sub(1, max)
end

local function point(p)
    if type(p) ~= "table" then return nil end
    local x, y, z = num(p[1] or p.x), num(p[2] or p.y), num(p[3] or p.z)
    if not x or not y or not z then return nil end
    return { x, y, z }
end

function Sanitize.attacker(a)
    if type(a) ~= "table" then return nil end
    local x, y, z = num(a.x), num(a.y), num(a.z)
    if not x or not y or not z then return nil end
    local D = GW.ATTACKER
    local weapon = int(a.weapon, D.weapon)
    if weapon ~= 0 and not GW.isPedWeapon(weapon) then weapon = D.weapon end
    local out = {
        skin = int(a.skin, D.skin, { 0, 312 }),
        x = x, y = y, z = z, rot = num(a.rot, 0) % 360,
        weapon = weapon, ammo = int(a.ammo, D.ammo, LIM.ammo),
        health = int(a.health, D.health, LIM.health), armor = int(a.armor, D.armor, LIM.armor),
        accuracy = math.max(0, math.min(1, num(a.accuracy, D.accuracy))),
        aggro = int(a.aggro, D.aggro, LIM.aggro),
        task = a.task == "patrol" and "patrol" or "guard",
        speed = (a.speed == "run" or a.speed == "sprint") and a.speed or "walk",
    }
    local wait = type(a.wait) == "table" and a.wait or D.wait
    local w1, w2 = int(wait[1], D.wait[1], LIM.wait), int(wait[2], D.wait[2], LIM.wait)
    out.wait = { math.min(w1, w2), math.max(w1, w2) }
    out.patrol = {}
    if type(a.patrol) == "table" then
        for _, p in ipairs(a.patrol) do
            local pt = point(p)
            if pt and #out.patrol < LIM.patrol then out.patrol[#out.patrol + 1] = pt end
        end
    end
    -- a patrol needs a route: fewer than 2 points stays a guard
    if out.task == "patrol" and #out.patrol < 2 then out.task = "guard" end
    return out
end

function Sanitize.attackers(list)
    local out = {}
    if type(list) ~= "table" then return out end
    for _, a in ipairs(list) do
        local clean = Sanitize.attacker(a)
        if clean and #out < LIM.attackers then out[#out + 1] = clean end
    end
    return out
end

local function days(v)
    local seen, out = {}, {}
    for d in tostring(v or ""):gmatch("[1-7]") do
        if not seen[d] then
            seen[d] = true
            out[#out + 1] = d
        end
    end
    table.sort(out)
    return table.concat(out)
end

-- doc from the editor -> clean gang war table | nil, error key
function Sanitize.doc(doc)
    if type(doc) ~= "table" then return nil, "bad_doc" end
    local D = GW.DEFAULTS
    local x, y, z = num(doc.x), num(doc.y), num(doc.z)
    if not x or not y or not z then return nil, "bad_position" end
    local gw = {
        id = int(doc.id),
        name = str(doc.name, LIM.name, D.name),
        gang = str(doc.gang, LIM.gang, D.gang):gsub("[^%w_%-]", "_"),
        enabled = doc.enabled ~= false,
        x = x, y = y, z = z,
        interior = int(doc.interior, 0, { 0, 255 }), dimension = int(doc.dimension, 0, { 0, 65535 }),
        trigger_radius = num(doc.trigger_radius, D.trigger_radius),
        zone_radius = num(doc.zone_radius, D.zone_radius),
        release_radius = num(doc.release_radius, D.release_radius),
        reward_money = int(doc.reward_money, D.reward_money, LIM.money),
        reward_xp = int(doc.reward_xp, D.reward_xp, LIM.xp),
        days = days(doc.days == nil and D.days or doc.days),
        hour_from = int(doc.hour_from, 0, { 0, 24 }), hour_to = int(doc.hour_to, 24, { 0, 24 }),
        attackers = Sanitize.attackers(doc.attackers),
    }
    gw.zone_radius = GW.clamp(gw.zone_radius, LIM.radius)
    -- the zone sits inside the trigger area, which sits inside the release area
    gw.trigger_radius = math.max(gw.zone_radius, GW.clamp(gw.trigger_radius, LIM.radius))
    gw.release_radius = math.max(gw.trigger_radius + 10, GW.clamp(gw.release_radius, LIM.radius))
    if gw.days == "" then return nil, "no_days" end
    return gw
end
