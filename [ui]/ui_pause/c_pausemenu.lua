-- GTA V style pause menu ("FreeV").
--
-- Opens with P or BACKSPACE. Controls: ARROWS navigate, ENTER confirm,
-- BACKSPACE go back / close. The ESC key is never used by this resource.
-- The menu is a centred box occupying at most 80% of the screen.
--
--  * MAP      - live world-map preview, ENTER opens the full-screen bigmap
--  * ONLINE   - Quick Job / Join Lobby / Official + Community (Race, Deathmatch) / Arena War / Leave Server
--  * STATS    - level / XP / played time + v_stats statistics by category
--  * SETTINGS - category column + settings column (Display > Show 3D Blips)

local uicore = exports.ui_core
local screenW, screenH = guiGetScreenSize()

local SCALE = (uicore:ui(1000) or 1000) / 1000
local function S(v)
    return v * SCALE
end

-- The menu is a centred box at most 80% of the screen.
local MENU_FRACTION = 0.8

local ROW_H  = S(34)
local HEAD_H = S(32)

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
    -- money colours match ui_core's yOverlay (yoverlay.lua)
    cash       = tocolor(50, 200, 50, 255),
    bank       = tocolor(120, 180, 255, 255),
}

local TABS = { "MAP", "ONLINE", "STATS", "SETTINGS" }

local pauseMenuOpen = false
local pauseMapOpen  = false
local focus         = "tabs" -- "tabs" | "content"
local selectedTab   = 1

-- JOBS tab: a small 2-level drill-down.
--   view = "root" | "joinlobby" | "race" | "deathmatch"
local JOBS_ROOT = {
    { id = "jobs",    label = "Jobs",              desc = "Quick Job, lobbies, official and community jobs." },
    { id = "arenawar",label = "Join Arena War",    desc = "Join an Arena War minigame." },
    { id = "leave",   label = "Leave Server",      desc = "Disconnect from the server." }
}
-- Jobs sub-menu.
local JOBS_SUB = {
    { id = "quick",   label = "Quick Job",         desc = "Join a random open lobby, or start a new one with a random game." },
    { id = "lobbies", label = "Join Lobby",        desc = "Browse every open lobby: game, mode and host." },
    { id = "official",  label = "Official",          desc = "Jobs made by the server team." },
    { id = "community", label = "Community created", desc = "Jobs created by other players." },
    { id = "creator",   label = "Creator",           desc = "Open the job creator to build your own job." },
}
-- Official / Community sub-menu: pick a game type, then list the jobs.
local JOBS_CATS = {
    { id = "race",       label = "Race",       desc = "Browse the available Race jobs." },
    { id = "deathmatch", label = "Deathmatch", desc = "Browse the available Deathmatch jobs." },
}
--   view = "root" | "joinlobby" | "cat" | "race" | "deathmatch"; src = "official" | "community"
local jobsMenu     = { view = "root", rootSel = 1, listSel = 1, catSel = 1, subSel = 1, src = "official" }
local jobRefreshAt = 0

-- STATS tab: category column + read-only value column.
local statsCat       = nil -- nil = category column, otherwise index into the built category list
local statsSel       = 1
local statsData      = { defs = nil, values = nil, loaded = false }
local statsRefreshAt = 0

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

local function colorsAvailable()
    local res = getResourceFromName("shader_colors")
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
    local community = jobsMenu.src == "community"
    for _, job in ipairs(getJobList()) do
        if job.type == jobType and (job.community and true or false) == community then table.insert(list, job) end
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
    return (negative and "-€" or "€") .. grouped
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
            {
                id = "gfx_colorpreset", label = "Color Grading", type = "choice",
                desc = "Color correction filter for livelier colors and modern contrast. Off saves performance.",
                available = colorsAvailable,
                options = function() return colorsAvailable() and exports.shader_colors:getColorPresets() or {} end,
                get = function() return colorsAvailable() and exports.shader_colors:getColorPreset() end,
                set = function(v) if colorsAvailable() then exports.shader_colors:setColorPreset(v) end end,
                valueText = function()
                    if colorsAvailable() and not exports.shader_colors:isColorGradingSupported() then
                        return "Not supported"
                    end
                end,
            },
            {
                id = "gfx_colorintensity", label = "Color Intensity", type = "range",
                min = 0, max = 100, step = 10, default = 70, suffix = "%",
                desc = "Strength of the color grading filter.",
                available = colorsAvailable,
                get = function() return colorsAvailable() and exports.shader_colors:getColorIntensity() end,
                set = function(v) if colorsAvailable() then exports.shader_colors:setColorIntensity(v) end end,
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
    {
        id = "online", label = "Online",
        items = {
            {
                id = "toggleOwnNametag", label = "Show Own Nametag", type = "toggle",
                desc = "Show your own nametag in the 3D world.",
                -- v_nametags stores the INVERSE: elementData "toggleOwnNametag" == true
                -- means "hide my own nametag". The menu speaks in "show" terms, so
                -- flip on the way in and out.
                get = function() return not getElementData(localPlayer, "toggleOwnNametag") end,
                set = function(v) setElementData(localPlayer, "toggleOwnNametag", not v) end,
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
        jobsMenu = { view = "root", rootSel = 1, listSel = 1, catSel = 1, subSel = 1, src = "official" }
        settingsCat = nil
        settingsSel = 1
        statsCat, statsSel = nil, 1
        statsRefreshAt = 0
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
    elseif tab == "ONLINE" then
        focus = "content"
        jobsMenu.view, jobsMenu.rootSel = "root", 1
        if jobsAvailable() then
            exports.v_jobmanager:jobmanagerRequestJobs()
        end
    elseif tab == "STATS" then
        focus = "content"
        statsCat, statsSel = nil, 1
        statsRefreshAt = 0
    elseif tab == "SETTINGS" then
        focus = "content"
        settingsCat = nil
        settingsSel = 1
    end
end

local function contentBack()
    if TABS[selectedTab] == "STATS" and statsCat then
        statsCat = nil
        return
    end
    if TABS[selectedTab] == "SETTINGS" and settingsCat then
        settingsCat = nil
        settingsSel = 1
        return
    end
    if TABS[selectedTab] == "ONLINE" and jobsMenu.view ~= "root" then
        if jobsMenu.view == "race" or jobsMenu.view == "deathmatch" then
            jobsMenu.view = "cat"
        elseif jobsMenu.view == "cat" or jobsMenu.view == "joinlobby" then
            jobsMenu.view = "jobs"
        else
            jobsMenu.view = "root"
        end
        return
    end
    focus = "tabs"
end

local function handleJobsKey(key)
    if jobsMenu.view == "root" or jobsMenu.view == "jobs" then
        local isRoot = jobsMenu.view == "root"
        local items = isRoot and JOBS_ROOT or JOBS_SUB
        local selKey = isRoot and "rootSel" or "subSel"
        if key == "arrow_u" then
            jobsMenu[selKey] = moveSel(jobsMenu[selKey], -1, #items)
        elseif key == "arrow_d" then
            jobsMenu[selKey] = moveSel(jobsMenu[selKey], 1, #items)
        elseif key == "enter" then
            local item = items[jobsMenu[selKey]]
            if not item then return end
            if item.id == "jobs" then
                jobsMenu.view, jobsMenu.subSel = "jobs", 1
                return
            end
            if item.id == "leave" then
                setPauseMenuOpen(false)
                executeCommandHandler("disconnect")
                return
            end
            if item.id == "creator" then
                local res = getResourceFromName("v_jobcreator")
                if res and getResourceState(res) == "running" then
                    setPauseMenuOpen(false)
                    exports.v_jobcreator:jobcreatorOpen()
                end
                return
            end
            if not jobsAvailable() then return end
            if item.id == "quick" then
                exports.v_jobmanager:jobmanagerQuickJob()
                setPauseMenuOpen(false)
            elseif item.id == "lobbies" then
                jobsMenu.view, jobsMenu.listSel = "joinlobby", 1
                exports.v_jobmanager:jobmanagerRequestLobbies()
            elseif item.id == "official" or item.id == "community" then
                jobsMenu.view, jobsMenu.src, jobsMenu.catSel = "cat", item.id, 1
            elseif item.id == "arenawar" then
                triggerServerEvent("pausemenu_joinArenawar", localPlayer)
                setPauseMenuOpen(false)
            end
        end
        return
    end

    if jobsMenu.view == "cat" then
        if key == "arrow_u" then
            jobsMenu.catSel = moveSel(jobsMenu.catSel, -1, #JOBS_CATS)
        elseif key == "arrow_d" then
            jobsMenu.catSel = moveSel(jobsMenu.catSel, 1, #JOBS_CATS)
        elseif key == "enter" then
            jobsMenu.view, jobsMenu.listSel = JOBS_CATS[jobsMenu.catSel].id, 1
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

-- STATS ------------------------------------------------------------------------

local STAT_CATS_ORDER = { "General", "Distance", "Vehicle time", "Combat", "Other" }

local function formatDuration(sec)
    sec = math.floor(tonumber(sec) or 0)
    local h, m, s = math.floor(sec / 3600), math.floor(sec % 3600 / 60), sec % 60
    if h > 0 then return ("%dh %02dm %02ds"):format(h, m, s) end
    if m > 0 then return ("%dm %02ds"):format(m, s) end
    return s .. "s"
end

local function formatInt(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

local function formatStatValue(def, v)
    v = tonumber(v) or 0
    if def.unit == "km" then return ("%.2f km"):format(v) end
    if def.unit == "s" then return formatDuration(v) end
    return formatInt(v)
end

local function statCategoryOf(def)
    if def.unit == "km" then return "Distance" end
    if def.unit == "s" then return "Vehicle time" end
    if def.id:find("^kills") or def.id:find("^deaths") then return "Combat" end
    return "Other"
end

-- Builds { {label=, rows={ {label=, value=} }}, ... }; empty categories dropped.
local function buildStatCategories()
    local level  = tonumber(getElementData(localPlayer, "level"))
    local xp     = tonumber(getElementData(localPlayer, "xp"))
    local nextXp = tonumber(getElementData(localPlayer, "next_xp"))
    local played = getElementData(localPlayer, "Játékidő")

    local byName = {
        General = {
            { label = "Level", value = level and tostring(level) or "-" },
            { label = "Total XP", value = xp and formatInt(xp) or "-" },
            { label = "XP to next level", value = (xp and nextXp) and formatInt(math.max(0, nextXp - xp)) or "-" },
            { label = "Played time", value = (type(played) == "string" and played ~= "N/A") and played or "-" },
        },
    }
    for _, def in ipairs(statsData.defs or {}) do
        local cat = statCategoryOf(def)
        byName[cat] = byName[cat] or {}
        local v = statsData.values and statsData.values[def.id]
        table.insert(byName[cat], { label = def.name, value = formatStatValue(def, v) })
    end

    local out = {}
    for _, name in ipairs(STAT_CATS_ORDER) do
        if byName[name] then out[#out + 1] = { label = name, rows = byName[name] } end
    end
    return out
end

local function handleStatsKey(key)
    local cats = buildStatCategories()
    if statsCat == nil then
        if key == "arrow_u" then
            statsSel = moveSel(statsSel, -1, #cats)
        elseif key == "arrow_d" then
            statsSel = moveSel(statsSel, 1, #cats)
        elseif key == "enter" or key == "arrow_r" then
            statsCat = statsSel
            statsSel = 1
        end
        return
    end
    local cat = cats[statsCat]
    if not cat then statsCat = nil return end
    if key == "arrow_u" then
        statsSel = moveSel(statsSel, -1, #cat.rows)
    elseif key == "arrow_d" then
        statsSel = moveSel(statsSel, 1, #cat.rows)
    end
end

addEvent("uipause:statsData", true)
addEventHandler("uipause:statsData", root, function(defs, values)
    statsData.defs, statsData.values, statsData.loaded = defs or nil, values or nil, true
end)

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
        elseif item.type == "choice" then
            local opts = item.options() or {}
            if #opts == 0 then return end
            local cur, idx = item.get(), 1
            for i, o in ipairs(opts) do
                if o.id == cur then idx = i break end
            end
            idx = moveSel(idx, key == "arrow_l" and -1 or 1, #opts)
            newValue = opts[idx].id
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
        -- v_introduce: while the server introduction runs only the panel it teaches may open
        local introAllow = getElementData(localPlayer, "intro.allow")
        if OPEN_KEYS[key]
            and not (type(introAllow) == "table" and not introAllow.pause)
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
    if tab == "ONLINE" or tab == "SETTINGS" or tab == "STATS" then
        playUI(key == "enter" and "select" or "click")
    end
    if tab == "ONLINE" then
        handleJobsKey(key)
    elseif tab == "STATS" then
        handleStatsKey(key)
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
        C.colHeadTxt, S(1.25), FONT.head, "left", "center")
    if right and right ~= "" then
        dxDrawText(right, x + S(12), y, x + w - S(12), y + HEAD_H,
            C.colHeadTxt, S(1.1), FONT.row, "right", "center")
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
            labelCol, S(1.18), sel and FONT.rowB or FONT.row, "left", "center")

        if r.badge and r.badge ~= "" then
            local bw = dxGetTextWidth(r.badge, S(0.85), FONT.rowB) + S(14)
            dxDrawRectangle(x + w - S(12) - bw, ry + ROW_H / 2 - S(9), bw, S(18), C.accent)
            dxDrawText(r.badge, x + w - S(12) - bw, ry + ROW_H / 2 - S(9), x + w - S(12), ry + ROW_H / 2 + S(9),
                tocolor(255, 255, 255), S(0.85), FONT.rowB, "center", "center")
        elseif r.value and r.value ~= "" then
            local v = r.value
            if r.selector and sel then v = "< " .. v .. " >" end
            dxDrawText(v, x + S(12), ry, x + w - S(12), ry + ROW_H,
                sel and C.rowSelTxt or C.value, S(1.1), sel and FONT.rowB or FONT.row, "right", "center")
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

    -- reward multiplier bubbles, top-right of the image (only when != 1)
    local bx = x + w - S(8)
    local function bubble(txt, col)
        local tw = dxGetTextWidth(txt, S(0.95), FONT.rowB)
        local bw, bh = tw + S(20), S(22)
        bx = bx - bw
        local by = y + S(8)
        local r = bh / 2
        dxDrawRectangle(bx + r, by, bw - bh, bh, col)
        dxDrawCircle(bx + r, by + r, r, 0, 360, col, col, 24)
        dxDrawCircle(bx + bw - r, by + r, r, 0, 360, col, col, 24)
        dxDrawText(txt, bx, by, bx + bw, by + bh, tocolor(255, 255, 255), S(0.95), FONT.rowB, "center", "center")
        bx = bx - S(6)
    end
    local function fmtMult(v)
        local s = string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", "")
        return s .. "x"
    end
    if job.xpMult and job.xpMult ~= 1 then bubble("XP " .. fmtMult(job.xpMult), tocolor(0, 130, 205, 235)) end
    if job.moneyMult and job.moneyMult ~= 1 then bubble("\226\130\172 " .. fmtMult(job.moneyMult), tocolor(46, 160, 80, 235)) end

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

local function drawJobsRoot(x, y, w, h, items, sel, title)
    local gap = S(6)
    local leftW = math.floor(w * 0.30)
    local rightX = x + leftW + gap
    local rightW = w - leftW - gap

    drawColumnHeader(x, y, leftW, title)
    drawColumnHeader(rightX, y, rightW, "ABOUT")

    local listY = y + HEAD_H
    local rows = {}
    for i, item in ipairs(items) do
        rows[i] = { label = item.label, value = (item.id == "jobs" or item.id == "lobbies" or item.id == "official" or item.id == "community" or item.id == "race" or item.id == "deathmatch") and ">" or nil }
    end
    drawRows(x, listY, leftW, rows, sel, focus == "content")

    local item = items[sel]
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

    drawColumnHeader(x, y, leftW, jobsMenu.view == "joinlobby" and "OPEN LOBBIES"
        or ((jobsMenu.src == "community" and "COMMUNITY " or "OFFICIAL ") .. string.upper(jobsMenu.view)))
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
            moneyMult = selected.moneyMult, xpMult = selected.xpMult,
        })
    else
        drawJobDetails(rightX, listY, rightW, detH, selected)
    end
end

local function drawJobsTab(x, y, w, h)
    if not jobsAvailable() then
        drawColumnHeader(x, y, w, "ONLINE")
        dxDrawRectangle(x, y + HEAD_H, w, h - HEAD_H, C.row)
        dxDrawText("Jobs unavailable", x + S(12), y + HEAD_H, x + w - S(12), y + h,
            C.txtDim, S(1.0), FONT.row, "left", "top")
        return
    end

    if jobsMenu.view == "root" then
        drawJobsRoot(x, y, w, h, JOBS_ROOT, jobsMenu.rootSel, "ONLINE")
    elseif jobsMenu.view == "jobs" then
        drawJobsRoot(x, y, w, h, JOBS_SUB, jobsMenu.subSel, "JOBS")
    elseif jobsMenu.view == "cat" then
        drawJobsRoot(x, y, w, h, JOBS_CATS, jobsMenu.catSel, string.upper(jobsMenu.src))
    elseif jobsMenu.view == "joinlobby" then
        drawJobsList(x, y, w, h, getLobbyList())
    else
        drawJobsList(x, y, w, h, filteredJobs(jobsMenu.view == "race" and "race" or "deathmatch"))
    end
end

local function drawStatsTab(x, y, w, h)
    local gap = S(6)
    local leftW = math.floor(w * 0.30)
    local rightX = x + leftW + gap
    local rightW = w - leftW - gap

    local cats = buildStatCategories()
    local catIndex = math.max(1, math.min(statsCat or statsSel, #cats))
    local cat = cats[catIndex]

    drawColumnHeader(x, y, leftW, "STATS")
    drawColumnHeader(rightX, y, rightW, cat and string.upper(cat.label) or "")

    local listY = y + HEAD_H
    local catRows = {}
    for i, c in ipairs(cats) do catRows[i] = { label = c.label, value = ">" } end
    drawRows(x, listY, leftW, catRows, catIndex, focus == "content")

    if not cat then return end
    drawRows(rightX, listY, rightW, cat.rows, statsSel, focus == "content" and statsCat ~= nil)

    if statsData.loaded and not statsData.defs then
        local ty = listY + #cat.rows * ROW_H + S(8)
        dxDrawText("Statistics unavailable", rightX + S(12), ty, rightX + rightW, ty + S(22),
            C.txtDim, S(1.0), FONT.row, "left", "top")
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
            value = tostring(tonumber(item.get()) or item.default or item.min) .. (item.suffix or "")
        elseif item.type == "choice" then
            local cur = item.get()
            value = tostring(cur or "")
            for _, o in ipairs(item.options() or {}) do
                if o.id == cur then value = o.label break end
            end
        end
        if enabled and item.valueText then
            value = item.valueText() or value
        end
        local selector = enabled and (item.type == "toggle" or item.type == "range" or item.type == "choice")
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
        if t == "ONLINE" then return "Join jobs, lobbies and minigames." end
        if t == "STATS" then return "Your level, XP, played time and statistics." end
        return "Change your settings."
    end
    local tab = TABS[selectedTab]
    if tab == "ONLINE" then
        if jobsMenu.view == "root" then
            local item = JOBS_ROOT[jobsMenu.rootSel]
            return item and item.desc or ""
        elseif jobsMenu.view == "jobs" then
            local item = JOBS_SUB[jobsMenu.subSel]
            return item and item.desc or ""
        elseif jobsMenu.view == "cat" then
            local item = JOBS_CATS[jobsMenu.catSel]
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
    if tab == "STATS" then
        return "Your level, XP, played time and statistics."
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

    local headerH = S(54)
    local tabH = S(40)
    local footerH = S(26)

    -- header band
    dxDrawRectangle(fx, fy, fw, headerH, C.header)
    dxDrawText("FreeV", fx + S(16), fy, fx + fw * 0.5, fy + headerH,
        C.txt, S(1.7), FONT.logo, "left", "center")

    -- name, then a money row under it: cash (green), then bank (blue) directly to
    -- its right. Colours come from ui_core's yOverlay (C.cash / C.bank).
    local moneyL = fx + fw * 0.30
    local moneyR = fx + fw - S(16)
    dxDrawText(stripHex(getPlayerName(localPlayer)), moneyL, fy + S(7), moneyR, fy + S(27),
        C.txt, S(1.1), FONT.name, "right", "top")

    local moneyScale = S(1.05)
    local cashText = formatMoney(playerMoney())
    local bankText = formatMoney(tonumber(getElementData(localPlayer, "bank_money")) or 0)
    local bankW = dxGetTextWidth(bankText, moneyScale, FONT.rowB)
    dxDrawText(bankText, moneyL, fy + S(29), moneyR, fy + S(50),
        C.bank, moneyScale, FONT.rowB, "right", "top")
    dxDrawText(cashText, moneyL, fy + S(29), moneyR - bankW - S(10), fy + S(50),
        C.cash, moneyScale, FONT.rowB, "right", "top")

    -- tab bar
    local tabY = fy + headerH + S(3)
    local tabW = fw / #TABS
    for i, name in ipairs(TABS) do
        local tx = fx + (i - 1) * tabW
        local activeTab = i == selectedTab
        dxDrawRectangle(tx + (i > 1 and S(1) or 0), tabY, tabW - S(2), tabH, activeTab and C.tabSel or C.tab)
        dxDrawText(name, tx, tabY, tx + tabW, tabY + tabH,
            activeTab and C.tabSelTxt or C.tabTxt, S(activeTab and 1.35 or 1.2),
            activeTab and FONT.head or FONT.rowB, "center", "center")
    end
    dxDrawText("<", fx + S(6), tabY, fx + S(26), tabY + tabH, C.tabTxt, S(1.5), FONT.rowB, "center", "center")
    dxDrawText(">", fx + fw - S(26), tabY, fx + fw - S(6), tabY + tabH, C.tabTxt, S(1.5), FONT.rowB, "center", "center")

    -- content
    local contentX = fx
    local contentY = tabY + tabH + S(6)
    local contentW = fw
    local contentH = fy + fh - contentY - footerH - S(4)

    local tab = TABS[selectedTab]
    if tab == "MAP" then
        drawMapTab(contentX, contentY, contentW, contentH)
    elseif tab == "ONLINE" then
        drawJobsTab(contentX, contentY, contentW, contentH)
    elseif tab == "STATS" then
        drawStatsTab(contentX, contentY, contentW, contentH)
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

    if TABS[selectedTab] == "ONLINE" and jobsAvailable() then
        local now = getTickCount()
        if now - jobRefreshAt > 2000 then
            jobRefreshAt = now
            exports.v_jobmanager:jobmanagerRequestJobs()
            if jobsMenu.view == "joinlobby" then
                exports.v_jobmanager:jobmanagerRequestLobbies()
            end
        end
    end

    if TABS[selectedTab] == "STATS" then
        local now = getTickCount()
        if now - statsRefreshAt > 3000 then
            statsRefreshAt = now
            triggerServerEvent("uipause:requestStats", localPlayer)
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
