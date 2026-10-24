-- biz_web / server/api.lua
-- sabusinessregistry.eu: register an organization, move the headquarters,
-- search the registry, top organizations by value. In-game only: the page is
-- not an <html> entry of meta.xml, and every call below refuses callers that
-- are not a player in the in-game browser (web_api:getCallerPlayer).

local SITE  = "sabusinessregistry.eu"
local TITLE = "San Andreas Business Registry"

local function core() return exports.biz_core end

local function running(name)
    local r = getResourceFromName(name)
    return r and getResourceState(r) == "running"
end

local function caller()
    if not running("web_api") or not running("biz_core") then return nil end
    local p = exports.web_api:getCallerPlayer()
    if isElement(p) and getElementType(p) == "player" then return p end
    return nil
end

local DENIED = { ok = false, error = "ingame_only" }

local function offices()
    local out = {}
    for _, p in ipairs(core():getCatalog() or {}) do
        if p.kind == "office" then out[#out + 1] = p end
    end
    table.sort(out, function(a, b) return a.price < b.price end)
    return out
end

function bwState()
    local player = caller()
    if not player then return DENIED end
    local my = core():getMyOrganization(player) or {}
    local cfg = core():getBizConfig() or {}
    return {
        ok = true,
        regFee = cfg.regFee or 0,
        bank = tonumber(getElementData(player, "bank_money")) or 0,
        player = (tostring(getElementData(player, "displayName") or getPlayerName(player)):gsub("#%x%x%x%x%x%x", "")),
        company = my.company or false,
        creating = my.creating or false,
        defaultName = my.defaultName or "",
        offices = offices(),
        nameMin = cfg.nameMin, nameMax = cfg.nameMax,
    }
end

function bwRegister(name, officeId)
    local player = caller()
    if not player then return DENIED end
    return core():createCompany(player, tostring(name or ""), tostring(officeId or ""))
end

function bwMoveHeadquarters(officeId)
    local player = caller()
    if not player then return DENIED end
    return core():moveHeadquarters(player, tostring(officeId or ""))
end

function bwRegistry(query)
    if not caller() then return DENIED end
    return { ok = true, rows = core():getRegistry(tostring(query or ""), 200) or {} }
end

function bwTop()
    if not caller() then return DENIED end
    return { ok = true, rows = core():getTopList(25) or {} }
end

function bwEntry(id)
    if not caller() then return DENIED end
    local e = core():getRegistryEntry(tonumber(id))
    return e and { ok = true, entry = e } or { ok = false, error = "not_found" }
end

local function registerSite()
    if not running("web_api") then return end
    exports.web_api:registerApp({
        title = TITLE, site = SITE, category = "business",
        description = "Register an organization, find companies and see the most valuable ones.",
        page = "web/index.html",
    })
end
addEventHandler("onResourceStart", resourceRoot, registerSite)
addEvent("onWebApiStart", false)
addEventHandler("onWebApiStart", root, registerSite)
