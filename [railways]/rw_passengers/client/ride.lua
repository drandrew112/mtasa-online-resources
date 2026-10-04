-- The ride as the local passenger feels it: the server sends the coach state every
-- RWP.STATE_MS (rwp:state); here the speed is smoothed and integrated every frame into the
-- distance travelled (Ride.dist), which scrolls the window scenery. Other client files read Ride.

Ride = {
    active = false,
    v = 0,          -- target speed along the coach's front (m/s, from the server)
    vNow = 0,       -- smoothed speed used for scrolling / sounds
    accel = 0,      -- m/s^2 (smoothed), < 0 = braking
    dist = 0,       -- metres travelled towards the coach's front since boarding
    x = 0, y = 0, z = 0,
    doors = "closed",
    service = false,
    train = nil, index = nil,
    serverSec = nil, secAt = 0,   -- server clock (seconds of day) and when it arrived
}

local function reset()
    Ride.active, Ride.v, Ride.vNow, Ride.accel, Ride.dist = false, 0, 0, 0, 0
    Ride.doors, Ride.service = "closed", false
end

addEvent("rwp:state", true)
addEventHandler("rwp:state", resourceRoot, function(st)
    if not rwpMyCoach() then return end
    if not Ride.active then
        reset()
        Ride.active = true
        Ride.vNow = st.v or 0
    end
    Ride.v = st.v or 0
    Ride.x, Ride.y, Ride.z = st.x or 0, st.y or 0, st.z or 0
    Ride.doors = st.doors or "closed"
    Ride.service = st.service or false
    Ride.train, Ride.index = st.train, st.index
    if type(Ride.service) == "table" and Ride.service.t then
        Ride.serverSec, Ride.secAt = Ride.service.t, getTickCount()
    end
end)

-- server clock now (seconds of day), the local clock until a service brings the server's
function Ride.clock()
    if Ride.serverSec then
        return (Ride.serverSec + (getTickCount() - Ride.secAt) / 1000) % 86400
    end
    local t = getRealTime()
    return t.hour * 3600 + t.minute * 60 + t.second
end

addEventHandler("onClientPreRender", root, function(dt)
    if not Ride.active then return end
    if not rwpMyCoach() then reset() return end
    local before = Ride.vNow
    -- follow the server speed within ~0.4 s: smooth enough, no visible lag at stops
    Ride.vNow = Ride.vNow + (Ride.v - Ride.vNow) * math.min(1, dt / 400)
    if math.abs(Ride.vNow) < 0.02 and Ride.v == 0 then Ride.vNow = 0 end
    local a = (Ride.vNow - before) / math.max(dt / 1000, 0.001)
    Ride.accel = Ride.accel + (a - Ride.accel) * math.min(1, dt / 300)
    Ride.dist = Ride.dist + Ride.vNow * dt / 1000
end)

addEventHandler("onClientElementDataChange", localPlayer, function(key)
    if key == "rwp.ride" and not rwpMyCoach() then reset() end
end)
