if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Client side of the air traffic controller tutorial: the texts of every step and the sub-steps the
-- client follows itself (the avi_controller scope through getScopeLayout, the tutorial aircraft
-- through the server's state updates). The server owns the session (server/session.lua).

local T = {
    active = false,
    step = nil,          -- server step
    sub = 1,             -- sub-step of the current step
    info = {},           -- from the server at begin: position, airport, marker, pay, ranks, runways
    ac = {},             -- dep / arr = the tutorial aircraft (compact snapshot from the server)
    cmds = { dep = {}, arr = {} },   -- accepted commands per aircraft
    receipt = nil,
    note = nil, noteColor = nil,
    fast = nil,          -- the time scale of the tutorial aircraft while nobody waits for the player (server)
}

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

---------------------------------------------------------------- what the player sees

local function scope() return call("avi_controller", "getScopeLayout") or {} end

local function scopeVisible() return scope().visible == true end
local function loginOpen() return scope().login ~= nil end

local function scopeRect(key)
    return function()
        local sc = scope()
        return sc.visible and sc[key] or nil
    end
end

local function acOf(role) return T.ac[role] end

-- the label of a tutorial aircraft on the scope
local function labelRect(role)
    return function()
        local a = acOf(role)
        local sc = scope()
        local e = a and sc.aircraft and sc.aircraft[a.cs]
        return e and e.label or nil
    end
end

local function menuOpenFor(role)
    local a = acOf(role)
    local m = scope().menu
    return a ~= nil and m ~= nil and m.ac == a.cs
end

-- a command menu item of the aircraft whose label starts with one of the prefixes, else its label
local function menuItem(role, ...)
    local prefixes = { ... }
    return function()
        local a = acOf(role)
        local sc = scope()
        local m = sc.menu
        if a and m and m.ac == a.cs then
            for _, it in ipairs(m.items or {}) do
                for _, p in ipairs(prefixes) do
                    if not it.header and it.label:sub(1, #p) == p then return it.rect end
                end
            end
            return m.rect
        end
        return labelRect(role)()
    end
end

-- the item the aircraft asks for (yellow) in the open menu, else its label
local function requestItem(role)
    return function()
        local a = acOf(role)
        local m = scope().menu
        if a and m and m.ac == a.cs then
            for _, it in ipairs(m.items or {}) do
                if it.request and not it.disabled then return it.rect end
            end
            return m.rect
        end
        return labelRect(role)()
    end
end

local function phaseOf(role)
    local a = acOf(role)
    return a and a.phase or nil
end

-- the departure is out of the tower's hands: gone, or airborne and controlled by nobody / somebody else
local function depLost()
    local a = acOf("dep")
    return a == nil or (not a.gnd and a.ctl ~= T.info.position)
end

local function focus(role, minScale)
    local a = acOf(role)
    if not a or not scopeVisible() then return end
    local sc = scope()
    call("avi_controller", "focusScope", a.x, a.y, nil, minScale and (sc.groundScale or 0.2) * minScale or nil)
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
    local def = currentList() and currentList()[T.sub]
    if def and def.enter then def.enter() end
    refresh()
end

local function serverNext()
    triggerServerEvent("atc:tut:next", resourceRoot, T.step)
end

local STEP_LABELS = {}
local function buildLabels()
STEP_LABELS = {
    console = L("work_atc.tut.steps.step_console"),
    scope = L("work_atc.tut.steps.step_scope"),
    label = L("work_atc.tut.steps.step_label"),
    delivery = L("work_atc.tut.steps.step_delivery"),
    ground = L("work_atc.tut.steps.step_ground"),
    air = L("work_atc.tut.steps.step_air"),
    arrival = L("work_atc.tut.steps.step_arrival"),
    alerts = L("work_atc.tut.steps.step_alerts"),
    done = L("work_atc.tut.steps.step_done"),
}
end

-- Sub-step fields:
--   text      = function -> string
--   next      = a Next button moves on;  check = function, moves on once it holds
--   rect      = function -> highlighted { x, y, w, h }
--   needScope = shown as a note while the scope is not on the screen
--   note      = function -> extra note (when nothing is missing)
--   enter     = function, called when the sub-step comes;  leave = function, called when it is done
local function S(key, params)
    return function() return L("work_atc.tut.steps." .. key, params and params() or nil) end
end

local function money(n) return L.money(n or 0) end

local function base()
    local rw = T.info.runways or {}
    return {
        console = K.console, position = T.info.position or "?", airport = T.info.airport or "?",
        dep_rwy = rw.dep or "?", arr_rwy = rw.arr or "?",
        dep = TUTORIAL.DEPARTURE.callsign, arr = TUTORIAL.ARRIVAL.callsign, command = TUTORIAL.COMMAND,
    }
end

local function payParams()
    local p, pay = base(), T.info.pay or {}
    local pen = pay.penalty or {}
    p.per_action = money(pay.perAction)
    p.per_aircraft = money(pay.perAircraft)
    p.bonus = math.floor((pay.minuteBonus or 0) * 100 + 0.5)
    p.max = pay.maxMult or 1
    p.gnd, p.tma, p.cta = money(pen.GND), money(pen.TMA), money(pen.CTA)
    p.app = T.info.ranks and T.info.ranks.app or 5
    p.radar = T.info.ranks and T.info.ranks.radar or 8
    return p
end

local function cmd(role, ...)
    for _, a in ipairs({ ... }) do
        if T.cmds[role][a] then return true end
    end
    return false
end

local LANDED = { landing = true, vacate = true, vacated = true, taxi_in = true, parked = true }

-- what the departure is asking for while it taxies (a note of the ground steps)
local function depRequestNote()
    local a = acOf("dep")
    if not a then return nil end
    if a.phase == "hold" and a.req then
        return L("work_atc.tut.steps.note_holding", { rwy = a.holdRwy or "?", req = a.req })
    end
    return L("work_atc.tut.steps.note_phase", { phase = a.phase or "?" })
end

local function goAroundNote()
    local a = acOf("arr")
    if a and a.proc and tostring(a.proc):sub(1, 3) == "GA " then
        return L("work_atc.tut.steps.note_go_around")
    end
end

local function buildSubs()
STEP_SUBS = {
    console = {
        { text = S("console_walk", base), check = function() return loginOpen() or scopeVisible() end },
        { text = S("console_login", base),
          rect = function()
              local lg = scope().login
              return lg and lg.rows and lg.rows[T.info.position] or nil
          end,
          note = function()
              if not loginOpen() then return L("work_atc.tut.steps.note_open_console", base()) end
          end },
        -- the server moves on once the tutorial login is done
    },
    scope = {
        { text = S("scope_intro", base), next = true, needScope = true },
        { text = S("scope_topbar", base), next = true, needScope = true, rect = scopeRect("runways") },
        { text = S("scope_tools"), next = true, needScope = true, rect = scopeRect("tools") },
        { text = S("scope_view"), next = true, needScope = true, rect = scopeRect("scaleBar") },
        { text = S("scope_list"), next = true, needScope = true, rect = scopeRect("list") },
        { text = S("scope_buttons", base), next = true, needScope = true, rect = scopeRect("hide"), leave = serverNext },
    },
    label = {
        { text = S("label_wait", base), needScope = true, check = function() return acOf("dep") ~= nil end },
        { text = S("label_ground", base), next = true, needScope = true, rect = labelRect("dep"),
          enter = function() focus("dep", 2) end },
        { text = S("label_air"), next = true, needScope = true, rect = labelRect("dep") },
        { text = S("label_menu", base), needScope = true, check = function() return menuOpenFor("dep") end,
          rect = labelRect("dep") },
        { text = S("label_menu_info"), next = true, needScope = true, rect = function()
              local m = scope().menu
              return m and m.rect or nil
          end, leave = serverNext },
    },
    delivery = {
        { text = S("delivery_ifr", base), needScope = true, check = function() return cmd("dep", "ifr") end,
          rect = menuItem("dep", "IFR clearance") },
        { text = S("delivery_push", base), needScope = true, check = function() return cmd("dep", "push") end,
          rect = menuItem("dep", "Pushback approved") },
        { text = S("delivery_pushing", base), needScope = true, rect = labelRect("dep"),
          check = function()
              local a = acOf("dep")
              return a ~= nil and a.req == "TAXI" and a.ready == true
          end, leave = serverNext },
    },
    ground = {
        { text = S("ground_taxi", base), needScope = true, check = function() return cmd("dep", "taxi") end,
          rect = menuItem("dep", "Taxi") },
        { text = S("ground_rules"), needScope = true, rect = labelRect("dep"), note = depRequestNote,
          check = function()
              local p = phaseOf("dep")
              return p == "hold" or p == "lined" or p == "takeoff" or p == "air" or cmd("dep", "takeoff")
          end },
        { text = S("ground_takeoff", base), needScope = true, rect = requestItem("dep"), note = depRequestNote,
          check = function() return cmd("dep", "takeoff") end, leave = serverNext },
    },
    air = {
        { text = S("air_wait", base), needScope = true, rect = labelRect("dep"),
          check = function() return phaseOf("dep") == "air" or depLost() end },
        { text = S("air_leave", base), needScope = true, rect = labelRect("dep"), check = depLost, leave = serverNext },
    },
    arrival = {
        { text = S("arr_wait", base), needScope = true, check = function() return acOf("arr") ~= nil end },
        { text = S("arr_land", base), needScope = true, rect = menuItem("arr", "Cleared to land"), note = goAroundNote,
          enter = function() focus("arr", 0.8) end,
          check = function()
              local a = acOf("arr")
              return cmd("arr", "land") or (a ~= nil and (a.landClr or LANDED[a.phase] == true))
          end },
        { text = S("arr_vacate"), needScope = true, rect = labelRect("arr"), note = goAroundNote,
          check = function() return LANDED[phaseOf("arr") or ""] == true end },
        { text = S("arr_taxi", base), needScope = true, rect = menuItem("arr", "Taxi to stand"),
          enter = function() focus("arr", 1.6) end,
          check = function() return cmd("arr", "taxi") or phaseOf("arr") == "taxi_in" or phaseOf("arr") == "parked" end },
        { text = S("arr_parked", base), needScope = true, rect = labelRect("arr"),
          check = function() return phaseOf("arr") == "parked" end, leave = serverNext },
    },
    alerts = {
        { text = S("alerts_emrg", base), next = true, needScope = true, rect = labelRect("arr"),
          enter = function() focus("arr", 1.6) end,
          leave = function() triggerServerEvent("atc:tut:restoreSquawk", resourceRoot) end },
        { text = S("alerts_fines", payParams), next = true, needScope = true },
        { text = S("alerts_pay", payParams), next = true, needScope = true },
        { text = S("alerts_logout"), needScope = true, rect = scopeRect("logout") },
        -- the server moves on at the logout (the receipt comes with it)
    },
}
end

---------------------------------------------------------------- card builders

local function missingNote(def)
    if def.needScope and not scopeVisible() then return L("work_atc.tut.steps.note_open_scope", base()) end
end

local function subCard(list, step)
    local def = list[T.sub]
    if not def then return nil end
    local spec = { step = STEP_LABELS[step], text = def.text(), note = T.note, noteColor = T.noteColor }

    local missing = missingNote(def)
    if missing then
        spec.note, spec.noteColor = missing, Card.colors.bad
    elseif not spec.note and def.note then
        spec.note, spec.noteColor = def.note(), Card.colors.muted
    end
    if T.fast and not missing then
        local fast = L("work_atc.tut.steps.note_fast", { scale = T.fast })
        spec.note = spec.note and (spec.note .. "\n" .. fast) or fast
        spec.noteColor = spec.noteColor or Card.colors.muted
    end

    if def.next then
        -- the scope and the login window show the cursor themselves, otherwise the card does
        spec.modal = not scopeVisible() and not loginOpen()
        spec.buttons = { { label = L("work_atc.tut.steps.next"), primary = true, disabled = missing ~= nil, fn = function()
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
        rows[#rows + 1] = { title = L("work_atc.tut.steps.receipt_total"), status = money(receipt.total),
            statusColor = Card.colors.text }
    end
    return {
        step = STEP_LABELS.done,
        title = L("work_atc.tut.steps.done_title"),
        text = L("work_atc.tut.steps.done_text", base()),
        rows = rows,
        buttons = { { label = L("work_atc.tut.steps.finish"), primary = true, fn = serverNext } },
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

handle("atc:tut:notify", function(text)
    pcall(function() exports.ui_core:addNotification(L("work_atc.tut.card.title"), tostring(text)) end)
end)

handle("atc:tut:offer", function()
    if T.active then return end
    Card.onSkip = nil
    Card.show({
        title = L("work_atc.tut.card.title"),
        text = L("work_atc.tut.steps.offer", { command = TUTORIAL.COMMAND }),
        buttons = {
            { label = L("work_atc.tut.steps.skip"), fn = function()
                Card.hide()
                triggerServerEvent("atc:tut:answer", resourceRoot, false)
            end },
            { label = L("work_atc.tut.steps.start"), primary = true, fn = function()
                Card.hide()
                triggerServerEvent("atc:tut:answer", resourceRoot, true)
            end },
        },
        modal = true, noSkip = true,
    })
end)

local function toggleCursor() Card.toggleCursor() end

handle("atc:tut:begin", function(info)
    T.active, T.step, T.sub = true, nil, 1
    T.info = type(info) == "table" and info or {}
    T.ac, T.cmds, T.receipt, T.note, T.fast = {}, { dep = {}, arr = {} }, nil, nil, nil
    bindKey(TUTORIAL.CURSOR_KEY, "down", toggleCursor)
    Card.onSkip = function() triggerServerEvent("atc:tut:skip", resourceRoot) end
end)

handle("atc:tut:step", function(step)
    T.step, T.sub, T.note = step, 1, nil
    if step == "console" then
        -- (again after an early logout: new aircraft come)
        T.ac, T.cmds = {}, { dep = {}, arr = {} }
    end
    local def = currentList() and currentList()[1]
    if def and def.enter then def.enter() end
    refresh()
end)

handle("atc:tut:info", function(kind, a, b)
    if kind == "aircraft" then
        T.ac = type(a) == "table" and a or {}
        T.fast = tonumber(b)
    elseif kind == "spawn" then
        T.ac[a] = b
        T.cmds[a] = {}
        -- the new aircraft in the middle of the scope
        if a == "dep" then focus("dep", 2) else focus("arr", 0.8) end
    elseif kind == "cmd" then
        if T.cmds[a] then T.cmds[a][b] = true end
    elseif kind == "receipt" then
        T.receipt = a
    end
    refresh()
end)

handle("atc:tut:end", function()
    T.active, T.step = false, nil
    unbindKey(TUTORIAL.CURSOR_KEY, "down", toggleCursor)
    Card.hide()
end)

-- Texts load only once the player is loaded (v_accounts loading gate).
local textsLoaded = false
local function loadTexts()
    if textsLoaded then return end
    textsLoaded = true
    buildLabels()
    buildSubs()
    pcall(function() exports.v_accounts:resourceReady() end)
end
addEvent("onClientLoadingStarted", true)
addEventHandler("onClientLoadingStarted", root, loadTexts)
addEventHandler("onClientResourceStart", resourceRoot, function()
    if getElementData(localPlayer, "loaded") then loadTexts() end
end)
