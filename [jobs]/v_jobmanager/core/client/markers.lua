if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- The cards above the job markers (ui_core marker UIs) and the E key inside a marker, which
-- joins a waiting lobby of that job or opens a new one.

local LABEL_HEIGHT = 1.6        -- above the marker position (ground level)
local LABEL_DISTANCE = 40       -- fully hidden beyond this
local LABEL_FULL_DISTANCE = 12  -- full size up to this
local LABEL_MIN_SCALE = 0.55
local KEY = "e"

local TYPE_UI = { race = { "job_race", "common.race" }, deathmatch = { "job_dm", "common.deathmatch" } }

local nearbyJobId = nil -- job id of the marker the local player stands in
local cards = {}        -- ui ids of the registered cards

local function registerCard(job)
    local t = TYPE_UI[job.type] or { "job", "common.job" }
    local id = "job:" .. tostring(job.id)
    local ok = exports.ui_core:createMarkerUI(id, {
        type = t[1], x = job.marker[1], y = job.marker[2], z = job.marker[3], interior = 0, dimension = 0,
        size = 2, title = job.name,
        name = L.msg("v_jobmanager.markers.players", { title = L.msg(t[2]), min_players = job.minPlayers, max_players = job.maxPlayers }),
        hint = L.msg("v_jobmanager.markers.step_into_marker_to_start_lobby"),
        hintActive = L.msg("v_jobmanager.markers.press_e_to_start_lobby"),
        radius = LABEL_DISTANCE, fullRadius = LABEL_FULL_DISTANCE, minScale = LABEL_MIN_SCALE, height = LABEL_HEIGHT,
    })
    if ok then cards[id] = true end
end

-- one ui_core marker UI per job marker
local function registerCards()
    for id in pairs(cards) do exports.ui_core:removeMarkerUI(id) end
    cards = {}
    for _, job in ipairs(jobs or {}) do
        if type(job.marker) == "table" then registerCard(job) end
    end
end

addEvent("onClientMarkerUISystemStart")
addEventHandler("onClientMarkerUISystemStart", root, registerCards)

-- no cards while paused or in a lobby (checked a few times a second, not every frame)
local cardsHidden = false
setTimer(function()
    local hide = (getElementData(localPlayer, "paused") or jobmanagerInLobby()) and true or false
    if hide ~= cardsHidden then
        cardsHidden = hide
        exports.ui_core:setMarkerUIsHidden(hide)
    end
end, 300, 0)

---------------------------------------------------------------- E in the marker

local function onKey()
    if not nearbyJobId or isCursorShowing() or isChatBoxInputActive() or isMainMenuActive() then return end
    if getElementData(localPlayer, "paused") or jobmanagerInLobby() then return end
    -- in a running match (own dimension) the marker binding is stale
    if getElementDimension(localPlayer) ~= 0 then return end
    playSound("assets/sounds/click.wav")
    jobmanagerJoinJob(nearbyJobId)
end

-- Marker games come from the server (game files are server-side only).
addEvent("jobmanager:markers", true)
addEventHandler("jobmanager:markers", resourceRoot, function(list)
    jobs, jobsById = {}, {}
    for _, job in ipairs(type(list) == "table" and list or {}) do
        table.insert(jobs, job)
        jobsById[job.id] = job
    end
    registerCards()
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("jobmanager:requestMarkers", resourceRoot)
end)

addEvent("jobmanager:showJoinHint", true)
addEventHandler("jobmanager:showJoinHint", resourceRoot, function(jobId)
    if type(jobId) ~= "string" or not jobsById[jobId] then return end
    if not nearbyJobId then bindKey(KEY, "down", onKey) end
    nearbyJobId = jobId
end)

addEvent("jobmanager:hideJoinHint", true)
addEventHandler("jobmanager:hideJoinHint", resourceRoot, function()
    if nearbyJobId then unbindKey(KEY, "down", onKey) end
    nearbyJobId = nil
end)

-- Texts load only once the player is loaded (v_loading gate).
local textsLoaded = false
local function loadTexts()
    if textsLoaded then return end
    textsLoaded = true
    exports.v_loading:resourceReady()
end
addEvent("onClientLoadingStarted", true)
addEventHandler("onClientLoadingStarted", root, loadTexts)
-- also when this resource started after the loading screen appeared (v_loading asks again)
addEvent("onClientReadyCheck")
addEventHandler("onClientReadyCheck", root, loadTexts)
addEventHandler("onClientResourceStart", resourceRoot, function()
    if getElementData(localPlayer, "loaded") then loadTexts() end
end)
