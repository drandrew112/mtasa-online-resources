-- Network on the client: asks the server for the data once, rebuilds whenever the server sends
-- a new version (edits), follows the switch states.

NetClient = { ready = false, version = 0 }

addEvent("rw:net:data", true)
addEventHandler("rw:net:data", resourceRoot, function(files, states)
    local ms = Net.build(files)
    Net.setStates(states)
    NetClient.ready = true
    NetClient.version = NetClient.version + 1
    triggerEvent("rw:net:onClientNetworkReady", resourceRoot, NetClient.version)
    if DEBUG_ENABLED then outputDebugString(string.format("[rw_customtracks] client network built in %d ms", ms)) end
end)

addEvent("rw:net:onClientNetworkReady", false)

triggerServerEvent("rw:net:hello", resourceRoot)

-- ------------------------------------------------------------------ client exports

function netIsReady() return NetClient.ready end

function netProject(x, y, z, maxDist)
    if not NetClient.ready then return false end
    local seg, s, d = Net.project(x, y, z, maxDist)
    if not seg then return false end
    local px, py, pz = Net.pointAt(seg, s)
    return { seg = seg, s = s, dist = d, x = px, y = py, z = pz, radius = Net.radiusAt(seg, s), grade = Net.gradeAt(seg, s) }
end

function netPointAt(seg, s)
    if not NetClient.ready then return false end
    local x, y, z, tx, ty, tz = Net.pointAt(seg, s)
    if not x then return false end
    return { x = x, y = y, z = z, tx = tx, ty = ty, tz = tz }
end

-- line ("track") position of a world point -> tp | false
function lineProject(line, x, y, maxDist)
    if not NetClient.ready then return false end
    local tp = Lines.project(line, x, y, maxDist)
    return tp or false
end
