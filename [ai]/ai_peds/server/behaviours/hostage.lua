-- Behaviour "hostage" (2026-11-12, v_scenemanager hostage scenes): stays where it is in a pose (args.pose: "cower"
-- crouching with the hands on the head | "handsup" | "stand"), never flees, never fights; shots and explosions do not
-- move it. While an officer leads it (police_system escort: element data pol.escort) the pose is off; when it is let
-- go the pose comes back (v_scenemanager switches it to "stand" once it is safe at a police car).

local POSES = {
    cower = { "ped", "cower", -1, true, false, false, true },
    handsup = { "ped", "handsup", -1, false, false, false, true },
}

local function pose(p)
    local a = POSES[p.b.pose]
    if not a or not isElement(p.el) then return end
    setPedAnimation(p.el, a[1], a[2], a[3], a[4], a[5], a[6], a[7])
    p.b.anim = true
end

local function clear(p)
    if p.b.anim and isElement(p.el) then setPedAnimation(p.el) end
    p.b.anim = false
end

Behaviours.hostage = {
    enter = function(p, args)
        p.b.pose = POSES[args.pose] and args.pose or (args.pose == "stand" and "stand" or "cower")
        Peds.idle(p)
        pose(p)
    end,
    update = function(p, now)
        if now < (p.b.next or 0) then return end
        p.b.next = now + 500
        local led = getElementData(p.el, "pol.escort") or getPedOccupiedVehicle(p.el)
        if led then
            if p.b.anim then clear(p) end
            if p.cmd.m ~= "idle" then Peds.idle(p) end
        elseif not p.b.anim and p.b.pose ~= "stand" then
            pose(p)
        end
    end,
    -- shots / attacks: it stays (no flee, no fight)
    threat = function() end,
    leave = function(p) clear(p) end,
}
