-- Behaviour "exiting": a driver taken over from ai_land_traffic gets out of its vehicle the GTA way (exit animation
-- on the syncer client: setPedExitVehicle / enter_exit), never teleported. Jacked drivers are pulled out by the
-- player; if one is still inside after DRIVER_JACK_WAIT it gets out itself. Once out it switches to `final`.
-- A ped that cannot get out (door blocked, no syncer for DRIVER_EXIT_GIVEUP) is left sitting in the vehicle
-- (behaviour "seated"; removed with the other drivers when nobody is near).
--
-- args: vehicle, jacked, final (behaviour name), finalArgs

Behaviours = Behaviours or {}

local T = AIPEDS

Behaviours.exiting = {
    enter = function(p, args)
        local b = p.b
        b.veh = args.vehicle
        b.jacked = args.jacked
        b.final, b.finalArgs = args.final or "scared", args.finalArgs or {}
        b.since = getTickCount()
        Peds.idle(p)
    end,

    update = function(p, now)
        local b = p.b
        local veh = getPedOccupiedVehicle(p.el)
        if not veh then
            p.outAt = now
            Peds.setBehaviour(p, b.final, b.finalArgs)
            return
        end
        if now - b.since > T.DRIVER_EXIT_GIVEUP then
            Peds.setBehaviour(p, "seated", { final = b.final, finalArgs = b.finalArgs })
            return
        end
        if b.jacked and now - b.since < T.DRIVER_JACK_WAIT then return end
        if now - b.since < T.DRIVER_EXIT_DELAY then return end
        local vx, vy, vz = getElementVelocity(veh)
        if (vx * vx + vy * vy + vz * vz) * 2500 > T.DRIVER_EXIT_SPEED ^ 2 then return end
        if not b.sentAt or now - b.sentAt > T.DRIVER_EXIT_RETRY then
            b.sentAt = now
            Peds.setCmd(p, { m = "exit" })
        end
    end,

    -- the syncer has the ped out but the server still has it seated (exit not confirmed): the server follows the
    -- syncer, so the other clients do not keep drawing it in the seat
    report = function(p, kind, data)
        if kind ~= "exited" then return end
        local veh = getPedOccupiedVehicle(p.el)
        if not veh then return end
        removePedFromVehicle(p.el)
        local x, y, z = type(data) == "table" and tonumber(data[1]), tonumber(data and data[2]), tonumber(data and data[3])
        if x and y and z then
            local vx, vy, vz = getElementPosition(veh)
            if (x - vx) ^ 2 + (y - vy) ^ 2 + (z - vz) ^ 2 < 10 * 10 then setElementPosition(p.el, x, y, z) end
        end
    end,

    threat = function(p, kind, src)
        -- shot at / attacked while still inside: the final behaviour turns on that attacker
        if src and Peds.alive(src) and p.b.finalArgs then
            if p.b.final == "enemy" then p.b.finalArgs.target = src
            else p.b.finalArgs.threat = src end
        end
    end,
}

-- Behaviour "seated": gave up getting out; sits there. Should it get out after all (a player pulls it out), the
-- final behaviour starts.
Behaviours.seated = {
    enter = function(p, args)
        p.b.final, p.b.finalArgs = args.final or "scared", args.finalArgs or {}
        Peds.idle(p)
    end,
    update = function(p, now)
        if not getPedOccupiedVehicle(p.el) then
            p.outAt = now
            Peds.setBehaviour(p, p.b.final, p.b.finalArgs)
        end
    end,
}

-- Behaviour "dead": nothing to do; traffic / driver bodies (and scripted ones unless keepBody) go after BODY_LIFE
-- once no player is close.
Behaviours.dead = {
    enter = function(p)
        p.dead = true
        p.b.at = getTickCount()
        Peds.setCmd(p, { m = "idle" })
    end,
    update = function(p, now)
        if p.keepBody or now - p.b.at < T.BODY_LIFE then return end
        for _, pl in ipairs(getElementsWithinRange(p.x, p.y, p.z, T.BODY_NEAR, "player")) do
            if getElementDimension(pl) == getElementDimension(p.el) then return end
        end
        Peds.remove(p, "body")
    end,
}
