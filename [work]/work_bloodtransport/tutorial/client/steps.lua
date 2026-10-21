if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Client side of the blood transport tutorial: the texts of every step and the sub-steps the client
-- follows itself (the bt_dispatch panel through getPanelLayout, the hands / inventory / port window
-- through v_inventory getUiLayout and the inv.slots data). The server owns the session
-- (server/session.lua).

local T = {
    active = false,
    step = nil,          -- server step
    sub = 1,             -- sub-step of the current step
    vehicle = nil,
    info = {},           -- from the server at begin: from / to { name, x, y, z }, cargoItem, pay
    taskId = nil, picked = false, delivered = false,
    receipt = nil,
    note = nil, noteColor = nil,
}

local BOX_ITEM = "bt_blood_box"
local K = TUTORIAL.KEYS

local function isRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function call(resource, fn, ...)
    if not isRunning(resource) then return nil end
    local ok, result = pcall(exports[resource][fn], exports[resource], ...)
    return ok and result or nil
end

---------------------------------------------------------------- what the player sees / holds

local function panel() return call("bt_dispatch", "getPanelLayout") or {} end
local function inventory() return call("v_inventory", "getUiLayout") or {} end

local function bigOpen()
    local p = panel()
    return p.visible == true and p.big == true
end

local function window() return inventory().window or nil end

local function windowOpen(kind)
    local w = window()
    return w ~= nil and w ~= false and (kind == nil or w.kind == kind)
end

local function carryingBox()
    local slots = getElementData(localPlayer, "inv.slots")
    if type(slots) ~= "table" then return false end
    for _, slot in ipairs({ "left", "right" }) do
        if type(slots[slot]) == "table" and slots[slot].d == BOX_ITEM then return true end
    end
    return false
end

local function inVehicle()
    return isElement(T.vehicle) and getPedOccupiedVehicle(localPlayer) == T.vehicle
end

-- Rectangles to highlight
local function panelRect(key)
    return function()
        local p = panel()
        return p.visible and p[key] or nil
    end
end

local function taskRect(key)
    return function()
        local p = panel()
        local t = T.taskId and p.tasks and p.tasks[tostring(T.taskId)]
        return t and t[key] or nil
    end
end

local function routeOn()
    local p = panel()
    local t = T.taskId and p.tasks and p.tasks[tostring(T.taskId)]
    return t and t.routeOn == true
end

local function windowRect(key)
    return function()
        local w = window()
        return w and w[key] or nil
    end
end

local function boxSlotRect()
    local w = window()
    for _, slot in pairs(w and w.slots or {}) do
        if slot.d == BOX_ITEM then return slot.rect end
    end
end

local function cargoRow(side)
    return function()
        local w = window()
        for _, row in ipairs(w and w.rows or {}) do
            if row.d == T.info.cargoItem and row.side == side then return row.rect end
        end
    end
end

local function hudRect() return inventory().hud or nil end

local function distanceTo(place)
    if not place or not place.x then return nil end
    local x, y, z = getElementPosition(localPlayer)
    return getDistanceBetweenPoints3D(x, y, z, place.x, place.y, place.z)
end

---------------------------------------------------------------- sub-step machinery

local refresh -- forward
local STEP_SUBS -- step -> its sub-step list

local function currentList()
    return T.step and STEP_SUBS and STEP_SUBS[T.step]
end

local function nextSub()
    T.sub = T.sub + 1
    T.note = nil
    refresh()
end

local function serverNext()
    triggerServerEvent("bt:tut:next", resourceRoot, T.step)
end

local STEP_LABELS = {}
local function buildLabels()
STEP_LABELS = {
    panel = L("work_bloodtransport.tut.steps.label_panel"),
    task = L("work_bloodtransport.tut.steps.label_task"),
    box = L("work_bloodtransport.tut.steps.label_box"),
    pickup = L("work_bloodtransport.tut.steps.label_pickup"),
    drive = L("work_bloodtransport.tut.steps.label_drive"),
    deliver = L("work_bloodtransport.tut.steps.label_deliver"),
    signoff = L("work_bloodtransport.tut.steps.label_signoff"),
    done = L("work_bloodtransport.tut.steps.label_done"),
}
end

-- Sub-step fields:
--   text      = function -> string
--   next      = a Next button moves on;  check = function, moves on once it holds
--   rect      = function -> highlighted { x, y, w, h }
--   needBig / needWindow ("own" | "port") / needVehicle = shown as a note while missing
--   note      = function -> extra note (when nothing is missing)
--   leave     = function, called when the sub-step is done
local function S(key, params)
    return function() return L("work_bloodtransport.tut.steps." .. key, params and params() or nil) end
end

local function keys() return { panel = K.panel, inventory = K.inventory, drop = K.drop, port = K.port } end

local function money(n) return L.money(n or 0) end

local function payParams()
    local pay = T.info.pay or {}
    return { base = money(pay.base), delivered = money(pay.delivered), in_transit = money(pay.inTransit) }
end

local function fromTo()
    local k = keys()
    k.from = T.info.from and T.info.from.name or "?"
    k.to = T.info.to and T.info.to.name or "?"
    return k
end

local function buildSubs()
STEP_SUBS = {
    panel = {
        { text = S("panel_small", fromTo), next = true, rect = panelRect("small") },
        { text = S("panel_open", keys), check = bigOpen, rect = panelRect("small") },
        { text = S("panel_sign_on"), needBig = true, needVehicle = true, rect = panelRect("signOn") },
        -- the server moves on once the tutorial service started
    },
    task = {
        { text = S("task_header"), next = true, needBig = true, rect = panelRect("stats") },
        { text = S("task_waiting"), needBig = true, check = function() return taskRect("row")() ~= nil end },
        { text = S("task_row"), next = true, needBig = true, rect = taskRect("row") },
        { text = S("task_route"), needBig = true, check = routeOn, rect = taskRect("route") },
        { text = S("task_more", keys), check = function() return not bigOpen() end, rect = taskRect("hand"),
          leave = serverNext },
    },
    box = {
        { text = S("box_get_out"), check = function() return not inVehicle() end },
        { text = S("box_take"), check = carryingBox },
        { text = S("box_hud", keys), next = true, rect = hudRect },
        { text = S("box_open_inventory", keys), check = function() return windowOpen("own") end },
        { text = S("box_slots"), next = true, needWindow = "own", rect = boxSlotRect },
        { text = S("box_container", keys), check = function() return not windowOpen() end, rect = windowRect("leftArea"),
          leave = serverNext },
    },
    pickup = {
        { text = S("pickup_port", fromTo), check = function() return windowOpen("port") end,
          note = function() if not carryingBox() then return L("work_bloodtransport.tut.steps.note_take_box") end end },
        { text = S("pickup_window"), next = true, needWindow = "port", rect = windowRect("banner") },
        { text = S("pickup_drag"), needWindow = "port", check = function() return T.picked end, rect = cargoRow("right") },
        { text = S("pickup_done"), check = function() return not windowOpen() end, leave = serverNext },
    },
    drive = {
        { text = S("drive_put_back"), check = function() return not carryingBox() end },
        { text = S("drive_get_in"), check = inVehicle },
        { text = S("drive_go", fromTo),
          note = function()
              local d = distanceTo(T.info.to)
              return d and L("work_bloodtransport.tut.steps.note_distance", { m = math.floor(d) }) or nil
          end },
        -- the server moves on at the destination
    },
    deliver = {
        { text = S("deliver_take"), check = carryingBox },
        { text = S("deliver_port", keys), check = function() return windowOpen("port") end },
        { text = S("deliver_drag"), needWindow = "port", check = function() return T.delivered end, rect = cargoRow("left") },
        { text = S("deliver_done"), check = function() return not windowOpen() and not carryingBox() end,
          note = function()
              if windowOpen() then return L("work_bloodtransport.tut.steps.note_close_window") end
              if carryingBox() then return L("work_bloodtransport.tut.steps.note_put_back") end
          end,
          leave = serverNext },
    },
    signoff = {
        { text = S("signoff_open", keys), check = bigOpen },
        { text = S("signoff_pay", payParams), next = true, needBig = true, rect = panelRect("stats") },
        { text = S("signoff_types"), next = true, needBig = true, rect = panelRect("windDown") },
        { text = S("signoff_press"), needBig = true, rect = panelRect("signOff") },
        -- the server moves on once the tutorial service ended
    },
}
end

---------------------------------------------------------------- card builders

local function missingNote(def)
    if def.needVehicle and not inVehicle() then return L("work_bloodtransport.tut.steps.note_get_in") end
    if def.needBig and not bigOpen() then return L("work_bloodtransport.tut.steps.note_open_panel", keys()) end
    if def.needWindow == "own" and not windowOpen("own") then return L("work_bloodtransport.tut.steps.note_open_inventory", keys()) end
    if def.needWindow == "port" and not windowOpen("port") then return L("work_bloodtransport.tut.steps.note_open_port", keys()) end
end

local function subCard(list, step)
    local def = list[T.sub]
    if not def then return nil end
    local spec = { step = STEP_LABELS[step], text = def.text(), note = T.note, noteColor = T.noteColor }
    -- the inventory window covers the middle of the screen: the card goes below it
    if windowOpen() then spec.side = "bottom" end

    local missing = missingNote(def)
    if missing then
        spec.note, spec.noteColor = missing, Card.colors.bad
    elseif not spec.note and def.note then
        spec.note, spec.noteColor = def.note(), Card.colors.muted
    end

    if def.next then
        -- the big panel and the inventory window show the cursor themselves, otherwise the card does
        spec.modal = not bigOpen() and not windowOpen()
        spec.buttons = { { label = L("work_bloodtransport.tut.steps.next"), primary = true, disabled = missing ~= nil, fn = function()
            if def.leave then def.leave() end
            nextSub()
        end } }
    end

    Card.highlight(not missing and def.rect and def.rect() or nil)
    return spec
end

local function doneCard()
    local rows = {}
    local receipt = T.receipt or {}
    for _, item in ipairs(receipt.items or {}) do
        rows[#rows + 1] = { title = tostring(item.label), status = money(item.amount),
            statusColor = (tonumber(item.amount) or 0) < 0 and Card.colors.bad or Card.colors.good }
    end
    if receipt.total then
        rows[#rows + 1] = { title = L("work_bloodtransport.tut.steps.receipt_total"), status = money(receipt.total),
            statusColor = Card.colors.text }
    end
    return {
        step = STEP_LABELS.done,
        title = L("work_bloodtransport.tut.steps.done_title"),
        text = L("work_bloodtransport.tut.steps.done_text", { panel = K.panel, port = K.port, command = TUTORIAL.COMMAND }),
        rows = rows,
        buttons = { { label = L("work_bloodtransport.tut.steps.finish"), primary = true, fn = serverNext } },
        modal = true, noSkip = true,
    }
end

function refresh()
    if not T.active then return end
    Card.highlight(nil)
    local spec
    local list = currentList()
    if list then
        spec = subCard(list, T.step)
    elseif T.step == "done" then
        spec = doneCard()
    end
    if spec then Card.show(spec) else Card.hide() end
end

-- Keep the card current and move on from a "check" sub-step once its condition holds (also when it
-- was done before the sub-step came)
setTimer(function()
    if not T.active then return end
    local list = currentList()
    local def = list and list[T.sub]
    if def and def.check and def.check() then
        if def.leave then def.leave() end
        return nextSub()
    end
    refresh()
end, 250, 0)

---------------------------------------------------------------- server events

local function handle(name, fn)
    addEvent(name, true)
    addEventHandler(name, resourceRoot, fn)
end

handle("bt:tut:notify", function(text)
    pcall(function() exports.ui_core:addNotification(L("work_bloodtransport.tut.card.title"), tostring(text)) end)
end)

handle("bt:tut:offer", function()
    if T.active then return end
    Card.onSkip = nil
    Card.show({
        title = L("work_bloodtransport.tut.card.title"),
        text = L("work_bloodtransport.tut.steps.offer", { command = TUTORIAL.COMMAND }),
        buttons = {
            { label = L("work_bloodtransport.tut.steps.skip"), fn = function()
                Card.hide()
                triggerServerEvent("bt:tut:answer", resourceRoot, false)
            end },
            { label = L("work_bloodtransport.tut.steps.start"), primary = true, fn = function()
                Card.hide()
                triggerServerEvent("bt:tut:answer", resourceRoot, true)
            end },
        },
        modal = true, noSkip = true,
    })
end)

local function toggleCursor() Card.toggleCursor() end

handle("bt:tut:begin", function(vehicle, info)
    T.active, T.vehicle, T.step, T.sub = true, vehicle, nil, 1
    T.info = type(info) == "table" and info or {}
    T.taskId, T.picked, T.delivered, T.receipt, T.note = nil, false, false, nil, nil
    bindKey(TUTORIAL.CURSOR_KEY, "down", toggleCursor)
    Card.onSkip = function() triggerServerEvent("bt:tut:skip", resourceRoot) end
end)

handle("bt:tut:step", function(step)
    T.step, T.sub, T.note = step, 1, nil
    if step == "panel" then
        -- (again after an early sign off: a new task comes)
        T.taskId, T.picked, T.delivered = nil, false, false
    end
    refresh()
end)

handle("bt:tut:info", function(kind, data)
    if kind == "task" then
        T.taskId, T.picked, T.delivered = data, false, false
    elseif kind == "taskStatus" then
        if data == "transit" then T.picked = true
        elseif data == "delivered" then T.picked, T.delivered = true, true end
    elseif kind == "receipt" then
        T.receipt = data
    end
    refresh()
end)

handle("bt:tut:end", function()
    T.active, T.step = false, nil
    unbindKey(TUTORIAL.CURSOR_KEY, "down", toggleCursor)
    Card.hide()
end)

-- Texts load only once the player is loaded (acc_loading gate).
local textsLoaded = false
local function loadTexts()
    if textsLoaded then return end
    textsLoaded = true
    buildLabels()
    buildSubs()
    pcall(function() exports.acc_loading:resourceReady() end)
end
addEvent("onClientLoadingStarted", true)
addEventHandler("onClientLoadingStarted", root, loadTexts)
addEventHandler("onClientResourceStart", resourceRoot, function()
    if getElementData(localPlayer, "loaded") then loadTexts() end
end)
