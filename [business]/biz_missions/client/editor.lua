-- biz_missions / client/editor.lua
-- /bizmissioneditor: every mission position as a local preview, spawned the way
-- the mission spawns it (vans at z + 1 and dropped by physics, guards at z + 0.5,
-- supply crate at z + 0.3, buyer circles of BUYER_RADIUS). Only this player sees
-- them. 3D labels show the name and the ground check (spawn point vs. ground
-- under it). Menu on MIS.EDITOR_KEY (ui_inac temp menu); "Move here" takes the
-- player's position (or the vehicle's, when driving) with the ground z under it.
-- Edits stay local until Save.

local inac, uicore = exports.ui_inac, exports.ui_core

local E = { active = false, previews = {}, labels = true }
local Pages = {}
local textToken, textApply

local function notify(text)
    uicore:addNotification("Mission editor", text)
end

local function deepcopy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = deepcopy(v) end
    return out
end

local function r2(v) return math.floor(v * 100 + 0.5) / 100 end

--- the admin's spot: ground z under the player / vehicle, heading
local function here()
    local el = getPedOccupiedVehicle(localPlayer) or localPlayer
    local x, y, z = getElementPosition(el)
    local _, _, rz = getElementRotation(el)
    local gz = getGroundPosition(x, y, z + 1)
    if not gz or gz == 0 or math.abs(gz - z) > 4 then gz = z - (el == localPlayer and 1 or 0.6) end
    return { x = r2(x), y = r2(y), z = r2(gz), rot = math.floor(rz % 360) }
end

local function zoneName(p)
    return getZoneName(p.x, p.y, p.z, false)
end

--------------------------------------------------------------------------------
-- previews
--------------------------------------------------------------------------------

local function clearPreviews()
    for _, p in ipairs(E.previews) do
        if isElement(p.el) then destroyElement(p.el) end
    end
    E.previews = {}
end

-- p: { el?, x, y, z (mission point), label, color, ring = radius?, spawnZ = z the element is created at }
local function add(p)
    E.previews[#E.previews + 1] = p
    if isElement(p.el) then
        setElementDimension(p.el, 0)
        setElementInterior(p.el, 0)
    end
    return p
end

local function guardRot(spot, g)
    return g.rot or (math.deg(math.atan2(spot.y - g.y, spot.x - g.x)) - 90)
end

local function buildPreviews()
    clearPreviews()
    local C, doc = E.C, E.doc
    for i, s in ipairs(doc.supply) do
        local crate = createObject(2912, s.x, s.y, s.z + 0.3, 0, 0, 0)
        if crate then
            setObjectScale(crate, 0.6)
            setElementCollisionsEnabled(crate, false)
        end
        add({ el = crate, x = s.x, y = s.y, z = s.z, label = ("Supply #%d: %s (crate)"):format(i, s.name),
            color = { 255, 200, 60 }, ring = C.stealRadius, page = "spot:" .. i })

        local v = s.van
        local vx, vy, vz, vrot = s.x + 2, s.y + 2, s.z, 0
        if v then vx, vy, vz, vrot = v.x, v.y, v.z, v.rot or 0 end
        local van = createVehicle(C.supplyVan, vx, vy, vz + 1, 0, 0, vrot)
        if van then
            setVehicleLocked(van, true)
            setVehicleDamageProof(van, true)
            if not v then setElementAlpha(van, 120) end
        end
        add({ el = van, x = vx, y = vy, z = vz, color = { 255, 200, 60 }, page = "spot:" .. i,
            label = v and ("Supply #%d van"):format(i) or ("Supply #%d van (no fixed spot: random heading)"):format(i) })

        if s.guards then
            for j, g in ipairs(s.guards) do
                local ped = createPed(C.guardSkin, g.x, g.y, g.z + 0.5, guardRot(s, g))
                add({ el = ped, x = g.x, y = g.y, z = g.z, color = { 255, 90, 90 }, page = ("guard:%d:%d"):format(i, j),
                    label = ("Supply #%d guard %d"):format(i, j) })
            end
        else
            add({ x = s.x, y = s.y, z = s.z, ring = 8, ring2 = 3, color = { 255, 90, 90 }, page = "spot:" .. i,
                label = ("%d-%d random guards, 3-8 m around the crate"):format(C.guards[1], C.guards[2]), offset = -0.4 })
        end
    end

    for id, b in pairs(E.buildings) do
        add({ x = b.x, y = b.y, z = b.z, ring = C.deliverRadius, color = { 90, 220, 120 }, page = "vanb:" .. id,
            label = ("%s entrance (supply delivery %d m)"):format(b.name, C.deliverRadius) })
        local list = doc.vanSpawns[id]
        if list then
            for k, s in ipairs(list) do
                local van = createVehicle(C.sellVan, s.x, s.y, s.z + 1, 0, 0, s.rot or 0)
                if van then
                    setVehicleColor(van, 40, 40, 40, 40, 40, 40)
                    setVehicleLocked(van, true)
                    setVehicleDamageProof(van, true)
                end
                add({ el = van, x = s.x, y = s.y, z = s.z, color = { 90, 220, 120 }, page = ("vansp:%s:%d"):format(id, k),
                    label = ("%s sell van %d"):format(b.name, k) })
            end
        else
            add({ x = b.x, y = b.y, z = b.z, color = { 90, 220, 120 }, page = "vanb:" .. id, offset = -0.4,
                label = "No sell van spawns: vans line up 7 m in front of the door" })
        end
    end

    for i, b in ipairs(doc.buyers) do
        add({ x = b.x, y = b.y, z = b.z, ring = C.buyerRadius, color = { 90, 170, 255 }, page = "buyer:" .. i,
            label = ("Buyer #%d: %s"):format(i, b.name) })
    end
end

local function changed()
    E.dirty = true
    buildPreviews()
end

--------------------------------------------------------------------------------
-- 3D labels + rings
--------------------------------------------------------------------------------

local function ring(x, y, z, r, c)
    local seg = math.max(16, math.min(64, math.floor(r * 2)))
    local px, py
    for i = 0, seg do
        local a = i / seg * math.pi * 2
        local nx, ny = x + math.cos(a) * r, y + math.sin(a) * r
        if px then dxDrawLine3D(px, py, z + 0.15, nx, ny, z + 0.15, tocolor(c[1], c[2], c[3], 170), 2) end
        px, py = nx, ny
    end
end

local function render()
    if not E.active then return end
    local cx, cy, cz = getCameraMatrix()
    local maxD = E.C.labelDist
    for _, p in ipairs(E.previews) do
        local d = getDistanceBetweenPoints3D(cx, cy, cz, p.x, p.y, p.z)
        if d <= maxD then
            local c = p.color
            if p.ring and d <= math.max(maxD, p.ring + 50) then
                ring(p.x, p.y, p.z, p.ring, c)
                if p.ring2 then ring(p.x, p.y, p.z, p.ring2, c) end
            end
            if E.labels then
                local sx, sy = getScreenFromWorldPosition(p.x, p.y, p.z + 2.2 + (p.offset or 0))
                if sx then
                    local gz = getGroundPosition(p.x, p.y, p.z + 3)
                    local diff = (gz and gz ~= 0) and (p.z - gz) or nil
                    local gtext, gcol = "ground ?", tocolor(200, 200, 200)
                    if diff then
                        gtext = ("ground %+.2f m"):format(diff)
                        gcol = math.abs(diff) > 1 and tocolor(255, 80, 80) or tocolor(140, 230, 140)
                    end
                    local text = p.label
                    local where = ("%.2f, %.2f, %.2f"):format(p.x, p.y, p.z)
                    dxDrawText(text, sx + 1, sy + 1, sx + 1, sy + 1, tocolor(0, 0, 0, 220), 1.1, "default-bold", "center", "bottom")
                    dxDrawText(text, sx, sy, sx, sy, tocolor(c[1], c[2], c[3]), 1.1, "default-bold", "center", "bottom")
                    dxDrawText(where .. "   " .. gtext, sx + 1, sy + 1, sx + 1, sy + 1, tocolor(0, 0, 0, 220), 1, "default", "center", "top")
                    dxDrawText(where .. "   ", sx, sy, sx, sy, tocolor(220, 220, 220), 1, "default", "right", "top")
                    dxDrawText(gtext, sx, sy, sx, sy, gcol, 1, "default", "left", "top")
                end
            end
        end
    end
    local w = guiGetScreenSize()
    local status = ("Business mission editor   [%s] menu   %s"):format(E.C.key:upper(), E.dirty and "UNSAVED CHANGES" or "saved")
    dxDrawText(status, 0, 21, w + 1, 21, tocolor(0, 0, 0, 200), 1.2, "default-bold", "center", "top")
    dxDrawText(status, 0, 20, w, 20, E.dirty and tocolor(255, 200, 60) or tocolor(255, 255, 255), 1.2, "default-bold", "center", "top")
end

--------------------------------------------------------------------------------
-- menu pages
--------------------------------------------------------------------------------

local function leaf(label, value, desc)
    return { label = label, value = value, desc = desc, closeOnSelect = false }
end

local function back(page) return leaf("< Back", { "go", page }) end

local function open(page, title, items)
    E.page = page
    E.menuId = inac:createTempMenu({ title = title, items = items }) or nil
end

local function closeMenu()
    if E.menuId then
        E.menuId = nil
        if inac:isTempMenuOpen() then inac:closeTempMenu() end
    end
end

local function tp(p, rot) return { "tp", p.x, p.y, p.z, rot } end

local function split(page)
    local out = {}
    for part in page:gmatch("[^:]+") do out[#out + 1] = tonumber(part) or part end
    return out
end

local function show(page)
    local a = split(page)
    local fn = Pages[a[1]]
    if not fn or fn(a[2], a[3]) == false then Pages.root() end
end

function Pages.root()
    local d = E.doc
    local nb = 0
    for _ in pairs(E.buildings) do nb = nb + 1 end
    open("root", "MISSION EDITOR", {
        leaf(("Supply spots (%d)"):format(#d.supply), { "go", "supply" }, "Steal targets: crate, van, guards"),
        leaf(("Sell van spawns (%d buildings)"):format(nb), { "go", "vans" }, "Where the delivery vans spawn"),
        leaf(("Buyers (%d)"):format(#d.buyers), { "go", "buyers" }, "Delivery targets of the sell vans"),
        leaf("Nearest position", { "nearest" }, "Opens the entry closest to you"),
        leaf(E.labels and "Labels: on" or "Labels: off", { "labels" }),
        leaf(E.dirty and "Save *" or "Save", { "save" }, "Writes data/positions.json; new missions use it"),
        leaf("Discard changes", { "discard" }, "Back to the saved positions"),
        leaf("Close editor", { "exit" }),
    })
end

function Pages.supply()
    local items = { back("root") }
    for i, s in ipairs(E.doc.supply) do
        local g = s.guards and (#s.guards .. " fixed guards") or "random guards"
        items[#items + 1] = leaf(("#%d %s"):format(i, s.name), { "go", "spot:" .. i },
            ("%s, %s"):format(s.van and "fixed van" or "random van", g))
    end
    items[#items + 1] = leaf("+ New supply spot here", { "addspot" }, "The crate goes where you stand")
    open("supply", "SUPPLY SPOTS", items)
end

Pages.spot = function(i)
    local s = E.doc.supply[i]
    if not s then return false end
    local items = {
        back("supply"),
        leaf("Teleport to the crate", tp(s)),
        leaf("Move the crate here", { "movespot", i }, "The spot centre: crate, radar circle, random guards"),
        leaf("Rename", { "renamespot", i }),
    }
    if s.van then
        items[#items + 1] = leaf("Teleport to the van", tp(s.van, s.van.rot))
        items[#items + 1] = leaf("Move the van here", { "setvan", i }, "Drive the van there for the heading")
        items[#items + 1] = leaf("Remove the fixed van", { "clearvan", i }, "Random: 2 m from the crate")
    else
        items[#items + 1] = leaf("Fixed van here", { "setvan", i }, "Now: 2 m from the crate, random heading")
    end
    for j, g in ipairs(s.guards or {}) do
        items[#items + 1] = leaf(("Guard %d"):format(j), { "go", ("guard:%d:%d"):format(i, j) })
    end
    items[#items + 1] = leaf("+ Fixed guard here", { "addguard", i }, "Faces your heading. Fixed guards replace the random ones")
    if s.guards then items[#items + 1] = leaf("Clear fixed guards", { "clearguards", i }, "Back to random guards") end
    items[#items + 1] = leaf("Delete this spot", { "delspot", i })
    open("spot:" .. i, ("#%d %s"):format(i, s.name):upper(), items)
end

Pages.guard = function(i, j)
    local s = E.doc.supply[i]
    local g = s and s.guards and s.guards[j]
    if not g then return false end
    open(("guard:%d:%d"):format(i, j), ("%s GUARD %d"):format(s.name, j):upper(), {
        back("spot:" .. i),
        leaf("Teleport", tp(g, g.rot)),
        leaf("Move here", { "moveguard", i, j }, "Position and heading from you"),
        leaf("Delete", { "delguard", i, j }),
    })
end

local function buildingIds()
    local ids = {}
    for id in pairs(E.buildings) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

function Pages.vans()
    local items = { back("root") }
    for _, id in ipairs(buildingIds()) do
        local list = E.doc.vanSpawns[id]
        items[#items + 1] = leaf(E.buildings[id].name, { "go", "vanb:" .. id }, list and (#list .. " spawns") or "no spawns")
    end
    open("vans", "SELL VAN SPAWNS", items)
end

Pages.vanb = function(id)
    local b = E.buildings[id]
    if not b then return false end
    local items = { back("vans"), leaf("Teleport to the entrance", tp(b, b.rot)) }
    for k in ipairs(E.doc.vanSpawns[id] or {}) do
        items[#items + 1] = leaf(("Van %d"):format(k), { "go", ("vansp:%s:%d"):format(id, k) })
    end
    items[#items + 1] = leaf("+ Van spawn here", { "addvan", id }, "Drive a van there for the heading. One van per spawn at most")
    open("vanb:" .. id, b.name:upper(), items)
end

Pages.vansp = function(id, k)
    local list = E.doc.vanSpawns[id]
    local s = list and list[k]
    if not s then return false end
    open(("vansp:%s:%d"):format(id, k), ("%s VAN %d"):format(E.buildings[id].name, k):upper(), {
        back("vanb:" .. id),
        leaf("Teleport", tp(s, s.rot)),
        leaf("Move here", { "movevan", id, k }),
        leaf("Delete", { "delvan", id, k }),
    })
end

function Pages.buyers()
    local items = { back("root") }
    for i, b in ipairs(E.doc.buyers) do
        items[#items + 1] = leaf(("#%d %s"):format(i, b.name), { "go", "buyer:" .. i })
    end
    items[#items + 1] = leaf("+ New buyer here", { "addbuyer" }, "Buyers should be on roads (the pursuers are lane bound)")
    open("buyers", "BUYERS", items)
end

Pages.buyer = function(i)
    local b = E.doc.buyers[i]
    if not b then return false end
    open("buyer:" .. i, ("#%d %s"):format(i, b.name):upper(), {
        back("buyers"),
        leaf("Teleport", tp(b)),
        leaf("Move here", { "movebuyer", i }),
        leaf("Rename", { "renamebuyer", i }),
        leaf("Delete", { "delbuyer", i }),
    })
end

local function reopen() show(E.page or "root") end

--------------------------------------------------------------------------------
-- actions
--------------------------------------------------------------------------------

local function askText(title, default, apply)
    closeMenu()
    textToken = uicore:openTextInput(title, 40, default or "")
    if textToken then textApply = apply else reopen() end
end

local function setPos(t, p, withRot)
    t.x, t.y, t.z = p.x, p.y, p.z
    if withRot then t.rot = p.rot end
end

local A = {}

function A.go(v) show(v[2]) end

function A.tp(v)
    triggerServerEvent("bizmis:editorTeleport", resourceRoot, v[2], v[3], v[4], v[5])
end

function A.labels()
    E.labels = not E.labels
    reopen()
end

function A.nearest()
    local x, y, z = getElementPosition(localPlayer)
    local best, bestD
    for _, p in ipairs(E.previews) do
        local d = getDistanceBetweenPoints3D(x, y, z, p.x, p.y, p.z)
        if p.page and (not bestD or d < bestD) then best, bestD = p, d end
    end
    if best then show(best.page) end
end

function A.save()
    E.waitingSave = true
    triggerServerEvent("bizmis:editorSave", resourceRoot, E.doc)
end

function A.discard()
    E.doc = deepcopy(E.saved)
    E.dirty = false
    buildPreviews()
    Pages.root()
end

function A.exit() Editor.stop(true) end

function A.addspot()
    local p = here()
    table.insert(E.doc.supply, { name = zoneName(p), x = p.x, y = p.y, z = p.z })
    changed()
    show("spot:" .. #E.doc.supply)
end

function A.movespot(v) setPos(E.doc.supply[v[2]], here()); changed(); reopen() end

function A.renamespot(v)
    local s = E.doc.supply[v[2]]
    askText("Supply spot name", s.name, function(t) if t ~= "" then s.name = t; changed() end end)
end

function A.setvan(v)
    local s = E.doc.supply[v[2]]
    s.van = {}
    setPos(s.van, here(), true)
    changed(); reopen()
end

function A.clearvan(v) E.doc.supply[v[2]].van = nil; changed(); reopen() end

function A.addguard(v)
    local s = E.doc.supply[v[2]]
    s.guards = s.guards or {}
    if #s.guards >= 12 then return notify("12 guards at most.") end
    local g = {}
    setPos(g, here(), true)
    s.guards[#s.guards + 1] = g
    changed(); reopen()
end

function A.clearguards(v) E.doc.supply[v[2]].guards = nil; changed(); reopen() end

function A.moveguard(v) setPos(E.doc.supply[v[2]].guards[v[3]], here(), true); changed(); reopen() end

function A.delguard(v)
    local s = E.doc.supply[v[2]]
    table.remove(s.guards, v[3])
    if #s.guards == 0 then s.guards = nil end
    changed()
    show("spot:" .. v[2])
end

function A.delspot(v)
    if #E.doc.supply <= 1 then return notify("At least one supply spot is needed.") end
    table.remove(E.doc.supply, v[2])
    changed()
    show("supply")
end

function A.addvan(v)
    local id = v[2]
    E.doc.vanSpawns[id] = E.doc.vanSpawns[id] or {}
    local list = E.doc.vanSpawns[id]
    if #list >= 16 then return notify("16 spawns at most.") end
    local s = {}
    setPos(s, here(), true)
    list[#list + 1] = s
    changed(); reopen()
end

function A.movevan(v) setPos(E.doc.vanSpawns[v[2]][v[3]], here(), true); changed(); reopen() end

function A.delvan(v)
    local list = E.doc.vanSpawns[v[2]]
    table.remove(list, v[3])
    if #list == 0 then E.doc.vanSpawns[v[2]] = nil end
    changed()
    show("vanb:" .. v[2])
end

function A.addbuyer()
    local p = here()
    table.insert(E.doc.buyers, { name = zoneName(p), x = p.x, y = p.y, z = p.z })
    changed()
    show("buyer:" .. #E.doc.buyers)
end

function A.movebuyer(v) setPos(E.doc.buyers[v[2]], here()); changed(); reopen() end

function A.renamebuyer(v)
    local b = E.doc.buyers[v[2]]
    askText("Buyer name", b.name, function(t) if t ~= "" then b.name = t; changed() end end)
end

function A.delbuyer(v)
    if #E.doc.buyers <= 1 then return notify("At least one buyer is needed.") end
    table.remove(E.doc.buyers, v[2])
    changed()
    show("buyers")
end

addEvent("ui_inac:tempMenuSelect")
addEventHandler("ui_inac:tempMenuSelect", root, function(rootId, value)
    if not E.active or rootId ~= E.menuId or type(value) ~= "table" then return end
    local fn = A[value[1]]
    if fn then fn(value) end
end)

addEvent("ui_inac:tempMenuClose")
addEventHandler("ui_inac:tempMenuClose", root, function(rootId)
    if rootId == E.menuId then E.menuId = nil end
end)

addEvent("ui_core:textInputResult")
addEventHandler("ui_core:textInputResult", root, function(token, text)
    if token ~= textToken then return end
    textToken = nil
    local apply = textApply
    textApply = nil
    if text and apply and E.active then apply((text:gsub("^%s+", ""):gsub("%s+$", ""))) end
    if E.active then reopen() end
end)

--------------------------------------------------------------------------------
-- start / stop
--------------------------------------------------------------------------------

Editor = {}

local function menuKey()
    if not E.active or textToken or inac:isTempMenuOpen() then return end
    reopen()
end

function Editor.stop(tellServer)
    if not E.active then return end
    E.active = false
    closeMenu()
    unbindKey(E.C.key, "down", menuKey)
    removeEventHandler("onClientRender", root, render)
    clearPreviews()
    if tellServer then triggerServerEvent("bizmis:editorClosed", resourceRoot) end
    notify(E.dirty and "Editor closed, unsaved changes dropped." or "Editor closed.")
end

addEvent("bizmis:editorStart", true)
addEventHandler("bizmis:editorStart", resourceRoot, function(doc, buildings, C)
    if E.active then Editor.stop(false) end
    E.active, E.C, E.buildings = true, C, buildings or {}
    E.saved = deepcopy(doc)
    E.doc = deepcopy(doc)
    E.doc.vanSpawns = E.doc.vanSpawns or {}
    E.dirty, E.page = false, "root"
    buildPreviews()
    bindKey(C.key, "down", menuKey)
    addEventHandler("onClientRender", root, render)
    Pages.root()
    notify(("Editor open. [%s] menu, /bizmissioneditor again closes it."):format(C.key:upper()))
end)

addEvent("bizmis:editorStop", true)
addEventHandler("bizmis:editorStop", resourceRoot, function() Editor.stop(false) end)

-- saved (by this or another admin)
addEvent("bizmis:editorData", true)
addEventHandler("bizmis:editorData", resourceRoot, function(doc)
    if not E.active then return end
    local mine = E.dirty
    E.saved = deepcopy(doc)
    if E.waitingSave or not mine then
        E.doc = deepcopy(doc)
        E.doc.vanSpawns = E.doc.vanSpawns or {}
        E.dirty = false
        buildPreviews()
        if E.menuId then reopen() end
    else
        notify("Another admin saved the positions. Your unsaved changes are kept; saving overwrites theirs.")
    end
    E.waitingSave = nil
end)

addEvent("bizmis:editorNotify", true)
addEventHandler("bizmis:editorNotify", resourceRoot, function(text, saveFailed)
    if saveFailed then E.waitingSave = nil end
    notify(text)
end)

addEventHandler("onClientResourceStop", resourceRoot, function() clearPreviews() end)
