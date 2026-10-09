-- Mirrors Editor.doc into client-side elements (only the editor sees them) and
-- draws the editor overlay: numbers, route lines, selection boxes.
--
-- An item is { element, kind, ref, index, list } where `ref` is the doc table it
-- shows (an object entry, a {x,y,z,rot} spawn, a {x,y,z,size} checkpoint ...).

View = { byElement = {}, groups = {}, helpersVisible = true }

local H = CREATOR.HELPER
local HIDDEN_DIMENSION = 65000

--------------------------------------------------------------------------------
-- kinds: how a doc entry becomes an element and how its position is read / written
--------------------------------------------------------------------------------

Kinds = {}

Kinds.object = {
    label = "Object",
    create = function(ref)
        local el = createObject(ref.model, ref.x, ref.y, ref.z, ref.rx or 0, ref.ry or 0, ref.rz or 0)
        return el
    end,
    apply = function(el, ref)
        setElementPosition(el, ref.x, ref.y, ref.z)
        setElementRotation(el, ref.rx or 0, ref.ry or 0, ref.rz or 0)
        setObjectScale(el, ref.scale or 1)
        setElementAlpha(el, ref.alpha or 255)
        setElementCollisionsEnabled(el, ref.collisions ~= false)
        setElementDoubleSided(el, ref.doublesided == true)
    end,
    model = function(ref) return ref.model end,
    get = function(ref) return ref.x, ref.y, ref.z, ref.rx or 0, ref.ry or 0, ref.rz or 0 end,
    set = function(ref, x, y, z, rx, ry, rz)
        ref.x, ref.y, ref.z = x, y, z
        ref.rx, ref.ry, ref.rz = rx ~= 0 and rx or nil, ry ~= 0 and ry or nil, rz ~= 0 and rz or nil
    end,
    rotate = "xyz",
}

local function spawnModel()
    local doc = Editor.doc
    if doc and doc.type == "race" then return doc.race.vehicles[1] or 411 end
    return getElementModel(localPlayer)
end

Kinds.spawn = {
    label = "Spawnpoint",
    helper = true,
    create = function(ref)
        if Editor.doc.type == "race" then
            return createVehicle(spawnModel(), ref[1], ref[2], ref[3], 0, 0, ref[4] or 0)
        end
        return createPed(spawnModel(), ref[1], ref[2], ref[3], ref[4] or 0)
    end,
    apply = function(el, ref)
        setElementPosition(el, ref[1], ref[2], ref[3])
        setElementRotation(el, 0, 0, ref[4] or 0)
        if getElementType(el) == "ped" then setPedRotation(el, ref[4] or 0) end
    end,
    model = function() return spawnModel() end,
    get = function(ref) return ref[1], ref[2], ref[3], 0, 0, ref[4] or 0 end,
    set = function(ref, x, y, z, _, _, rz) ref[1], ref[2], ref[3], ref[4] = x, y, z, rz % 360 end,
    rotate = "z",
}

-- markerColor: the item also shows the real checkpoint marker (item.extra)
local function pointKind(label, helperModel, markerColor)
    return {
        label = label,
        helper = true,
        create = function(ref) return createObject(helperModel, ref[1], ref[2], ref[3]) end,
        extra = markerColor and function(ref)
            return createMarker(ref[1], ref[2], ref[3], "checkpoint", ref[4] or 5, markerColor[1], markerColor[2], markerColor[3], 110)
        end,
        apply = function(el, ref, extra)
            setElementPosition(el, ref[1], ref[2], ref[3])
            if isElement(extra) then
                setElementPosition(extra, ref[1], ref[2], ref[3])
                setMarkerSize(extra, ref[4] or 5)
            end
        end,
        model = function() return helperModel end,
        get = function(ref) return ref[1], ref[2], ref[3], 0, 0, 0 end,
        set = function(ref, x, y, z) ref[1], ref[2], ref[3] = x, y, z end,
    }
end

Kinds.checkpoint = pointKind("Checkpoint", H.checkpoint, { 255, 200, 0 })
Kinds.finish = pointKind("Finish", H.finish, { 255, 70, 70 })
Kinds.marker = pointKind("Job marker", H.marker)
Kinds.camera = {
    label = "Finish camera",
    helper = true,
    create = function(ref) return createObject(H.camera, ref.pos[1], ref.pos[2], ref.pos[3]) end,
    apply = function(el, ref)
        setElementPosition(el, ref.pos[1], ref.pos[2], ref.pos[3])
        local dx, dy = ref.lookAt[1] - ref.pos[1], ref.lookAt[2] - ref.pos[2]
        setElementRotation(el, 0, 0, math.deg(math.atan2(dy, dx)) - 90)
    end,
    model = function() return H.camera end,
    fixed = true,   -- not movable, "Set to current view" instead
}

-- Height of the element's origin above the surface it is placed on.
function Kinds.surfaceOffset(kind, el)
    if kind == "object" then
        local _, _, minZ = getElementBoundingBox(el)
        return minZ and -minZ or 0
    elseif kind == "spawn" then
        if getElementType(el) == "vehicle" then
            return getElementDistanceFromCentreOfMassToBaseOfModel(el) or 1
        end
        return 1
    end
    return 1
end

-- Common look of every editor element (also the placement ghost).
function View.prepare(el, kind)
    setElementDimension(el, View.helpersVisible and Editor.info.dimension or HIDDEN_DIMENSION)
    if Kinds[kind].helper then
        setElementCollisionsEnabled(el, false)
        setElementFrozen(el, true)
        if getElementType(el) == "vehicle" then
            setVehicleDamageProof(el, true)
            setElementAlpha(el, 170)
        elseif getElementType(el) == "ped" then
            setElementAlpha(el, 170)
        end
    end
    setElementData(el, "jobcreator.item", true, false)
end

--------------------------------------------------------------------------------
-- sync
--------------------------------------------------------------------------------

local function destroyItem(item)
    if not item then return end
    View.byElement[item.element] = nil
    if isElement(item.element) then destroyElement(item.element) end
    if isElement(item.extra) then destroyElement(item.extra) end
    if Editor.selected == item then Editor.selected = nil end
end

-- group = name in View.groups; refs = the doc list (or a one-element list)
local function syncGroup(group, kind, refs)
    local items = View.groups[group] or {}
    View.groups[group] = items
    for index, ref in ipairs(refs) do
        local item = items[index]
        local K = Kinds[kind]
        if item and isElement(item.element) and getElementModel(item.element) == K.model(ref) then
            item.ref, item.index = ref, index
        else
            destroyItem(item)
            local el = K.create(ref)
            if el then
                View.prepare(el, kind)
                item = { element = el, kind = kind, ref = ref, index = index, group = group }
                if K.extra then
                    item.extra = K.extra(ref)
                    if item.extra then setElementDimension(item.extra, getElementDimension(el)) end
                end
                View.byElement[el] = item
            else
                item = nil
            end
            items[index] = item
        end
        if item then K.apply(item.element, ref, item.extra) end
    end
    for index = #items, #refs + 1, -1 do
        destroyItem(items[index])
        items[index] = nil
    end
end

function View.sync()
    local doc = Editor.doc
    if not doc then return View.clear() end
    syncGroup("objects", "object", doc.objects)
    syncGroup("spawns", "spawn", Editor.spawnList())
    syncGroup("checkpoints", "checkpoint", doc.race and doc.race.checkpoints or {})
    syncGroup("finish", "finish", doc.race and doc.race.finish and { doc.race.finish } or {})
    syncGroup("camera", "camera", doc.race and doc.race.finishCamera and { doc.race.finishCamera } or {})
    syncGroup("marker", "marker", doc.marker and { doc.marker } or {})
    if Editor.selected and not isElement(Editor.selected.element) then Editor.selected = nil end
end

function View.clear()
    for _, items in pairs(View.groups) do
        for _, item in pairs(items) do destroyItem(item) end
    end
    View.groups, View.byElement = {}, {}
    Editor.selected = nil
end

-- Spawn vehicles change model when the race vehicle changes.
function View.rebuildSpawns()
    local items = View.groups.spawns or {}
    for index = #items, 1, -1 do destroyItem(items[index]) items[index] = nil end
    View.sync()
end

-- Helpers (spawns, checkpoint arrows, markers ...) are parked in another
-- dimension for test runs and photos; placed objects stay.
function View.setHelpersVisible(visible)
    View.helpersVisible = visible
    for _, items in pairs(View.groups) do
        for _, item in pairs(items) do
            if Kinds[item.kind].helper then
                local dimension = visible and Editor.info.dimension or HIDDEN_DIMENSION
                setElementDimension(item.element, dimension)
                if isElement(item.extra) then setElementDimension(item.extra, dimension) end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- picking
--------------------------------------------------------------------------------

-- The surface point under a screen position (cursor or screen centre).
function View.trace(sx, sy, ignore)
    local cx, cy, cz = getCameraMatrix()
    local tx, ty, tz = getWorldFromScreenPosition(sx, sy, 400)
    if not tx then return end
    local hit, hx, hy, hz, hitElement, nx, ny, nz = processLineOfSight(cx, cy, cz, tx, ty, tz,
        true, true, true, true, true, false, false, false, ignore or (Editor.camMode == "foot" and localPlayer or nil))
    if hit then return hx, hy, hz, hitElement, nx, ny, nz end
end

function View.pick(sx, sy)
    local _, _, _, hitElement = View.trace(sx, sy)
    if hitElement and View.byElement[hitElement] then return View.byElement[hitElement] end
    -- helpers have no collision: nearest one on screen
    local best, bestDist = nil, 40
    for el, item in pairs(View.byElement) do
        if isElement(el) and getElementDimension(el) == Editor.info.dimension then
            local x, y, z = getElementPosition(el)
            local px, py = getScreenFromWorldPosition(x, y, z + 0.5)
            if px then
                local d = math.sqrt((px - sx) ^ 2 + (py - sy) ^ 2)
                if d < bestDist then best, bestDist = item, d end
            end
        end
    end
    return best
end

--------------------------------------------------------------------------------
-- overlay
--------------------------------------------------------------------------------

local sw, sh = guiGetScreenSize()
local FONT = "default-bold"

local function label(x, y, z, text, color)
    local px, py = getScreenFromWorldPosition(x, y, z)
    if not px then return end
    local w = dxGetTextWidth(text, 1, FONT) + 12
    dxDrawRectangle(px - w / 2, py - 10, w, 20, tocolor(0, 0, 0, 170))
    dxDrawText(text, px - w / 2, py - 10, px + w / 2, py + 10, color or tocolor(255, 255, 255), 1, FONT, "center", "center")
end

local EDGES = { { 1, 2 }, { 2, 4 }, { 4, 3 }, { 3, 1 }, { 5, 6 }, { 6, 8 }, { 8, 7 }, { 7, 5 }, { 1, 5 }, { 2, 6 }, { 3, 7 }, { 4, 8 } }

function View.drawBox(el, color)
    if not isElement(el) then return end
    local minX, minY, minZ, maxX, maxY, maxZ = getElementBoundingBox(el)
    local m = getElementMatrix(el)
    if not minX or not m then return end
    if getElementType(el) == "object" then
        local s = getObjectScale(el) or 1
        minX, minY, minZ, maxX, maxY, maxZ = minX * s, minY * s, minZ * s, maxX * s, maxY * s, maxZ * s
    end
    local corners = {}
    for i = 0, 7 do
        local x = (i % 2 == 0) and minX or maxX
        local y = (math.floor(i / 2) % 2 == 0) and minY or maxY
        local z = (i < 4) and minZ or maxZ
        corners[i + 1] = {
            x * m[1][1] + y * m[2][1] + z * m[3][1] + m[4][1],
            x * m[1][2] + y * m[2][2] + z * m[3][2] + m[4][2],
            x * m[1][3] + y * m[2][3] + z * m[3][3] + m[4][3],
        }
    end
    for _, e in ipairs(EDGES) do
        local a, b = corners[e[1]], corners[e[2]]
        dxDrawLine3D(a[1], a[2], a[3], b[1], b[2], b[3], color, 2)
    end
end

local C = {
    route = tocolor(255, 200, 0, 200),
    hover = tocolor(255, 220, 60, 255),
    selected = tocolor(0, 160, 255, 255),
    spawn = tocolor(120, 220, 120),
    checkpoint = tocolor(255, 200, 0),
    finish = tocolor(255, 90, 90),
    marker = tocolor(80, 170, 255),
}

View.hovered = nil

addEventHandler("onClientRender", root, function()
    if not Editor.active or not Editor.doc or Editor.photo then return end
    local doc = Editor.doc

    if View.helpersVisible then
        -- race route
        if doc.race then
            local prev = Editor.spawnList()[1]
            for i, cp in ipairs(doc.race.checkpoints) do
                if prev then dxDrawLine3D(prev[1], prev[2], prev[3], cp[1], cp[2], cp[3], C.route, 3) end
                local size = cp[4] or 5
                dxDrawLine3D(cp[1] - size / 2, cp[2], cp[3] - 0.9, cp[1] + size / 2, cp[2], cp[3] - 0.9, C.route, 2)
                label(cp[1], cp[2], cp[3] + 1.6, "CP " .. i .. "  (" .. size .. ")", C.checkpoint)
                prev = cp
            end
            local fin = doc.race.finish
            if fin then
                if prev then dxDrawLine3D(prev[1], prev[2], prev[3], fin[1], fin[2], fin[3], C.finish, 3) end
                label(fin[1], fin[2], fin[3] + 1.6, "FINISH  (" .. (fin[4] or 5) .. ")", C.finish)
            end
            local cam = doc.race.finishCamera
            if cam then
                dxDrawLine3D(cam.pos[1], cam.pos[2], cam.pos[3], cam.lookAt[1], cam.lookAt[2], cam.lookAt[3], C.finish, 1)
                label(cam.pos[1], cam.pos[2], cam.pos[3] + 0.8, "FINISH CAMERA", C.finish)
            end
        end
        for i, sp in ipairs(Editor.spawnList()) do
            label(sp[1], sp[2], sp[3] + 1.5, "#" .. i, C.spawn)
            local r = math.rad((sp[4] or 0) + 90)
            dxDrawLine3D(sp[1], sp[2], sp[3], sp[1] + math.cos(r) * 2.5, sp[2] + math.sin(r) * 2.5, sp[3], C.spawn, 3)
        end
        if doc.marker then
            local m = doc.marker
            label(m[1], m[2], m[3] + 1.2, "JOB MARKER", C.marker)
        end
    end

    if View.hovered and View.hovered ~= Editor.selected then View.drawBox(View.hovered.element, C.hover) end
    if Editor.selected then View.drawBox(Editor.selected.element, C.selected) end
end)

-- cylinder marker preview for the world marker (createMarker is not an item)
local markerPreview
addEventHandler("onClientPreRender", root, function()
    local m = Editor.active and Editor.doc and Editor.doc.marker
    if m and View.helpersVisible and not Editor.photo then
        if not isElement(markerPreview) then
            markerPreview = createMarker(m[1], m[2], m[3] - 1, "cylinder", 2, 50, 160, 255, 120)
            setElementDimension(markerPreview, Editor.info.dimension)
        end
        setElementPosition(markerPreview, m[1], m[2], m[3] - 1)
    elseif isElement(markerPreview) then
        destroyElement(markerPreview)
        markerPreview = nil
    end
end)
