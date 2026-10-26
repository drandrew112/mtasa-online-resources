-- v_modloader (client): replaces / restores the models.
--
-- Nothing is loaded before v_loading starts the loading (onClientLoadingStarted), or
-- before this resource starts on a client that is already loading / loaded. From then on
-- the loaded set follows the options: a model is loaded when its category is turned on
-- (or it is an ALWAYS_LOAD_OBJECTS id) and every file of it is on this PC.
-- Loading runs in time slices, every mod inside pcall: a broken file is skipped and
-- reported, never blocks the rest. v_loading waits for resourceReady() until the first
-- pass is done.

local started = false
local loaded = {}            -- [category][id] = { element, ... }
local busy, dirty = false, false
local progress = { done = 0, total = 0, finished = false }
local readyReported = false

addEvent("onClientLoadingStarted")
addEvent("onClientReadyCheck")

local function loadMod(category, id, codes, errors)
    local base = category .. "/" .. id
    local steps = {
        { "t", ".txd", engineLoadTXD, engineImportTXD },
        { "d", ".dff", engineLoadDFF, engineReplaceModel },
        { "c", ".col", engineLoadCOL, engineReplaceCOL },
    }
    local ok, elements = true, {}
    for _, step in ipairs(steps) do
        if codes:find(step[1], 1, true) then
            local path = base .. step[2]
            local element
            if not fileExists(path) then
                errors[#errors + 1] = path .. ": file was not downloaded"
                ok = false
            else
                local loadedOk, result = pcall(step[3], path)
                element = loadedOk and result or nil
                if not element then
                    errors[#errors + 1] = path .. ": cannot be loaded" .. (loadedOk and "" or (" (" .. tostring(result) .. ")"))
                    ok = false
                else
                    local applied, success = pcall(step[4], element, id)
                    if not applied or not success then
                        errors[#errors + 1] = path .. ": cannot be applied to model " .. id
                        pcall(destroyElement, element)
                        ok = false
                    else
                        elements[#elements + 1] = element
                    end
                end
            end
        end
    end
    return ok, elements
end

local function unloadMod(category, id)
    local elements = loaded[category] and loaded[category][id]
    if not elements then return end
    loaded[category][id] = nil
    pcall(engineRestoreModel, id)
    pcall(engineRestoreCOL, id)
    for _, element in ipairs(elements) do
        if isElement(element) then pcall(destroyElement, element) end
    end
end

local function wanted(cat, id)
    if not (optionValue(cat.setting) or isAlwaysLoaded(cat.name, id)) then return false end
    return isModelPresent(cat.name, id)
end

local function reportReady()
    if readyReported then return end
    readyReported = true
    pcall(function() exports.v_loading:resourceReady() end)
end

--- Brings the loaded models in line with the options and the files on this PC.
function syncModels()
    if not started or not Mods then return end
    if busy then dirty = true return end

    -- unload at once, load in slices
    local queue = {}
    for _, cat in ipairs(MODLOADER.categories) do
        loaded[cat.name] = loaded[cat.name] or {}
        for id in pairs(loaded[cat.name]) do
            if not (Mods[cat.name] and Mods[cat.name][id]) or not wanted(cat, id) then unloadMod(cat.name, id) end
        end
        local ids = {}
        for id in pairs(Mods[cat.name] or {}) do
            if not loaded[cat.name][id] and wanted(cat, id) then ids[#ids + 1] = id end
        end
        table.sort(ids)
        for _, id in ipairs(ids) do queue[#queue + 1] = { cat.name, id, Mods[cat.name][id].c or "" } end
    end

    -- the loading screen counts the first pass only
    if not progress.finished then progress.done, progress.total = 0, #queue end

    busy, dirty = true, false
    local index, okCount, errors = 1, 0, {}

    local function slice()
        local t0 = getTickCount()
        while index <= #queue and getTickCount() - t0 < MODLOADER.SLICE_MS do
            local item = queue[index]
            index = index + 1
            local called, ok, elements = pcall(loadMod, item[1], item[2], item[3], errors)
            if not called then
                errors[#errors + 1] = ("%s/%s: unexpected error (%s)"):format(item[1], item[2], tostring(ok))
            else
                if #elements > 0 then loaded[item[1]][item[2]] = elements end
                if ok then okCount = okCount + 1 end
            end
            if not progress.finished then progress.done = progress.done + 1 end
        end

        if index <= #queue then
            setTimer(slice, MODLOADER.SLICE_PAUSE, 1)
            return
        end

        if #queue > 0 then
            outputDebugString(("[modloader] %d/%d mod(s) loaded, %d error(s)"):format(okCount, #queue, #errors), 3)
        end
        for _, line in ipairs(errors) do outputDebugString("[modloader] " .. line, 1) end
        if #errors > 0 then triggerServerEvent("modloader:report", resourceRoot, errors) end
        busy = false
        progress.finished = true
        reportReady()
        if dirty then syncModels() end
    end

    slice()
end

--- Files of these models were replaced (download): the loaded old copies go, then the
--- new ones load like any other. changed = { [category] = { [id] = true } }
function refreshModels(changed)
    if busy then dirty = true end
    for catName, ids in pairs(changed or {}) do
        for id in pairs(ids) do unloadMod(catName, id) end
    end
    syncModels()
end

local function start()
    if started then return end
    started = true
    syncModels()
end

-- state.lua hooks
function onModsReceived()
    if started then syncModels() end
end

function onOptionChanged(id)
    if started then syncModels() end
end

--- done, total, finished of the first loading pass (v_loading screen).
function getLoadProgress()
    return progress.done, progress.total, progress.finished, started and Mods ~= nil
end

addEventHandler("onClientLoadingStarted", root, start)

addEventHandler("onClientReadyCheck", root, function()
    if progress.finished then
        readyReported = false
        reportReady()
    end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    -- restarted while the player is loading / playing
    local loadingActive = false
    pcall(function() loadingActive = exports.v_loading:isLoadingActive() end)
    if loadingActive or getElementData(localPlayer, "loaded") == true then start() end
end)
