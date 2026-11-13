-- wx_snow :: /snow, /snowbake, /snowtest (account admin_level >= SNOW.ADMIN_LEVEL)
--
--   /snow                         status (server + own client)
--   /snow <0-5> [slow]            preview on the own client only (instant; slow = 20 min build-up)
--   /snow cover <0-1>             own client: fixed ground coverage
--   /snow reset                   own client: back to the server state
--   /snow global <0-5> [slow]     override for everybody (until /snow global reset or the next week);
--                                 instant unless slow (the weekly event always builds up / melts slowly)
--   /snow global reset            back to the weekly value
--   /snow debug                   own client: category colour view
--   /snow quality off|low|high    own client quality (same as ui_pause)
--   /snow shader v1|v2            own client: old (v1) or F1 (v2) ground shader, for A/B measuring
--   /snowbake start|stop|status   roof map bake on the own client (client/bake.lua)
--   /snowtest interiors|zones|tour|cost|stop   (cost: where the fixed fps drop comes from, at the
--                                 current spot)

local function adminLevel(player)
    local ok, v = pcall(function() return exports.v_mysql:getAccData(player, "admin_level") end)
    return ok and tonumber(v) or 0
end

local function allowed(player)
    if getElementType(player) ~= "player" then return true end -- console
    return adminLevel(player) >= SNOW.ADMIN_LEVEL
end

-- message on the client: key of the wx_snow namespace + params (ui_core notification)
function snowNotify(player, key, params)
    if getElementType(player) ~= "player" then
        outputServerLog("[wx_snow] " .. key .. " " .. (params and toJSON(params) or ""))
        return
    end
    triggerClientEvent(player, "wx_snow:notify", resourceRoot, key, params or {})
end

local function toClient(player, action, args)
    if getElementType(player) ~= "player" then
        outputServerLog("[wx_snow] /snow " .. action .. ": in game only")
        return
    end
    triggerClientEvent(player, "wx_snow:cmd", resourceRoot, action, args or {})
end

local function parseLevel(s)
    local n = tonumber(s)
    if not n or n ~= math.floor(n) or n < 0 or n > SNOW.MAX_LEVEL then return nil end
    return n
end

local function who(player)
    return getElementType(player) == "player" and getPlayerName(player) or "console"
end

addCommandHandler("snow", function(player, _, a, b, c)
    if not allowed(player) then return end
    a = a and a:lower() or nil

    if not a or a == "info" then
        local info = snowInfo()
        if getElementType(player) ~= "player" then
            outputServerLog("[wx_snow] " .. toJSON(info))
        else
            toClient(player, "info", info)
        end
        return
    end

    if a == "global" then
        if b and b:lower() == "reset" then
            setSnowOverride(nil, false)
            outputServerLog(("[wx_snow] %s: /snow global reset"):format(who(player)))
            return snowNotify(player, "wx_snow.cmd.global_reset", { level = snowInfo().target })
        end
        local lvl = parseLevel(b)
        if not lvl then return snowNotify(player, "wx_snow.cmd.usage") end
        local instant = not (c and c:lower() == "slow")
        setSnowOverride(lvl, instant, who(player))
        outputServerLog(("[wx_snow] %s: /snow global %d%s"):format(who(player), lvl, instant and "" or " slow"))
        return snowNotify(player, "wx_snow.cmd.global_set", { level = lvl })
    end

    local lvl = parseLevel(a)
    if lvl then
        return toClient(player, "preview", { level = lvl, instant = not (b and b:lower() == "slow") })
    end
    if a == "cover" then
        local v = tonumber(b)
        if not v then return snowNotify(player, "wx_snow.cmd.usage") end
        return toClient(player, "cover", { value = math.max(0, math.min(1, v)) })
    end
    if a == "reset" or a == "debug" then
        return toClient(player, a, {})
    end
    if a == "quality" and (b == "off" or b == "low" or b == "high") then
        return toClient(player, "quality", { value = b })
    end
    if a == "shader" and (b == "v1" or b == "v2") then
        return toClient(player, "shader", { value = b })
    end
    snowNotify(player, "wx_snow.cmd.usage")
end)

addCommandHandler("snowbake", function(player, _, a, b)
    if not allowed(player) then return end
    toClient(player, "bake", { action = (a or "status"):lower(), from = tonumber(b) })
end)

addCommandHandler("snowtest", function(player, _, a)
    if not allowed(player) then return end
    a = (a or ""):lower()
    if a ~= "interiors" and a ~= "zones" and a ~= "tour" and a ~= "cost" and a ~= "stop" then
        return snowNotify(player, "wx_snow.test.usage")
    end
    local args = { action = a }
    if a == "interiors" then
        -- world_interiors registry: inside position of every interior
        local list = {}
        local res = getResourceFromName("world_interiors")
        if res and getResourceState(res) == "running" then
            local ok, all = pcall(function() return exports.world_interiors:getInteriors() end)
            for _, rec in ipairs(ok and type(all) == "table" and all or {}) do
                local e = type(rec.exit) == "table" and rec.exit or nil
                if e and tonumber(e.x) then
                    list[#list + 1] = { id = tostring(rec.id), name = tostring(rec.name or rec.id),
                        x = e.x, y = e.y, z = e.z, interior = tonumber(e.interior) or 0,
                        dimension = tonumber(rec.dimension) or 0 }
                end
            end
        end
        args.list = list
    end
    toClient(player, "test", args)
end)

-- the test tour moves the admin between dimensions / interiors; the server confirms it
addEvent("wx_snow:testMove", true)
addEventHandler("wx_snow:testMove", resourceRoot, function(x, y, z, interior, dimension)
    if not client or not allowed(client) then return end
    if tonumber(interior) then setElementInterior(client, tonumber(interior)) end
    if tonumber(dimension) then setElementDimension(client, tonumber(dimension)) end
    if tonumber(x) and tonumber(y) and tonumber(z) then setElementPosition(client, x, y, z) end
end)
