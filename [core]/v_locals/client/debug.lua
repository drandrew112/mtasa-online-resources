-- Client debug tools, driven by the admin commands of server/commands.lua.
--
--   keys      every L() shows its key
--   pseudo    accented, ~35% longer texts: shows overflow, glyph gaps and the
--             texts that are not localized yet (they have no [ ] around them)
--   overflow  dxDrawText wrapper in every lib: logs texts wider than their box
--
-- The mode is not saved; it resets on reconnect / v_locals restart.

local mode = nil

function locGetDebugMode()
    return mode
end

addEvent("v_locals:onClientDebugModeChange")

addEvent("v_locals:setDebugMode", true)
addEventHandler("v_locals:setDebugMode", resourceRoot, function(newMode)
    if not LOC.DEBUG_MODES[newMode] then return end
    mode = newMode ~= "off" and newMode or nil
    triggerEvent("v_locals:onClientDebugModeChange", root, mode)
end)

addEvent("v_locals:printMissing", true)
addEventHandler("v_locals:printMissing", resourceRoot, function()
    local n = 0
    for key, res in pairs(LocMissing) do
        outputConsole(("[v_locals] client: %s (%s)"):format(key, res))
        n = n + 1
    end
    outputConsole(("[v_locals] client: %d missing keys"):format(n))
end)

--------------------------------------------------------------------------------
-- benchmark (results: F8 console + server log)
--------------------------------------------------------------------------------

local function run(lines, label, n, fn)
    local t = getTickCount()
    for i = 1, n do fn(i) end
    local ms = getTickCount() - t
    lines[#lines + 1] = ("%-32s %7d x %6d ms  %8.3f us/op"):format(label, n, ms, ms * 1000 / n)
end

-- the old-style word wrap most resources use today (measures on every call)
local function uncachedWrap(text, maxW, scale, font)
    local lines = {}
    local line = ""
    for word in text:gmatch("%S+") do
        local try = line == "" and word or (line .. " " .. word)
        if dxGetTextWidth(try, scale, font) > maxW and line ~= "" then
            lines[#lines + 1] = line
            line = word
        else
            line = try
        end
    end
    lines[#lines + 1] = line
    return lines
end

addEvent("v_locals:runBench", true)
addEventHandler("v_locals:runBench", resourceRoot, function()
    local C = L._engine
    C.inject(L.lang(), LOC.BENCH_STRINGS)
    local lines = { "client benchmark (lang " .. L.lang() .. ")" }
    local label = "Open the Graphics settings"
    local para = "Your money is kept in two places. Cash is what you carry: you pay with it in shops, and it is at risk. The bank keeps the rest safe."

    run(lines, "L() static", 100000, function() L("__bench.static") end)
    run(lines, "L() 2 params", 100000, function(i) L("__bench.params", { name = "Andrew", amount = i }) end)
    run(lines, "L() plural", 100000, function(i) L("__bench.items", { count = i % 3 }) end)
    run(lines, "L.upper UTF-8 (cached)", 100000, function() L.upper("árvíztűrő tükörfúrógép") end)
    run(lines, "dxGetTextWidth (raw)", 20000, function() dxGetTextWidth(label, 1, "default-bold") end)
    run(lines, "L.width (cached)", 20000, function() L.width(label, 1, "default-bold") end)
    run(lines, "word wrap, measured each call", 2000, function() uncachedWrap(para, 300, 1, "default") end)
    run(lines, "L.wrap (cached)", 20000, function() L.wrap(para, 300, 1, "default") end)
    run(lines, "L.fit (cached)", 20000, function() L.fit(para, 200, 1, "default") end)
    run(lines, "export translate (static)", 10000, function() exports.v_locals:translate("__bench.static") end)

    C.forget("__bench.")
    for _, line in ipairs(lines) do outputConsole("[v_locals] " .. line) end
    triggerServerEvent("v_locals:benchResult", resourceRoot, lines)
end)

LOCALS_INTERNAL.getDebugMode = locGetDebugMode
