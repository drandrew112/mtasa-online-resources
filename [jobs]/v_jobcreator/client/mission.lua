if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Mission editing: the doc.mission helpers, the Mission Settings and Stages menus and the
-- menus of the mission elements (zones, peds, vehicles, items, interaction points).
-- The format is v_jobmanager's (mode_mission/README.md); the server sanitizes it
-- (server/sanitize.lua) and v_jobmanager validates the references on Check / Publish.

MissionEdit = {}

-- editor kind -> doc.mission list, id prefix
local LISTS = { zone = "zones", ped = "peds", mvehicle = "vehicles", item = "items", point = "points" }
local PREFIX = { zone = "zone", ped = "ped", mvehicle = "veh", item = "item", point = "point" }
MissionEdit.LISTS = LISTS

local function M() return Editor.doc and Editor.doc.mission end

function MissionEdit.isMission()
    return Editor.doc ~= nil and Editor.doc.type == "mission"
end

function MissionEdit.limits()
    local official = (Editor.meta and Editor.meta.official) or (Editor.doc and Editor.doc.scriptOnly)
    return official and CREATOR.OFFICIAL_MISSION or CREATOR.LIMITS.mission
end

function MissionEdit.list(kind)
    local m = M()
    return m and m[LISTS[kind]]
end

function MissionEdit.limit(kind)
    return MissionEdit.limits()[LISTS[kind]]
end

-- first free "<prefix><n>" over every mission list (ids are unique across lists)
function MissionEdit.newId(kind)
    local used = {}
    for _, name in pairs(LISTS) do
        for _, e in ipairs(M()[name] or {}) do used[e.id] = true end
    end
    local n = 1
    while used[PREFIX[kind] .. n] do n = n + 1 end
    return PREFIX[kind] .. n
end

function MissionEdit.newStageId()
    local used = {}
    for _, s in ipairs(M().stages) do used[s.id] = true end
    local n = 1
    while used["s" .. n] do n = n + 1 end
    return "s" .. n
end

-- entity by id -> entry, kind
function MissionEdit.find(id)
    for kind, name in pairs(LISTS) do
        for _, e in ipairs(M()[name] or {}) do
            if e.id == id then return e, kind end
        end
    end
end

-- "ped3 · Guard" style names for menus
function MissionEdit.entityName(e, kind)
    if not e then return "?" end
    if kind == "zone" then return L("v_jobcreator.mission.zone_name", { id = e.id, radius = e.radius }) end
    if kind == "ped" then return L("v_jobcreator.mission.ped_name", { id = e.id, behaviour = L("v_jobcreator.mission.beh." .. (e.behaviour or "guard")) }) end
    if kind == "mvehicle" then
        local names = Editor.info.vehicleNames or {}
        return L("v_jobcreator.mission.vehicle_name", { id = e.id, model = names[e.model] or getVehicleNameFromModel(e.model) or tostring(e.model), role = L("v_jobcreator.mission.role." .. (e.role or "loot")) })
    end
    if kind == "item" then
        local def = CATALOG.missionItem[e.item]
        return L("v_jobcreator.mission.item_name", { id = e.id, item = e.label or (def and def.name) or e.item })
    end
    if kind == "point" then return L("v_jobcreator.mission.point_name", { id = e.id, label = e.label or L("v_jobcreator.mission.no_label") }) end
    return e.id
end

local function nameOf(id)
    local e, kind = MissionEdit.find(id)
    return e and MissionEdit.entityName(e, kind) or (tostring(id) .. " (?)")
end

-- an objective in one line ("Enter zone: zone2 (8 m) · all players")
function MissionEdit.objectiveText(o)
    local t = L("v_jobcreator.mission.obj." .. tostring(o.type):lower())
    local parts = {}
    for _, key in ipairs({ "vehicle", "item", "zone", "point", "ped" }) do
        if o[key] then parts[#parts + 1] = nameOf(o[key]) end
    end
    if o.type == "killPeds" then parts[#parts + 1] = o.all and L("v_jobcreator.mission.all_enemies") or L("v_jobcreator.mission.count", { count = #(o.peds or {}) }) end
    if o.seconds then parts[#parts + 1] = o.seconds .. " s" end
    if o.type == "scriptEvent" then parts[#parts + 1] = o.name or "?" end
    if o.who == "all" then parts[#parts + 1] = L("v_jobcreator.mission.all_players") end
    local text = t
    if #parts > 0 then text = text .. ": " .. table.concat(parts, " · ") end
    if o.label then text = text .. "  \"" .. o.label .. "\"" end
    return text
end

-- An entity is gone: objectives / fail conditions that point at it go too, and its id leaves
-- every despawn and kill list. -> number of removed objectives
function MissionEdit.removeRefs(doc, id)
    local removed = 0
    for _, s in ipairs(doc.mission.stages) do
        for _, field in ipairs({ "objectives", "fail" }) do
            local list = s[field] or {}
            for i = #list, 1, -1 do
                local o = list[i]
                local uses = o.zone == id or o.vehicle == id or o.item == id or o.point == id or o.ped == id
                if o.peds then
                    for j = #o.peds, 1, -1 do if o.peds[j] == id then table.remove(o.peds, j) end end
                    if not o.all and #o.peds == 0 then uses = true end
                end
                if uses then table.remove(list, i) removed = removed + 1 end
            end
        end
        if s.despawn then
            for j = #s.despawn, 1, -1 do if s.despawn[j] == id then table.remove(s.despawn, j) end end
        end
    end
    return removed
end

-- what the client can tell before the server check
function MissionEdit.problems(list)
    local m = M()
    if #m.stages == 0 then list[#list + 1] = L("v_jobcreator.mission.problem_no_stages") end
    for i, s in ipairs(m.stages) do
        if #s.objectives == 0 then list[#list + 1] = L("v_jobcreator.mission.problem_empty_stage", { stage = i, title = s.title }) end
    end
    if #m.loadout == 0 then list[#list + 1] = L("v_jobcreator.mission.problem_no_weapons") end
end

--------------------------------------------------------------------------------
-- menu building helpers (same item format as client/menus.lua)
--------------------------------------------------------------------------------

local function leaf(label, value, desc, extra)
    local item = { label = label, value = value, desc = desc }
    for k, v in pairs(extra or {}) do item[k] = v end
    return item
end

local function sub(label, items, desc, title)
    return { label = label, items = items, desc = desc, title = title or L.upper(label) }
end

local function pickList(action, values, current, fmt, extraArgs)
    local items = {}
    for _, v in ipairs(values) do
        local value = { action }
        for _, a in ipairs(extraArgs or {}) do value[#value + 1] = a end
        value[#value + 1] = v
        items[#items + 1] = leaf(fmt and fmt(v) or tostring(v), value, nil, { checked = v == current, closeOnSelect = false })
    end
    return items
end

local function minutes(v) return v == 0 and L("v_jobcreator.mission.no_limit") or L("v_jobcreator.mission.minutes", { n = v }) end
local function seconds(v) return v == 0 and L("v_jobcreator.mission.no_limit") or (v .. " s") end
local function money(v) return v == 0 and L("v_jobcreator.mission.automatic") or ("€" .. v) end
local function xp(v) return v == 0 and L("v_jobcreator.mission.automatic") or (v .. " XP") end

--------------------------------------------------------------------------------
-- Mission Settings (hub submenu)
--------------------------------------------------------------------------------

function MissionEdit.settingsMenu()
    local m = M()
    local reward = m.reward or {}
    local weapons = {}
    local inLoadout = {}
    for _, w in ipairs(m.loadout) do inLoadout[w.id] = true end
    for _, cat in ipairs(CATALOG.weapons) do
        local items = {}
        for _, id in ipairs(cat.items) do
            items[#items + 1] = leaf(getWeaponNameFromID(id) or tostring(id), { "mWeapon", id }, nil, { checked = inLoadout[id] == true, closeOnSelect = false })
        end
        weapons[#weapons + 1] = sub(cat.name, items)
    end
    local ammo = m.loadout[1] and m.loadout[1].ammo or 300
    local items = {
        sub(L("v_jobcreator.mission.team_lives"), pickList("mLives", CATALOG.teamLives, m.teamLives), L("v_jobcreator.mission.team_lives_desc", { n = m.teamLives })),
        sub(L("v_jobcreator.mission.time_limit"), pickList("mTime", CATALOG.missionMinutes, math.floor((m.timeLimit or 0) / 60), minutes), minutes(math.floor((m.timeLimit or 0) / 60))),
        sub(L("v_jobcreator.mission.weapons"), weapons, L("v_jobcreator.mission.weapons_desc", { n = #m.loadout })),
        sub(L("v_jobcreator.mission.ammo"), pickList("mAmmo", CATALOG.ammo, ammo), "now: " .. ammo),
        sub(L("v_jobcreator.mission.armour"), pickList("mArmour", CATALOG.armour, m.armour or 0), "now: " .. (m.armour or 0)),
        sub(L("v_jobcreator.mission.reward_money"), pickList("mMoney", CATALOG.rewardMoney, reward.money or 0, money), money(reward.money or 0)),
        sub(L("v_jobcreator.mission.reward_xp"), pickList("mXp", CATALOG.rewardXp, reward.xp or 0, xp), xp(reward.xp or 0)),
    }
    if Editor.info.officialAdmin then
        items[#items + 1] = leaf(L("v_jobcreator.mission.script_only"), { "mScript" }, L("v_jobcreator.mission.script_only_desc"),
            { checked = Editor.doc.scriptOnly == true, closeOnSelect = false })
    end
    return sub(L("v_jobcreator.mission.settings"), items)
end

--------------------------------------------------------------------------------
-- Stages
--------------------------------------------------------------------------------

function MissionEdit.stagesMenu()
    local items = {}
    for i, s in ipairs(M().stages) do
        items[#items + 1] = leaf(i .. ". " .. s.title, { "stOpen", i }, L("v_jobcreator.mission.stage_desc", { objectives = #s.objectives }))
    end
    items[#items + 1] = leaf(L("v_jobcreator.mission.add_stage"), { "stAdd" })
    return sub(L("v_jobcreator.mission.stages"), items, L("v_jobcreator.mission.stages_desc", { n = #M().stages }))
end

-- entity pick lists: every entity of the kinds, value = base .. { id }
local function entityPicks(kinds, base, filter)
    local items = {}
    for _, kind in ipairs(kinds) do
        for _, e in ipairs(MissionEdit.list(kind) or {}) do
            if not filter or filter(e, kind) then
                local value = {}
                for i, v in ipairs(base) do value[i] = v end
                value[#value + 1] = e.id
                items[#items + 1] = leaf(MissionEdit.entityName(e, kind), value)
            end
        end
    end
    if #items == 0 then items[1] = leaf(L("v_jobcreator.mission.none_placed"), { "none" }, nil, { closeOnSelect = false }) end
    return items
end

-- Add objective: type -> target(s). Two-target types pick the first target, then the zone.
local function addObjectiveMenu(si)
    local types = {}
    local function zones(base) return entityPicks({ "zone" }, base) end
    for _, t in ipairs(CATALOG.objectiveTypes) do
        local label = L("v_jobcreator.mission.obj." .. t:lower())
        local items
        if t == "enterZone" or t == "stayInZone" then
            items = zones({ "objAdd", si, t })
        elseif t == "enterVehicle" or t == "destroyVehicle" then
            items = entityPicks({ "mvehicle" }, { "objAdd", si, t })
        elseif t == "deliverVehicle" then
            items = {}
            for _, v in ipairs(MissionEdit.list("mvehicle")) do
                items[#items + 1] = sub(MissionEdit.entityName(v, "mvehicle"), zones({ "objAdd2", si, t, v.id }))
            end
        elseif t == "collectItem" then
            items = entityPicks({ "item" }, { "objAdd", si, t })
        elseif t == "deliverItem" then
            items = {}
            for _, it in ipairs(MissionEdit.list("item")) do
                items[#items + 1] = sub(MissionEdit.entityName(it, "item"), zones({ "objAdd2", si, t, it.id }))
            end
        elseif t == "killPeds" then
            items = { leaf(L("v_jobcreator.mission.all_enemies"), { "objAdd", si, t, "__all" }) }
            for _, e in ipairs(entityPicks({ "ped", "mvehicle" }, { "objAdd", si, t }, function(e, kind)
                return (kind == "ped" and e.behaviour ~= "civilian") or (kind == "mvehicle" and e.role == "enemy")
            end)) do items[#items + 1] = e end
        elseif t == "interact" then
            items = entityPicks({ "point" }, { "objAdd", si, t })
        elseif t == "survive" then
            items = pickList("objAdd", CATALOG.holdSeconds, nil, seconds, { si, t })
        elseif t == "scriptEvent" then
            items = nil
        end
        if items then
            if #items == 0 then items[1] = leaf(L("v_jobcreator.mission.none_placed"), { "none" }, nil, { closeOnSelect = false }) end
            types[#types + 1] = sub(label, items, L("v_jobcreator.mission.objdesc." .. t:lower()))
        else
            types[#types + 1] = leaf(label, { "objAddEvent", si }, L("v_jobcreator.mission.objdesc." .. t:lower()))
        end
    end
    return sub(L("v_jobcreator.mission.add_objective"), types)
end

local function objectiveMenu(si, oi, o)
    local items = {}
    if o.type == "enterZone" or o.type == "stayInZone" or o.type == "enterVehicle" then
        items[#items + 1] = leaf(L("v_jobcreator.mission.every_player"), { "objWho", si, oi }, L("v_jobcreator.mission.every_player_desc"),
            { checked = o.who == "all", closeOnSelect = false })
    end
    if o.type == "stayInZone" or o.type == "survive" then
        items[#items + 1] = sub(L("v_jobcreator.mission.duration"), pickList("objSec", CATALOG.holdSeconds, o.seconds, seconds, { si, oi }), (o.seconds or 30) .. " s")
    end
    if o.type == "enterZone" then
        items[#items + 1] = sub(L("v_jobcreator.mission.in_vehicle"), (function()
            local list = { leaf(L("v_jobcreator.mission.any_or_on_foot"), { "objVeh", si, oi, false }, nil, { checked = o.vehicle == nil, closeOnSelect = false }) }
            for _, v in ipairs(MissionEdit.list("mvehicle")) do
                list[#list + 1] = leaf(MissionEdit.entityName(v, "mvehicle"), { "objVeh", si, oi, v.id }, nil, { checked = o.vehicle == v.id, closeOnSelect = false })
            end
            return list
        end)())
    end
    if o.type == "killPeds" then
        local list = { leaf(L("v_jobcreator.mission.all_enemies"), { "objAll", si, oi }, L("v_jobcreator.mission.all_enemies_desc"), { checked = o.all == true, closeOnSelect = false }) }
        local chosen = {}
        for _, id in ipairs(o.peds or {}) do chosen[id] = true end
        for _, kind in ipairs({ "ped", "mvehicle" }) do
            for _, e in ipairs(MissionEdit.list(kind)) do
                if (kind == "ped" and e.behaviour ~= "civilian") or (kind == "mvehicle" and e.role == "enemy") then
                    list[#list + 1] = leaf(MissionEdit.entityName(e, kind), { "objPed", si, oi, e.id }, nil, { checked = chosen[e.id] == true, closeOnSelect = false })
                end
            end
        end
        items[#items + 1] = sub(L("v_jobcreator.mission.targets"), list)
    end
    if o.type == "scriptEvent" then
        items[#items + 1] = leaf(L("v_jobcreator.mission.event_name"), { "objName", si, oi }, o.name)
    end
    items[#items + 1] = leaf(L("v_jobcreator.mission.label"), { "objLabel", si, oi }, o.label or L("v_jobcreator.mission.label_desc"))
    items[#items + 1] = sub(L("v_jobcreator.mission.remove"), { leaf(L("v_jobcreator.mission.yes_remove"), { "objDel", si, oi }) })
    return sub(MissionEdit.objectiveText(o), items)
end

local function failMenu(si, s)
    local items = {}
    for fi, f in ipairs(s.fail or {}) do
        items[#items + 1] = sub(MissionEdit.objectiveText(f), { leaf(L("v_jobcreator.mission.yes_remove"), { "failDel", si, fi }) })
    end
    items[#items + 1] = sub(L("v_jobcreator.mission.add_fail"), {
        sub(L("v_jobcreator.mission.obj.vehicledestroyed"), entityPicks({ "mvehicle" }, { "failAdd", si, "vehicleDestroyed", "vehicle" })),
        sub(L("v_jobcreator.mission.obj.peddied"), entityPicks({ "ped" }, { "failAdd", si, "pedDied", "ped" })),
        sub(L("v_jobcreator.mission.obj.leavezone"), entityPicks({ "zone" }, { "failAdd", si, "leaveZone", "zone" })),
    })
    return sub(L("v_jobcreator.mission.fail_conditions"), items, L("v_jobcreator.mission.count", { count = #(s.fail or {}) }))
end

function MissionEdit.openStage(si)
    local s = M().stages[si]
    if not s then return Menus.openHub() end
    local objectives = {}
    for oi, o in ipairs(s.objectives) do objectives[#objectives + 1] = objectiveMenu(si, oi, o) end
    objectives[#objectives + 1] = addObjectiveMenu(si)

    local despawn = {}
    local removed = {}
    for _, id in ipairs(s.despawn or {}) do removed[id] = true end
    for _, kind in ipairs({ "ped", "mvehicle", "item" }) do
        for _, e in ipairs(MissionEdit.list(kind)) do
            despawn[#despawn + 1] = leaf(MissionEdit.entityName(e, kind), { "stDespawn", si, e.id }, nil, { checked = removed[e.id] == true, closeOnSelect = false })
        end
    end
    if #despawn == 0 then despawn[1] = leaf(L("v_jobcreator.mission.none_placed"), { "none" }, nil, { closeOnSelect = false }) end

    local items = {
        leaf(L("v_jobcreator.mission.title"), { "stTitle", si }, s.title),
        sub(L("v_jobcreator.mission.objectives"), objectives, L("v_jobcreator.mission.count", { count = #s.objectives })),
        sub(L("v_jobcreator.mission.complete_when"), {
            leaf(L("v_jobcreator.mission.complete_all"), { "stComplete", si, "all" }, nil, { checked = s.complete ~= "any", closeOnSelect = false }),
            leaf(L("v_jobcreator.mission.complete_any"), { "stComplete", si, "any" }, nil, { checked = s.complete == "any", closeOnSelect = false }),
        }),
        failMenu(si, s),
        sub(L("v_jobcreator.mission.time_limit"), pickList("stTime", CATALOG.stageSeconds, s.timeLimit or 0, seconds, { si }), seconds(s.timeLimit or 0)),
        leaf(L("v_jobcreator.mission.respawn_here"), { "stRespawn", si }, s.respawnPoint and L("v_jobcreator.mission.respawn_set") or L("v_jobcreator.mission.respawn_default")),
    }
    if s.respawnPoint then items[#items + 1] = leaf(L("v_jobcreator.mission.respawn_clear"), { "stRespawnClear", si }) end
    items[#items + 1] = sub(L("v_jobcreator.mission.removed_at_start"), despawn, L("v_jobcreator.mission.removed_at_start_desc"))
    if si > 1 then items[#items + 1] = leaf(L("v_jobcreator.mission.move_up"), { "stMove", si, -1 }) end
    if si < #M().stages then items[#items + 1] = leaf(L("v_jobcreator.mission.move_down"), { "stMove", si, 1 }) end
    items[#items + 1] = leaf(L("v_jobcreator.mission.test_from_here"), { "test", "mission", s.id })
    items[#items + 1] = sub(L("v_jobcreator.mission.delete_stage"), { leaf(L("v_jobcreator.mission.yes_remove"), { "stDel", si }) })
    items[#items + 1] = leaf(L("common.back"), { "hub" })
    Menus.openCustom("stage", L.upper(si .. ". " .. s.title), items)
    Menus.stage = si
end

--------------------------------------------------------------------------------
-- element menus (Menus.openItem adds these rows for the mission kinds)
--------------------------------------------------------------------------------

local function stageRows(ref, items)
    local appears = { leaf(L("v_jobcreator.mission.mission_start"), { "eStage", false }, nil, { checked = ref.stage == nil, closeOnSelect = false }) }
    local removes = {}
    for _, s in ipairs(M().stages) do
        appears[#appears + 1] = leaf(s.title, { "eStage", s.id }, nil, { checked = ref.stage == s.id, closeOnSelect = false })
        local on = false
        for _, id in ipairs(s.despawn or {}) do if id == ref.id then on = true end end
        removes[#removes + 1] = leaf(s.title, { "eDespawn", s.id }, nil, { checked = on, closeOnSelect = false })
    end
    items[#items + 1] = sub(L("v_jobcreator.mission.appears_at"), appears, L("v_jobcreator.mission.appears_at_desc"))
    items[#items + 1] = sub(L("v_jobcreator.mission.removed_at"), removes, L("v_jobcreator.mission.removed_at_desc"))
end

local function skinMenu(action, current)
    local cats = {}
    for _, cat in ipairs(CATALOG.skins) do
        cats[#cats + 1] = sub(cat.name, pickList(action, cat.items, current, function(v) return L("v_jobcreator.mission.skin", { id = v }) end))
    end
    return sub(L("v_jobcreator.mission.skin_menu"), cats, L("v_jobcreator.mission.skin", { id = current }))
end

local function weaponPick(action, current)
    local cats = { leaf(L("v_jobcreator.mission.unarmed"), { action, 0 }, nil, { checked = not current or current == 0, closeOnSelect = false }) }
    for _, cat in ipairs(CATALOG.weapons) do
        cats[#cats + 1] = sub(cat.name, pickList(action, cat.items, current, function(v) return getWeaponNameFromID(v) or tostring(v) end))
    end
    return sub(L("v_jobcreator.mission.weapon"), cats, current and current > 0 and (getWeaponNameFromID(current) or tostring(current)) or L("v_jobcreator.mission.unarmed"))
end

function MissionEdit.itemRows(item, items)
    local ref, kind = item.ref, item.kind
    items[#items + 1] = leaf(ref.id, { "none" }, MissionEdit.entityName(ref, kind), { closeOnSelect = false })
    if kind == "zone" then
        items[#items + 1] = sub(L("v_jobcreator.mission.radius"), pickList("zRadius", CATALOG.zoneRadii, ref.radius, function(v) return v .. " m" end), ref.radius .. " m")
        items[#items + 1] = sub(L("v_jobcreator.mission.height"), pickList("zHeight", CATALOG.zoneHeights, ref.height, function(v) return v .. " m" end), (ref.height or 8) .. " m")
    elseif kind == "ped" then
        items[#items + 1] = skinMenu("pSkin", ref.skin)
        items[#items + 1] = weaponPick("pWeapon", ref.weapon)
        items[#items + 1] = sub(L("v_jobcreator.mission.behaviour"), pickList("pBeh", CATALOG.pedBehaviours, ref.behaviour, function(v) return L("v_jobcreator.mission.beh." .. v) end),
            L("v_jobcreator.mission.behdesc." .. (ref.behaviour or "guard")))
        if ref.behaviour == "patrol" then
            items[#items + 1] = leaf(L("v_jobcreator.mission.patrol_add"), { "pPatrolAdd" }, L("v_jobcreator.mission.patrol_points", { n = #(ref.patrol or {}) }), { closeOnSelect = false })
            items[#items + 1] = leaf(L("v_jobcreator.mission.patrol_clear"), { "pPatrolClear" })
        end
        items[#items + 1] = sub(L("v_jobcreator.mission.health"), pickList("pHealth", CATALOG.pedHealth, ref.health), tostring(ref.health or 100))
        items[#items + 1] = sub(L("v_jobcreator.mission.armour"), pickList("pArmor", CATALOG.armour, ref.armor or 0), tostring(ref.armor or 0))
        items[#items + 1] = sub(L("v_jobcreator.mission.accuracy"), pickList("pAcc", CATALOG.accuracies, ref.accuracy, function(v) return math.floor(v * 100) .. "%" end), math.floor((ref.accuracy or 0.4) * 100) .. "%")
        items[#items + 1] = sub(L("v_jobcreator.mission.aggro"), pickList("pAggro", CATALOG.aggroRadii, ref.aggroRadius, function(v) return v .. " m" end), (ref.aggroRadius or 35) .. " m")
        stageRows(ref, items)
    elseif kind == "mvehicle" then
        local names = Editor.info.vehicleNames or {}
        local cats = {}
        for _, cat in ipairs(CATALOG.vehicles) do
            cats[#cats + 1] = sub(cat.name, pickList("vModel", cat.items, ref.model, function(v) return names[v] or tostring(v) end))
        end
        items[#items + 1] = sub(L("v_jobcreator.mission.model"), cats, names[ref.model] or tostring(ref.model))
        items[#items + 1] = sub(L("v_jobcreator.mission.role"), pickList("vRole", CATALOG.vehicleRoles, ref.role, function(v) return L("v_jobcreator.mission.role." .. v) end),
            L("v_jobcreator.mission.roledesc." .. (ref.role or "loot")))
        if ref.role == "enemy" then
            items[#items + 1] = sub(L("v_jobcreator.mission.behaviour"), pickList("vBeh", { "park", "pursue" }, ref.behaviour or "park", function(v) return L("v_jobcreator.mission.vbeh." .. v) end))
            items[#items + 1] = sub(L("v_jobcreator.mission.crew"), pickList("vCrew", CATALOG.crewSizes, ref.crew or 1), L("v_jobcreator.mission.crew_desc"))
            local driver = ref.driver or {}
            items[#items + 1] = skinMenu("vSkin", driver.skin or 102)
            items[#items + 1] = weaponPick("vWeapon", driver.weapon or 28)
        else
            items[#items + 1] = leaf(L("v_jobcreator.mission.locked"), { "vLocked" }, nil, { checked = ref.locked == true, closeOnSelect = false })
        end
        stageRows(ref, items)
    elseif kind == "item" then
        local types = {}
        for _, entry in ipairs(CATALOG.missionItems) do
            types[#types + 1] = leaf(entry[3], { "iType", entry[1] }, nil, { checked = ref.item == entry[1], closeOnSelect = false })
        end
        items[#items + 1] = sub(L("v_jobcreator.mission.item_type"), types)
        items[#items + 1] = leaf(L("v_jobcreator.mission.label"), { "eLabel" }, ref.label or L("v_jobcreator.mission.label_desc"))
        stageRows(ref, items)
    elseif kind == "point" then
        items[#items + 1] = leaf(L("v_jobcreator.mission.label"), { "eLabel" }, ref.label or L("v_jobcreator.mission.label_desc"))
        items[#items + 1] = sub(L("v_jobcreator.mission.hold_time"), pickList("ptHold", CATALOG.interactSeconds, math.floor((ref.holdMs or 3000) / 1000), function(v) return v .. " s" end))
    end
end

--------------------------------------------------------------------------------
-- actions (merged into Menus.actions)
--------------------------------------------------------------------------------

local A = {}
MissionEdit.actions = A

local function change(fn, reopen)
    Editor.change(function(doc) fn(doc.mission, doc) end)
    if reopen then reopen() end
end

local function itemField(key, value, group)
    local item = Menus.item
    if not item then return end
    Editor.change(function() item.ref[key] = value end)
    if group then Menus.retick(group, value) end
end

-- settings
A.mLives = function(v) change(function(m) m.teamLives = v[2] end) Menus.retick("mLives", v[2]) end
A.mTime = function(v) change(function(m) m.timeLimit = v[2] > 0 and v[2] * 60 or nil end) Menus.retick("mTime", v[2]) end
A.mArmour = function(v) change(function(m) m.armour = v[2] end) Menus.retick("mArmour", v[2]) end
A.mAmmo = function(v) change(function(m) for _, w in ipairs(m.loadout) do w.ammo = v[2] end end) Menus.retick("mAmmo", v[2]) end
A.mMoney = function(v)
    change(function(m)
        local r = m.reward or {}
        r.money = v[2]
        m.reward = ((r.money or 0) > 0 or (r.xp or 0) > 0) and { money = r.money or 0, xp = r.xp or 0 } or nil
    end)
    Menus.retick("mMoney", v[2])
end
A.mXp = function(v)
    change(function(m)
        local r = m.reward or {}
        r.xp = v[2]
        m.reward = ((r.money or 0) > 0 or (r.xp or 0) > 0) and { money = r.money or 0, xp = r.xp or 0 } or nil
    end)
    Menus.retick("mXp", v[2])
end
A.mWeapon = function(v, path)
    local id, on = v[2], nil
    change(function(m)
        for i, w in ipairs(m.loadout) do
            if w.id == id then table.remove(m.loadout, i) on = false return end
        end
        if #m.loadout >= 4 then notify(L("v_jobcreator.mission.max_weapons")) on = false return end
        m.loadout[#m.loadout + 1] = { id = id, ammo = m.loadout[1] and m.loadout[1].ammo or 300 }
        on = true
    end)
    inac:updateTempMenuItem(path, { checked = on })
end
A.mScript = function(v, path)
    local on = Editor.doc.scriptOnly ~= true
    Editor.change(function(doc) doc.scriptOnly = on or nil end)
    inac:updateTempMenuItem(path, { checked = on })
    if on then notify(L("v_jobcreator.mission.script_only_on")) end
end

-- stages
A.stOpen = function(v) MissionEdit.openStage(v[2]) end
A.hub = function() Menus.openHub() end
A.stAdd = function()
    local id
    change(function(m)
        if #m.stages >= MissionEdit.limits().stages then return end
        id = MissionEdit.newStageId()
        m.stages[#m.stages + 1] = { id = id, title = L("v_jobcreator.mission.stage_n", { n = #m.stages + 1 }), objectives = {} }
    end)
    MissionEdit.openStage(#M().stages)
end
A.stTitle = function(v)
    local si = v[2]
    Menus.askText(L("v_jobcreator.mission.title"), 80, M().stages[si].title, function(text)
        if text ~= "" then change(function(m) m.stages[si].title = text end) end
        MissionEdit.openStage(si)
    end)
end
A.stComplete = function(v) change(function(m) m.stages[v[2]].complete = v[3] == "any" and "any" or nil end) Menus.retick("stComplete", v[3], 3) end
A.stTime = function(v) change(function(m) m.stages[v[2]].timeLimit = v[3] > 0 and v[3] or nil end) Menus.retick("stTime", v[3], 3) end
A.stRespawn = function(v)
    if Editor.camMode == "free" then Freecam.stop() end
    local x, y, z = getElementPosition(localPlayer)
    local rz = select(3, getElementRotation(localPlayer))
    change(function(m) m.stages[v[2]].respawnPoint = { math.floor(x * 1000) / 1000, math.floor(y * 1000) / 1000, math.floor(z * 1000) / 1000, math.floor(rz) } end)
    notify(L("v_jobcreator.mission.respawn_saved"))
    MissionEdit.openStage(v[2])
end
A.stRespawnClear = function(v) change(function(m) m.stages[v[2]].respawnPoint = nil end) MissionEdit.openStage(v[2]) end
A.stDespawn = function(v, path)
    local si, id, on = v[2], v[3], true
    change(function(m)
        local s = m.stages[si]
        s.despawn = s.despawn or {}
        for i, x in ipairs(s.despawn) do if x == id then table.remove(s.despawn, i) on = false break end end
        if on then s.despawn[#s.despawn + 1] = id end
        if #s.despawn == 0 then s.despawn = nil end
    end)
    inac:updateTempMenuItem(path, { checked = on })
end
A.stMove = function(v)
    local si, d = v[2], v[3]
    change(function(m)
        local j = si + d
        if m.stages[j] then m.stages[si], m.stages[j] = m.stages[j], m.stages[si] end
    end)
    MissionEdit.openStage(math.max(1, math.min(#M().stages, si + d)))
end
A.stDel = function(v)
    local si = v[2]
    change(function(m)
        local id = m.stages[si].id
        table.remove(m.stages, si)
        for _, name in ipairs({ "peds", "vehicles", "items" }) do
            for _, e in ipairs(m[name]) do if e.stage == id then e.stage = nil end end
        end
        for _, s in ipairs(m.stages) do if s.next == id then s.next = nil end end
    end)
    Menus.openHub()
end

-- objectives
local function addObjective(si, o)
    change(function(m)
        local s = m.stages[si]
        if #s.objectives >= MissionEdit.limits().objectives then notify(L("v_jobcreator.tools.limit_reached", { max = MissionEdit.limits().objectives })) return end
        s.objectives[#s.objectives + 1] = o
    end)
    MissionEdit.openStage(si)
end

local TARGET_KEY = { enterZone = "zone", stayInZone = "zone", enterVehicle = "vehicle", destroyVehicle = "vehicle", collectItem = "item", interact = "point" }

A.objAdd = function(v)
    local si, t, arg = v[2], v[3], v[4]
    local o = { type = t }
    if TARGET_KEY[t] then o[TARGET_KEY[t]] = arg end
    if t == "stayInZone" then o.seconds = 30 end
    if t == "survive" then o.seconds = arg end
    if t == "killPeds" then
        if arg == "__all" then o.all = true else o.peds = { arg } end
    end
    addObjective(si, o)
end
A.objAdd2 = function(v)
    local si, t, first, zone = v[2], v[3], v[4], v[5]
    addObjective(si, { type = t, [t == "deliverVehicle" and "vehicle" or "item"] = first, zone = zone })
end
A.objAddEvent = function(v)
    local si = v[2]
    Menus.askText(L("v_jobcreator.mission.event_name"), 24, "signal", function(text)
        text = text:gsub("[^%w_]", "")
        if text ~= "" then addObjective(si, { type = "scriptEvent", name = text }) else MissionEdit.openStage(si) end
    end)
end
local function objective(v) local s = M().stages[v[2]] return s and s.objectives[v[3]] end
A.objWho = function(v, path)
    local on = objective(v).who ~= "all"
    change(function(m) m.stages[v[2]].objectives[v[3]].who = on and "all" or nil end)
    inac:updateTempMenuItem(path, { checked = on })
end
A.objSec = function(v) change(function(m) m.stages[v[2]].objectives[v[3]].seconds = v[4] end) Menus.retick("objSec", v[4], 4) end
A.objVeh = function(v) change(function(m) m.stages[v[2]].objectives[v[3]].vehicle = v[4] or nil end) Menus.retick("objVeh", v[4], 4) end
A.objAll = function(v, path)
    local on = objective(v).all ~= true
    change(function(m)
        local o = m.stages[v[2]].objectives[v[3]]
        o.all = on or nil
        if on then o.peds = nil else o.peds = o.peds or {} end
    end)
    inac:updateTempMenuItem(path, { checked = on })
end
A.objPed = function(v, path)
    local id, on = v[4], true
    change(function(m)
        local o = m.stages[v[2]].objectives[v[3]]
        o.all, o.peds = nil, o.peds or {}
        for i, x in ipairs(o.peds) do if x == id then table.remove(o.peds, i) on = false break end end
        if on then o.peds[#o.peds + 1] = id end
    end)
    inac:updateTempMenuItem(path, { checked = on })
end
A.objLabel = function(v)
    local si, oi = v[2], v[3]
    Menus.askText(L("v_jobcreator.mission.label"), 60, objective(v).label or "", function(text)
        change(function(m) m.stages[si].objectives[oi].label = text ~= "" and text or nil end)
        MissionEdit.openStage(si)
    end)
end
A.objName = function(v)
    local si, oi = v[2], v[3]
    Menus.askText(L("v_jobcreator.mission.event_name"), 24, objective(v).name or "", function(text)
        text = text:gsub("[^%w_]", "")
        if text ~= "" then change(function(m) m.stages[si].objectives[oi].name = text end) end
        MissionEdit.openStage(si)
    end)
end
A.objDel = function(v) change(function(m) table.remove(m.stages[v[2]].objectives, v[3]) end) MissionEdit.openStage(v[2]) end
A.failAdd = function(v)
    local si, t, key, id = v[2], v[3], v[4], v[5]
    change(function(m)
        local s = m.stages[si]
        s.fail = s.fail or {}
        if #s.fail >= MissionEdit.limits().fails then return end
        s.fail[#s.fail + 1] = { type = t, [key] = id }
    end)
    MissionEdit.openStage(si)
end
A.failDel = function(v)
    change(function(m)
        local s = m.stages[v[2]]
        table.remove(s.fail, v[3])
        if #s.fail == 0 then s.fail = nil end
    end)
    MissionEdit.openStage(v[2])
end

-- element fields (Menus.item = the selected element)
A.zRadius = function(v) itemField("radius", v[2], "zRadius") end
A.zHeight = function(v) itemField("height", v[2], "zHeight") end
A.pSkin = function(v) itemField("skin", v[2], "pSkin") end
A.pWeapon = function(v)
    local item = Menus.item
    if not item then return end
    Editor.change(function()
        item.ref.weapon = v[2] > 0 and v[2] or nil
        item.ref.ammo = v[2] > 0 and (item.ref.ammo or 300) or nil
    end)
    Menus.retick("pWeapon", v[2])
end
A.pBeh = function(v)
    itemField("behaviour", v[2], "pBeh")
    local item = Menus.item
    if item and v[2] == "patrol" then Menus.openItem(item) end
end
A.pPatrolAdd = function(v, path)
    local item = Menus.item
    if not item then return end
    if Editor.camMode == "free" then Freecam.stop() end
    local x, y, z = getElementPosition(localPlayer)
    Editor.change(function()
        item.ref.patrol = item.ref.patrol or { { item.ref.x, item.ref.y, item.ref.z } }
        if #item.ref.patrol < MissionEdit.limits().patrol then
            item.ref.patrol[#item.ref.patrol + 1] = { math.floor(x * 1000) / 1000, math.floor(y * 1000) / 1000, math.floor(z * 1000) / 1000 }
        end
    end)
    notify(L("v_jobcreator.mission.patrol_points", { n = #item.ref.patrol }))
end
A.pPatrolClear = function() itemField("patrol", nil) end
A.pHealth = function(v) itemField("health", v[2], "pHealth") end
A.pArmor = function(v) itemField("armor", v[2], "pArmor") end
A.pAcc = function(v) itemField("accuracy", v[2], "pAcc") end
A.pAggro = function(v) itemField("aggroRadius", v[2], "pAggro") end
A.vModel = function(v) itemField("model", v[2], "vModel") end
A.vRole = function(v)
    local item = Menus.item
    if not item then return end
    Editor.change(function()
        local ref = item.ref
        ref.role = v[2]
        if v[2] == "enemy" then
            ref.behaviour, ref.crew = ref.behaviour or "park", ref.crew or 1
            ref.driver = ref.driver or { skin = 102, weapon = 28 }
            ref.locked = nil
        else
            ref.behaviour, ref.crew, ref.driver = nil, nil, nil
        end
    end)
    Menus.openItem(item)
end
A.vBeh = function(v) itemField("behaviour", v[2], "vBeh") end
A.vCrew = function(v) itemField("crew", v[2], "vCrew") end
A.vSkin = function(v)
    local item = Menus.item
    if not item then return end
    Editor.change(function() item.ref.driver = item.ref.driver or {} item.ref.driver.skin = v[2] end)
    Menus.retick("vSkin", v[2])
end
A.vWeapon = function(v)
    local item = Menus.item
    if not item then return end
    Editor.change(function() item.ref.driver = item.ref.driver or {} item.ref.driver.weapon = v[2] > 0 and v[2] or 28 end)
    Menus.retick("vWeapon", v[2])
end
A.vLocked = function(v, path)
    local item = Menus.item
    if not item then return end
    local on = item.ref.locked ~= true
    Editor.change(function() item.ref.locked = on or nil end)
    inac:updateTempMenuItem(path, { checked = on })
end
A.iType = function(v) itemField("item", v[2], "iType") end
A.ptHold = function(v) itemField("holdMs", v[2] * 1000, nil) Menus.retick("ptHold", v[2]) end
A.eLabel = function()
    local item = Menus.item
    if not item then return end
    Menus.askText(L("v_jobcreator.mission.label"), 40, item.ref.label or "", function(text)
        Editor.change(function() item.ref.label = text ~= "" and text or nil end)
        Menus.openItem(item)
    end)
end
A.eStage = function(v)
    itemField("stage", v[2] or nil, nil)
    Menus.retick("eStage", v[2])
end
A.eDespawn = function(v, path)
    local item = Menus.item
    if not item then return end
    local id, on = item.ref.id, true
    change(function(m)
        for _, s in ipairs(m.stages) do
            if s.id == v[2] then
                s.despawn = s.despawn or {}
                for i, x in ipairs(s.despawn) do if x == id then table.remove(s.despawn, i) on = false break end end
                if on then s.despawn[#s.despawn + 1] = id end
                if #s.despawn == 0 then s.despawn = nil end
            end
        end
    end)
    inac:updateTempMenuItem(path, { checked = on })
end
