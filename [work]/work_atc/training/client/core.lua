if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Client side of the ATC training: the step / sub-step machinery shared by the modules, the
-- helpers their sub-steps use (the avi_controller scope through getScopeLayout, the training aircraft
-- through the server's state updates), the first-duty offer and the module list of the marker.
-- The sub-steps and texts of each module are in client/scope.lua, adc.lua, apc.lua, acc.lua (TRN.modules[id]).
-- The server owns the session (server/session.lua).

TRN = { modules = {} }

local T = {
    active = false,
    module = nil,        -- module id (scope / adc / apc / acc)
    step = nil,          -- server step
    sub = 1,             -- sub-step of the current step
    info = {},           -- from the server at begin: module, code, steps, position, airport, pay, ranks, runways
    ac = {},             -- role -> the training aircraft (compact snapshot from the server)
    cmds = {},           -- role -> accepted commands
    receipt = nil,
    note = nil, noteColor = nil,
    fast = nil,          -- the time scale of the training aircraft while the player only watches (server)
    subs = nil,          -- step -> sub-step list of the running module
    sentFast = false,
}
TRN.T = T

local K = TRAINING.KEYS

local function isRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function call(resource, fn, ...)
    if not isRunning(resource) then return nil end
    local ok, result = pcall(exports[resource][fn], exports[resource], ...)
    return ok and result or nil
end

---------------------------------------------------------------- helpers for the module files

local H = {}
TRN.H = H

function H.scope() return call("avi_controller", "getScopeLayout") or {} end
function H.scopeVisible() return H.scope().visible == true end
function H.loginOpen() return H.scope().login ~= nil end

function H.scopeRect(key)
    return function()
        local sc = H.scope()
        return sc.visible and sc[key] or nil
    end
end

function H.ac(role) return T.ac[role] end

function H.phase(role)
    local a = T.ac[role]
    return a and a.phase or nil
end

-- the aircraft is (was) under the trainee's control
function H.mine(role)
    local a = T.ac[role]
    return a ~= nil and a.ctl == T.info.position
end

function H.had(role)
    local a = T.ac[role]
    return a ~= nil and a.had == true
end

-- was the trainee's and is not any more (gone, or left the sector)
function H.handedOff(role)
    local a = T.ac[role]
    if a == nil then return T.hadOnce and T.hadOnce[role] == true end
    return a.had == true and a.ctl ~= T.info.position
end

-- the label of a training aircraft on the scope
function H.labelRect(role)
    return function()
        local a = T.ac[role]
        local sc = H.scope()
        local e = a and sc.aircraft and sc.aircraft[a.cs]
        return e and e.label or nil
    end
end

function H.menuOpenFor(role)
    local a = T.ac[role]
    local m = H.scope().menu
    return a ~= nil and m ~= nil and m.ac == a.cs
end

-- a command menu item of the aircraft whose label starts with one of the prefixes, else its label
function H.menuItem(role, ...)
    local prefixes = { ... }
    return function()
        local a = T.ac[role]
        local m = H.scope().menu
        if a and m and m.ac == a.cs then
            -- of several matches (Taxi to runway 04 / 22) the current one (the runway in use) wins
            local first
            for _, it in ipairs(m.items or {}) do
                for _, p in ipairs(prefixes) do
                    if not it.header and it.label:sub(1, #p) == p then
                        if it.current then return it.rect end
                        first = first or it.rect
                    end
                end
            end
            return first or m.rect
        end
        return H.labelRect(role)()
    end
end

-- the item the aircraft asks for (yellow) in the open menu, else its label
function H.requestItem(role)
    return function()
        local a = T.ac[role]
        local m = H.scope().menu
        if a and m and m.ac == a.cs then
            for _, it in ipairs(m.items or {}) do
                if it.request and not it.disabled then return it.rect end
            end
            return m.rect
        end
        return H.labelRect(role)()
    end
end

-- the open menu, else the label of the aircraft
function H.menuRect(role)
    return function()
        local m = H.scope().menu
        if m and H.menuOpenFor(role) then return m.rect end
        return H.labelRect(role)()
    end
end

-- centre the scope on the aircraft; minScale = x the ground scale (nil = keep the zoom)
function H.focus(role, minScale)
    local a = T.ac[role]
    if not a or not H.scopeVisible() then return end
    local sc = H.scope()
    call("avi_controller", "focusScope", a.x, a.y, nil, minScale and (sc.groundScale or 0.2) * minScale or nil)
end

function H.cmd(role, ...)
    local c = T.cmds[role]
    if not c then return false end
    for _, a in ipairs({ ... }) do
        if c[a] then return true end
    end
    return false
end

function H.serverNext()
    triggerServerEvent("atc:trn:next", resourceRoot, T.step)
end

function H.money(n) return L.money(n or 0) end

-- the text parameters every module may use
function H.base()
    local rw = T.info.runways or {}
    local cs = TRAINING.CALLSIGNS[T.module] or {}
    local p = {
        console = K.console, position = T.info.position or "?", airport = T.info.airport or "?",
        dep_rwy = rw.dep or "?", arr_rwy = rw.arr or "?", command = TRAINING.COMMAND, code = T.info.code or "?",
        app = T.info.ranks and T.info.ranks.app or 5, radar = T.info.ranks and T.info.ranks.radar or 8,
    }
    for role, c in pairs(cs) do p[role] = c end
    -- the TMA entry fix of the approach arrivals
    for role, a in pairs(T.ac) do
        if a and a.entry then p[role .. "_entry"] = a.entry end
    end
    return p
end

function H.payParams()
    local p, pay = H.base(), T.info.pay or {}
    local pen = pay.penalty or {}
    p.per_action = H.money(pay.perAction)
    p.per_aircraft = H.money(pay.perAircraft)
    p.bonus = math.floor((pay.minuteBonus or 0) * 100 + 0.5)
    p.max = pay.maxMult or 1
    p.gnd, p.tma, p.cta = H.money(pen.GND), H.money(pen.TMA), H.money(pen.CTA)
    return p
end

-- text of the running module: S("key", params function) -> function returning the text
function H.S(key, params)
    return function()
        return L("work_atc.trn." .. T.module .. "." .. key, params and params() or H.base())
    end
end

function H.note(key, params) return L("work_atc.trn.common." .. key, params or H.base()) end

H.LANDED = { landing = true, vacate = true, vacated = true, taxi_in = true, parked = true }

---------------------------------------------------------------- sub-step machinery

local refresh -- forward

local function currentList()
    return T.step and T.subs and T.subs[T.step]
end

local function currentDef()
    local list = currentList()
    return list and list[T.sub]
end

-- tell the server whether the aircraft may fly faster now (a sub-step that only waits)
local function syncFast()
    local def = currentDef()
    local f = def ~= nil and def.fast == true
    if f ~= T.sentFast then
        T.sentFast = f
        triggerServerEvent("atc:trn:fast", resourceRoot, f)
    end
end

local function nextSub()
    T.sub = T.sub + 1
    T.note = nil
    local def = currentDef()
    if def and def.enter then def.enter() end
    syncFast()
    refresh()
end

local function stepLabel(step)
    local steps = T.info.steps or {}
    local n = 0
    for i, st in ipairs(steps) do
        if st == step then n = i end
    end
    return L("work_atc.trn.common.step_header", { code = T.info.code or "?", n = n, total = #steps,
        name = L("work_atc.trn." .. T.module .. ".step_" .. step) })
end

-- Sub-step fields:
--   text      = function -> string
--   next      = a Next button moves on;  check = function, moves on once it holds
--   rect      = function -> highlighted { x, y, w, h }
--   needScope = shown as a note while the scope is not on the screen
--   note      = function -> extra note (when nothing is missing)
--   fast      = the player only watches: the aircraft may fly TRAINING.FAST_SCALE times faster
--   enter     = function, called when the sub-step comes;  leave = function, called when it is done

local function missingNote(def)
    if def.needScope and not H.scopeVisible() then return H.note("note_open_scope") end
end

local function subCard(list, step)
    local def = list[T.sub]
    if not def then return nil end
    local spec = { step = stepLabel(step), title = L("work_atc.trn.common.title", { code = T.info.code or "?" }),
        text = def.text(), note = T.note, noteColor = T.noteColor }

    local missing = missingNote(def)
    if missing then
        spec.note, spec.noteColor = missing, Card.colors.bad
    elseif not spec.note and def.note then
        spec.note, spec.noteColor = def.note(), Card.colors.muted
    end
    if T.fast and not missing then
        local fast = H.note("note_fast", { scale = T.fast })
        spec.note = spec.note and (spec.note .. "\n" .. fast) or fast
        spec.noteColor = spec.noteColor or Card.colors.muted
    end

    if def.next then
        -- the scope and the login window show the cursor themselves, otherwise the card does
        spec.modal = not H.scopeVisible() and not H.loginOpen()
        spec.buttons = { { label = L("work_atc.trn.common.next"), primary = true, disabled = missing ~= nil, fn = function()
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
        rows[#rows + 1] = { title = tostring(item.label), status = H.money(item.amount),
            statusColor = (tonumber(item.amount) or 0) < 0 and Card.colors.bad or Card.colors.good }
    end
    if receipt.total then
        rows[#rows + 1] = { title = L("work_atc.trn.common.receipt_total"), status = H.money(receipt.total),
            statusColor = Card.colors.text }
    end
    return {
        step = stepLabel("done"),
        title = L("work_atc.trn.common.done_title", { code = T.info.code or "?" }),
        text = L("work_atc.trn." .. T.module .. ".done_text", H.base()),
        rows = rows,
        buttons = { { label = L("work_atc.trn.common.finish"), primary = true, fn = H.serverNext } },
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
    local def = currentDef()
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

handle("atc:trn:notify", function(text)
    pcall(function() exports.ui_core:addNotification(L("work_atc.trn.card.title"), tostring(text)) end)
end)

-- the first duty start offers the SCOPE module (TRAINING.OFFER)
handle("atc:trn:offer", function(minutes)
    if T.active then return end
    Card.onSkip = nil
    Card.show({
        title = L("work_atc.trn.card.title"),
        text = L("work_atc.trn.common.offer", { minutes = minutes or 15 }),
        buttons = {
            { label = L("work_atc.trn.common.later"), fn = function()
                Card.hide()
                triggerServerEvent("atc:trn:answer", resourceRoot, false)
            end },
            { label = L("work_atc.trn.common.start"), primary = true, fn = function()
                Card.hide()
                triggerServerEvent("atc:trn:answer", resourceRoot, true)
            end },
        },
        modal = true, noSkip = true,
    })
end)

-- the module list of the training marker
handle("atc:trn:menu", function(list)
    if T.active or type(list) ~= "table" then return end
    Card.onSkip = nil
    local rows = {}
    for _, m in ipairs(list) do
        local status, color
        if not m.unlocked then
            status, color = L("work_atc.trn.menu.locked", { level = m.level or "?" }), Card.colors.bad
        elseif m.done then
            status, color = L("work_atc.trn.menu.completed"), Card.colors.good
        else
            status, color = L("work_atc.trn.menu.available"), Card.colors.muted
        end
        local id = m.id
        rows[#rows + 1] = {
            title = L("work_atc.trn.menu." .. id .. "_name"),
            desc = L("work_atc.trn.menu." .. id .. "_desc", { minutes = m.minutes or 15 }),
            status = status, statusColor = color,
            button = { label = m.done and L("work_atc.trn.menu.again") or L("work_atc.trn.common.start"),
                disabled = not m.unlocked, fn = function()
                    Card.hide()
                    triggerServerEvent("atc:trn:choose", resourceRoot, id)
                end },
        }
    end
    Card.show({
        title = L("work_atc.trn.menu.title"),
        text = L("work_atc.trn.menu.text"),
        rows = rows,
        buttons = { { label = L("work_atc.trn.menu.close"), fn = function() Card.hide() end } },
        modal = true, noSkip = true,
    })
end)

local function toggleCursor() Card.toggleCursor() end

handle("atc:trn:begin", function(info)
    info = type(info) == "table" and info or {}
    local mod = TRN.modules[info.module]
    if not mod then return end
    T.active, T.module, T.step, T.sub = true, info.module, nil, 1
    T.info = info
    T.ac, T.cmds, T.receipt, T.note, T.fast, T.hadOnce = {}, {}, nil, nil, nil, {}
    T.sentFast = false
    T.subs = mod.build(H)
    bindKey(TRAINING.CURSOR_KEY, "down", toggleCursor)
    Card.onSkip = function() triggerServerEvent("atc:trn:quit", resourceRoot) end
end)

handle("atc:trn:step", function(step)
    T.step, T.sub, T.note = step, 1, nil
    if step == "console" then
        -- (again after an early logout: new aircraft come)
        T.ac, T.cmds, T.hadOnce = {}, {}, {}
    end
    local def = currentDef()
    if def and def.enter then def.enter() end
    T.sentFast = false            -- the server forgets it at every step
    syncFast()
    refresh()
end)

handle("atc:trn:info", function(kind, a, b)
    if kind == "aircraft" then
        T.ac = type(a) == "table" and a or {}
        for role, snap in pairs(T.ac) do
            if snap.had then T.hadOnce[role] = true end
        end
        T.fast = tonumber(b)
    elseif kind == "spawn" then
        T.ac[a] = b
        T.cmds[a] = {}
        T.hadOnce[a] = nil
        -- the new aircraft in the middle of the scope
        local mod = TRN.modules[T.module]
        if mod and mod.onSpawn then mod.onSpawn(H, a) end
    elseif kind == "cmd" then
        T.cmds[a] = T.cmds[a] or {}
        T.cmds[a][b] = true
    elseif kind == "receipt" then
        T.receipt = a
    end
    refresh()
end)

handle("atc:trn:end", function()
    T.active, T.step, T.module, T.subs = false, nil, nil, nil
    unbindKey(TRAINING.CURSOR_KEY, "down", toggleCursor)
    Card.hide()
end)

function TRN.isActive() return T.active end

-- Texts load only once the player is loaded (v_accounts loading gate).
local textsLoaded = false
local function loadTexts()
    if textsLoaded then return end
    textsLoaded = true
    pcall(function() exports.v_accounts:resourceReady() end)
end
addEvent("onClientLoadingStarted", true)
addEventHandler("onClientLoadingStarted", root, loadTexts)
addEventHandler("onClientResourceStart", resourceRoot, function()
    if getElementData(localPlayer, "loaded") then loadTexts() end
end)
