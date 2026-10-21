-- Agent state sync (server -> clients). The server sends (segment, s, v, a, lateral, next segment)
-- records; clients extrapolate them with the same rule as predict() and place the vehicles every
-- frame. A record goes out when the client's prediction would be off (dead reckoning), when the
-- segment / next segment / lateral target changes, or after SEND_MAX_AGE.
--
-- EV_STATE payload: flat list, RECORD fields per agent:
--   vehicle, code, s, v, a, lat, latTarget, latSlope, nextCode, flags (1 = horn), latRate
-- lat is at s; the clients continue it with Geo.latAfter over the distance driven since s.

Sync = { players = {} }   -- [player] = { known = { [agent] = flush id it was last in range } }

local T = TRAFFIC
local abs, floor, sqrt = math.abs, math.floor, math.sqrt
Sync.RECORD = 11

-- the clients' extrapolation (keep in sync with client/puppets.lua)
function Sync.predict(s, v, a, dt)
    local ta = dt < 1 and dt or 1
    local v1 = v + a * ta
    if v1 < 0 then
        -- stops during the accelerating part
        local tStop = a < 0 and -v / a or 0
        return s + v * tStop * 0.5, 0
    end
    return s + (v + v1) * 0.5 * ta + v1 * (dt - ta), v1
end

local function r2(x) return floor(x * 100 + 0.5) / 100 end
local function r3(x) return floor(x * 1000 + 0.5) / 1000 end

-- tolerances by the distance from the nearest player (ag.near2, Sim.step): 0 = close, 1 = SEND_FAR_TO
local FAR_FROM, FAR_SPAN = T.SEND_FAR_FROM, T.SEND_FAR_TO - T.SEND_FAR_FROM
local function farness(ag)
    local d = sqrt(ag.near2 or 0) - FAR_FROM
    if d <= 0 then return 0 end
    return d >= FAR_SPAN and 1 or d / FAR_SPAN
end

local function isDirty(ag, now)
    local st = ag.sent
    if not st or ag.horn then return true end
    if st.code ~= ag.plan[1].code or st.next ~= Agents.nextCode(ag) or st.latTarget ~= ag.latTarget
        or st.slope ~= ag.latSlope then return true end
    local f = farness(ag)
    local dt = (now - st.t) / 1000
    if dt * 1000 > T.SEND_MAX_AGE + (T.SEND_MAX_AGE_FAR - T.SEND_MAX_AGE) * f then return true end
    local ps, pv = Sync.predict(st.s, st.v, st.a, dt)
    return abs(ps - ag.s) > T.SEND_POS_ERR + (T.SEND_POS_ERR_FAR - T.SEND_POS_ERR) * f
        or abs(pv - ag.v) > T.SEND_SPEED_ERR + (T.SEND_SPEED_ERR_FAR - T.SEND_SPEED_ERR) * f
end

-- reused buffers: the records of this flush, the agents near a player, one player's payload
local records, nearBuf, out, outN = {}, {}, {}, 0
local flushId = 0

-- players: active players { { el, x, y, z } }
function Sync.flush(players, now)
    for ag in pairs(records) do records[ag] = nil end
    for _, ag in pairs(Agents.list) do
        if isDirty(ag, now) then
            local code, nxt = ag.plan[1].code, Agents.nextCode(ag)
            local s, v, a = r2(ag.s), r2(ag.v), r2(ag.a)
            local lat, rate = r2(ag.lat), r3(ag.latRate)
            local st = ag.sent
            if not st then st = {}; ag.sent = st end
            st.code, st.next, st.s, st.v, st.a, st.lat, st.rate = code, nxt, s, v, a, lat, rate
            st.latTarget, st.slope, st.t = ag.latTarget, ag.latSlope, now
            local rec = ag.rec
            if not rec then rec = {}; ag.rec = rec end
            rec[1], rec[2], rec[3], rec[4], rec[5], rec[6] = ag.veh, code, s, v, a, lat
            rec[7], rec[8], rec[9], rec[10], rec[11] = ag.latTarget, ag.latSlope, nxt, ag.horn and 1 or 0, rate
            records[ag] = rec
        end
        ag.horn = false
    end

    local range = T.SIM_RADIUS + 50
    local visited = {}
    flushId = flushId + 1
    for _, p in ipairs(players) do
        local sp = Sync.players[p.el]
        visited[p.el] = true
        if sp then
            local n = 0
            local known = sp.known
            for i = #nearBuf, 1, -1 do nearBuf[i] = nil end
            Agents.near(p.x, p.y, range, nearBuf)
            for i = 1, #nearBuf do
                local ag = nearBuf[i]
                -- the hash is from this tick's step: agents destroyed since are still in it
                if Agents.list[ag.id] == ag then
                    local rec = records[ag]
                    if not rec and not known[ag] then
                        local st = ag.sent
                        -- not dirty, but this player has not seen it yet: send the last record
                        -- the client measures age from arrival: send the extrapolated state
                        local ps, pv = Sync.predict(st.s, st.v, st.a, (now - st.t) / 1000)
                        local lat, rate = Geo.latAfter(st.lat, st.rate, st.latTarget, st.slope, ps - st.s)
                        rec = { ag.veh, st.code, r2(ps), r2(pv), 0, r2(lat), st.latTarget, st.slope, st.next, 0, r3(rate) }
                    end
                    if rec then
                        for k = 1, Sync.RECORD do out[n + k] = rec[k] end
                        n = n + Sync.RECORD
                    end
                    known[ag] = flushId
                end
            end
            -- out of range (or gone) since the last flush: sent again in full when it comes back
            for ag, id in pairs(known) do
                if id ~= flushId then known[ag] = nil end
            end
            for k = n + 1, outN do out[k] = nil end
            outN = n
            if n > 0 then triggerClientEvent(p.el, EV_STATE, resourceRoot, out) end
        end
    end
    -- players outside the traffic world (other dimension etc.) get everything again when they return
    for pl, sp in pairs(Sync.players) do
        if not isElement(pl) then Sync.players[pl] = nil
        elseif not visited[pl] and next(sp.known) then sp.known = {} end
    end
end

function Sync.forget(ag)
    for _, sp in pairs(Sync.players) do sp.known[ag] = nil end
end

function Sync.release(ag, reason)
    local targets = {}
    for pl in pairs(Sync.players) do
        if isElement(pl) then targets[#targets + 1] = pl end
    end
    if #targets > 0 then
        local v = ag.v
        triggerClientEvent(targets, EV_RELEASE, resourceRoot, ag.veh, reason, ag.fx * v, ag.fy * v, ag.fz * v)
    end
end

function Sync.forgetPlayerAgents(player)
    local sp = Sync.players[player]
    if sp then sp.known = {} end
end

addEvent(EV_READY, true)
addEventHandler(EV_READY, resourceRoot, function()
    Sync.players[client] = { known = {} }
end)

addEventHandler("onPlayerQuit", root, function()
    Sync.players[source] = nil
end)
