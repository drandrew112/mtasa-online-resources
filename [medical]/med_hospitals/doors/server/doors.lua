-- Hospital glass doors (model 2678 = one-sided glass door, two leaves side by side).
-- A trigger area (colshape) around the door: while a player or ped stands in it the leaves slide
-- apart and vanish into the wall (collision off); when it is empty they slide back and close.
--
-- Door fields (measured live on the hospital cut-outs, 2026-11-07):
--   x, y, z     centre of the cut-out (the wall plane) and the floor height
--   axis        "y" = door in a wall running along Y (leaves slide along Y), "x" = wall along X
--   leaf        width of ONE leaf. Model 2678: origin at the bottom of the HINGE EDGE, the glass
--               runs 1.1 m along the model's local +X, thin along local Y, 2.62 m high.
--   zoff        height offset of the model origin above the floor, default 0
--   depth, height   size of the trigger area (through the door / above the floor)
--   staffOnly   true = never opens by itself: only EMS / hospital staff on duty, pressing E inside the
--               area (hint shown on entering); it still closes automatically when the area is empty
-- Opening 2.18 m wide = two leaves of 1.1 m, meeting in the centre. Open: each leaf slides one full
-- leaf width sideways and vanishes inside the wall.
DOORS = {
    { id = "as_entrance", name = "All Saints entrance",
      x = 1171.72, y = -1323.55, z = 14.41, axis = "y", leaf = 1.1 },
    { id = "as_bay", name = "All Saints ambulance bay",
      x = 1150.03, y = -1326.43, z = 14.39, axis = "y", leaf = 1.1, staffOnly = true, depth = 8.0 },
}

local MODEL, INT, DIM = 2678, 0, 0
local SLIDE_MS, POLL_MS = 700, 100
local states = {}

-- leaf i origin (hinge edge) closed / open; leaf 1 covers the negative side of the centre, leaf 2 the positive
-- axis y: local +X of rz 90 points to +Y (MTA rotates counter-clockwise), of rz 270 to -Y; axis x: rz 0 points to +X, rz 180 to -X
local function leafPositions(d, open)
    local z = d.z + (d.zoff or 0)
    local reach = open and 2 * d.leaf or d.leaf
    local res = {}
    for i, sign in ipairs({ -1, 1 }) do
        local a = sign * reach
        if d.axis == "x" then res[i] = { d.x + a, d.y, z } else res[i] = { d.x, d.y + a, z } end
    end
    return res
end

local function leafRotation(d, i)
    if d.axis == "x" then return i == 1 and 0 or 180 end
    return i == 1 and 90 or 270
end

local function setOpen(d, st, open)
    if st.open == open then return end
    st.open = open
    local target = leafPositions(d, open)
    for i, obj in ipairs(st.leaves) do
        if isElement(obj) then
            if open then setElementCollisionsEnabled(obj, false) end
            moveObject(obj, SLIDE_MS, target[i][1], target[i][2], target[i][3], 0, 0, 0, "InOutQuad")
        end
    end
    if st.timer and isTimer(st.timer) then killTimer(st.timer) end
    if not open then
        st.timer = setTimer(function()
            if st.open then return end
            for _, obj in ipairs(st.leaves) do
                if isElement(obj) then setElementCollisionsEnabled(obj, true) end
            end
        end, SLIDE_MS + 50, 1)
    end
end

local function occupied(st)
    for _, t in ipairs({ "player", "ped" }) do
        for _, e in ipairs(getElementsWithinColShape(st.col, t)) do
            if not isPedDead(e) then return true end
        end
    end
    return false
end

local function isStaff(p)
    local res = getResourceFromName("work_core")
    if not (res and getResourceState(res) == "running") then return false end
    return exports.work_core:isPlayerOnDuty(p, "ems") == true or exports.work_core:isPlayerOnDuty(p, "hospital") == true
end

-- staff players in the area (on foot or in a vehicle)
local function staffInside(st)
    local res = {}
    local function add(p) if isElement(p) and not isPedDead(p) and isStaff(p) then res[p] = true end end
    for _, p in ipairs(getElementsWithinColShape(st.col, "player")) do add(p) end
    for _, v in ipairs(getElementsWithinColShape(st.col, "vehicle")) do
        for _, p in pairs(getVehicleOccupants(v) or {}) do add(p) end
    end
    return res
end

addEvent("hosp:doorOpen", true)
addEventHandler("hosp:doorOpen", resourceRoot, function(id)
    local st = states[id]
    if not st or not st.def.staffOnly or not st.hint or not st.hint[client] then return end
    setOpen(st.def, st, true)
end)

local function build(d)
    local start = leafPositions(d, false)
    local leaves = {}
    for i = 1, 2 do
        local o = createObject(MODEL, start[i][1], start[i][2], start[i][3], 0, 0, leafRotation(d, i))
        setElementInterior(o, INT); setElementDimension(o, DIM)
        leaves[i] = o
    end
    local w, depth, h = d.leaf * 2 + 2.0, d.depth or 7.0, d.height or 3.0
    local sx, sy = depth, w
    if d.axis == "x" then sx, sy = w, depth end
    local col = createColCuboid(d.x - sx / 2, d.y - sy / 2, d.z - 0.5, sx, sy, h)
    setElementInterior(col, INT); setElementDimension(col, DIM)
    states[d.id] = { leaves = leaves, col = col, open = false, def = d }
end

addEventHandler("onResourceStart", resourceRoot, function()
    for _, d in ipairs(DOORS) do build(d) end
    setTimer(function()
        for _, st in pairs(states) do
            local occ = occupied(st)
            if st.def.staffOnly then
                local now = st.open and {} or staffInside(st) -- no hint while the door is open
                st.hint = st.hint or {}
                for p in pairs(now) do
                    if not st.hint[p] then
                        triggerClientEvent(p, "hosp:doorArea", resourceRoot, st.def.id, true,
                            L.forPlayer(p, "med_hospitals.doors.press_e_to_open"))
                    end
                end
                for p in pairs(st.hint) do
                    if not now[p] and isElement(p) then triggerClientEvent(p, "hosp:doorArea", resourceRoot, st.def.id, false) end
                end
                st.hint = now
                if st.open and not occ then setOpen(st.def, st, false) end
            elseif occ ~= st.open then
                setOpen(st.def, st, occ)
            end
        end
    end, POLL_MS, 0)
end)
