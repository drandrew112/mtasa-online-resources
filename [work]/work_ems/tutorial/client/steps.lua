if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Client side of the EMS tutorial: the texts of every step and the sub-steps the client drives
-- itself (tablet explanation through med_erm's tutorial mode, the equipment through med_bag's
-- hand data and contents window, examination panel highlights through medsys' panel layout).
-- The server owns the session (server/session.lua).

local T = {
    active = false,
    step = nil,          -- server step
    sub = 1,             -- sub-step of the tablet / equipment / examine / treat steps
    vehicle = nil,
    equipment = false,   -- med_bag runs: the equipment is taught and checked
    world = { stretcher = { state = "none" } },   -- polled by the server (worldInfo)
    done = {},           -- treatments done on the patient (server)
    games = {}, running = false, practice = false,
    note = nil, noteColor = nil,
}

local STEP_LABELS, ITEM_STATE = {}, {}
local function buildLabels()
STEP_LABELS = {
    tablet = L("work_ems.steps.step_1_8_ems_tablet"),
    equipment = L("work_ems.steps.step_2_8_equipment"),
    examine = L("work_ems.steps.step_3_8_examination"),
    treat = L("work_ems.steps.step_4_8_treatment"),
    stretcher = L("work_ems.steps.step_5_8_stretcher"),
    transfer = L("work_ems.steps.step_6_8_transport"),
    handover = L("work_ems.steps.step_6_8_hospital_handover"),
    restock = L("work_ems.steps.step_7_8_restock"),
    done = L("work_ems.steps.step_8_8_finished"),
}

ITEM_STATE = {
    stowed = L("work_ems.steps.in_ambulance"), carried = L("work_ems.steps.in_your_hands"), ground = L("work_ems.steps.on_ground"),
    stretcher = L("work_ems.steps.on_stretcher"), none = "-",
}
end

local function isRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function tablet(fn, ...)
    if isRunning("med_erm") then return exports.med_erm[fn](exports.med_erm, ...) end
end

local function tabletOpen()
    return isRunning("med_erm") and exports.med_erm:isTabletTutorial() and T.tabletOpen == true
end

local function panelOpen()
    return isRunning("medsys") and exports.medsys:isExaminationOpen() == true
end

local function panelLayout()
    return isRunning("medsys") and exports.medsys:getExaminationPanelLayout() or nil
end

local function panelRect(key)
    local layout = panelLayout()
    return layout and layout[key] or nil
end

local function actionRect(action)
    local layout = panelLayout()
    for _, b in ipairs(layout and layout.buttonList or {}) do
        if b.action == action then return { b.x, b.y, b.w, b.h } end
    end
end

-- The medicine card while the medication grid is open, otherwise the Medication button
local function drugRect(id)
    local layout = panelLayout()
    for _, card in ipairs(layout and layout.drugCards or {}) do
        if card.id == id then return { card.x, card.y, card.w, card.h } end
    end
    return actionRect("medication")
end

-- med_bag: what the player carries ({ bag = model, monitor = model } or nil)
local function carrying(kind)
    local hands = getElementData(localPlayer, "medbag.hands")
    return type(hands) == "table" and hands[kind] ~= nil
end

local function itemState(kind)
    local items = T.world.items
    return items and items[kind] and items[kind].state or "none"
end

local function itemsLine()
    if not T.world.items then return nil end
    return L("work_ems.steps.medical_bag_monitor", { item_state = ITEM_STATE[itemState("bag")] or "-", item_state2 = ITEM_STATE[itemState("monitor")] or "-" })
end

local function noEquipment() return not T.equipment end

local refresh -- forward
local STEP_SUBS -- step -> its sub-step list (the steps the client drives)

local function currentList()
    return T.step and STEP_SUBS and STEP_SUBS[T.step]
end

-- Moves to the next sub-step, past the ones that do not apply (skip)
local function nextSub()
    local list = currentList()
    T.sub = T.sub + 1
    while list and list[T.sub] and list[T.sub].skip and list[T.sub].skip() do T.sub = T.sub + 1 end
    T.note = nil
    refresh()
end

local function firstSub()
    local list = currentList()
    T.sub = 1
    while list and list[T.sub] and list[T.sub].skip and list[T.sub].skip() do T.sub = T.sub + 1 end
end

local function serverNext()
    triggerServerEvent("ems:tut:next", resourceRoot, T.step)
end

---------------------------------------------------------------- step 1: tablet

local TABLET_KEY = "J"

local TABLET, EQUIPMENT, EXAMINE, TREAT
local function buildSubs()
TABLET = {
    { text = L("work_ems.steps.you_are_sitting_in_your_ambulance", { tablet_key = TABLET_KEY }),
      wait = "tablet:open" },
    { text = L("work_ems.steps.this_is_sign_in_screen_pick"),
      wait = "tablet:signIn", tablet = true },
    { text = L("work_ems.steps.you_are_signed_in_header_shows"),
      next = true, tablet = true,
      leave = function()
          tablet("setTabletTutorialCase", TUTORIAL.CASE)
      end },
    { text = L("work_ems.steps.case_was_assigned_to_you_that"),
      wait = "tablet:page:case", tablet = true },
    { text = L("work_ems.steps.active_case_page_priority_p1_is"),
      wait = "tablet:caseAction:start", tablet = true },
    { text = L("work_ems.steps.rest_is_automatic_your_status_becomes"),
      next = true, tablet = true,
      leave = function()
          tablet("setTabletTutorialUnit", { status = "onscene", reachedScene = true, responding = false })
          tablet("addTabletTutorialMessage", L("work_ems.steps.caller_says_patient_is_waiting_right"), "case")
      end },
    { text = L("work_ems.steps.you_got_message_messages_has_two"),
      wait = "tablet:page:messages", tablet = true },
    { text = L("work_ems.steps.here_you_read_and_send_messages"),
      next = true, tablet = true },
    { text = L("work_ems.steps.you_arrived_at_scene_so_your", { tablet_key = TABLET_KEY }),
      wait = "tablet:close",
      leave = function() serverNext() end },
}

---------------------------------------------------------------- step 2: equipment (med_bag)

EQUIPMENT = {
    { text = L("work_ems.steps.your_patient_is_standing_next_to"),
      wait = "bag:contents" },
    { text = L("work_ems.steps.contents_of_medical_bag_window_on"),
      next = true },
    { text = L("work_ems.steps.now_take_equipment_in_same_menu"),
      check = function() return carrying("bag") and carrying("monitor") end },
    { text = L("work_ems.steps.panel_on_right_shows_what_you"),
      wait = "panel:open",
      leave = function() serverNext() end },
}

---------------------------------------------------------------- step 3: examination

EXAMINE = {
    { text = L("work_ems.steps.look_at_patient_and_press_x"),
      check = panelOpen },
    { text = L("work_ems.steps.this_is_examination_panel_top_bar"),
      next = true, panel = "consciousness" },
    { text = L("work_ems.steps.these_chips_show_equipment_within_reach"),
      next = true, panel = "equipment", skip = noEquipment },
    { text = L("work_ems.steps.without_monitor_you_only_see_what"),
      next = true, panel = "vitals" },
    { text = L("work_ems.steps.iv_access_airway_and_pain_most"),
      next = true, panel = "status" },
    { text = L("work_ems.steps.injuries_their_severity_and_whether_they"),
      next = true, panel = "injuries" },
    { text = L("work_ems.steps.treatments_in_rows_grey_button_cannot"),
      next = true, panel = "buttons" },
    { text = L("work_ems.steps.blood_pressure_oxygen_level_spo2_and"),
      check = function() return panelRect("lifepak") ~= nil end, panel = "monitorButton" },
    { text = L("work_ems.steps.lifepak_15_monitor_top_heart_rate"),
      next = true, panel = "lifepakScreen" },
    { text = L("work_ems.steps.defibrillator_charge_200_j_then_shock"),
      next = true, panel = "lifepakKeypad",
      leave = function() serverNext() end },
}

---------------------------------------------------------------- step 4: treatment

local function treated(key) return function() return T.done[key] == true end end

TREAT = {
    { text = L("work_ems.steps.treat_injuries_start_with_burn_press"),
      check = treated("bandage"), panel = "action:bandage" },
    { text = L("work_ems.steps.burn_is_dressed_now_fracture_press"),
      check = treated("splint"), panel = "action:splint" },
    { text = L("work_ems.steps.fracture_still_hurts_lot_pain_needs"),
      check = treated("iv"), panel = "action:iv" },
    { text = L("work_ems.steps.now_press_medication_and_choose_fentanyl"),
      check = treated("painkiller"), panel = "drug:" .. TUTORIAL.PAINKILLER },
    { text = L("work_ems.steps.last_press_o2_mask_o2_chip"),
      check = treated("oxygen"), panel = "action:oxygen" },
    { text = L("work_ems.steps.well_done_burn_is_dressed_leg"),
      next = true,
      leave = function() serverNext() end },
}

STEP_SUBS = { tablet = TABLET, equipment = EQUIPMENT, examine = EXAMINE, treat = TREAT }
end

---------------------------------------------------------------- card builders

local function subRect(panel)
    if not panel then return nil end
    local action = panel:match("^action:(.+)$")
    if action then return actionRect(action) end
    local drug = panel:match("^drug:(.+)$")
    if drug then return drugRect(drug) end
    return panelRect(panel)
end

local function subCard(list, step)
    local def = list[T.sub]
    if not def then return nil end
    local spec = { step = STEP_LABELS[step], title = def.title, text = def.text, note = T.note, noteColor = T.noteColor }
    -- the Lifepak window opens left of the panel, where the card would cover it
    if (step == "examine" or step == "treat") and panelOpen() then spec.side = "right" end

    local blocked
    if def.tablet and not tabletOpen() then
        blocked = L("work_ems.steps.press_to_open_tablet_again", { tablet_key = TABLET_KEY })
    elseif def.panel and not panelOpen() then
        blocked = L("work_ems.steps.open_examination_panel_again_look_at")
    end
    if blocked then
        spec.note, spec.noteColor = blocked, Card.colors.bad
    end

    if def.next then
        -- the tablet and the panel show the cursor themselves, otherwise the card does
        spec.modal = not tabletOpen() and not panelOpen()
        spec.buttons = { { label = L("work_ems.steps.next"), primary = true, disabled = blocked ~= nil, fn = function()
            if def.leave then def.leave() end
            nextSub()
        end } }
    end

    Card.highlight(not blocked and subRect(def.panel) or nil)
    return spec
end

local function gamesCard()
    local rows = {}
    for _, g in ipairs(TUTORIAL.GAMES) do
        local stats = T.games[g.id]
        local status, color
        if stats then
            status = L("work_ems.steps.successful", { success = stats.success or 0, played = stats.played or 0 })
            color = (stats.success or 0) > 0 and Card.colors.good or Card.colors.muted
        end
        rows[#rows + 1] = {
            title = g.label, desc = g.desc, status = status, statusColor = color,
            button = { label = L("work_ems.steps.practice"), disabled = T.running ~= false, fn = function()
                T.note = nil
                triggerServerEvent("ems:tut:game", resourceRoot, g.id)
            end },
        }
    end
    return {
        step = STEP_LABELS.done,
        title = L("work_ems.steps.practice_minigames"),
        text = L("work_ems.steps.every_treatment_of_panel_is_minigame"),
        note = T.note, noteColor = T.noteColor,
        rows = rows,
        buttons = { { label = L("common.back"), primary = true, disabled = T.running ~= false, fn = function()
            T.practice, T.note = false, nil
            refresh()
        end } },
        modal = true, noSkip = true,
    }
end

-- The item that is still out of the ambulance, in words ("the medical bag" / "the monitor" / both)
local function itemsOutside()
    local out = {}
    if itemState("bag") ~= "stowed" then out[#out + 1] = L("work_ems.steps.medical_bag") end
    if itemState("monitor") ~= "stowed" then out[#out + 1] = L("work_ems.steps.monitor") end
    return #out > 0 and table.concat(out, " and ") or nil
end

local function stretcherCard()
    local st = T.world.stretcher
    local text
    if st.loaded and st.state == "stowed" then
        text = L("work_ems.steps.patient_is_in_ambulance_but_is", { items_outside = (itemsOutside() or "something") })
    elseif st.patient and st.state ~= "stowed" then
        text = L("work_ems.steps.patient_is_on_stretcher_now_equipment")
    elseif st.state == "ground" or st.state == "pushing" then
        text = L("work_ems.steps.stretcher_is_out_bring_it_next")
    elseif st.state == "moving" then
        text = T.lastStretcherText or "..."
    else
        text = L("work_ems.steps.your_patient_is_treated_and_goes")
    end
    if not T.equipment and st.patient and st.state ~= "stowed" then
        text = L("work_ems.steps.patient_is_on_stretcher_choose_push")
    end
    T.lastStretcherText = text
    return { step = STEP_LABELS.stretcher, title = L("work_ems.steps.load_patient"), text = text, note = itemsLine() }
end

local function handoverCard()
    local st = T.world.stretcher
    local text
    if st.patient and st.state ~= "stowed" then
        text = L("work_ems.steps.push_stretcher_into_blue_patient_handover")
    elseif st.state == "moving" then
        text = T.lastHandoverText or "..."
    else
        text = L("work_ems.steps.you_arrived_at_hospital_on_real")
        if T.equipment then
            text = L("work_ems.steps.equipment_that_went_in_on_stretcher", { text = text })
        end
    end
    T.lastHandoverText = text
    return { step = STEP_LABELS.handover, title = L("work_ems.steps.hand_over_patient"), text = text, note = itemsLine() }
end

local function restockCard()
    local st = T.world.stretcher
    local text
    if st.state ~= "stowed" then
        text = L("work_ems.steps.patient_is_handed_over_equipment_stays")
    elseif itemsOutside() then
        text = L("work_ems.steps.stretcher_is_in_but_is_still", { items_outside = itemsOutside() })
    else
        text = L("work_ems.steps.everything_is_back_in_ambulance_you")
    end
    return { step = STEP_LABELS.restock, title = L("work_ems.steps.restock_bag"), text = text, note = itemsLine() }
end

local function doneCard()
    local lines = {
        L("work_ems.steps.go_on_duty_take_ambulance_at", { tablet_key = TABLET_KEY }),
        L("work_ems.steps.cases_come_from_dispatchers_or_automatic"),
    }
    if T.equipment then
        lines[#lines + 1] = L("work_ems.steps.take_bag_and_monitor_at_side")
    end
    lines[#lines + 1] = L("work_ems.steps.examine_patient_x_1_attach_monitor")
    lines[#lines + 1] = L("work_ems.steps.load_patient_with_stretcher_park_in")
    if T.equipment then
        lines[#lines + 1] = L("work_ems.steps.load_empty_stretcher_and_restock_bag")
    end
    return {
        step = STEP_LABELS.done,
        title = L("work_ems.steps.tutorial_complete"),
        text = L("work_ems.steps.you_know_basics_now_you_can", { lines = table.concat(lines, "\n"), command = TUTORIAL.COMMAND }),
        note = T.note, noteColor = T.noteColor,
        buttons = {
            { label = L("work_ems.steps.practice_minigames_2"), fn = function()
                T.practice, T.note = true, nil
                refresh()
            end },
            { label = L("work_ems.steps.finish"), primary = true, fn = serverNext },
        },
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
    elseif T.step == "stretcher" then
        spec = stretcherCard()
    elseif T.step == "transfer" then
        spec = { step = STEP_LABELS.transfer, title = L("work_ems.steps.off_to_hospital"),
                 text = L("work_ems.steps.patient_is_in_ambulance_driving_to"), noSkip = true }
    elseif T.step == "handover" then
        spec = handoverCard()
    elseif T.step == "restock" then
        spec = restockCard()
    elseif T.step == "done" then
        spec = T.practice and gamesCard() or doneCard()
    end
    if spec then Card.show(spec) else Card.hide() end
    Card.setHidden(T.running ~= false and T.running ~= nil)
end

-- Something happened that a "wait" sub-step may be waiting for
local function signal(name)
    if not T.active then return end
    local list = currentList()
    local def = list and list[T.sub]
    if def and def.wait == name then
        if def.leave then def.leave() end
        return nextSub()
    end
    refresh()
end

-- The panel / tablet / hands state changes the notes and highlights: keep the card current, and move
-- on from a "check" sub-step once its condition holds (also when it was done before the step came)
setTimer(function()
    if not T.active then return end
    local list = currentList()
    if not list then return end
    local def = list[T.sub]
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

handle("ems:tut:offer", function()
    if T.active then return end
    Card.onSkip = nil
    Card.show({
        title = L("work_ems.card.ems_tutorial"),
        text = L("work_ems.steps.is_this_your_first_shift_tutorial", { command = TUTORIAL.COMMAND }),
        buttons = {
            { label = L("work_ems.steps.skip"), fn = function()
                Card.hide()
                triggerServerEvent("ems:tut:answer", resourceRoot, false)
            end },
            { label = L("work_ems.steps.start_tutorial"), primary = true, fn = function()
                Card.hide()
                triggerServerEvent("ems:tut:answer", resourceRoot, true)
            end },
        },
        modal = true, noSkip = true,
    })
end)

local function toggleCursor() Card.toggleCursor() end

handle("ems:tut:begin", function(vehicle, equipment)
    T.active, T.vehicle, T.step, T.sub = true, vehicle, nil, 1
    T.equipment = equipment == true
    T.games, T.running, T.practice, T.note, T.tabletOpen = {}, false, false, nil, false
    T.world, T.done = { stretcher = { state = "none" } }, {}
    tablet("startTabletTutorial")
    bindKey(TUTORIAL.CURSOR_KEY, "down", toggleCursor)
    Card.onSkip = function() triggerServerEvent("ems:tut:skip", resourceRoot) end
end)

handle("ems:tut:step", function(step)
    T.step, T.note = step, nil
    if step == "examine" then T.tabletOpen, T.done = false, {} end
    firstSub()
    refresh()
end)

local TREATMENT_LABELS = {}
local function buildTreatmentLabels()
TREATMENT_LABELS = {
    bandage = L("work_ems.steps.bandage_did_not_hold"), splint = L("work_ems.steps.splint_did_not_hold"), iv = L("work_ems.steps.iv_access_failed"),
    painkiller = L("work_ems.steps.medicine_was_not_given"), oxygen = L("work_ems.steps.oxygen_mask_was_not_changed"),
}
end

handle("ems:tut:info", function(kind, data)
    if kind == "treatment" then
        T.done = data.done or T.done
        if data.success then
            T.note = nil
        elseif TREATMENT_LABELS[data.key] then
            T.note, T.noteColor = L("work_ems.steps.panel_is_open_again_try_once", { key = TREATMENT_LABELS[data.key] }), Card.colors.bad
        end
        refresh()
    elseif kind == "world" then
        T.world = data
        refresh()
    elseif kind == "gameError" then
        T.note, T.noteColor = tostring(data), Card.colors.bad
        refresh()
    end
end)

handle("ems:tut:games", function(games, running, lastId, lastSuccess)
    T.games, T.running = games or {}, running or false
    if lastId then
        local label = lastId
        for _, g in ipairs(TUTORIAL.GAMES) do if g.id == lastId then label = g.label end end
        if lastSuccess then
            T.note, T.noteColor = L("work_ems.steps.success", { label = label }), Card.colors.good
        else
            T.note, T.noteColor = L("work_ems.steps.not_this_time_try_again", { label = label }), Card.colors.bad
        end
    end
    refresh()
end)

handle("ems:tut:end", function()
    T.active, T.step = false, nil
    unbindKey(TUTORIAL.CURSOR_KEY, "down", toggleCursor)
    tablet("stopTabletTutorial")
    Card.hide()
end)

---------------------------------------------------------------- other resources

addEvent("onClientErmTabletTutorial")
addEventHandler("onClientErmTabletTutorial", localPlayer, function(action, arg)
    if action == "open" then
        T.tabletOpen = true
        signal("tablet:open")
    elseif action == "close" then
        T.tabletOpen = false
        signal("tablet:close")
    elseif action == "page" then
        signal("tablet:page:" .. tostring(arg))
    elseif action == "caseAction" then
        signal("tablet:caseAction:" .. tostring(arg))
    else
        signal("tablet:" .. tostring(action))
    end
end)

addEvent("onClientMedicPanel")
addEventHandler("onClientMedicPanel", localPlayer, function(open)
    if open then signal("panel:open") else refresh() end
end)

-- med_bag opened its contents window (Check contents in the side-door menu)
addEvent("bag:contents", true)
addEventHandler("bag:contents", root, function()
    signal("bag:contents")
end)

-- tutorial patients cannot be hurt
addEventHandler("onClientPedDamage", root, function()
    if getElementData(source, "ems.tutorialPed") then cancelEvent() end
end)

-- med_erm restarted: its tutorial mode is gone, switch it on again
addEventHandler("onClientResourceStart", root, function(res)
    if T.active and getResourceName(res) == "med_erm" then tablet("startTabletTutorial") end
end)

-- Texts load only once the player is loaded (v_accounts loading gate).
local textsLoaded = false
local function loadTexts()
    if textsLoaded then return end
    textsLoaded = true
    buildLabels()
    buildSubs()
    buildTreatmentLabels()
    exports.v_accounts:resourceReady()
end
addEvent("onClientLoadingStarted", true)
addEventHandler("onClientLoadingStarted", root, loadTexts)
addEventHandler("onClientResourceStart", resourceRoot, function()
    if getElementData(localPlayer, "loaded") then loadTexts() end
end)
