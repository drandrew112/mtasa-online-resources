-- v_customs :: workshop buildings (server)
--
-- Every workshop gets a blip and a movable garage door: the stock door model
-- is removed from the map and re-created as a script object. A vehicle with a
-- driver near the door opens it; driving far enough in starts the session
-- (server/shop.lua). Only dimension 0 is handled here - inside a session the
-- client animates its own copy of the door.

Customs = Customs or {}

local state = {}   -- [idx] = { obj, blip, colApproach, colInside, open, lastWant, holds }

local TICK = 300

local function doorTarget(d, open)
    if not open then return d.x, d.y, d.z end
    local o = d.open
    return d.x + o[1], d.y + o[2], d.z + o[3]
end

local function setDoor(idx, open)
    local st = state[idx]
    if not st or st.open == open then return end
    st.open = open

    local d = Customs.WORKSHOPS[idx].door
    local tx, ty, tz = doorTarget(d, open)
    stopObject(st.obj)

    -- reversing mid-move: only take the share of the time that is left. Position
    -- and rotation share the easing, so how far the door got along its path
    -- also says how far it has turned.
    local cx, cy, cz = getElementPosition(st.obj)
    local full = getDistanceBetweenPoints3D(d.x, d.y, d.z, doorTarget(d, true))
    local done = full > 0 and getDistanceBetweenPoints3D(d.x, d.y, d.z, cx, cy, cz) / full or (open and 0 or 1)
    done = math.max(0, math.min(1, done))
    local share = open and (1 - done) or done
    local time = math.max(50, math.floor(d.time * share))

    local r = d.openRot or { 0, 0, 0 }
    local sign = open and share or -share
    moveObject(st.obj, time, tx, ty, tz, r[1] * sign, r[2] * sign, r[3] * sign, "InOutQuad")
end

-- Keeps the door open while a session drives out (on = true/false pairs).
function Customs.holdDoor(idx, on)
    local st = state[idx]
    if not st then return end
    st.holds = math.max(0, st.holds + (on and 1 or -1))
    if on then
        st.lastWant = getTickCount()
        setDoor(idx, true)
    end
end

local function driverOf(veh)
    if getElementDimension(veh) ~= 0 then return nil end
    local driver = getVehicleController(veh)
    if driver and getElementType(driver) == "player" then return driver end
    return nil
end

local function tick()
    local now = getTickCount()
    for idx, st in pairs(state) do
        local want = st.holds > 0

        for _, veh in ipairs(getElementsWithinColShape(st.colInside, "vehicle")) do
            local driver = driverOf(veh)
            if driver then
                want = true
                Customs.startSession(driver, veh, idx)
            end
        end
        if not want then
            for _, veh in ipairs(getElementsWithinColShape(st.colApproach, "vehicle")) do
                if driverOf(veh) then want = true break end
            end
        end

        if want then
            st.lastWant = now
            setDoor(idx, true)
        elseif st.open and now - st.lastWant > (Customs.DOOR_CLOSE_DELAY or 2500) then
            setDoor(idx, false)
        end
    end
end

addEventHandler("onResourceStart", resourceRoot, function()
    for idx, ws in ipairs(Customs.WORKSHOPS or {}) do
        local d, a, b = ws.door, ws.approach, ws.inside

        removeWorldModel(d.model, 3, d.x, d.y, d.z)
        local obj = createObject(d.model, d.x, d.y, d.z, d.rx or 0, d.ry or 0, d.rz or 0)

        local blip = createBlip(ws.blip[1], ws.blip[2], ws.blip[3], Customs.BLIP_ICON or 27)

        state[idx] = {
            obj         = obj,
            blip        = blip,
            colApproach = createColSphere(a[1], a[2], a[3], a[4]),
            colInside   = createColCuboid(b.minX, b.minY, b.minZ,
                                          b.maxX - b.minX, b.maxY - b.minY, b.maxZ - b.minZ),
            open        = false,
            lastWant    = 0,
            holds       = 0,
        }
    end
    setTimer(tick, TICK, 0)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for idx, ws in ipairs(Customs.WORKSHOPS or {}) do
        local d = ws.door
        restoreWorldModel(d.model, 3, d.x, d.y, d.z)
    end
end)
