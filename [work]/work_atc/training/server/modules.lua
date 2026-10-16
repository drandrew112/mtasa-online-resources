-- The training modules, server side: their steps, the aircraft roles, what happens when a step
-- comes (enter), what the server checks before the client may leave a step (checks) and which lost
-- aircraft come again from which step (lost). The texts and the sub-steps are in client/<module>.lua.
--
-- Every module starts with "console" (log in at the console of its position; the session engine
-- removes all aircraft there) and ends with "alerts" (or its logoutStep; Logout = the receipt) and
-- "done". The scope itself is taught only by SCOPE: the other modules take it as known.
--
-- Roles (avi_traffic spawnTutorialFlight kinds, see avi_traffic/server/tutorial.lua):
--   dep = departure at a stand, arr = arrival (ADC: on the final cleared for the approach; APC: in the
--   CTA before its TMA entry fix, on a STAR), vec = a second APC arrival (another entry fix, no STAR),
--   ovf = overflight,
--   cfa / cfb = the head-on conflict pair, inb = an arrival entering the CTA.

local M = Training.modules
local T = Training

local function had(s, role) return s.had[role] == true end

---------------------------------------------------------------- SCOPE - the radar scope (short tour)

-- On the tower position: where the parts of the scope are, then the label and the command menu of a
-- departure at its stand (only shown, no command needed), then Logout.
M.scope = {
    steps = { "console", "tour", "menu", "logout", "done" },
    logoutStep = "logout",
    roles = { dep = { kind = "dep" } },
    lostAlways = true,
    lost = { dep = { menu = "menu" } },
    enter = {
        menu = function(s) T.ensure(s, "dep") end,
        logout = function(s) T.removeAll(s) end,
    },
    checks = {
        tour = function() return true end,
        menu = function(s) return s.ids.dep ~= nil end,
        done = function() return true end,
    },
}

---------------------------------------------------------------- ADC - Aerodrome Controller (tower)

M.adc = {
    steps = { "console", "label", "delivery", "ground", "air", "arrival", "alerts", "done" },
    roles = { dep = { kind = "dep" }, arr = { kind = "arr" } },
    -- a tower aircraft is under control from the start: losing it is always a loss
    lostAlways = true,
    lost = {
        dep = { label = "label", delivery = "label", ground = "label" },
        arr = { arrival = "arrival", alerts = "arrival" },
    },
    enter = {
        label = function(s) T.ensure(s, "dep") end,
        arrival = function(s)
            T.removeRole(s, "dep")
            T.ensure(s, "arr")
        end,
        alerts = function(s)
            if s.ids.arr then T.call("avi_traffic", "setTutorialSquawk", s.player, s.ids.arr, TRAINING.ALERT_SQUAWK) end
        end,
    },
    checks = {
        label = function(s) return s.ids.dep ~= nil end,
        delivery = function(s) return T.cmd(s, "dep", "push") end,
        ground = function(s) return T.cmd(s, "dep", "takeoff") end,
        -- out of the tower's hands: gone, or airborne and left the CTR
        air = function(s, ac)
            local dep = ac.dep
            return not dep or (not dep.gnd and dep.ctl ~= s.position)
        end,
        arrival = function(s, ac) return ac.arr ~= nil and ac.arr.phase == "parked" end,
        done = function() return true end,
    },
}

---------------------------------------------------------------- APC - Approach Controller

M.apc = {
    steps = { "console", "airspace", "departure", "arrival", "vectors", "alerts", "done" },
    roles = {
        dep = { kind = "dep" },
        arr = { kind = "tma_arr", star = true },             -- on the STAR the pilots picked (radar is closed)
        vec = { kind = "tma_arr", avoidFixOf = "arr" },     -- another entry fix, no STAR: radar vectors
    },
    lost = {
        dep = { departure = "departure" },
        arr = { arrival = "arrival" },
        vec = { vectors = "vectors" },
    },
    enter = {
        departure = function(s) T.ensure(s, "dep") end,
        arrival = function(s)
            T.removeRole(s, "dep")
            T.ensure(s, "arr")
        end,
        vectors = function(s)
            T.ensure(s, "vec")
            T.removeRole(s, "arr")
        end,
        alerts = function(s) T.removeAll(s) end,
    },
    checks = {
        airspace = function() return true end,
        -- each one is done once it left the TMA after the trainee had it
        departure = function(s, ac) return T.handedOff(s, "dep", ac) end,
        arrival = function(s, ac) return T.handedOff(s, "arr", ac) end,
        vectors = function(s, ac) return T.handedOff(s, "vec", ac) end,
        done = function() return true end,
    },
}

---------------------------------------------------------------- ACC - Area Control Centre (radar)

-- the conflict pair has passed each other (or one of them is gone after the trainee had it)
local function pairPassed(s, ac)
    local a, b = ac.cfa, ac.cfb
    if not a or not b then return had(s, "cfa") or had(s, "cfb") end
    local h = math.rad(a.hdg or 0)
    local along = (b.x - a.x) * math.sin(h) + (b.y - a.y) * math.cos(h)
    return along < 0 and getDistanceBetweenPoints2D(a.x, a.y, b.x, b.y) > 600
end
T.pairPassed = pairPassed

M.acc = {
    steps = { "console", "airspace", "overflight", "conflict", "inbound", "alerts", "done" },
    roles = {
        ovf = { kind = "overflight" },
        cfa = { kind = "conflict", pair = "cfb" },
        cfb = { kind = "pair", pair = "cfa" },             -- spawned with cfa
        inb = { kind = "inbound" },
    },
    lost = {
        ovf = { overflight = "overflight" },
        cfa = { conflict = "conflict" },
        cfb = { conflict = "conflict" },
        inb = { inbound = "inbound" },
    },
    enter = {
        overflight = function(s) T.ensure(s, "ovf") end,
        conflict = function(s)
            T.removeRole(s, "ovf")
            T.ensure(s, "cfa")
        end,
        inbound = function(s)
            T.removeRole(s, "cfa")
            T.removeRole(s, "cfb")
            T.ensure(s, "inb")
        end,
        alerts = function(s) T.removeAll(s) end,
    },
    checks = {
        airspace = function() return true end,
        overflight = function(s, ac) return T.handedOff(s, "ovf", ac) end,
        conflict = pairPassed,
        inbound = function(s, ac) return T.handedOff(s, "inb", ac) end,
        done = function() return true end,
    },
}
