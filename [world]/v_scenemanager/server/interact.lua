-- ui_interactobject menus on the editor's scene vehicles / peds (X opens, 1-9 picks).
-- Only the editing player sees them, so every label is resolved here in that player's language (L.forPlayer).
-- Element changes are not saved to disk until Save.

Interact = {}

local IO = "ui_interactobject"
local menus = {} -- [menuId] = { session, kind, id }

local function iobj()
    return exports[IO]
end

local function mark(on, label)
    return (on and "» " or "") .. label
end

-- text in the editing player's language
local function T(session, key, params)
    return L.forPlayer(session.player, key, params)
end

local function txt(session, label)
    if type(label) == "string" and label:find("^v_scenemanager%.") then return T(session, label) end
    return tostring(label)
end

local function onOff(session, v) return T(session, v and "v_scenemanager.common.on" or "v_scenemanager.common.off") end

local function weaponName(session, w)
    if (w or 0) == 0 then return T(session, "v_scenemanager.ai.fists") end
    return getWeaponNameFromID(w) or tostring(w)
end

local function rangeText(v, decimals)
    local a, b = vsmRange(v)
    if not a then return "-" end
    local f = decimals and ("%." .. decimals .. "f") or "%d"
    if a == b then return f:format(a) end
    return (f .. "-" .. f):format(a, b)
end

-- penal code of police_system: { list = { { id, cat, warrant, warning } }, items, warrant } | nil
local function penal()
    if not vsmResourceRunning(VSM.POLICE) then return nil end
    local ok, p = pcall(function() return exports[VSM.POLICE]:getPenalItems() end)
    return ok and type(p) == "table" and p or nil
end

-- a police_system key in the player's language (the id when it has no text)
local function policeText(session, key, fallback)
    local ok, text = pcall(L.forPlayer, session.player, key)
    if ok and type(text) == "string" and text ~= "" and text ~= key then return text end
    return tostring(fallback)
end

local function btkLabel(session, id)
    return policeText(session, "police_system.btk." .. tostring(id), policeText(session, "police_system.reason." .. tostring(id), id))
end

---------------------------------------------------------------- ped menus

local function aiItems(session, entry)
    local a = entry.ai or {}
    local items = {}
    local function choice(key, label, current, values, fmt)
        local sub = {}
        for _, v in ipairs(values) do
            sub[#sub + 1] = { label = mark(current == v, fmt(v)), value = { a = "ai", k = key, v = v }, closeOnSelect = false }
        end
        items[#items + 1] = { label = ("%s: %s"):format(T(session, label), fmt(current)), items = sub }
    end
    local weapon = function(v) return weaponName(session, v) end
    local pct = function(v) return ("%d%%"):format(math.floor((v or 0) * 100 + 0.5)) end
    if entry.role == "fighter" then
        choice("side", "v_scenemanager.ai.side", a.side, { "a", "b" }, function(v) return T(session, "v_scenemanager.ai.side_" .. tostring(v)) end)
        choice("weapon", "v_scenemanager.ai.weapon", a.weapon, VSM_WEAPONS, weapon)
        choice("start", "v_scenemanager.ai.start", a.start, VSM_FIGHT_START, function(v) return T(session, "v_scenemanager.ai.start_" .. tostring(v)) end)
        choice("onPolice", "v_scenemanager.ai.on_police", a.onPolice, VSM_ON_POLICE, function(v) return T(session, "v_scenemanager.ai.police_" .. tostring(v)) end)
    elseif entry.role == "hostile" then
        choice("targets", "v_scenemanager.ai.targets", a.targets, VSM_TARGETS, function(v) return T(session, "v_scenemanager.ai.targets_" .. tostring(v)) end)
        choice("weapon", "v_scenemanager.ai.weapon", a.weapon, VSM_WEAPONS, weapon)
        choice("accuracy", "v_scenemanager.ai.accuracy", a.accuracy, { 0.2, 0.35, 0.5, 0.7 }, pct)
        choice("aggroRadius", "v_scenemanager.ai.aggro", a.aggroRadius, { 20, 35, 60 }, function(v) return tostring(v) .. " m" end)
        choice("task", "v_scenemanager.ai.task", a.task, VSM_HOSTILE_TASKS, function(v) return T(session, "v_scenemanager.ai.task_" .. tostring(v)) end)
        choice("surrenderHealth", "v_scenemanager.ai.surrender", a.surrenderHealth, VSM_SURRENDER_PRESETS, function(v)
            return (v or 0) == 0 and T(session, "v_scenemanager.ai.never") or (tostring(v) .. " HP") end)
        choice("flee", "v_scenemanager.ai.flee", a.flee, VSM_FLEE_PRESETS, pct)
    elseif entry.role == "suspect" then
        choice("weapon", "v_scenemanager.ai.weapon", a.weapon, VSM_WEAPONS, weapon)
        choice("flee", "v_scenemanager.ai.flee", a.flee, VSM_FLEE_PRESETS, pct)
    end
    return items
end

local function recordItems(session, entry)
    local r = entry.record or {}
    local f = r.flags or {}
    local items = {}
    local function set(key, v, label, current)
        return { label = mark(current, label), value = { a = "rec", k = key, v = v }, closeOnSelect = false }
    end

    items[#items + 1] = { label = ("%s: %s"):format(T(session, "v_scenemanager.rec.name"), r.name or T(session, "v_scenemanager.rec.random")), items = {
        set("name", false, T(session, "v_scenemanager.rec.random"), r.name == nil),
        { label = T(session, "v_scenemanager.rec.custom_name"), value = { a = "recName" } },
    } }
    local ages = { set("age", false, T(session, "v_scenemanager.rec.random"), r.age == nil) }
    for i, p in ipairs(VSM_AGE_PRESETS) do ages[#ages + 1] = set("age", i, rangeText(p), rangeText(r.age) == rangeText(p)) end
    items[#items + 1] = { label = ("%s: %s"):format(T(session, "v_scenemanager.rec.age"), r.age and rangeText(r.age) or T(session, "v_scenemanager.rec.random")), items = ages }

    local lic = { set("licence", false, T(session, "v_scenemanager.rec.random"), f.licence == nil) }
    for _, l in ipairs(VSM_LICENCES) do lic[#lic + 1] = set("licence", l, T(session, "v_scenemanager.rec.licence_" .. l), f.licence == l) end
    items[#items + 1] = { label = ("%s: %s"):format(T(session, "v_scenemanager.rec.licence"),
        f.licence and T(session, "v_scenemanager.rec.licence_" .. f.licence) or T(session, "v_scenemanager.rec.random")), items = lic }

    local bac = {}
    for i, p in ipairs(VSM_BAC_PRESETS) do
        local label = (p[1] == 0 and p[2] == 0) and T(session, "v_scenemanager.rec.sober") or rangeText(p, 1)
        bac[#bac + 1] = set("bac", i, label, (f.bac == nil and i == 1) or rangeText(f.bac, 1) == rangeText(p, 1))
    end
    items[#items + 1] = { label = ("%s: %s"):format(T(session, "v_scenemanager.rec.bac"), f.bac and rangeText(f.bac, 1) or T(session, "v_scenemanager.rec.sober")),
        items = bac, desc = T(session, "v_scenemanager.rec.bac_desc") }

    local drugs = { set("drug", false, T(session, "v_scenemanager.rec.none"), f.drug == nil) }
    for _, d in ipairs(VSM_DRUGS) do drugs[#drugs + 1] = set("drug", d.id, T(session, d.label), f.drug == d.id) end
    local drug = f.drug and vsmDrugById(f.drug)
    items[#items + 1] = { label = ("%s: %s"):format(T(session, "v_scenemanager.rec.drug"), drug and T(session, drug.label) or T(session, "v_scenemanager.rec.none")), items = drugs }
    items[#items + 1] = { label = ("%s: %s"):format(T(session, "v_scenemanager.rec.flee"), onOff(session, f.flee)), value = { a = "rec", k = "flee" }, closeOnSelect = false }

    -- past items (fines / warnings of the penal code)
    local p = penal()
    local past = {}
    if p then
        local cats, order = {}, {}
        for _, it in ipairs(p.list) do
            if not it.warrant then
                if not cats[it.cat] then cats[it.cat] = {}; order[#order + 1] = it.cat end
                local list = cats[it.cat]
                list[#list + 1] = { label = btkLabel(session, it.id), value = { a = "recPast", v = it.id, w = it.warning and true or false } }
            end
        end
        local add = {}
        for _, cat in ipairs(order) do
            add[#add + 1] = { label = policeText(session, "police_system.btk_cat." .. cat, cat), items = cats[cat] }
        end
        past[#past + 1] = { label = T(session, "v_scenemanager.rec.past_add"), items = add }
    end
    for i, it in ipairs(r.past or {}) do
        past[#past + 1] = { label = T(session, "v_scenemanager.rec.past_remove", { item = btkLabel(session, it.btk), days = rangeText(it.daysAgo) }),
            value = { a = "recPastDel", i = i }, closeOnSelect = false }
    end
    items[#items + 1] = { label = T(session, "v_scenemanager.rec.past", { count = #(r.past or {}) }), items = past }

    -- warrant: one warrant with reasons + description per language
    local w = r.warrants and r.warrants[1]
    local reasons = {}
    local has = {}
    for _, id in ipairs(w and w.reasons or {}) do has[id] = true end
    if p then
        for _, it in ipairs(p.list) do
            if it.warrant then
                local label = it.extra and policeText(session, "police_system.reason." .. it.id, it.id) or btkLabel(session, it.id)
                reasons[#reasons + 1] = { label = mark(has[it.id], label), value = { a = "recReason", v = it.id }, closeOnSelect = false }
            end
        end
    end
    local wItems = { { label = T(session, "v_scenemanager.rec.warrant_reasons"), items = reasons } }
    for _, lang in ipairs(VSM.LANGS) do
        local d = w and w.description[lang]
        wItems[#wItems + 1] = { label = T(session, "v_scenemanager.rec.warrant_text", { lang = lang:upper() }),
            desc = d or T(session, "v_scenemanager.common.empty"), value = { a = "recWarrantText", lang = lang } }
    end
    if w then wItems[#wItems + 1] = { label = T(session, "v_scenemanager.rec.warrant_delete"), value = { a = "rec", k = "warrant", v = false } } end
    local wlabel = {}
    for _, id in ipairs(w and w.reasons or {}) do wlabel[#wlabel + 1] = btkLabel(session, id) end
    items[#items + 1] = { label = ("%s: %s"):format(T(session, "v_scenemanager.rec.warrant"), #wlabel > 0 and table.concat(wlabel, ", ") or "-"), items = wItems }

    items[#items + 1] = { label = ("%s: %s"):format(T(session, "v_scenemanager.rec.announce"), onOff(session, r.announce)),
        value = { a = "rec", k = "announce" }, closeOnSelect = false, desc = T(session, "v_scenemanager.rec.announce_desc") }
    items[#items + 1] = { label = ("%s: %s"):format(T(session, "v_scenemanager.rec.persistent"), onOff(session, r.persistent)),
        value = { a = "rec", k = "persistent" }, closeOnSelect = false, desc = T(session, "v_scenemanager.rec.persistent_desc") }
    if entry.record then
        items[#items + 1] = { label = T(session, "v_scenemanager.rec.delete"), items = { { label = T(session, "v_scenemanager.common.yes_delete"), value = { a = "rec", k = "all", v = false } } } }
    end
    return items
end

local function pedItems(session, entry)
    local anims = {}
    for _, a in ipairs(VSM_ANIMS) do
        anims[#anims + 1] = { label = mark(entry.anim == a.id, T(session, a.label)), value = { a = "anim", v = a.id }, closeOnSelect = false }
    end

    local addInjury = {}
    for _, inj in ipairs(VSM_INJURIES) do
        local severities = {}
        for sev, label in ipairs(VSM_SEVERITY) do
            severities[sev] = { label = T(session, label), value = { a = "injury", t = inj.id, s = sev }, closeOnSelect = false }
        end
        addInjury[#addInjury + 1] = { label = T(session, inj.label), items = severities }
    end
    local injuries = { { label = T(session, "v_scenemanager.ped.add_injury"), items = addInjury } }
    for i, inj in ipairs(entry.injuries) do
        -- one submenu per injury: body part, side, remove
        local partDef = inj.part and VSM_PART_BY_ID[inj.part]
        local where = partDef and T(session, partDef.label) or T(session, "v_scenemanager.ped.part_none")
        if partDef and inj.side then where = T(session, "medsys.body." .. inj.side) .. " " .. where end
        local sub = {}
        if not VSM_SYSTEMIC[inj.type] then
            local parts = {}
            for _, p in ipairs(VSM_PARTS) do
                parts[#parts + 1] = { label = mark(inj.part == p.id, T(session, p.label)), value = { a = "injpart", i = i, p = p.id }, closeOnSelect = false }
            end
            sub[#sub + 1] = { label = T(session, "v_scenemanager.ped.part", { part = where }), items = parts }
            if partDef and partDef.sided then
                for _, sd in ipairs({ "left", "right" }) do
                    sub[#sub + 1] = { label = mark(inj.side == sd, T(session, "medsys.body." .. sd)), value = { a = "injside", i = i, s = sd }, closeOnSelect = false }
                end
            end
        end
        sub[#sub + 1] = { label = T(session, "v_scenemanager.ped.remove"), value = { a = "uninjure", i = i }, closeOnSelect = false }
        injuries[#injuries + 1] = {
            label = T(session, "v_scenemanager.ped.injury_entry", { injury = T(session, vsmInjuryLabel(inj.type)),
                severity = T(session, VSM_SEVERITY[inj.severity] or "?"), part = VSM_SYSTEMIC[inj.type] and "-" or where }),
            items = sub,
        }
    end
    if #entry.injuries > 0 then
        injuries[#injuries + 1] = { label = T(session, "v_scenemanager.ped.remove_all"), value = { a = "uninjure", i = 0 }, closeOnSelect = false }
    end

    local state = {}
    for _, key in ipairs(VSM_STATE_ORDER) do
        local def = VSM_STATE[key]
        local current = entry.state[key]
        local values = { { label = mark(current == nil, T(session, "v_scenemanager.ped.not_set")), value = { a = "state", k = key, clear = true }, closeOnSelect = false } }
        for i, preset in ipairs(def.presets) do
            values[#values + 1] = { label = mark(current == preset[2], txt(session, preset[1])), value = { a = "state", k = key, i = i }, closeOnSelect = false }
        end
        if def.min then
            values[#values + 1] = { label = T(session, "v_scenemanager.ped.custom_value", { min = def.min, max = def.max }), value = { a = "stateCustom", k = key } }
        end
        local shown = "-"
        if current ~= nil then
            shown = tostring(current)
            for _, preset in ipairs(def.presets) do
                if preset[2] == current then shown = txt(session, preset[1]) end
            end
            if shown == tostring(current) and def.unit then shown = shown .. " " .. def.unit end
        end
        state[#state + 1] = { label = ("%s: %s"):format(T(session, def.label), shown), items = values }
    end

    local seats = {
        { label = T(session, "v_scenemanager.ped.seat_0"), value = { a = "seat", s = 0 } },
        { label = T(session, "v_scenemanager.ped.seat_1"), value = { a = "seat", s = 1 } },
        { label = T(session, "v_scenemanager.ped.seat_2"), value = { a = "seat", s = 2 } },
        { label = T(session, "v_scenemanager.ped.seat_3"), value = { a = "seat", s = 3 } },
        { label = T(session, "v_scenemanager.ped.unseat"), value = { a = "unseat" }, disabled = entry.vehicle == nil },
    }

    local roles = {}
    for _, r in ipairs(VSM_ROLES) do
        roles[#roles + 1] = { label = mark(entry.role == r.id, T(session, r.label)), value = { a = "role", v = r.id }, closeOnSelect = false,
            desc = T(session, "v_scenemanager.role." .. r.id .. "_desc") }
    end
    local role = vsmRoleById(entry.role)

    local items = {
        { label = T(session, "v_scenemanager.ped.move"), value = { a = "move" } },
        { label = T(session, "v_scenemanager.ped.face"), value = { a = "face" }, closeOnSelect = false },
        { label = ("%s: %s"):format(T(session, "v_scenemanager.ped.role"), T(session, role and role.label or "v_scenemanager.role.bystander")), items = roles },
    }
    if role and role.ai then
        items[#items + 1] = { label = T(session, "v_scenemanager.ped.ai"), items = aiItems(session, entry) }
    end
    items[#items + 1] = { label = T(session, "v_scenemanager.ped.record") .. (entry.record and " ✓" or ""), items = recordItems(session, entry) }
    items[#items + 1] = { label = T(session, "v_scenemanager.ped.pose"), items = anims }
    items[#items + 1] = { label = T(session, "v_scenemanager.ped.injuries", { count = #entry.injuries }), items = injuries }
    items[#items + 1] = { label = T(session, "v_scenemanager.ped.medical_state"), items = state }
    items[#items + 1] = { label = T(session, "v_scenemanager.ped.skin", { skin = entry.skin or 0 }), value = { a = "skin" } }
    items[#items + 1] = { label = entry.vehicle and T(session, "v_scenemanager.ped.seated", { vehicle = entry.vehicle, seat = entry.seat or 0 })
        or T(session, "v_scenemanager.ped.seat"), items = seats }
    items[#items + 1] = { label = T(session, "v_scenemanager.common.delete"), items = { { label = T(session, "v_scenemanager.common.yes_delete_id", { id = entry.id }), value = { a = "delete" } } } }
    return items
end

---------------------------------------------------------------- vehicle menus

local function vehicleItems(session, entry)
    local damage, colors = {}, {}
    for _, d in ipairs(VSM_DAMAGE) do
        damage[#damage + 1] = { label = T(session, d.label), value = { a = "damage", v = d.id }, closeOnSelect = false }
    end
    for i, c in ipairs(VSM_COLORS) do
        colors[#colors + 1] = { label = T(session, c[1]), value = { a = "color", i = i }, closeOnSelect = false }
    end
    local options = {
        { label = ("%s: %s"):format(T(session, "v_scenemanager.veh.engine"), onOff(session, entry.engine)), value = { a = "toggle", k = "engine" }, closeOnSelect = false },
        { label = ("%s: %s"):format(T(session, "v_scenemanager.veh.lights"), onOff(session, entry.lightsOn)), value = { a = "toggle", k = "lightsOn" }, closeOnSelect = false },
        { label = ("%s: %s"):format(T(session, "v_scenemanager.veh.sirens"), onOff(session, entry.sirens)), value = { a = "toggle", k = "sirens" }, closeOnSelect = false },
        { label = ("%s: %s"):format(T(session, "v_scenemanager.veh.locked"), onOff(session, entry.locked)), value = { a = "toggle", k = "locked" }, closeOnSelect = false },
        { label = ("%s: %s"):format(T(session, "v_scenemanager.veh.frozen"), onOff(session, entry.frozen)), value = { a = "toggle", k = "frozen" }, closeOnSelect = false },
    }
    local r = entry.record or {}
    local owners = {
        { label = mark(r.owner == nil, T(session, "v_scenemanager.veh.owner_random")), value = { a = "vrec", k = "owner", v = false }, closeOnSelect = false },
        { label = mark(r.owner == "none", T(session, "v_scenemanager.veh.owner_none")), value = { a = "vrec", k = "owner", v = "none" }, closeOnSelect = false },
    }
    for _, p in ipairs(session.scene.data.peds) do
        owners[#owners + 1] = { label = mark(r.owner == p.id, T(session, "v_scenemanager.veh.owner_ped", { id = p.id })),
            value = { a = "vrec", k = "owner", v = p.id }, closeOnSelect = false }
    end
    local ownerLabel = r.owner == nil and T(session, "v_scenemanager.veh.owner_random")
        or r.owner == "none" and T(session, "v_scenemanager.veh.owner_none") or r.owner
    local record = {
        { label = ("%s: %s"):format(T(session, "v_scenemanager.veh.stolen"), onOff(session, r.stolen)), value = { a = "vrec", k = "stolen" },
          closeOnSelect = false, desc = T(session, "v_scenemanager.veh.stolen_desc") },
        { label = ("%s: %s"):format(T(session, "v_scenemanager.veh.owner"), ownerLabel), items = owners },
        { label = ("%s: %s"):format(T(session, "v_scenemanager.veh.inspection"), T(session, "v_scenemanager.veh.inspection_" .. (r.inspection or "valid"))),
          value = { a = "vrec", k = "inspection" }, closeOnSelect = false },
    }
    return {
        { label = T(session, "v_scenemanager.veh.save"), value = { a = "save" } },
        { label = T(session, "v_scenemanager.veh.enter"), value = { a = "enter" } },
        { label = ("%s: %s"):format(T(session, "v_scenemanager.veh.tow"), onOff(session, entry.tow)), value = { a = "tow" },
          closeOnSelect = false, desc = T(session, "v_scenemanager.veh.tow_desc") },
        { label = T(session, "v_scenemanager.veh.record") .. (entry.record and " ✓" or ""), items = record },
        { label = T(session, "v_scenemanager.veh.damage"), items = damage },
        { label = T(session, "v_scenemanager.veh.colour"), items = colors },
        { label = T(session, "v_scenemanager.veh.options"), items = options },
        { label = T(session, "v_scenemanager.veh.plate", { plate = entry.plate or "-" }), value = { a = "plate" } },
        { label = T(session, "v_scenemanager.veh.model", { model = entry.model }), value = { a = "model" } },
        { label = T(session, "v_scenemanager.common.delete"), items = { { label = T(session, "v_scenemanager.common.yes_delete_id", { id = entry.id }), value = { a = "delete" } } } },
    }
end

local function definition(session, kind, entry)
    if kind == "vehicle" then
        return {
            title = T(session, "v_scenemanager.veh.title", { id = entry.id }), range = VSM.INTERACT_RANGE, priority = 50,
            lineOfSight = false, allowInVehicle = true, items = vehicleItems(session, entry),
        }
    end
    return {
        title = T(session, "v_scenemanager.ped.title", { id = entry.id }), range = VSM.INTERACT_RANGE, priority = 50,
        lineOfSight = false, items = pedItems(session, entry),
    }
end

---------------------------------------------------------------- registry

function Interact.add(session, kind, entry, element)
    if not vsmResourceRunning(IO) then return end
    local id = iobj():addInteractMenu(element, definition(session, kind, entry), session.player)
    if id then
        menus[id] = { session = session, kind = kind, id = entry.id, element = element }
        session.menus = session.menus or {}
        session.menus[kind .. ":" .. entry.id] = id
    end
end

function Interact.update(session, kind, entry)
    local menuId = session.menus and session.menus[kind .. ":" .. entry.id]
    if not menuId or not vsmResourceRunning(IO) then return end
    local def = definition(session, kind, entry)
    iobj():updateInteractMenu(menuId, { title = def.title, items = def.items })
end

function Interact.remove(session, kind, entryId)
    local key = kind .. ":" .. entryId
    local menuId = session.menus and session.menus[key]
    if not menuId then return end
    session.menus[key] = nil
    menus[menuId] = nil
    if vsmResourceRunning(IO) and iobj():isInteractMenu(menuId) then iobj():removeInteractMenu(menuId) end
end

function Interact.clear(session)
    for _, menuId in pairs(session.menus or {}) do
        menus[menuId] = nil
        if vsmResourceRunning(IO) and iobj():isInteractMenu(menuId) then iobj():removeInteractMenu(menuId) end
    end
    session.menus = {}
end

-- every menu of a session rebuilt (language change, a ped added / removed: vehicle owner lists)
function Interact.refreshAll(session)
    local scene = session.scene
    if not scene then return end
    for _, entry in ipairs(scene.data.vehicles) do Interact.update(session, "vehicle", entry) end
    for _, entry in ipairs(scene.data.peds) do Interact.update(session, "ped", entry) end
end

-- ui_interactobject restarted: every registration is gone, register again
addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) ~= IO then return end
    setTimer(function()
        menus = {}
        for _, session in pairs(Editor.sessions) do
            local scene = session.scene
            session.menus = {}
            if scene then
                for _, entry in ipairs(scene.data.vehicles) do
                    if isElement(scene.vehicles[entry.id]) then Interact.add(session, "vehicle", entry, scene.vehicles[entry.id]) end
                end
                for _, entry in ipairs(scene.data.peds) do
                    if isElement(scene.peds[entry.id]) then Interact.add(session, "ped", entry, scene.peds[entry.id]) end
                end
            end
        end
    end, 500, 1)
end)

addEvent("onPlayerLanguageChange")
addEventHandler("onPlayerLanguageChange", root, function()
    local session = Editor.sessions[source]
    if session then Interact.refreshAll(session) end
end)

---------------------------------------------------------------- vehicle actions

local function nearestSceneVehicle(scene, element, maxDist)
    local x, y, z = getElementPosition(element)
    local best, bestId, bestDist
    for id, vehicle in pairs(scene.vehicles) do
        if isElement(vehicle) then
            local d = getDistanceBetweenPoints3D(x, y, z, getElementPosition(vehicle))
            if d <= maxDist and (not bestDist or d < bestDist) then best, bestId, bestDist = vehicle, id, d end
        end
    end
    return best, bestId
end

local function respawnVehicle(session, entry)
    local scene = session.scene
    local old = scene.vehicles[entry.id]
    Interact.remove(session, "vehicle", entry.id)
    if isElement(old) then destroyElement(old) end
    scene.vehicles[entry.id] = nil
    Editor.spawnVehicle(session, entry)
    -- seat the peds again
    for _, ped in ipairs(scene.data.peds) do
        if ped.vehicle == entry.id and isElement(scene.peds[ped.id]) then
            if not Builder.seatPed(scene.peds[ped.id], ped, scene.vehicles) then
                ped.vehicle, ped.seat = nil, nil
                setElementFrozen(scene.peds[ped.id], true)
                Builder.applyPedPose(scene.peds[ped.id], ped)
            end
            Editor.refreshElement(session, "ped", ped)
        end
    end
end

local function takePedOut(session, pedEntry, vehicle)
    local ped = session.scene.peds[pedEntry.id]
    local x, y, z = getElementPosition(vehicle or ped)
    pedEntry.vehicle, pedEntry.seat = nil, nil
    pedEntry.pos = { vsmRound(x + 2), vsmRound(y), vsmRound(z + 0.3) }
    if isElement(ped) then
        Builder.seatPed(ped, pedEntry)
        setElementFrozen(ped, true)
        Builder.applyPedPose(ped, pedEntry)
    end
end

local VEHICLE = {
    save = function(session, entry) Editor.saveVehicle(session, entry); return true end,
    enter = function(session, entry, vehicle)
        local occupant = getVehicleOccupant(vehicle, 0)
        if occupant and occupant ~= session.player then
            Editor.notify(session, "v_scenemanager.editor.driver_seat_taken")
            return true
        end
        warpPedIntoVehicle(session.player, vehicle, 0)
        return true
    end,
    damage = function(session, entry, vehicle, value)
        if not Builder.damagePreset(entry, value.v) then return true end
        Builder.applyVehicle(vehicle, entry)
    end,
    color = function(session, entry, vehicle, value)
        local c = VSM_COLORS[tonumber(value.i) or 0]
        if not c then return true end
        local colors = { getVehicleColor(vehicle, true) }
        colors[1], colors[2], colors[3] = c[2], c[3], c[4]
        setVehicleColor(vehicle, unpack(colors))
        entry.colors = colors
    end,
    toggle = function(session, entry, vehicle, value)
        local key = value.k
        if key ~= "engine" and key ~= "lightsOn" and key ~= "sirens" and key ~= "locked" and key ~= "frozen" then return true end
        entry[key] = not entry[key]
        Builder.applyVehicleOptions(vehicle, entry)
    end,
    tow = function(session, entry)
        entry.tow = not entry.tow or nil
    end,
    vrec = function(session, entry, vehicle, value)
        local r = entry.record or {}
        if value.k == "stolen" then
            r.stolen = not r.stolen or nil
            if r.stolen and r.owner and r.owner ~= "none" then r.owner = nil end
        elseif value.k == "owner" then
            r.owner = value.v or nil
            if r.owner and r.owner ~= "none" then r.stolen = nil end
        elseif value.k == "inspection" then
            r.inspection = r.inspection ~= "expired" and "expired" or nil
        else
            return true
        end
        entry.record = next(r) and r or nil
    end,
    plate = function(session, entry)
        Editor.askText(session.player, "v_scenemanager.editor.ask_plate", 8, entry.plate or "", function(text)
            local vehicle = session.scene and session.scene.vehicles[entry.id]
            if not isElement(vehicle) then return end
            entry.plate = text:sub(1, 8)
            setVehiclePlateText(vehicle, entry.plate)
            Editor.refreshElement(session, "vehicle", entry)
            Editor.markDirty(session)
        end)
        return true
    end,
    model = function(session, entry)
        Editor.askText(session.player, "v_scenemanager.editor.ask_model", 30, tostring(entry.model), function(text)
            local vehicle = session.scene and session.scene.vehicles[entry.id]
            if not isElement(vehicle) then return end
            local model = tonumber(text) or getVehicleModelFromName(text)
            local name = model and getVehicleNameFromModel(model)
            if not name or name == "" then
                Editor.notify(session, "v_scenemanager.editor.unknown_model", { model = text })
                return
            end
            entry.model = model
            entry.upgrades, entry.variant, entry.paintjob = {}, nil, 3
            respawnVehicle(session, entry)
            Editor.markDirty(session)
        end)
        return true
    end,
    delete = function(session, entry, vehicle)
        local scene = session.scene
        for _, ped in ipairs(scene.data.peds) do
            if ped.vehicle == entry.id then
                takePedOut(session, ped, vehicle)
                Editor.refreshElement(session, "ped", ped)
            end
        end
        if getPedOccupiedVehicle(session.player) == vehicle then removePedFromVehicle(session.player) end
        local _, index = Editor.findEntry(scene, "vehicle", entry.id)
        if index then table.remove(scene.data.vehicles, index) end
        Interact.remove(session, "vehicle", entry.id)
        scene.vehicles[entry.id] = nil
        if isElement(vehicle) then destroyElement(vehicle) end
        Editor.markDirty(session)
        return true
    end,
}

---------------------------------------------------------------- ped actions

local AI_KEYS = { side = true, weapon = true, start = true, onPolice = true, targets = true, accuracy = true,
    aggroRadius = true, task = true, surrenderHealth = true, flee = true }

local function record(entry)
    entry.record = entry.record or {}
    return entry.record
end

local function tidyRecord(entry)
    local r = entry.record
    if not r then return end
    if r.flags and not next(r.flags) then r.flags = nil end
    if r.past and #r.past == 0 then r.past = nil end
    if r.warrants and #r.warrants == 0 then r.warrants = nil end
    if not next(r) then entry.record = nil end
end

local function warrant(entry)
    local r = record(entry)
    r.warrants = r.warrants or {}
    r.warrants[1] = r.warrants[1] or { reasons = {}, description = {} }
    return r.warrants[1]
end

local PED = {
    move = function(session, entry, ped)
        if entry.vehicle then return true end
        local x, y, z = getElementPosition(session.player)
        local _, _, rz = getElementRotation(session.player)
        entry.pos, entry.rot = { vsmRound(x), vsmRound(y), vsmRound(z) }, vsmRound(rz, 1)
        local a = math.rad(rz)
        setElementPosition(session.player, x + math.sin(a) * 1.2, y - math.cos(a) * 1.2, z)
        Builder.seatPed(ped, entry)
        Builder.applyPedPose(ped, entry)
    end,
    face = function(session, entry, ped)
        if entry.vehicle then return true end
        local px, py = getElementPosition(session.player)
        local x, y = getElementPosition(ped)
        entry.rot = vsmRound(-math.deg(math.atan2(px - x, py - y)), 1)
        setElementRotation(ped, 0, 0, entry.rot, "default", true)
        Builder.applyPedPose(ped, entry)
    end,
    role = function(session, entry, ped, value)
        if not vsmRoleById(value.v) then return true end
        entry.role = value.v
        -- the AI settings of the new role (defaults filled in by the normalizer)
        local normalized = Storage.normalize({ peds = { { id = entry.id, role = entry.role, ai = entry.ai } } }).peds[1]
        entry.ai = normalized.ai
    end,
    ai = function(session, entry, ped, value)
        if not AI_KEYS[value.k] then return true end
        entry.ai = entry.ai or {}
        entry.ai[value.k] = value.v
        entry.ai = Storage.normalize({ peds = { { id = entry.id, role = entry.role, ai = entry.ai } } }).peds[1].ai
    end,
    rec = function(session, entry, ped, value)
        local k = value.k
        if k == "all" then
            entry.record = nil
            return
        end
        local r = record(entry)
        r.flags = r.flags or {}
        if k == "name" then r.name = nil
        elseif k == "age" then r.age = value.v and vsmCopy(VSM_AGE_PRESETS[tonumber(value.v) or 0]) or nil; r.birth = nil
        elseif k == "licence" then r.flags.licence = value.v or nil
        elseif k == "bac" then
            local p = VSM_BAC_PRESETS[tonumber(value.v) or 0]
            r.flags.bac = (p and p[2] > 0) and vsmCopy(p) or nil
        elseif k == "drug" then r.flags.drug = value.v or nil
        elseif k == "flee" then r.flags.flee = not r.flags.flee or nil
        elseif k == "announce" then r.announce = not r.announce or nil
        elseif k == "persistent" then r.persistent = not r.persistent or nil
        elseif k == "warrant" then r.warrants = nil
        end
        tidyRecord(entry)
    end,
    recName = function(session, entry)
        Editor.askText(session.player, "v_scenemanager.editor.ask_record_name", 48, entry.record and entry.record.name or "", function(text)
            if not session.scene then return end
            text = vsmCleanText(text, 48)
            record(entry).name = text ~= "" and text or nil
            tidyRecord(entry)
            Editor.refreshElement(session, "ped", entry)
            Editor.markDirty(session)
        end)
        return true
    end,
    recPast = function(session, entry, ped, value)
        if type(value.v) ~= "string" then return true end
        local r = record(entry)
        r.past = r.past or {}
        r.past[#r.past + 1] = { type = value.w and "warning" or "fine", btk = value.v,
            daysAgo = vsmCopy(VSM_DAYS_PRESETS[math.random(#VSM_DAYS_PRESETS)]) }
    end,
    recPastDel = function(session, entry, ped, value)
        local r = entry.record
        local i = tonumber(value.i)
        if r and r.past and i and r.past[i] then table.remove(r.past, i) end
        tidyRecord(entry)
    end,
    recReason = function(session, entry, ped, value)
        if type(value.v) ~= "string" then return true end
        local w = warrant(entry)
        for i, id in ipairs(w.reasons) do
            if id == value.v then
                table.remove(w.reasons, i)
                if #w.reasons == 0 then entry.record.warrants = nil end
                tidyRecord(entry)
                return
            end
        end
        w.reasons[#w.reasons + 1] = value.v
    end,
    recWarrantText = function(session, entry, ped, value)
        local lang = value.lang
        if type(lang) ~= "string" or not lang:match("^%l%l$") then return true end
        local w = entry.record and entry.record.warrants and entry.record.warrants[1]
        if not w then
            Editor.notify(session, "v_scenemanager.editor.warrant_reason_first")
            return true
        end
        Editor.askText(session.player, "v_scenemanager.editor.ask_warrant_text", 200, w.description[lang] or "", function(text)
            if not session.scene then return end
            text = vsmCleanText(text, 200)
            w.description[lang] = text ~= "" and text or nil
            Editor.refreshElement(session, "ped", entry)
            Editor.markDirty(session)
        end, { lang = lang:upper() })
        return true
    end,
    anim = function(session, entry, ped, value)
        if not vsmAnimById(value.v) then return true end
        entry.anim = value.v
        Builder.applyPedPose(ped, entry)
    end,
    injury = function(session, entry, ped, value)
        local sev = tonumber(value.s)
        if not sev or sev < 1 or sev > 3 then return true end
        local inj = { type = tostring(value.t), severity = sev }
        -- a body part right away (medsys picks it by type and the scene category); editable after
        if not VSM_SYSTEMIC[inj.type] and vsmResourceRunning(VSM.MEDSYS) then
            local ok, part, side = pcall(function()
                return exports[VSM.MEDSYS]:resolveInjuryPart(inj.type, nil, nil, VSM_CATEGORY_CAUSE[session.scene and session.scene.data and session.scene.data.category or ""])
            end)
            if ok and VSM_PART_BY_ID[part] then inj.part, inj.side = part, side end
        end
        entry.injuries[#entry.injuries + 1] = inj
    end,
    injpart = function(session, entry, ped, value)
        local inj = entry.injuries[tonumber(value.i) or 0]
        local p = VSM_PART_BY_ID[value.p]
        if not inj or not p then return true end
        inj.part = p.id
        if not p.sided then inj.side = nil elseif inj.side ~= "left" and inj.side ~= "right" then inj.side = "left" end
    end,
    injside = function(session, entry, ped, value)
        local inj = entry.injuries[tonumber(value.i) or 0]
        if not inj or not VSM_PART_BY_ID[inj.part] or not VSM_PART_BY_ID[inj.part].sided then return true end
        if value.s == "left" or value.s == "right" then inj.side = value.s end
    end,
    uninjure = function(session, entry, ped, value)
        local i = tonumber(value.i)
        if i == 0 then
            entry.injuries = {}
        elseif i and entry.injuries[i] then
            table.remove(entry.injuries, i)
        end
    end,
    state = function(session, entry, ped, value)
        local def = VSM_STATE[value.k]
        if not def then return true end
        if value.clear then
            entry.state[value.k] = nil
        else
            local preset = def.presets[tonumber(value.i) or 0]
            if not preset then return true end
            entry.state[value.k] = preset[2]
        end
    end,
    stateCustom = function(session, entry, ped, value)
        local key = value.k
        local def = VSM_STATE[key]
        if not def or not def.min then return true end
        Editor.askText(session.player, "v_scenemanager.editor.ask_state_value", 3, tostring(entry.state[key] or ""), function(text)
            local number = tonumber(text)
            if not number or number < def.min or number > def.max then
                Editor.notify(session, "v_scenemanager.editor.number_range", { min = def.min, max = def.max })
                return
            end
            entry.state[key] = math.floor(number + 0.5)
            Editor.refreshElement(session, "ped", entry)
            Editor.markDirty(session)
        end, { label = L.msg(def.label), min = def.min, max = def.max, unit = def.unit or "" })
        return true
    end,
    skin = function(session, entry)
        Editor.askText(session.player, "v_scenemanager.editor.ask_skin", 3, tostring(entry.skin or 0), function(text)
            local ped = session.scene and session.scene.peds[entry.id]
            local skin = tonumber(text)
            if not isElement(ped) or not skin then return end
            if not setElementModel(ped, math.floor(skin)) then
                Editor.notify(session, "v_scenemanager.editor.invalid_skin", { skin = text })
                return
            end
            entry.skin = math.floor(skin)
            Builder.applyPedPose(ped, entry)
            Editor.refreshElement(session, "ped", entry)
            Editor.markDirty(session)
        end)
        return true
    end,
    seat = function(session, entry, ped, value)
        local scene = session.scene
        local vehicle, vehicleId = nearestSceneVehicle(scene, ped, 10)
        if not vehicle then
            Editor.notify(session, "v_scenemanager.editor.no_vehicle_near")
            return true
        end
        local seat = math.floor(tonumber(value.s) or 0)
        if seat > (getVehicleMaxPassengers(vehicle) or 0) then
            Editor.notify(session, "v_scenemanager.editor.no_such_seat")
            return true
        end
        local occupant = getVehicleOccupant(vehicle, seat)
        if occupant and occupant ~= ped then
            Editor.notify(session, "v_scenemanager.editor.seat_taken")
            return true
        end
        local old = { entry.vehicle, entry.seat }
        entry.vehicle, entry.seat = vehicleId, seat
        setElementFrozen(ped, false)
        setPedAnimation(ped)
        if getPedOccupiedVehicle(ped) then removePedFromVehicle(ped) end
        if not Builder.seatPed(ped, entry, scene.vehicles) then
            entry.vehicle, entry.seat = old[1], old[2]
            setElementFrozen(ped, true)
            Editor.notify(session, "v_scenemanager.editor.seat_failed")
        end
    end,
    unseat = function(session, entry, ped)
        if not entry.vehicle then return true end
        takePedOut(session, entry, getPedOccupiedVehicle(ped))
    end,
    delete = function(session, entry, ped)
        local scene = session.scene
        local _, index = Editor.findEntry(scene, "ped", entry.id)
        if index then table.remove(scene.data.peds, index) end
        Interact.remove(session, "ped", entry.id)
        scene.peds[entry.id] = nil
        if isElement(ped) then destroyElement(ped) end
        -- vehicle owners pointing at it
        for _, v in ipairs(scene.data.vehicles) do
            if v.record and v.record.owner == entry.id then
                v.record.owner = nil
                if not next(v.record) then v.record = nil end
            end
        end
        Interact.refreshAll(session)
        Editor.markDirty(session)
        return true
    end,
}

addEventHandler("onInteractMenuSelect", root, function(menuId, value, target)
    local info = menus[menuId]
    if not info or type(value) ~= "table" then return end
    local session = info.session
    if source ~= session.player or Editor.sessions[source] ~= session or not session.scene then return end
    local entry = Editor.findEntry(session.scene, info.kind, info.id)
    local element = entry and (info.kind == "vehicle" and session.scene.vehicles[entry.id] or session.scene.peds[entry.id])
    if not entry or not isElement(element) then return end

    local handler = (info.kind == "vehicle" and VEHICLE or PED)[value.a]
    if not handler then return end
    -- true = handled completely (own refresh / async text input)
    if handler(session, entry, element, value) then return end
    Editor.refreshElement(session, info.kind, entry)
    Editor.markDirty(session)
end)
