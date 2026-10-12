-- Admin developer commands (output: F8 console + server log). These are tools,
-- their texts are not localized (DESIGN.md D14).
--
--   /locdebug off|keys|pseudo|overflow   debug mode of YOUR client
--   /locreload                           re-read the server catalogs, revalidate
--   /locbench [client|server]            lookup / format / measure benchmark
--   /locmissing                          missing keys reported on the server + your client

local function isAdmin(player)
    if getElementData(player, "isLogged") ~= true then return false end
    local res = getResourceFromName("v_mysql")
    if not res or getResourceState(res) ~= "running" then return false end
    return (tonumber(exports.v_mysql:getAccData(player, "admin_level")) or 0) >= LOC.ADMIN_LEVEL
end

local function reply(player, text)
    outputConsole("[v_locals] " .. text, player)
end

addCommandHandler("locdebug", function(player, _, mode)
    if not isAdmin(player) then return end
    mode = mode or "off"
    if not LOC.DEBUG_MODES[mode] then
        reply(player, "usage: /locdebug off|keys|pseudo|overflow")
        return
    end
    triggerClientEvent(player, "v_locals:setDebugMode", resourceRoot, mode)
    reply(player, "debug mode: " .. mode)
end)

addCommandHandler("locreload", function(player)
    if not isAdmin(player) then return end
    reloadCatalogs()
    reply(player, "server catalogs reloaded, see the server log for the validation result")
end)

addCommandHandler("locmissing", function(player)
    if not isAdmin(player) then return end
    local n = 0
    for key, res in pairs(LocMissing) do
        reply(player, ("server: %s (%s)"):format(key, res))
        n = n + 1
    end
    reply(player, ("server: %d missing keys"):format(n))
    triggerClientEvent(player, "v_locals:printMissing", resourceRoot)
end)

--------------------------------------------------------------------------------
-- benchmark
--------------------------------------------------------------------------------

local function run(lines, label, n, fn)
    local t = getTickCount()
    for i = 1, n do fn(i) end
    local ms = getTickCount() - t
    lines[#lines + 1] = ("%-32s %7d x %6d ms  %8.3f us/op"):format(label, n, ms, ms * 1000 / n)
end

local function serverBench(player)
    local C = L._engine
    C.inject(LOC.DEFAULT_LANG, LOC.BENCH_STRINGS)
    local lines = { "server benchmark (" .. getPlayerName(player) .. ", lang " .. L.lang(player) .. ")" }

    run(lines, "L.forPlayer static", 100000, function() L.forPlayer(player, "__bench.static") end)
    run(lines, "L.forPlayer 2 params", 100000, function(i) L.forPlayer(player, "__bench.params", { name = "Andrew", amount = i }) end)
    run(lines, "L.forPlayer plural", 100000, function(i) L.forPlayer(player, "__bench.items", { count = i % 3 }) end)
    run(lines, "L.upper UTF-8 (cached)", 100000, function() L.upper("árvíztűrő tükörfúrógép") end)
    run(lines, "export translate (static)", 10000, function() exports.v_locals:translate(player, "__bench.static") end)

    C.forget("__bench.")
    for _, line in ipairs(lines) do
        reply(player, line)
        outputServerLog("[v_locals] " .. line)
    end
end

addCommandHandler("locbench", function(player, _, which)
    if not isAdmin(player) then return end
    if which ~= "client" then serverBench(player) end
    if which ~= "server" then triggerClientEvent(player, "v_locals:runBench", resourceRoot) end
end)

addEvent("v_locals:benchResult", true)
addEventHandler("v_locals:benchResult", resourceRoot, function(lines)
    if not isElement(client) or type(lines) ~= "table" or not isAdmin(client) then return end
    for _, line in ipairs(lines) do
        outputServerLog("[v_locals] client " .. getPlayerName(client) .. ": " .. tostring(line))
    end
end)
