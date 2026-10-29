if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Marker UI: the 3D cards above the markers of every resource (work duty, hospital bays,
-- interiors, shops, depots ...), drawn here in one place. Resources register them through the
-- server or the client exports. A proximity timer finds the cards within their radius; the
-- single onClientRender is attached only while there is at least one. Server meta (per player
-- fields) is asked for only while a card is in range (server/markers.lua).
--
-- Card fields (def, meta and local meta use the same names; meta overrides def, local meta
-- overrides both). Every text may be a string or a v_locals message object (L.msg).
--   type        style preset (MARKER_TYPES): colour, icon, image
--   icon        letters on the icon tile ("cross" = medical cross); default: type icon or the
--               first letter of name
--   image       ":resource/path.png" drawn on the icon tile instead of the letters
--   color       { r, g, b }
--   name        small coloured line (upper case), e.g. company / work / hospital name
--   title       big white line
--   hint        bottom line; hintActive replaces it while the player is inside the marker
--   element     follow this element (position, interior, dimension); or x, y, z, interior,
--               dimension (-1 = every dimension)
--   radius      draw (and stream) distance, fullRadius full-size distance, minScale, height
--               (label above the marker point), size (marker diameter for the inside check;
--               default: getMarkerSize of a marker element)
--   los         false = no line of sight check
--   hidden      true = not drawn (still streamed, so meta can reveal it)
--   work        work_core work id: drawn only while the local player is on duty in it
--   pinned      true = drawn at the bottom of the screen (a menu of the marker is open)
--   level, levelName, xp, xpFrom, xpTo     level box above the card (work markers)
--   progress    { duration = ms, remaining = ms, text = "" } progress bar in the card
--
-- Client exports: createMarkerUI(id, def), updateMarkerUI(id, fields), removeMarkerUI(id),
--   setMarkerUIMeta(id, meta | nil)  (local layer, also on cards the own server side made)
--   setMarkerUIsHidden(bool)         (hides every card of the calling resource)
--   isMarkerUIInside(id) -> bool
-- Client events on the owner's resourceRoot: onClientMarkerUIStreamIn / StreamOut (id),
--   onClientMarkerUIHit / onClientMarkerUILeave (id) (player inside the marker size)

local sw, sh = guiGetScreenSize()
local function s(v) return v * sh / 1080 end

local TICK = 200                -- ms, proximity check
local HYSTERESIS = 2            -- metres: stream out only this far beyond the radius
local FADE_MS = 150
local DEFAULTS = { radius = 25, fullRadius = 8, minScale = 0.55, height = 1.25 }

local BLUE, RED, GREEN, YELLOW, WHITE = { 56, 132, 244 }, { 218, 54, 51 }, { 46, 160, 67 }, { 230, 190, 40 }, { 255, 255, 255 }

-- Style presets. image = ":ui_core/client/images/markers/<type>.png" later.
MARKER_TYPES = {
    default         = { color = YELLOW },
    work_duty       = { color = BLUE },
    work_veh        = { color = BLUE, icon = "V" },
    hosp_ambu       = { color = YELLOW, icon = "P" },
    hosp_heli       = { color = YELLOW, icon = "H" },
    hosp_handover   = { color = BLUE, icon = "cross" },
    hosp_heal       = { color = GREEN, icon = "cross" },
    hosp_restricted = { color = RED, icon = "!" },
    rw_depot        = { color = { 80, 160, 255 }, icon = "D" },
    int_enter       = { color = WHITE, icon = "»" },
    int_exit        = { color = WHITE, icon = "«" },
    biz_enter       = { color = WHITE, icon = "€" },
    biz_exit        = { color = WHITE, icon = "«" },
    shop_clothes    = { color = { 200, 120, 220 } },
    shop_weapon     = { color = RED },
    job_race        = { color = BLUE, icon = "R" },
    job_dm          = { color = RED, icon = "DM" },
    job             = { color = YELLOW, icon = "J" },
    timetrial       = { color = { 255, 150, 40 }, icon = "T" },
    atc             = { color = { 70, 130, 210 }, icon = "ATC" },
    inv_port        = { color = YELLOW, icon = "P" },
    warning         = { color = RED, icon = "!" },
}

local TEXTS = { "name", "title", "hint", "hintActive", "levelName", "icon" }

local entries = {}       -- key -> entry
local near = {}          -- entries within their radius (drawn)
local hiddenOwners = {}  -- resource name -> true
local rendering = false
local streamIn, streamOut = {}, {} -- server keys to report

---------------------------------------------------------------- entries

local function ownerRoot(owner)
    local res = getResourceFromName(owner)
    return res and getResourceRootElement(res) or nil
end

local function fire(e, name)
    local r = ownerRoot(e.owner)
    if r then triggerEvent(name, r, e.id) end
end

-- the merged, resolved fields the renderer reads
local function build(e)
    local v = {}
    for k, x in pairs(e.def) do v[k] = x end
    if e.smeta then for k, x in pairs(e.smeta) do v[k] = x end end
    if e.lmeta then for k, x in pairs(e.lmeta) do v[k] = x end end
    local t = MARKER_TYPES[v.type] or MARKER_TYPES.default
    for _, f in ipairs(TEXTS) do
        if type(v[f]) == "table" then v[f] = L.resolve(v[f]) end
        if v[f] ~= nil then v[f] = tostring(v[f]) end
    end
    v.name, v.title, v.hint = v.name or "", v.title or "", v.hint or ""
    v.nameUp = L.upper(v.name)
    v.color = type(v.color) == "table" and v.color or t.color
    v.image = v.image or t.image
    v.icon = v.icon or t.icon or (v.name ~= "" and L.upper(L.sub(v.name, 1, 1))) or "?"
    for k, d in pairs(DEFAULTS) do v[k] = tonumber(v[k]) or d end
    e.v = v
end

local function updateRender()
    local want = #near > 0
    if want == rendering then return end
    rendering = want
    if want then
        addEventHandler("onClientRender", root, MarkerUIRender, true, "high+5")
    else
        removeEventHandler("onClientRender", root, MarkerUIRender)
    end
end

local function setNear(e, isNear)
    if e.near == isNear then return end
    e.near = isNear
    if isNear then
        e.fade = 0
        near[#near + 1] = e
        if e.server then streamIn[#streamIn + 1] = e.key end
        fire(e, "onClientMarkerUIStreamIn")
    else
        for i = #near, 1, -1 do
            if near[i] == e then table.remove(near, i) end
        end
        if e.inside then e.inside = false; fire(e, "onClientMarkerUILeave") end
        if e.server then
            e.smeta = nil -- the server sends it again on the next stream in
            build(e)
            streamOut[#streamOut + 1] = e.key
        end
        fire(e, "onClientMarkerUIStreamOut")
    end
end

local function add(key, owner, id, def, server)
    local old = entries[key]
    if old then setNear(old, false) end
    local e = { key = key, owner = owner, id = id, def = def, server = server,
                lmeta = old and old.lmeta or nil, near = false, inside = false, fade = 0 }
    entries[key] = e
    build(e)
    updateRender()
end

local function del(key)
    local e = entries[key]
    if not e then return end
    setNear(e, false)
    entries[key] = nil
    updateRender()
end

-- position / world of the entry -> false when it has none right now
local function locate(e)
    local d = e.def
    if d.element then
        if not isElement(d.element) then return false end
        e.x, e.y, e.z = getElementPosition(d.element)
        e.int, e.dim = getElementInterior(d.element), getElementDimension(d.element)
        e.size = tonumber(e.v.size) or (getElementType(d.element) == "marker" and getMarkerSize(d.element)) or nil
    else
        e.x, e.y, e.z = tonumber(d.x), tonumber(d.y), tonumber(d.z)
        if not e.x then return false end
        e.int, e.dim = tonumber(d.interior) or 0, tonumber(d.dimension) or 0
        e.size = tonumber(e.v.size)
    end
    return true
end

local function tick()
    local px, py, pz = getElementPosition(localPlayer)
    local int, dim = getElementInterior(localPlayer), getElementDimension(localPlayer)
    for _, e in pairs(entries) do
        local isNear = false
        if locate(e) and e.int == int and (e.dim == dim or e.dim == -1) then
            local reach = e.v.radius + (e.near and HYSTERESIS or 0)
            isNear = getDistanceBetweenPoints3D(px, py, pz, e.x, e.y, e.z) <= reach
        end
        setNear(e, isNear)
    end
    if #streamIn > 0 or #streamOut > 0 then
        triggerServerEvent("ui_core:mk:stream", resourceRoot, streamIn, streamOut)
        streamIn, streamOut = {}, {}
    end
    updateRender()
end

---------------------------------------------------------------- drawing

local fonts = {}
local function font(size, bold)
    local key = size .. (bold and "b" or "")
    if fonts[key] == nil then
        fonts[key] = dxCreateFont(bold and "client/fonts/RobotoB.ttf" or "client/fonts/Roboto.ttf", s(size), false, "antialiased")
            or (bold and "default-bold" or "default")
    end
    return fonts[key]
end

local function rgb(c, a) return tocolor(c[1], c[2], c[3], a or 255) end

local function round(x, y, w, h, r, color)
    r = math.min(r, w / 2, h / 2)
    if r < 1 then return dxDrawRectangle(x, y, w, h, color) end
    dxDrawRectangle(x + r, y, w - 2 * r, h, color)
    dxDrawRectangle(x, y + r, r, h - 2 * r, color)
    dxDrawRectangle(x + w - r, y + r, r, h - 2 * r, color)
    dxDrawCircle(x + r, y + r, r, 180, 270, color, color, 12)
    dxDrawCircle(x + w - r, y + r, r, 270, 360, color, color, 12)
    dxDrawCircle(x + r, y + h - r, r, 90, 180, color, color, 12)
    dxDrawCircle(x + w - r, y + h - r, r, 0, 90, color, color, 12)
end

local function cross(x, y, size, color)
    local t = size / 3
    dxDrawRectangle(x + t, y, t, size, color)
    dxDrawRectangle(x, y + t, size, t, color)
end

-- sx, sy = bottom centre of the card; stem = pointer under it
local function drawCard(sx, sy, k, a, v, inside, stem)
    local color = v.color
    local fTitle, fName, fHint = font(13, true), font(9, true), font(9, inside)
    local hint = inside and v.hintActive or v.hint

    local pad, iconSize, gap = s(10) * k, s(34) * k, s(10) * k
    local textW = math.max(L.width(v.title, k, fTitle), L.width(v.nameUp, k, fName), L.width(hint, k, fHint))
    local w = pad + iconSize + gap + textW + pad * 1.4

    local prog = v.progress
    local fLv, fXp, lvLeft, lvRight
    if v.level then
        fLv, fXp = font(10, true), font(9)
        lvLeft = v.levelName and L("ui_core.markers.level_named", { level = v.level, name = L.upper(v.levelName) })
            or L("ui_core.markers.level", { level = v.level })
        lvRight = v.xpTo and L("ui_core.markers.xp", { xp = v.xp or 0, to = v.xpTo })
            or L("ui_core.markers.max_xp", { xp = v.xp or 0 })
        w = math.max(w, pad * 2 + L.width(lvLeft, k, fLv) + s(16) * k + L.width(lvRight, k, fXp))
    end

    local headH, hintH = s(46) * k, hint ~= "" and s(22) * k or s(6) * k
    local progH = prog and s(30) * k or 0
    local h = headH + hintH + progH
    local x, y = sx - w / 2, sy - h

    round(x, y, w, h, s(7) * k, tocolor(14, 17, 21, 220 * a))
    round(x, y + h - s(3) * k, w, s(3) * k, s(1.5) * k, rgb(color, 235 * a))

    -- icon tile
    local ix, iy = x + pad, y + (headH - iconSize) / 2 + s(2) * k
    round(ix, iy, iconSize, iconSize, s(5) * k, rgb(color, 240 * a))
    if v.image then
        local m = iconSize * 0.15
        dxDrawImage(ix + m, iy + m, iconSize - m * 2, iconSize - m * 2, v.image, 0, 0, 0, tocolor(255, 255, 255, 255 * a))
    elseif v.icon == "cross" then
        local c = iconSize * 0.62
        cross(ix + (iconSize - c) / 2, iy + (iconSize - c) / 2, c, tocolor(255, 255, 255, 255 * a))
    else
        local len = L.len(v.icon)
        local fIcon = font(len > 2 and 10 or len > 1 and 12 or 16, true)
        -- dark letters on light tiles (yellow / white)
        local light = color[1] * 0.299 + color[2] * 0.587 + color[3] * 0.114 > 170
        dxDrawText(v.icon, ix, iy, ix + iconSize, iy + iconSize,
            light and tocolor(20, 20, 20, 255 * a) or tocolor(255, 255, 255, 255 * a), k, fIcon, "center", "center")
    end

    local tx = ix + iconSize + gap
    dxDrawText(v.nameUp, tx, y + s(6) * k, tx + textW, y + headH * 0.45, rgb(color, 255 * a), k, fName, "left", "center")
    dxDrawText(v.title, tx, y + headH * 0.42, tx + textW, y + headH, tocolor(255, 255, 255, 255 * a), k, fTitle, "left", "center")

    local hy = y + headH
    if hint ~= "" then
        local hc = inside and tocolor(255, 255, 255, 255 * a) or tocolor(200, 205, 212, 220 * a)
        dxDrawText(hint, x + pad, hy, x + w - pad, hy + hintH, hc, k, fHint, "left", "center")
    end

    if prog then
        local py = hy + hintH
        local bx, bw, bh = x + pad, w - pad * 2, s(8) * k
        local dur = math.max(1, tonumber(prog.duration) or 1)
        local left = math.max(0, (prog.endTick or 0) - getTickCount())
        local f = 1 - math.min(1, left / dur)
        dxDrawText(tostring(prog.text or ""), bx, py, bx + bw, py + s(14) * k, tocolor(255, 255, 255, 240 * a), k, fHint, "left", "center")
        dxDrawText(L("ui_core.markers.seconds", { left = math.ceil(left / 1000) }), bx, py, bx + bw, py + s(14) * k,
            rgb(color, 255 * a), k, font(9, true), "right", "center")
        local by = py + s(16) * k
        round(bx, by, bw, bh, bh / 2, tocolor(255, 255, 255, 40 * a))
        if f > 0 then round(bx, by, math.max(bh, bw * f), bh, bh / 2, rgb(color, 255 * a)) end
    end

    if stem then
        dxDrawRectangle(sx - s(1) * k, y + h, s(2) * k, s(10) * k, tocolor(14, 17, 21, 220 * a))
    end

    if v.level then
        local bh, bgap = s(44) * k, s(5) * k
        local by = y - bgap - bh
        round(x, by, w, bh, s(7) * k, tocolor(14, 17, 21, 220 * a))
        local rowH = s(26) * k
        dxDrawText(lvLeft, x + pad, by, x + w - pad, by + rowH, rgb(color, 255 * a), k, fLv, "left", "center")
        dxDrawText(lvRight, x + pad, by, x + w - pad, by + rowH, tocolor(200, 205, 212, 230 * a), k, fXp, "right", "center")
        local barX, barY, barW, barH = x + pad, by + rowH + s(1) * k, w - pad * 2, s(6) * k
        round(barX, barY, barW, barH, barH / 2, tocolor(255, 255, 255, 38 * a))
        local frac = 1
        if v.xpTo then
            local from = tonumber(v.xpFrom) or 0
            frac = math.min(1, math.max(0, ((v.xp or 0) - from) / math.max(1, v.xpTo - from)))
        end
        if frac > 0 then round(barX, barY, math.max(barH, barW * frac), barH, barH / 2, rgb(color, 240 * a)) end
    end
end

local lastFrame = getTickCount()
local function byDistance(a, b) return a.dist > b.dist end -- far first, the nearest on top

function MarkerUIRender()
    local now = getTickCount()
    local step = math.min(1, (now - lastFrame) / FADE_MS)
    lastFrame = now
    if isPlayerMapVisible() then return end

    local cx, cy, cz = getCameraMatrix()
    local px, py, pz = getElementPosition(localPlayer)
    local veh = getPedOccupiedVehicle(localPlayer)
    local ex, ey, ez = getElementPosition(veh or localPlayer)
    local myWork = getElementData(localPlayer, "work.id")   -- work_core WORK_DATA.PLAYER_WORK

    for _, e in ipairs(near) do e.dist = getDistanceBetweenPoints3D(px, py, pz, e.x, e.y, e.z) end
    table.sort(near, byDistance)

    for _, e in ipairs(near) do
        local v = e.v
        local inside = e.size and getDistanceBetweenPoints2D(ex, ey, e.x, e.y) <= e.size / 2 + 0.5
            and ez >= e.z - 1 and ez <= e.z + 3 or false
        if inside ~= e.inside then
            e.inside = inside
            fire(e, inside and "onClientMarkerUIHit" or "onClientMarkerUILeave")
        end

        if v.pinned and not v.hidden and not hiddenOwners[e.owner] and (not v.work or v.work == myWork) then
            drawCard(sw / 2, sh - s(60), 1, 1, v, inside, false)
        else
            local lz = e.z + v.height
            local show = not v.hidden and not hiddenOwners[e.owner] and e.dist <= v.radius
                and (not v.work or v.work == myWork)
            if show and v.los ~= false then
                show = isLineOfSightClear(cx, cy, cz, e.x, e.y, lz, true, false, false, true, false, false, false, veh or localPlayer)
            end
            e.fade = show and math.min(1, e.fade + step) or math.max(0, e.fade - step)
            if e.fade > 0 then
                local sx, sy = getScreenFromWorldPosition(e.x, e.y, lz, 0.1)
                if sx then
                    local k = 1
                    if e.dist > v.fullRadius then
                        k = 1 - (e.dist - v.fullRadius) / math.max(0.1, v.radius - v.fullRadius) * (1 - v.minScale)
                    end
                    local a = e.fade
                    if e.dist > v.radius * 0.8 then a = a * math.max(0, (v.radius - e.dist) / (v.radius * 0.2)) end
                    drawCard(sx, sy, math.max(v.minScale, k), a, v, inside, true)
                end
            end
        end
    end
end

---------------------------------------------------------------- exports

local function caller()
    return sourceResource and getResourceName(sourceResource) or getResourceName(resource)
end

local function copy(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

-- progress bars count from the moment the meta arrives
local function stampProgress(m)
    if type(m) == "table" and type(m.progress) == "table" and not m.progress.endTick then
        local p = copy(m.progress)
        p.endTick = getTickCount() + (tonumber(p.remaining) or tonumber(p.duration) or 0)
        if type(p.text) == "table" then p.text = L.resolve(p.text) end
        m.progress = p
    end
    return m
end

function createMarkerUI(id, def)
    if id == nil or type(def) ~= "table" then return false end
    if not def.element and not (tonumber(def.x) and tonumber(def.y) and tonumber(def.z)) then return false end
    local owner = caller()
    add(owner .. "/" .. tostring(id), owner, id, copy(def), false)
    return true
end

function updateMarkerUI(id, fields)
    local e = entries[caller() .. "/" .. tostring(id)]
    if not e or type(fields) ~= "table" then return false end
    for k, v in pairs(fields) do
        if v == false and k ~= "hidden" and k ~= "los" then v = nil end
        e.def[k] = v
    end
    build(e)
    return true
end

function removeMarkerUI(id)
    local key = caller() .. "/" .. tostring(id)
    local e = entries[key]
    if not e or e.server then return false end
    del(key)
    return true
end

function setMarkerUIMeta(id, meta)
    local e = entries[caller() .. "/" .. tostring(id)]
    if not e then return false end
    e.lmeta = type(meta) == "table" and stampProgress(copy(meta)) or nil
    build(e)
    return true
end

function setMarkerUIsHidden(hidden)
    hiddenOwners[caller()] = hidden and true or nil
    return true
end

function isMarkerUIInside(id)
    local e = entries[caller() .. "/" .. tostring(id)]
    return e and e.inside or false
end

---------------------------------------------------------------- server sync

addEvent("ui_core:mk:ops", true)
addEventHandler("ui_core:mk:ops", resourceRoot, function(ops)
    if type(ops) ~= "table" then return end
    for _, op in ipairs(ops) do
        local kind, key, data = op[1], op[2], op[3]
        local owner, id = tostring(key):match("^([^/]+)/(.*)$")
        if kind == "set" and owner and type(data) == "table" then
            add(key, owner, id, data, true)
        elseif kind == "upd" and entries[key] and type(data) == "table" then
            local e = entries[key]
            for k, v in pairs(data) do
                if v == false and k ~= "hidden" and k ~= "los" then v = nil end
                e.def[k] = v
            end
            build(e)
        elseif kind == "del" then
            del(key)
        end
    end
end)

addEvent("ui_core:mk:meta", true)
addEventHandler("ui_core:mk:meta", resourceRoot, function(key, meta)
    local e = entries[key]
    if not e or not e.near then return end
    e.smeta = type(meta) == "table" and stampProgress(meta) or nil
    build(e)
end)

-- client-made cards of a stopped resource
addEventHandler("onClientResourceStop", root, function(res)
    local name = getResourceName(res)
    hiddenOwners[name] = nil
    for key, e in pairs(entries) do
        if e.owner == name and not e.server then del(key) end
    end
end)

addEvent("onClientMarkerUIStreamIn")
addEvent("onClientMarkerUIStreamOut")
addEvent("onClientMarkerUIHit")
addEvent("onClientMarkerUILeave")
addEvent("onClientMarkerUISystemStart")

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("ui_core:mk:ready", resourceRoot)
    setTimer(tick, TICK, 0)
    triggerEvent("onClientMarkerUISystemStart", root)
end)

L.onChange(function()
    for _, e in pairs(entries) do build(e) end
end)
