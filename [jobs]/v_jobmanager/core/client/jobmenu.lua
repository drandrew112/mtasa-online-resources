if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- The job menu during a match (F2), the leave confirmation (/leavejob, ui_pause) and the
-- server notifications. Every temp menu of this resource (also the spectator list in
-- spectate.lua) goes through JobUi.openMenu, so they never fight over ui_inac's one temp menu.

local uicore = exports.ui_core

JobUi = {
    match = nil,        -- { id, type, name, test } while in a running match
    racing = false,     -- in a race vehicle and not finished (mode_race/client/recover.lua)
    menuId = nil, menuKind = nil,
    handlers = {},      -- kind -> { select = fn(value, path), hover = fn(value), close = fn() }
}

function JobUi.inputBlocked()
    return isChatBoxInputActive() or isConsoleActive() or isMTAWindowActive()
        or getElementData(localPlayer, "textInputOpen") or getElementData(localPlayer, "paused")
        or getElementData(localPlayer, "phoneOpen")
end

function JobUi.openMenu(kind, title, items)
    if JobUi.menuId then exports.ui_inac:closeTempMenu() end
    JobUi.menuKind = kind
    JobUi.menuId = exports.ui_inac:createTempMenu({ title = title, items = items })
    if not JobUi.menuId then JobUi.menuKind = nil end
    return JobUi.menuId
end

function JobUi.closeMenu(kind)
    if JobUi.menuId and (not kind or JobUi.menuKind == kind) then exports.ui_inac:closeTempMenu() end
end

function JobUi.isMenuOpen(kind)
    return JobUi.menuId ~= nil and (not kind or JobUi.menuKind == kind)
end

function JobUi.on(kind, handlers)
    JobUi.handlers[kind] = handlers
end

addEventHandler("ui_inac:tempMenuSelect", root, function(rootId, value, path)
    if rootId ~= JobUi.menuId or type(value) ~= "table" then return end
    local h = JobUi.handlers[JobUi.menuKind]
    if h and h.select then h.select(value, path) end
end)

addEventHandler("ui_inac:tempMenuHover", root, function(rootId, value, path)
    if rootId ~= JobUi.menuId then return end
    local h = JobUi.handlers[JobUi.menuKind]
    if h and h.hover then h.hover(value, path) end
end)

addEventHandler("ui_inac:tempMenuClose", root, function(rootId)
    if rootId ~= JobUi.menuId then return end
    local h = JobUi.handlers[JobUi.menuKind]
    JobUi.menuId, JobUi.menuKind = nil, nil
    if h and h.close then h.close() end
end)

--------------------------------------------------------------------------------
-- notifications
--------------------------------------------------------------------------------

addEvent("jobmanager:notify", true)
addEventHandler("jobmanager:notify", resourceRoot, function(text)
    uicore:addNotification(L("v_jobmanager.jobmenu.jobs"), text)
end)

--------------------------------------------------------------------------------
-- leaving
--------------------------------------------------------------------------------

-- the "Leave job" submenu rows (job menu, spectator menu)
function JobUi.leaveItems()
    return {
        { label = L("common.cancel"), value = { "leaveCancel" } },
        { label = L("v_jobmanager.jobmenu.yes_leave"), value = { "leave" }, desc = L("v_jobmanager.jobmenu.leave_desc") },
    }
end

function JobUi.leave()
    triggerServerEvent("jobmanager:leaveJob", resourceRoot, true)
end

local function openConfirm()
    if not JobUi.match then return end
    JobUi.openMenu("confirm", L("v_jobmanager.jobmenu.leave_job_question"), JobUi.leaveItems())
end

JobUi.on("confirm", {
    select = function(value)
        if value[1] == "leave" then JobUi.leave() end
    end,
})

addEvent("jobmanager:confirmLeave", true)
addEventHandler("jobmanager:confirmLeave", resourceRoot, openConfirm)

--------------------------------------------------------------------------------
-- job menu (F2)
--------------------------------------------------------------------------------

local TYPE_KEY = { race = "common.race", deathmatch = "common.deathmatch", mission = "v_jobmanager.jobmenu.mission" }

local function openJobMenu()
    local match = JobUi.match
    if not match then return end
    local items = {
        { label = L(TYPE_KEY[match.type] or "common.job"), value = { "none" }, closeOnSelect = false,
          desc = L("v_jobmanager.jobmenu.leave_hint") },
    }
    if match.type == "race" and JobUi.racing then
        items[#items + 1] = { label = L("v_jobmanager.jobmenu.reset_to_checkpoint"), value = { "reset" },
            desc = L("v_jobmanager.jobmenu.reset_desc") }
    end
    if JobSpectate and JobSpectate.active then
        items[#items + 1] = { label = L("v_jobmanager.jobmenu.spectate_players"), value = { "spectate" } }
    end
    if JobMission and JobMission.active then
        items[#items + 1] = { label = L("v_jobmanager.jobmenu.objective"), value = { "none" }, closeOnSelect = false,
            desc = JobMission.objectiveText() }
    end
    items[#items + 1] = { label = match.test and L("v_jobmanager.jobmenu.stop_test") or L("v_jobmanager.jobmenu.leave_job"),
        items = JobUi.leaveItems(), title = L.upper(L("v_jobmanager.jobmenu.leave_job_question")) }
    JobUi.openMenu("job", L.upper(match.name or L("common.job")), items)
end

JobUi.on("job", {
    select = function(value)
        local action = value[1]
        if action == "reset" then
            triggerServerEvent("jobmanager:raceRecover", resourceRoot, "manual")
        elseif action == "spectate" then
            if JobSpectate then JobSpectate.openMenu() end
        elseif action == "leave" then
            JobUi.leave()
        end
    end,
})

local function jobMenuKey()
    if not JobUi.match or JobUi.inputBlocked() then return end
    if getElementData(localPlayer, "scoreboardOpen") then return end
    if JobUi.isMenuOpen("job") then JobUi.closeMenu("job") return end
    openJobMenu()
end

--------------------------------------------------------------------------------
-- match state
--------------------------------------------------------------------------------

local function matchOver()
    JobUi.match, JobUi.racing = nil, false
    JobUi.closeMenu()
end

addEvent("jobmanager:matchStarted", true)
addEventHandler("jobmanager:matchStarted", resourceRoot, function(_, info)
    JobUi.match = type(info) == "table" and info or nil
end)

addEvent("jobmanager:matchEnded", true)
addEventHandler("jobmanager:matchEnded", resourceRoot, matchOver)

addEvent("jobmanager:matchLeft", true)
addEventHandler("jobmanager:matchLeft", resourceRoot, matchOver)

-- end without a scoreboard (creator tests, quiet script missions)
addEvent("jobmanager:matchQuietEnd", true)
addEventHandler("jobmanager:matchQuietEnd", resourceRoot, function(reason, test)
    matchOver()
    if not test and reason then uicore:addNotification(L("v_jobmanager.jobmenu.jobs"), reason) end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey(JOBS_CONFIG.KEYS.jobMenu, "down", jobMenuKey)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if JobUi.menuId then exports.ui_inac:closeTempMenu() end
end)

--------------------------------------------------------------------------------
-- client exports (ui_pause)
--------------------------------------------------------------------------------

function jobmanagerInMatch()
    return JobUi.match ~= nil
end

-- confirmed = true leaves at once, otherwise the confirmation menu opens
function jobmanagerLeaveJob(confirmed)
    if not JobUi.match then return false end
    if confirmed == true then JobUi.leave() else openConfirm() end
    return true
end
