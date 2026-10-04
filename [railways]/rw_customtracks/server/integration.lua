-- Exports for the other rw_ resources (phase 4): line ("track") geometry, stop points of red
-- signals, and the cab's requests from rw_loco clients.

-- ------------------------------------------------------------------ lines
function getNetLines()
    local t = {}
    for _, id in ipairs(Lines.ids()) do t[#t + 1] = { id = id, length = Lines.length(id), closed = Lines.isClosed(id) } end
    return t
end

-- -> tp, distance | false
function lineProject(line, x, y, maxDist)
    local tp, d = Lines.project(line, x, y, maxDist)
    if not tp then return false end
    return tp, d
end

-- -> x, y, z, dirX, dirY
function linePoint(line, tp) return Lines.pointAt(line, tp) end

-- line position -> seg, s, dir (dir = +1 when the line runs towards the segment's b end)
function lineToNet(line, tp)
    local seg, s, dir = Lines.toNet(line, tp)
    if not seg then return false end
    return seg, s, dir
end

-- the train drives to line position tp and arrives running in line direction dir
function setNetTrainLineDestination(id, line, tp, dir)
    local seg, s, ldir = Lines.toNet(line, tp)
    if not seg then return false, "unknown line" end
    return setNetTrainDestination(id, seg, s, dir and ldir * dir or nil)
end
function lineLength(line) return Lines.length(line) end
function lineDelta(line, a, b) return Lines.delta(line, a, b) end
function linePolyline(line, a, b, step) return Lines.polyline(line, a, b, step) end

-- every line's points every `step` metres (web map) -> { [line] = { {x, y}, ... } }
function getNetLinePoints(step)
    local t = {}
    for _, id in ipairs(Lines.ids()) do
        local pts = {}
        for tp = 0, Lines.length(id), step or 20 do
            local x, y = Lines.pointAt(id, tp)
            pts[#pts + 1] = { math.floor(x * 10) / 10, math.floor(y * 10) / 10 }
        end
        t[id] = pts
    end
    return t
end

-- ------------------------------------------------------------------ stop points (signals)
-- list = { { line, tp, dir, id } }: trains moving in line direction `dir` stop before tp
function setNetStopPoints(list)
    local pts = {}
    for _, p in ipairs(list or {}) do
        local seg, s, ldir = Lines.toNet(p.line, p.tp)
        if seg then pts[#pts + 1] = { seg = seg, s = s, dir = (p.dir or 1) * ldir, id = p.id } end
    end
    Switches.setStops(pts)
    return #pts
end

function getNetStopPoints() return Switches.getStops() end

-- ------------------------------------------------------------------ cab requests (rw_loco)
-- "lock" (reason, on) traction lock | "emergency" (on) | "rev" reverser (standing only)
addEvent("rw:net:cab", true)
addEventHandler("rw:net:cab", resourceRoot, function(action, a, b)
    local t = Trains.ofPlayer(client)
    if not t or t.driver ~= client then return end
    if action == "lock" then
        t.locks[tostring(a)] = b and true or nil
    elseif action == "emergency" then
        setNetTrainEmergency(t.id, a and true or false)
    elseif action == "rev" then
        if math.abs(t.v) < 0.1 then t.rev = -t.rev end
    end
end)
