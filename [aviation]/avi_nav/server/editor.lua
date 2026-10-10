-- In-game nav point editor (admins, avi_core admin level). Writes data/nav.json.
--   /avinav add <FIX|NDB|VOR> <ID> [freq] [model] [name...]   at your position (z = your feet)
--   /avinav move <ID>                                            to your position
--   /avinav object <ID> <model> [rz]                             ground object of a VOR / NDB (model 0 = none)
--   /avinav del <ID>
--   /avinav info <ID>
-- VOR example: /avinav add VOR LSV 113.1 0 Los Santos VOR

local function core() return exports.avi_core end

local function isAdmin(player)
    local res = getResourceFromName("avi_core")
    return res and getResourceState(res) == "running" and core():isAviationAdmin(player)
end

local function say(player, text)
    triggerClientEvent(player, "avi:notify", root, "NAV", text)
    outputConsole("[avi_nav] " .. text, player)
end

local function feetPos(player)
    local x, y, z = getElementPosition(player)
    local veh = getPedOccupiedVehicle(player)
    if veh then
        local _, _, rz = getElementRotation(veh)
        return x, y, z - 1, rz
    end
    local _, _, rz = getElementRotation(player)
    return x, y, z - 1, rz
end

local function r1(v) return math.floor(v * 10 + 0.5) / 10 end

local function removeById(id)
    for _, key in ipairs({ "fixes", "ndbs", "vors" }) do
        for i, p in ipairs(NAV[key]) do
            if p.id == id then return table.remove(NAV[key], i), key end
        end
    end
end

addCommandHandler("avinav", function(player, _, action, a1, a2, a3, ...)
    if not isAdmin(player) then return end
    action = action and action:lower()
    local id = a1 and a1:upper()

    if action == "add" then
        local kind, pid = id, a2 and a2:upper()
        local key = kind and navKeyOf(kind)
        if not key or not pid or pid == "" then
            say(player, "Usage: /avinav add <FIX|NDB|VOR> <ID> [freq] [model] [name]")
            return
        end
        if getNavPoint(pid) then say(player, pid .. " already exists (use move / del).") return end
        local x, y, z, rz = feetPos(player)
        local p = { id = pid, x = r1(x), y = r1(y) }
        if kind == "FIX" then
            p.kind = "enroute"
        else
            -- a3 = freq, then model, then the name (rest of the words)
            local rest = { ... }
            local model = tonumber(rest[1])
            p.freq = a3 or (kind == "VOR" and "110.0" or "300")
            p.z = r1(z)
            p.name = #rest > 1 and table.concat(rest, " ", 2) or (pid .. " " .. kind)
            if model and model > 0 then p.object = { model = model, rz = math.floor(rz) } end
        end
        table.insert(NAV[key], p)
        if saveNav() then say(player, ("%s %s added at %.1f, %.1f"):format(kind, pid, p.x, p.y)) end

    elseif action == "move" then
        local p = getNavPoint(id)
        if not p then say(player, "Unknown nav point " .. tostring(id)) return end
        local x, y, z = feetPos(player)
        p.x, p.y = r1(x), r1(y)
        if p.type ~= "FIX" then p.z = r1(z) end
        if saveNav() then say(player, ("%s moved to %.1f, %.1f"):format(p.id, p.x, p.y)) end

    elseif action == "object" then
        local p = getNavPoint(id)
        local model = tonumber(a2)
        if not p or p.type == "FIX" or not model then
            say(player, "Usage: /avinav object <VOR/NDB id> <model> [rz]")
            return
        end
        p.object = model > 0 and { model = model, rz = tonumber(a3) or 0 } or nil
        if not p.z then local _, _, z = feetPos(player) p.z = r1(z) end
        if saveNav() then say(player, p.id .. " object set to " .. model) end

    elseif action == "del" then
        local p = removeById(id)
        if not p then say(player, "Unknown nav point " .. tostring(id)) return end
        if saveNav() then say(player, p.id .. " deleted") end

    elseif action == "info" then
        local p = getNavPoint(id)
        if not p then say(player, "Unknown nav point " .. tostring(id)) return end
        say(player, ("%s %s  %.1f, %.1f%s%s"):format(p.type, p.id, p.x, p.y, p.freq and ("  " .. p.freq) or "",
            p.object and ("  obj " .. p.object.model) or ""))
    else
        say(player, "/avinav add|move|object|del|info  (see avi_nav/server/editor.lua)")
    end
end)
