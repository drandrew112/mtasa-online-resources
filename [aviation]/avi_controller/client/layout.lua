-- Client exports for other resources that guide the controller (the work_atc tutorial): where the
-- parts of the scope are on the screen, a screen area the scope leaves alone (the tutorial card) and
-- moving the view.

SCOPE_RECTS = SCOPE_RECTS or {}     -- filled by scope.lua every frame
local blocked                       -- { x, y, w, h } or nil

local function inside(r, x, y)
    return r and x and x >= r[1] and x <= r[1] + r[3] and y >= r[2] and y <= r[2] + r[4]
end

-- is the screen point inside the area set with setScopeBlockedRect?
function scopeBlocked(x, y)
    return inside(blocked, x, y) == true
end

-- rect = { x, y, w, h } (screen px): the scope ignores clicks / the wheel / hover there; nil = none
function setScopeBlockedRect(rect)
    if type(rect) == "table" and tonumber(rect[1]) and tonumber(rect[2]) and tonumber(rect[3]) and tonumber(rect[4]) then
        blocked = { tonumber(rect[1]), tonumber(rect[2]), tonumber(rect[3]), tonumber(rect[4]) }
    else
        blocked = nil
    end
    return true
end

-- centre the view on a world point; scale = px per m (nil = keep, at least `minScale`)
function focusScope(x, y, scale, minScale)
    if not SC.open or not tonumber(x) or not tonumber(y) then return false end
    if tonumber(scale) then VIEW.scale = tonumber(scale) end
    if tonumber(minScale) and VIEW.scale < tonumber(minScale) then VIEW.scale = tonumber(minScale) end
    centerOn(tonumber(x), tonumber(y))
    return true
end

local function copy(r)
    return r and { r[1], r[2], r[3], r[4] } or nil
end

-- Everything as screen rectangles { x, y, w, h }:
--   open, visible, position (id), scale, groundScale (ground traffic shown from this scale on)
--   login     = { rect, rows = { [posId] = rect of its Log in button } }    (nil when closed)
--   topBar, position, runways, tools, listButton, reset, hide, logout, list, scaleBar
--   aircraft  = { [callsign] = { id, label = rect, x, y (target on screen), phase, req, ready, ctl, alert } }
--   menu      = { ac (callsign), mode, rect, items = { { label, rect, disabled, request } } }   (nil when closed)
--   picker    = { ac (callsign), rect, dir }                                                (nil when closed)
function getScopeLayout()
    local out = {
        open = SC.open, visible = SC.visible, position = SC.pos and SC.pos.id or nil,
        scale = VIEW and VIEW.scale or nil, groundScale = CTL.GROUND_MIN_SCALE,
    }
    if LOGIN.open then
        local rows = {}
        for id, r in pairs(LOGIN.rows or {}) do rows[id] = copy(r) end
        out.login = { rect = copy(LOGIN.rect), rows = rows }
    end
    if not SC.visible then return out end
    for key, r in pairs(SCOPE_RECTS) do out[key] = copy(r) end

    out.aircraft = {}
    for id, e in pairs(SC.traffic) do
        local s = e.s
        local x, y = w2s(trafficPos(e))
        out.aircraft[s.cs] = { id = id, label = copy(LABEL_RECTS and LABEL_RECTS[id]), x = x, y = y, phase = s.phase,
            req = s.req, ready = s.ready, ctl = s.ctl, alert = s.alert, gnd = s.gnd }
    end

    local function csOf(id)
        local e = id and SC.traffic[id]
        return e and e.s.cs or nil
    end
    if MENU.open and MENU.rect then
        local items = {}
        for _, b in ipairs(MENU.items or {}) do
            items[#items + 1] = { label = b.item.label, rect = copy(b.rect), disabled = b.item.disabled == true,
                request = b.item.request == true, header = b.item.header == true }
        end
        out.menu = { ac = csOf(MENU.ac), mode = MENU.mode, rect = copy(MENU.rect), items = items }
    end
    if PICK.open and PICK.rect then
        out.picker = { ac = csOf(PICK.ac), rect = copy(PICK.rect), dir = PICK.dir }
    end
    return out
end
