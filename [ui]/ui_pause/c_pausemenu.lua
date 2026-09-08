-- GTA V style pause menu ("FreeV").
--
-- Opens with P or BACKSPACE. Controls: ARROWS navigate, ENTER confirm,
-- BACKSPACE go back / close. The ESC key is never used by this resource.
-- The menu is a centred box occupying at most 80% of the screen.
--
--  * MAP      - live world-map preview, ENTER opens the full-screen bigmap
--  * JOBS     - Quick Job / Join Lobby / Games: Race / Games: Deathmatch
--  * SETTINGS - category column + settings column (Display > Show 3D Blips)

local uicore = exports.ui_core
local screenW, screenH = guiGetScreenSize()

local SCALE = (uicore:ui(1000) or 1000) / 1000
local function S(v)
    return v * SCALE
end

-- The menu is a centred box at most 80% of the screen.
local MENU_FRACTION = 0.8

local ROW_H  = S(26)
local HEAD_H = S(22)

local OPEN_KEYS = { p = true, backspace = false }

local C = {
    wash       = tocolor(0, 0, 0, 120),
    header     = tocolor(0, 0, 0, 205),
    tabSel     = tocolor(243, 243, 243, 255),
    tabSelTxt  = tocolor(10, 10, 10, 255),
    tab        = tocolor(36, 34, 30, 235),
    tabTxt     = tocolor(196, 198, 201, 255),
    colHead    = tocolor(0, 113, 184, 255),
    colHeadTxt = tocolor(255, 255, 255, 255),
    row        = tocolor(0, 0, 0, 140),
    rowSep     = tocolor(255, 255, 255, 18),
    rowSel     = tocolor(243, 243, 243, 245),
    rowSelTxt  = tocolor(12, 12, 12, 255),
    txt        = tocolor(235, 235, 235, 255),
    txtDim     = tocolor(152, 156, 161, 255),
    value      = tocolor(188, 192, 197, 255),
    infobar    = tocolor(0, 0, 0, 200),
    accent     = tocolor(0, 130, 205, 255),
}

local TABS = { "MAP", "JOBS", "SETTINGS" }

local pauseMenuOpen = false
local pauseMapOpen  = false
local focus         = "tabs" -- "tabs" | "content"
local selectedTab   = 1

-- JOBS tab: a small 2-level drill-down.
--   view = "root" | "joinlobby" | "race" | "deathmatch"
local JOBS_ROOT = {
    { id = "quick",   label = "Quick Job",         desc = "Join a random open lobby, or start a new one with a random game." },
    { id = "lobbies", label = "Join Lobby",        desc = "Browse every open lobby: game, mode and host." },
    { id = "race",    label = "Games: Race",       desc = "Browse every Race job." },
    { id = "dm",      label = "Games: Deathmatch", desc = "Browse every Deathmatch job." },
    { id = "arenawar",label = "Join Arena War",    desc = "Join an Arena War minigame." }
}
local jobsMenu     = { view = "root", rootSel = 1, listSel = 1 }
local jobRefreshAt = 0

local settingsCat   = nil -- nil = category column, otherwise index into SETTINGS_TREE
local settingsSel   = 1

local FONT = { small = "default", row = "default", rowB = "default-bold", head = "default-bold", logo = "pricedown", name = "default-bold" }

--------------------------------------------------------------------------------
-- resource availability helpers
--------------------------------------------------------------------------------

local function radarAvailable()
    local res = getResourceFromName("v_radar")
    return res and getResourceState(res) == "running"
end

local function drawdistanceAvailable()
    local res = getResourceFromName("drawdistance")
    return res and getResourceState(res) == "running"
end

local function jobsAvailable()
    local res = getResourceFromName("v_jobmanager")
    return res and getResourceState(res) == "running"
end

local function getJobList()
    if not jobsAvailable() then return {} end
    return exports.v_jobmanager:jobmanagerGetJobs() or {}
end

local function getLobbyList()
    if not jobsAvailable() then return {} end
    return exports.v_jobmanager:jobmanagerGetLobbies() or {}
end

local function filteredJobs(jobType)
    local list = {}
    for _, job in ipairs(getJobList()) do
        if job.type == jobType then table.insert(list, job) end
    end
    return list
end

local function inJobLobby()
    return jobsAvailable() and exports.v_jobmanager:jobmanagerInLobby()
end

--------------------------------------------------------------------------------
-- misc helpers
--------------------------------------------------------------------------------

local function stripHex(text)
    return (tostring(text):gsub("#%x%x%x%x%x%x", ""))
end

local function formatMoney(value)
    value = tonumber(value) or 0
    local negative = value < 0
    local digits = tostring(math.floor(math.abs(value) + 0.5))
    local grouped = digits:reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", "")
    return (negative and "-$" or "$") .. grouped
end

local function playerMoney()
    local data = tonumber(getElementData(localPlayer, "char.money"))
    if data then return data end
    return getPlayerMoney(localPlayer) or 0
end

local function moveSel(current, delta, count)
    if count <= 0 then return 1 end
    current = current + delta
    if current < 1 then current = count end
    if current > count then current = 1 end
    return current
end

--------------------------------------------------------------------------------
-- settings tree
--------------------------------------------------------------------------------

-- Global (not local): c_settings.lua walks this tree by item id to apply
-- account-saved values after login.
SETTINGS_TREE = {
    {
        id = "graphics", label = "Graphics",
        items = {
            {
                id = "gfx_farclip", label = "Render distance", type = "range",
                min = 400, max = 3400, step = 200, default = 1400,
                desc = "How far the world is drawn. Higher values cost performance.",
                available = drawdistanceAvailable,
                get = function() return drawdistanceAvailable() and exports.drawdistance:getFarClip() end,
                set = function(v) if drawdistanceAvailable() then exports.drawdistance:setFarClip(v) end end,
            },
            {
                id = "gfx_modellod", label = "Model LOD", type = "range",
                min = 200, max = 2800, step = 200, default = 400,
                desc = "Distance at which mapped objects switch to their low-detail version.",
                available = drawdistanceAvailable,
                get = function() return drawdistanceAvailable() and exports.drawdistance:getModelLOD() end,
                set = function(v) if drawdistanceAvailable() then exports.drawdistance:setModelLOD(v) end end,
            },
            {
                id = "gfx_pedlod", label = "Ped LOD", type = "range",
                min = 200, max = 500, step = 200, default = 500,
                desc = "How far away other pedestrians keep being drawn (engine limit 500).",
                available = drawdistanceAvailable,
                get = function() return drawdistanceAvailable() and exports.drawdistance:getPedLOD() end,
                set = function(v) if drawdistanceAvailable() then exports.drawdistance:setPedLOD(v) end end,
            },
            {
                id = "gfx_vehiclelod", label = "Vehicle LOD", type = "range",
                min = 200, max = 500, step = 200, default = 500,
                desc = "How far away other vehicles keep being drawn (engine limit 500).",
                available = drawdistanceAvailable,
                get = function() return drawdistanceAvailable() and exports.drawdistance:getVehicleLOD() end,
                set = function(v) if drawdistanceAvailable() then exports.drawdistance:setVehicleLOD(v) end end,
            },
        },
    },
    {
        id = "display", label = "Display",
        items = {
            {
                id = "show3dblips", label = "Show 3D Blips", type = "toggle",
                desc = "Show 3D world markers above map blips while on foot or driving.",
                available = radarAvailable,
                get = function() return radarAvailable() and exports.v_radar:getShow3DBlips() end,
                set = function(v) if radarAvailable() then exports.v_radar:setShow3DBlips(v) end end,
            },
            {
                id = "enable3dnavigation", label = "Enable 3D Navigation", type = "toggle",
                desc = "Enable 3D navigation features.",
                available = radarAvailable,
                get = function() return radarAvailable() and exports.v_radar:getEnable3DNavigation() end,
                set = function(v) if radarAvailable() then exports.v_radar:setEnable3DNavigation(v) end end,
            },
        },
    },
}

--------------------------------------------------------------------------------
-- ui sounds
--------------------------------------------------------------------------------

local UI_SOUNDS = {
    open   = "sounds/open.mp3",   -- pause menu opened
    close  = "sounds/close.mp3",  -- pause menu closed
    select = "sounds/select.wav", -- confirm / enter
    click  = "sounds/click.wav",  -- navigation
}

local function playUI(name)
    local path = UI_SOUNDS[name]
    if path then playSound(path) end
end

--------------------------------------------------------------------------------
-- open / close
--------------------------------------------------------------------------------

local function closeBigmap()
    if not pauseMapOpen then return end
    if radarAvailable() then
        exports.v_radar:closePauseBigmap()
    end
    pauseMapOpen = false
    showCursor(false)
    setElementData(localPlayer, "hideHUD", pauseMenuOpen)
end

local function openBigmap()
    if not radarAvailable() then return end
    exports.v_radar:openPauseBigmap()
    pauseMapOpen = true
end

local function setPauseMenuOpen(open)
    if open ~= pauseMenuOpen then
        playUI(open and "open" or "close")
    end
    pauseMenuOpen = open

    if not open and pauseMapOpen then
        closeBigmap()
    end

    setElementData(localPlayer, "paused", open)
    setElementData(localPlayer, "showChat", not open)
    setElementData(localPlayer, "hideHUD", open)
    uicore:toggleMoveControls(not open)
    showCursor(false)

    if open then
        -- Always start on the first tab (MAP), on the tab bar.
        focus = "tabs"
        selectedTab = 1
        jobsMenu = { view = "root", rootSel = 1, listSel = 1 }
        settingsCat = nil
        settingsSel = 1
        if jobsAvailable() then
            exports.v_jobmanager:jobmanagerRequestJobs()
        end
    end
end

--------------------------------------------------------------------------------
-- navigation
--------------------------------------------------------------------------------

local function enterContent()
    local tab = TABS[selectedTab]
    if tab == "MAP" then
        openBigmap()
    elseif tab == "JOBS" then
        focus = "content"
        jobsMenu.view, jobsMenu.rootSel = "root", 1
        if jobsAvailable() then
            exports.v_jobmanager:jobmanagerRequestJobs()
        end
    elseif tab == "SETTINGS" then
        focus = "content"
        settingsCat = nil
        settingsSel = 1
    end
end

local function contentBack()
    if TABS[selectedTab] == "SETTINGS" and settingsCat then
        settingsCat = nil
        settingsSel = 1
        return
    end
    if TABS[selectedTab] == "JOBS" and jobsMenu.view ~= "root" then
        jobsMenu.view = "root"
        return
    end
    focus = "tabs"
end

local function handleJobsKey(key)
    if jobsMenu.view == "root" then
        if key == "arrow_u" then
            jobsMenu.rootSel = moveSel(jobsMenu.rootSel, -1, #JOBS_ROOT)
        elseif key == "arrow_d" then
            jobsMenu.rootSel = moveSel(jobsMenu.rootSel, 1, #JOBS_ROOT)
        elseif key == "enter" then
            local item = JOBS_ROOT[jobsMenu.rootSel]
            if not item or not jobsAvailable() then return end
            if item.id == "quick" then
                exports.v_jobmanager:jobmanagerQuickJob()
                setPauseMenuOpen(false)
            elseif item.id == "lobbies" then
                jobsMenu.view, jobsMenu.listSel = "joinlobby", 1
                exports.v_jobmanager:jobmanagerRequestLobbies()
            elseif item.id == "race" then
                jobsMenu.view, jobsMenu.listSel = "race", 1
            elseif item.id == "dm" then
                jobsMenu.view, jobsMenu.listSel = "deathmatch", 1
            elseif item.id == "arenawar" then
                triggerServerEvent("pausemenu_joinArenawar", localPlayer)
                setPauseMenuOpen(false)
            end
        end
        return
    end

    if jobsMenu.view == "joinlobby" then
        local list = getLobbyList()
        if key == "arrow_u" then
            jobsMenu.listSel = moveSel(jobsMenu.listSel, -1, #list)
        elseif key == "arrow_d" then
            jobsMenu.listSel = moveSel(jobsMenu.listSel, 1, #list)
        elseif key == "enter" then
            local entry = list[jobsMenu.listSel]
            if entry then
                exports.v_jobmanager:jobmanagerJoinLobby(entry.id)
                setPauseMenuOpen(false)
            end
        end
        return
    end

    local list = filteredJobs(jobsMenu.view == "race" and "race" or "deathmatch")
    if key == "arrow_u" then
        jobsMenu.listSel = moveSel(jobsMenu.listSel, -1, #list)
    elseif key == "arrow_d" then
        jobsMenu.listSel = moveSel(jobsMenu.listSel, 1, #list)
    elseif key == "enter" then
        local job = list[jobsMenu.listSel]
        if job then
            exports.v_jobmanager:jobmanagerJoinJob(job.id)
            setPauseMenuOpen(false)
        end
    end
end

local function handleSettingsKey(key)
    if settingsCat == nil then
        if key == "arrow_u" then
            settingsSel = moveSel(settingsSel, -1, #SETTINGS_TREE)
        elseif key == "arrow_d" then
            settingsSel = moveSel(settingsSel, 1, #SETTINGS_TREE)
        elseif key == "enter" or key == "arrow_r" then
            settingsCat = settingsSel
            settingsSel = 1
        end
        return
    end

    local cat = SETTINGS_TREE[settingsCat]
    local item = cat.items[settingsSel]
    if key == "arrow_u" then
        settingsSel = moveSel(settingsSel, -1, #cat.items)
    elseif key == "arrow_d" then
        settingsSel = moveSel(settingsSel, 1, #cat.items)
    elseif key == "enter" or key == "arrow_l" or key == "arrow_r" then
        if not item then return end
        local enabled = (not item.available) or item.available()
        if not enabled then return end

        local newValue
        if item.type == "toggle" then
            newValue = not (item.get() and true or false)
        elseif item.type == "range" and (key == "arrow_l" or key == "arrow_r") then
            local cur = tonumber(item.get()) or item.default or item.min
            local delta = (key == "arrow_r") and item.step or -item.step
            newValue = math.max(item.min, math.min(item.max, cur + delta))
            if newValue == cur then return end
        end

        if newValue ~= nil then
            item.set(newValue)
            if item.id then
                -- persist the change to the player's account (c_settings.lua)
                pauseSettingsPersist(item.id, newValue)
            end
        end
    end
end

addEventHandler("onClientKey", root, function(key, press)
    if not press then return end
    if getElementData(localPlayer, "showChatInput") then return end

    -- While the social panel is open it owns the foreground: the pause menu can
    -- neither be opened nor operated until the social panel is closed. Keys are
    -- left uncancelled so the social panel still receives them.
    if getElementData(localPlayer, "socialPanelOpen") then return end

    -- Same for the v_admin report / reports panel.
    if getElementData(localPlayer, "reportPanelOpen") then return end

    -- Same while the virtual browser (ui_browser) is open.
    if getElementData(localPlayer, "browserOpen") then return end

    if not pauseMenuOpen then
        if OPEN_KEYS[key]
            and not getElementData(localPlayer, "bigmapIsVisible")
            and not getElementData(localPlayer, "interactionMenuOpen")
            and not getElementData(localPlayer, "scoreboardOpen")
            and not inJobLobby() then
            cancelEvent()
            setPauseMenuOpen(true)
        end
        return
    end

    if pauseMapOpen then
        if key == "backspace" then
            cancelEvent()
            closeBigmap()
        end
        return
    end

    if key == "p" then
        cancelEvent()
        setPauseMenuOpen(false)
        return
    end

    if key ~= "arrow_l" and key ~= "arrow_r" and key ~= "arrow_u"
        and key ~= "arrow_d" and key ~= "enter" and key ~= "backspace" then
        return
    end
    cancelEvent()

    if focus == "tabs" then
        if key == "arrow_l" then
            selectedTab = moveSel(selectedTab, -1, #TABS)
            playUI("click")
        elseif key == "arrow_r" then
            selectedTab = moveSel(selectedTab, 1, #TABS)
            playUI("click")
        elseif key == "enter" then
            playUI("select")
            enterContent()
        elseif key == "arrow_d" and TABS[selectedTab] ~= "MAP" then
            playUI("select")
            enterContent()
        elseif key == "backspace" then
            setPauseMenuOpen(false)
        end
        return
    end

    if key == "backspace" then
        playUI("click")
        contentBack()
        return
    end

    local tab = TABS[selectedTab]
    if tab == "JOBS" or tab == "SETTINGS" then
        playUI(key == "enter" and "select" or "click")
    end
    if tab == "JOBS" then
        handleJobsKey(key)
    elseif tab == "SETTINGS" then
        handleSettingsKey(key)
    end
end)

--------------------------------------------------------------------------------
-- rendering primitives
--------------------------------------------------------------------------------

local function drawColumnHeader(x, y, w, text, right)
    dxDrawRectangle(x, y, w, HEAD_H, C.colHead)
    dxDrawText(text, x + S(12), y, x + w - S(12), y + HEAD_H,
        C.colHeadTxt, S(1.05), FONT.head, "left", "center")
    if right and right ~= "" then
        dxDrawText(right, x + S(12), y, x + w - S(12), y + HEAD_H,
            C.colHeadTxt, S(1.0), FONT.row, "right", "center")
    end
end

-- rows: { {label=, value=, selector=bool, badge=, dim=bool}, ... }
local function drawRows(x, y, w, rows, selectedIndex, active)
    for i, r in ipairs(rows) do
        local ry = y + (i - 1) * ROW_H
        local sel = active and i == selectedIndex
        dxDrawRectangle(x, ry, w, ROW_H, sel and C.rowSel or C.row)
        dxDrawRectangle(x, ry + ROW_H - 1, w, 1, C.rowSep)

        local labelCol = sel and C.rowSelTxt or (r.dim and C.txtDim or C.txt)
        dxDrawText(r.label, x + S(12), ry, x + w - S(12), ry + ROW_H,
            labelCol, S(1.05), sel and FONT.rowB or FONT.row, "left", "center")

        if r.badge and r.badge ~= "" then
            local bw = dxGetTextWidth(r.badge, S(0.85), FONT.rowB) + S(14)
            dxDrawRectangle(x + w - S(12) - bw, ry + ROW_H / 2 - S(9), bw, S(18), C.accent)
            dxDrawText(r.badge, x + w - S(12) - bw, ry + ROW_H / 2 - S(9), x + w - S(12), ry + ROW_H / 2 + S(9),
                tocolor(255, 255, 255), S(0.85), FONT.rowB, "center", "center")
        elseif r.value and r.value ~= "" then
            local v = r.value
            if r.selector and sel then v = "< " .. v .. " >" end
            dxDrawText(v, x + S(12), ry, x + w - S(12), ry + ROW_H,
                sel and C.rowSelTxt or C.value, S(1.0), sel and FONT.rowB or FONT.row, "right", "center")
        end
    end
end

--------------------------------------------------------------------------------
-- tab pages
--------------------------------------------------------------------------------

local function drawMapTab(x, y, w, h)
    if radarAvailable() then
        exports.v_radar:renderPausePreview(x, y, w, h)
    else
        dxDrawRectangle(x, y, w, h, tocolor(0, 0, 0, 180))
        dxDrawText("Map unavailable", x, y, x + w, y + h, C.txtDim, S(1.1), FONT.row, "center", "center")
    end
end

-- job: { name=, type=, min=, max=, image=, description= }
local function drawJobDetails(x, y, w, h, job)
    if not job then return end
    dxDrawRectangle(x, y, w, h, C.row)

    local boxH = math.min(h * 0.5, w * 9 / 16)
    local imgH = boxH
    local imgW = imgH * 16 / 9
    if imgW > w then imgW = w; imgH = imgW * 9 / 16 end
    local imgX = x + (w - imgW) / 2

    local imgPath = ":v_jobmanager/" .. (job.image or "assets/jobs/default.jpg")
    if not fileExists(imgPath) then
        imgPath = ":v_jobmanager/assets/jobs/default.jpg"
    end
    dxDrawRectangle(x, y, w, boxH, tocolor(0, 0, 0, 220))
    dxDrawImage(imgX, y + (boxH - imgH) / 2, imgW, imgH, imgPath)
    dxDrawText(job.name or "", x + S(10), y + boxH - S(30), x + w - S(10), y + boxH - S(6),
        tocolor(255, 255, 255), S(1.15), FONT.name, "right", "bottom")

    local info = {
        { "Type",    (job.type == "race" and "Race") or (job.type == "deathmatch" and "Deathmatch") or "Job" },
        { "Players", tostring(job.min or "?") .. "-" .. tostring(job.max or "?") },
    }
    local iy = y + boxH
    for i, row in ipairs(info) do
        local ry = iy + (i - 1) * ROW_H
        dxDrawRectangle(x, ry, w, ROW_H, i % 2 == 0 and tocolor(255, 255, 255, 10) or tocolor(0, 0, 0, 0))
        dxDrawText(row[1], x + S(12), ry, x + w - S(12), ry + ROW_H, C.txtDim, S(1.0), FONT.row, "left", "center")
        dxDrawText(row[2], x + S(12), ry, x + w - S(12), ry + ROW_H, C.txt, S(1.0), FONT.rowB, "right", "center")
    end

    if job.description then
        dxDrawText(job.description, x + S(12), iy + #info * ROW_H + S(10), x + w - S(12), y + h - S(8),
            C.txtDim, S(0.95), FONT.row, "left", "top", false, true)
    end
end

local function drawJobsRoot(x, y, w, h)
    local gap = S(6)
    local leftW = math.floor(w * 0.30)
    local rightX = x + leftW + gap
    local rightW = w - leftW - gap

    drawColumnHeader(x, y, leftW, "JOBS")
    drawColumnHeader(rightX, y, rightW, "ABOUT")

    local listY = y + HEAD_H
    local rows = {}
    for i, item in ipairs(JOBS_ROOT) do
        rows[i] = { label = item.label }
    end
    drawRows(x, listY, leftW, rows, jobsMenu.rootSel, focus == "content")

    local item = JOBS_ROOT[jobsMenu.rootSel]
    dxDrawRectangle(rightX, listY, rightW, y + h - listY, C.row)
    if item then
        dxDrawText(item.desc, rightX + S(12), listY + S(10), rightX + rightW - S(12), y + h - S(8),
            C.txtDim, S(1.0), FONT.row, "left", "top", false, true)
    end
end

local function drawJobsList(x, y, w, h, list)
    local gap = S(6)
    local leftW = math.floor(w * 0.30)
    local rightX = x + leftW + gap
    local rightW = w - leftW - gap

    drawColumnHeader(x, y, leftW, jobsMenu.view == "joinlobby" and "OPEN LOBBIES" or "JOBS")
    drawColumnHeader(rightX, y, rightW, "DETAILS")

    local listY = y + HEAD_H
    local detH = h - HEAD_H

    if #list == 0 then
        dxDrawRectangle(x, listY, leftW, detH, C.row)
        dxDrawText(jobsMenu.view == "joinlobby" and "No open lobbies" or "No jobs available",
            x + S(12), listY + S(10), x + leftW - S(12), listY + detH, C.txtDim, S(1.0), FONT.row, "left", "top")
        return
    end
    if jobsMenu.listSel > #list then jobsMenu.listSel = #list end

    local rows = {}
    if jobsMenu.view == "joinlobby" then
        for i, entry in ipairs(list) do
            rows[i] = {
                label = entry.jobName or ("Lobby " .. entry.id),
                value = (entry.type == "race" and "Race" or "Deathmatch") .. "  " .. entry.count .. "/" .. entry.max,
                badge = entry.hostName,
            }
        end
    else
        for i, job in ipairs(list) do
            rows[i] = {
                label = job.name or ("Job " .. i),
                value = tostring(job.min or "?") .. "-" .. tostring(job.max or "?"),
            }
        end
    end
    drawRows(x, listY, leftW, rows, jobsMenu.listSel, focus == "content")

    local selected = list[jobsMenu.listSel]
    if jobsMenu.view == "joinlobby" and selected then
        drawJobDetails(rightX, listY, rightW, detH, {
            name = selected.jobName, type = selected.type,
            min = nil, max = selected.max, image = selected.image, description = selected.description,
        })
    else
        drawJobDetails(rightX, listY, rightW, detH, selected)
    end
end

local function drawJobsTab(x, y, w, h)
    if not jobsAvailable() then
        drawColumnHeader(x, y, w, "JOBS")
        dxDrawRectangle(x, y + HEAD_H, w, h - HEAD_H, C.row)
        dxDrawText("Jobs unavailable", x + S(12), y + HEAD_H, x + w - S(12), y + h,
            C.txtDim, S(1.0), FONT.row, "left", "top")
        return
    end

    if jobsMenu.view == "root" then
        drawJobsRoot(x, y, w, h)
    elseif jobsMenu.view == "joinlobby" then
        drawJobsList(x, y, w, h, getLobbyList())
    else
        drawJobsList(x, y, w, h, filteredJobs(jobsMenu.view == "race" and "race" or "deathmatch"))
    end
end

local function drawSettingsTab(x, y, w, h)
    local gap = S(6)
    local leftW = math.floor(w * 0.30)
    local rightX = x + leftW + gap
    local rightW = w - leftW - gap

    local catIndex = settingsCat or settingsSel
    local cat = SETTINGS_TREE[catIndex]

    drawColumnHeader(x, y, leftW, "SETTINGS")
    drawColumnHeader(rightX, y, rightW, cat and string.upper(cat.label) or "")

    local listY = y + HEAD_H

    local catRows = {}
    for i, c in ipairs(SETTINGS_TREE) do
        catRows[i] = { label = c.label, value = ">" }
    end
    drawRows(x, listY, leftW, catRows, catIndex, focus == "content")

    if not cat then return end

    local itemRows = {}
    for i, item in ipairs(cat.items) do
        local enabled = (not item.available) or item.available()
        local value = ""
        if not enabled then
            value = "unavailable"
        elseif item.type == "toggle" then
            value = (item.get() and true or false) and "ON" or "OFF"
        elseif item.type == "range" then
            value = tostring(tonumber(item.get()) or item.default or item.min)
        end
        local selector = enabled and (item.type == "toggle" or item.type == "range")
        itemRows[i] = { label = item.label, value = value, selector = selector, dim = not enabled }
    end
    drawRows(rightX, listY, rightW, itemRows, settingsSel, focus == "content" and settingsCat ~= nil)
end

--------------------------------------------------------------------------------
-- frame
--------------------------------------------------------------------------------

local function contextHelp()
    if focus == "tabs" then
        local t = TABS[selectedTab]
        if t == "MAP" then return "Open the full-screen map." end
        if t == "JOBS" then return "Browse and join jobs." end
        return "Change your settings."
    end
    local tab = TABS[selectedTab]
    if tab == "JOBS" then
        if jobsMenu.view == "root" then
            local item = JOBS_ROOT[jobsMenu.rootSel]
            return item and item.desc or ""
        elseif jobsMenu.view == "joinlobby" then
            local entry = getLobbyList()[jobsMenu.listSel]
            return entry and (entry.description or "Join this lobby.") or "No open lobbies right now."
        else
            local list = filteredJobs(jobsMenu.view == "race" and "race" or "deathmatch")
            local job = list[jobsMenu.listSel]
            return job and (job.description or "Join this job.") or ""
        end
    end
    if tab == "SETTINGS" then
        if settingsCat == nil then
            local c = SETTINGS_TREE[settingsSel]
            return c and ("Open the " .. c.label .. " settings.") or ""
        end
        local item = SETTINGS_TREE[settingsCat].items[settingsSel]
        return item and item.desc or ""
    end
    return ""
end

local function drawPanel()
    dxDrawRectangle(0, 0, screenW, screenH, C.wash)

    local fw, fh = screenW * MENU_FRACTION, screenH * MENU_FRACTION
    local fx, fy = math.floor((screenW - fw) / 2), math.floor((screenH - fh) / 2)

    local headerH = S(44)
    local tabH = S(32)
    local footerH = S(26)

    -- header band
    dxDrawRectangle(fx, fy, fw, headerH, C.header)
    dxDrawText("FreeV", fx + S(16), fy, fx + fw * 0.5, fy + headerH,
        C.txt, S(1.5), FONT.logo, "left", "center")
    dxDrawText(stripHex(getPlayerName(localPlayer)), fx + fw * 0.35, fy + S(6), fx + fw - S(16), fy + S(24),
        C.txt, S(1.0), FONT.name, "right", "top")
    dxDrawText(formatMoney(playerMoney()), fx + fw * 0.35, fy + S(24), fx + fw - S(16), fy + S(42),
        C.accent, S(1.0), FONT.rowB, "right", "top")

    -- tab bar
    local tabY = fy + headerH + S(3)
    local tabW = fw / #TABS
    for i, name in ipairs(TABS) do
        local tx = fx + (i - 1) * tabW
        local activeTab = i == selectedTab
        dxDrawRectangle(tx + (i > 1 and S(1) or 0), tabY, tabW - S(2), tabH, activeTab and C.tabSel or C.tab)
        dxDrawText(name, tx, tabY, tx + tabW, tabY + tabH,
            activeTab and C.tabSelTxt or C.tabTxt, S(activeTab and 1.15 or 1.05),
            activeTab and FONT.head or FONT.rowB, "center", "center")
    end
    dxDrawText("<", fx + S(6), tabY, fx + S(26), tabY + tabH, C.tabTxt, S(1.4), FONT.rowB, "center", "center")
    dxDrawText(">", fx + fw - S(26), tabY, fx + fw - S(6), tabY + tabH, C.tabTxt, S(1.4), FONT.rowB, "center", "center")

    -- content
    local contentX = fx
    local contentY = tabY + tabH + S(6)
    local contentW = fw
    local contentH = fy + fh - contentY - footerH - S(4)

    local tab = TABS[selectedTab]
    if tab == "MAP" then
        drawMapTab(contentX, contentY, contentW, contentH)
    elseif tab == "JOBS" then
        drawJobsTab(contentX, contentY, contentW, contentH)
    elseif tab == "SETTINGS" then
        drawSettingsTab(contentX, contentY, contentW, contentH)
    end

    -- footer / info bar
    local infoY = fy + fh - footerH
    dxDrawRectangle(fx, infoY, fw, footerH, C.infobar)
    dxDrawText(contextHelp(), fx + S(16), infoY, fx + fw * 0.62, infoY + footerH,
        C.txtDim, S(0.92), FONT.row, "left", "center", true)
    local hint = focus == "tabs"
        and "ENTER  Select      BACKSPACE / P  Close"
        or  "ENTER  Select      BACKSPACE  Back"
    dxDrawText(hint, fx + fw * 0.62, infoY, fx + fw - S(16), infoY + footerH,
        C.txt, S(0.92), FONT.rowB, "right", "center")
end

addEventHandler("onClientRender", root, function()
    if not pauseMenuOpen or pauseMapOpen then return end

    if TABS[selectedTab] == "JOBS" and jobsAvailable() then
        local now = getTickCount()
        if now - jobRefreshAt > 2000 then
            jobRefreshAt = now
            exports.v_jobmanager:jobmanagerRequestJobs()
            if jobsMenu.view == "joinlobby" then
                exports.v_jobmanager:jobmanagerRequestLobbies()
            end
        end
    end

    drawPanel()
end)

--------------------------------------------------------------------------------
-- lifecycle
--------------------------------------------------------------------------------

local function makeFont(file, px, fallback)
    local f = dxCreateFont(file, px)
    return isElement(f) and f or fallback
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    FONT.small = makeFont("files/Roboto.ttf", 9, "default")
    FONT.row   = makeFont("files/Roboto.ttf", 11, "default")
    FONT.rowB  = makeFont("files/RobotoB.ttf", 11, "default-bold")
    FONT.head  = makeFont("files/RobotoB.ttf", 13, "default-bold")
    FONT.name  = makeFont("files/RobotoB.ttf", 15, "default-bold")

    setElementData(localPlayer, "paused", false)
    if jobsAvailable() then
        exports.v_jobmanager:jobmanagerRequestJobs()
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if pauseMenuOpen then
        setPauseMenuOpen(false)
    end
end)
