-- The lib (lib/*.lua): one engine, imported by every consumer resource.
--
--   loadstring(exports.v_locals:import())()      -- once, at load time, both sides
--
-- import() returns lib/utf8x + template + formats + core + client|server
-- concatenated into one chunk, so every resource gets a private copy of the
-- engine and a translation is a local table lookup (DESIGN.md 4.7).
--
-- Server-side loadstring needs the ACL right "function.loadstring" (granted in
-- the Default ACL for now). v_locals itself does not need it: on the server the
-- lib files run as plain <script>s (LIB is a global there), on the client
-- loadstring is always allowed.
--
-- LOCALS_INTERNAL is the backend the lib talks to inside v_locals (direct calls
-- instead of exports). The side scripts add the remaining functions.

local SIDE = triggerClientEvent and "server" or "client"

-- missing keys reported on this side: key -> resource name
LocMissing = {}

LOCALS_INTERNAL = {
    getCatalog      = function(lang, ns) return Catalog.get(lang, ns) end,
    getFile         = function(lang, path) return Catalog.getFile(lang, path) end,
    getLanguageInfo = function() return Catalog.info() end,
    reportMissing   = function(key, res) if LocMissing[key] == nil then LocMissing[key] = tostring(res) end end,
}

local LIB_FILES = { "lib/utf8x.lua", "lib/template.lua", "lib/formats.lua", "lib/core.lua", "lib/" .. SIDE .. ".lua" }

local function buildSource()
    local parts = {
        "if type(_G[__LOCALS_NAME]) == \"table\" and rawget(_G[__LOCALS_NAME], \"__v_locals\") then return end",
        ("local LIB = { side = %q, defaultLang = %q, cacheMax = %d }"):format(SIDE, LOC.DEFAULT_LANG, LOC.CACHE_MAX),
    }
    for _, path in ipairs(LIB_FILES) do
        local text = Catalog.readFile(path)
        if not text then
            outputDebugString("[v_locals] cannot read " .. path, 1)
            return nil
        end
        parts[#parts + 1] = text
    end
    parts[#parts + 1] = "_G[__LOCALS_NAME] = LIB.L"
    return table.concat(parts, "\n")
end

local LIB_SOURCE = buildSource()

-- import([name]) -> lib source; name = global the lib is stored in (default "L")
function import(name)
    if type(name) ~= "string" or not name:match("^[%a_][%w_]*$") then name = "L" end
    if not LIB_SOURCE then return "" end
    return ("local __LOCALS_NAME = %q\n"):format(name) .. LIB_SOURCE
end

if SIDE == "server" then
    -- own instance: read by the lib scripts that follow in meta.xml,
    -- server/ready.lua publishes it
    LIB = { side = "server", defaultLang = LOC.DEFAULT_LANG, cacheMax = LOC.CACHE_MAX }
    return
end

-- client own instance: loaded once every script of v_locals ran, so the backend
-- functions of client/state.lua and client/debug.lua exist by then
addEventHandler("onClientResourceStart", resourceRoot, function()
    if not LIB_SOURCE then return end
    local fn, err = loadstring(import("L"), "@v_locals/lib")
    if not fn then
        outputDebugString("[v_locals] lib compile error: " .. tostring(err), 1)
        return
    end
    fn()
end, true, "high+10")
