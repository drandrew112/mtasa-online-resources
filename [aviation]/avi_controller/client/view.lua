-- Map view: world centre + scale (screen px per world metre). North (+y) is up.

VIEW = { x = 0, y = 0, scale = 0.15 }
local MIN_SCALE, MAX_SCALE = 0.03, 6

function w2s(x, y)
    return SC.sx / 2 + (x - VIEW.x) * VIEW.scale, SC.sy / 2 - (y - VIEW.y) * VIEW.scale
end

function s2w(px, py)
    return VIEW.x + (px - SC.sx / 2) / VIEW.scale, VIEW.y - (py - SC.sy / 2) / VIEW.scale
end

local function fitBox(minx, miny, maxx, maxy, margin)
    margin = margin or 1.1
    VIEW.x, VIEW.y = (minx + maxx) / 2, (miny + maxy) / 2
    local w, h = math.max(50, maxx - minx) * margin, math.max(50, maxy - miny) * margin
    local usableW = SC.sx - (SC.showList and LIST_W or 0)
    VIEW.scale = math.max(MIN_SCALE, math.min(MAX_SCALE, math.min(usableW / w, (SC.sy - 60 * U) / h)))
    -- keep the box centred in the area left of the traffic list
    if SC.showList then VIEW.x = VIEW.x + (LIST_W / 2) / VIEW.scale end
end

local function polyBox(poly, box)
    for _, p in ipairs(poly) do
        box[1], box[2] = math.min(box[1], p[1]), math.min(box[2], p[2])
        box[3], box[4] = math.max(box[3], p[1]), math.max(box[4], p[2])
    end
    return box
end

-- default view of the logged-in position: CTR = whole CTA, APP = its TMA, TWR = the airfield
function resetView()
    if not SC.pos or not SC.data then return end
    local box = { math.huge, math.huge, -math.huge, -math.huge }
    local p = SC.pos
    if p.type == "TWR" then
        local a = airportOf(p.airport)
        if a then
            for _, rw in ipairs(a.runways or {}) do
                for _, e in ipairs(rw.ends or {}) do polyBox({ { e.x, e.y } }, box) end
            end
            for _, g in ipairs(a.gates or {}) do polyBox({ { g.x, g.y } }, box) end
            box = { box[1] - 150, box[2] - 150, box[3] + 150, box[4] + 150 }
        end
    else
        local want = p.type == "APP" and (p.airport .. "_TMA") or nil
        for _, a in ipairs(SC.data.airspaces or {}) do
            if (want and a.id == want) or (not want and a.type == "CTA") then polyBox(a.polygon, box) end
        end
    end
    if box[1] == math.huge then box = { -3500, -3500, 3500, 3500 } end
    fitBox(box[1], box[2], box[3], box[4], 1.08)
end

function zoomAt(px, py, factor)
    local wx, wy = s2w(px, py)
    VIEW.scale = math.max(MIN_SCALE, math.min(MAX_SCALE, VIEW.scale * factor))
    -- keep the world point under the cursor
    VIEW.x = wx - (px - SC.sx / 2) / VIEW.scale
    VIEW.y = wy + (py - SC.sy / 2) / VIEW.scale
end

function panBy(dx, dy)
    VIEW.x = VIEW.x - dx / VIEW.scale
    VIEW.y = VIEW.y + dy / VIEW.scale
end

function centerOn(x, y)
    VIEW.x, VIEW.y = x, y
    if SC.showList then VIEW.x = VIEW.x + (LIST_W / 2) / VIEW.scale end
end

-- a "nice" distance for the scale bar, in nautical miles
function scaleBarLength()
    local target = 140 * U / VIEW.scale / M_PER_NM
    local best = 0.05
    for _, v in ipairs({ 0.02, 0.05, 0.1, 0.25, 0.5, 1, 2, 5 }) do
        if v <= target then best = v end
    end
    return best
end
