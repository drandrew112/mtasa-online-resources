-- police_system / modules/query/client/window.lua
-- Query and search results as ui_core pinned notifications (bottom of the notification column, 2026-11-11 - the own
-- query window and the centre search panel are gone):
--   * person / vehicle check: title, subtitle = name / plate, flags (WARRANT, WANTED, Suspended, Stolen, Expired)
--     and the rows colour coded; the default pinned lifetime (5 x the notification time). One person + one vehicle
--     check at a time (a new one replaces the old one). The MDC keeps the checks (Overview / profile).
--   * search (kind "search"): every item with its class colour (legal green / questionable orange / illegal red),
--     the default pinned lifetime too. Opening it closes the stop menu.
-- No key is needed for any of them (user rule 2026-11-12: only the call offer has keys, Y / N); they expire in ui_core.

POL.module("queryw", {})

local HEX = { red = "#EB4040", green = "#40C86E", orange = "#F58C32", yellow = "#F0C83C", dim = "#8C9EBE",
              text = "#E1E8F5", blue = "#468CFF" }
local ID = { person = "pol.query.person", vehicle = "pol.query.vehicle", search = "pol.search" }

local function uic()
    local res = getResourceFromName("ui_core")
    return res and getResourceState(res) == "running" and exports.ui_core or nil
end

-- names / plates must not turn into colour codes
local function safe(s) return (tostring(s or "-"):gsub("#(%x%x%x%x%x%x)", "# %1")) end

local function row(label, value, color)
    return HEX.dim .. label .. ":  " .. (color or HEX.text) .. safe(value)
end

local function flagLine(flags)
    local parts = {}
    for _, f in ipairs(flags) do parts[#parts + 1] = f[2] .. f[1] end
    return table.concat(parts, HEX.dim .. "  ·  ")
end

-- the pinned notification of a person / vehicle check
local function queryOpts(r)
    local lines, flags = {}, {}
    local accent = HEX.blue
    if r.kind == "person" then
        lines[#lines + 1] = row(L("police_system.query.citizen_id"), r.id)
        lines[#lines + 1] = row(L("police_system.query.birth"), r.birth or "-")
        lines[#lines + 1] = row(L("police_system.query.licence"), L("police_system.query.licence_" .. tostring(r.licence)),
            r.licence ~= "valid" and HEX.red or nil)
        if (r.warrants or 0) > 0 then flags[#flags + 1] = { "WARRANT", HEX.red } end
        if (r.wanted or 0) > 0 then flags[#flags + 1] = { "WANTED " .. tostring(r.wanted), HEX.yellow } end
        if r.licence ~= "valid" then flags[#flags + 1] = { L.upper(L("police_system.query.licence_" .. tostring(r.licence))), HEX.orange } end
        if (r.warrants or 0) > 0 then accent = HEX.red elseif #flags > 0 then accent = HEX.orange end
    else
        local regExp = tostring(r.registration):find("expired")
        local inspExp = tostring(r.inspection):find("expired")
        lines[#lines + 1] = row(L("police_system.query.model"), exports.veh_manager:getModelName(r.model or 0) or "?")
        lines[#lines + 1] = row(L("police_system.query.owner"), tostring(r.owner) .. (r.ownerNpc and "  (NPC)" or ""))
        lines[#lines + 1] = row(L("police_system.query.registration"), r.registration, regExp and HEX.red or nil)
        lines[#lines + 1] = row(L("police_system.query.inspection"), r.inspection, inspExp and HEX.red or nil)
        if r.stolen then flags[#flags + 1] = { "STOLEN", HEX.red } end
        if (r.ownerWarrants or 0) > 0 then flags[#flags + 1] = { "OWNER WARRANT", HEX.red } end
        if regExp or inspExp then flags[#flags + 1] = { L.upper(L("police_system.query.expired")), HEX.orange } end
        if r.stolen or (r.ownerWarrants or 0) > 0 then accent = HEX.red elseif #flags > 0 then accent = HEX.orange end
    end
    if #flags > 0 then table.insert(lines, 1, flagLine(flags)) end
    local subtitle = r.kind == "person" and (safe(r.name) .. (r.npc and "  (NPC)" or "")) or safe(r.plate or "-")
    return {
        id = ID[r.kind],
        title = L.upper(L(r.kind == "person" and "police_system.query.person_check" or "police_system.query.vehicle_check")),
        subtitle = subtitle,
        description = table.concat(lines, "\n"),
        hint = L("police_system.query.details_mdc"),
        accent = accent,
    }
end

-- the pinned notification of a search
local function searchOpts(r)
    local cls = { legal = HEX.green, questionable = HEX.orange, illegal = HEX.red }
    local lines, illegal = {}, 0
    for _, it in ipairs(r.items or {}) do
        if it.class == "illegal" then illegal = illegal + 1 end
        lines[#lines + 1] = (cls[it.class] or HEX.text) .. L("police_system.item." .. tostring(it.id))
            .. HEX.dim .. "  ·  " .. L("police_system.search.class_" .. tostring(it.class))
            .. (it.seized and ("  ·  " .. L.upper(L("police_system.evidence.seized_tag"))) or "")
    end
    if #lines == 0 then lines[1] = HEX.dim .. L("police_system.search.nothing") end
    if illegal > 0 then
        table.insert(lines, 1, HEX.red .. L.upper(L("police_system.search.illegal_found")) .. " ×" .. illegal)
    end
    local label = L(r.what == "vehicle" and "police_system.query.plate" or "police_system.query.name")
    return {
        id = ID.search,
        title = L.upper(L(r.what == "vehicle" and "police_system.search.title_vehicle" or "police_system.search.title_person")),
        subtitle = label .. ":  " .. safe(r.name),
        description = table.concat(lines, "\n"),
        hint = L("police_system.search.logged_hint"),
        accent = illegal > 0 and HEX.red or HEX.green,
    }
end

local function clearAll()
    local ui = uic()
    if ui then for _, id in pairs(ID) do ui:removePinnedNotification(id) end end
end

local function closeStopMenu()
    local ok, m = pcall(function() return getResourceState(getResourceFromName("ui_inac")) == "running" and exports.ui_inac end)
    if ok and m then pcall(function() if m:isTempMenuOpen() then m:closeTempMenu() end end) end
end

POL.handle("query:result", function(r)
    if type(r) ~= "table" then return end
    local ui = uic()
    if not ui then return end
    local opts
    if r.kind == "search" then
        closeStopMenu()
        opts = searchOpts(r)
    elseif r.kind == "person" or r.kind == "vehicle" then
        opts = queryOpts(r)
    else
        return
    end
    ui:addPinnedNotification(opts)
end)

-- off duty: the results of the unit go
POL.on("unit", function(u) if not u then clearAll() end end)
