if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Spectator menu + label (server: core/spectate.lua). Scrolling the list switches the camera at
-- once (ui_inac:tempMenuHover). Backspace closes the menu, Space opens it again.

local uicore = exports.ui_core
local screenW, screenH = guiGetScreenSize()
local SCALE = (uicore:ui(1000) or 1000) / 1000
local function S(v) return v * SCALE end

JobSpectate = { active = false, targets = {}, current = false, jobName = nil }

local rendering = false
local renderLabel
local lastSwitch = 0

local function setRendering(on)
    if on == rendering then return end
    rendering = on
    if on then addEventHandler("onClientRender", root, renderLabel) else removeEventHandler("onClientRender", root, renderLabel) end
end

local function currentEntry()
    for _, t in ipairs(JobSpectate.targets) do
        if t.player == JobSpectate.current then return t end
    end
end

local function menuItems()
    local items = {}
    for i, t in ipairs(JobSpectate.targets) do
        items[#items + 1] = {
            label = t.name, desc = t.info or nil, value = { "spec", i },
            checked = t.player == JobSpectate.current, closeOnSelect = false,
        }
    end
    if #items == 0 then
        items[1] = { label = L("v_jobmanager.spectate.nobody_left"), value = { "none" }, closeOnSelect = false }
    end
    items[#items + 1] = { label = L("v_jobmanager.jobmenu.leave_job"), items = JobUi.leaveItems(),
        title = L.upper(L("v_jobmanager.jobmenu.leave_job_question")) }
    return items
end

function JobSpectate.openMenu()
    if not JobSpectate.active then return end
    JobUi.openMenu("spectate", L("v_jobmanager.spectate.title"), menuItems())
end

local function pick(index)
    local t = JobSpectate.targets[index]
    if not t or t.player == JobSpectate.current or not isElement(t.player) then return end
    -- the server switches the camera; a short gap keeps fast scrolling from flooding it
    local now = getTickCount()
    if now - lastSwitch < 120 then return end
    lastSwitch = now
    JobSpectate.current = t.player
    triggerServerEvent("jobmanager:spectateSet", resourceRoot, t.player)
end

JobUi.on("spectate", {
    hover = function(value)
        if type(value) == "table" and value[1] == "spec" then pick(value[2]) end
    end,
    select = function(value)
        if value[1] == "spec" then pick(value[2])
        elseif value[1] == "leave" then JobUi.leave() end
    end,
})

local function samePlayers(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i].player ~= b[i].player then return false end end
    return true
end

addEvent("jobmanager:spectate", true)
addEventHandler("jobmanager:spectate", resourceRoot, function(data)
    if type(data) ~= "table" or not data.active then
        if JobSpectate.active then
            JobSpectate.active, JobSpectate.targets, JobSpectate.current = false, {}, false
            JobUi.closeMenu("spectate")
            setRendering(false)
        end
        return
    end
    local wasActive = JobSpectate.active
    local changed = not samePlayers(JobSpectate.targets, data.targets or {})
    JobSpectate.active = true
    JobSpectate.targets = data.targets or {}
    JobSpectate.current = data.current or false
    JobSpectate.jobName = data.jobName
    setRendering(true)
    if not wasActive then
        JobSpectate.openMenu()
    elseif changed and JobUi.isMenuOpen("spectate") then
        JobSpectate.openMenu()
    end
end)

-- a spectator is invisible and takes no damage
addEventHandler("onClientPlayerDamage", localPlayer, function()
    if JobSpectate.active then cancelEvent() end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey(JOBS_CONFIG.KEYS.spectate, "down", function()
        if JobSpectate.active and not JobUi.isMenuOpen() and not JobUi.inputBlocked() then JobSpectate.openMenu() end
    end)
end)

renderLabel = function()
    if not JobSpectate.active then return setRendering(false) end
    if getElementData(localPlayer, "scoreboardOpen") then return end
    local entry = currentEntry()
    local y = S(70)
    dxDrawText(L.upper(L("v_jobmanager.spectate.title")), 0, y, screenW, y + S(24),
        tocolor(255, 255, 255, 200), S(1.1), "default-bold", "center", "top")
    if entry then
        dxDrawText(entry.name, 0, y + S(22), screenW, y + S(56),
            tocolor(255, 255, 255, 255), S(2.0), "default-bold", "center", "top")
        if entry.info then
            dxDrawText(L.resolve(entry.info), 0, y + S(56), screenW, y + S(80),
                tocolor(200, 205, 210, 230), S(1.0), "default-bold", "center", "top")
        end
    else
        dxDrawText(L("v_jobmanager.spectate.nobody_left"), 0, y + S(22), screenW, y + S(56),
            tocolor(200, 205, 210, 230), S(1.2), "default-bold", "center", "top")
    end
    if not JobUi.isMenuOpen() then
        dxDrawText(L("v_jobmanager.spectate.hint", { key = JOBS_CONFIG.KEYS.spectate:upper(), menu = JOBS_CONFIG.KEYS.jobMenu:upper() }),
            0, screenH - S(60), screenW, screenH - S(36), tocolor(255, 255, 255, 190), S(1.0), "default-bold", "center", "top")
    end
end
