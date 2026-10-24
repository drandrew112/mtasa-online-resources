-- v_modloader (client): downloads the "manual" categories (download="false" files).
--
--   downloadModels(category) starts it from Settings > Models; autoUpdate() after the login
--   (acc_menu) when Auto-update is on. One file at a time through downloadFile, the progress
--   on ui_download's external mode; Backspace there cancels (the finished files stay).
--   Local events (source = localPlayer):
--     onClientModelDownloadStart  (category)
--     onClientModelDownloadFinish (category, downloadedFiles, failedFiles, cancelled)
--   The panel that was open hides on Start and comes back on Finish (ui_pause, acc_menu).
--   Loading still follows the options: a download alone never loads a turned-off category.

addEvent("onClientModelDownloadStart")
addEvent("onClientModelDownloadFinish")
addEvent("onClientDownloadCancel")          -- ui_download: the player pressed Backspace

local dl = nil      -- { cat, queue, index, tries, doneBytes, totalBytes, files, failed, cancelled }
local inflight = {} -- [path] = md5 requested; a late answer after a cancel is still registered
local changed = {}  -- [category][id] = true: new files since the last reload (refreshModels)

local function markChanged(path)
    local catName, id = path:match("^(%a+)/(%d+)%.")
    id = tonumber(id)
    if not id then return end
    changed[catName] = changed[catName] or {}
    changed[catName][id] = true
end

local function applyChanged()
    local c = changed
    changed = {}
    -- loads the new ones when the category is turned on (and the loading already started)
    refreshModels(c)
end
local autoChecked, autoWaiting = false, false

local function uiDownload(fn, ...)
    local res = getResourceFromName("ui_download")
    if not res or getResourceState(res) ~= "running" then return nil end
    local ok, result = pcall(exports.ui_download[fn], exports.ui_download, ...)
    return ok and result or nil
end

local function notify(text)
    pcall(function() exports.ui_core:addNotification(L("v_modloader.title"), text) end)
end

local function mb(bytes)
    return ("%.1f"):format((tonumber(bytes) or 0) / 1048576)
end

local function progressLabel()
    return L("v_modloader.download.progress", {
        title = L("v_modloader.download.title_" .. dl.cat),
        index = math.min(dl.index, #dl.queue), count = #dl.queue,
        done = mb(dl.doneBytes), total = mb(dl.totalBytes),
    })
end

local function updateProgress()
    uiDownload("setExternalProgress", dl.doneBytes, dl.totalBytes, progressLabel())
end

local function finish()
    local d = dl
    dl = nil
    saveRegistry()
    uiDownload("endExternal")
    statusChanged()
    triggerServerEvent("modloader:downloaded", resourceRoot, d.files, d.doneBytes, d.failed, d.cancelled)

    local status = getModelStatus(d.cat)
    if d.cancelled then
        notify(L("v_modloader.download.cancelled", { ok = status.ok, total = status.total }))
    elseif d.failed > 0 then
        notify(L("v_modloader.download.failed", { count = d.failed }))
    else
        notify(L("v_modloader.download.done", { count = d.models }))
    end
    triggerEvent("onClientModelDownloadFinish", localPlayer, d.cat, d.files, d.failed, d.cancelled)
    applyChanged()
end

local function nextFile()
    if not dl then return end
    if dl.cancelled or dl.index > #dl.queue then return finish() end
    local file = dl.queue[dl.index]
    updateProgress()
    inflight[file.p] = file.h
    if not downloadFile(file.p) then
        inflight[file.p] = nil
        outputDebugString("[modloader] downloadFile refused " .. file.p, 1)
        dl.failed = dl.failed + 1
        dl.index, dl.tries = dl.index + 1, 0
        return nextFile()
    end
end

addEventHandler("onClientFileDownloadComplete", resourceRoot, function(fileName, success)
    fileName = tostring(fileName or ""):gsub("\\", "/")
    local path, hash
    for p, h in pairs(inflight) do
        if fileName == p or fileName:sub(-#p - 1) == "/" .. p then path, hash = p, h break end
    end
    if not path then return end
    inflight[path] = nil
    if success then
        registerDownloaded(path, hash)
        markChanged(path)
    end

    local file = dl and dl.queue[dl.index]
    if not file or file.p ~= path then
        -- a late answer after a cancel: keep it and load it
        if success and not dl then
            saveRegistry()
            statusChanged()
            applyChanged()
        end
        return
    end
    if success then
        dl.files = dl.files + 1
        dl.doneBytes = dl.doneBytes + (tonumber(file.s) or 0)
        dl.index, dl.tries = dl.index + 1, 0
        if dl.files % 10 == 0 then saveRegistry() end
    elseif dl.tries < MODLOADER.DOWNLOAD_RETRIES then
        dl.tries = dl.tries + 1
    else
        outputDebugString("[modloader] download failed: " .. path, 1)
        triggerServerEvent("modloader:report", resourceRoot, { path .. ": download failed" })
        dl.failed = dl.failed + 1
        dl.doneBytes = dl.doneBytes + (tonumber(file.s) or 0)
        dl.index, dl.tries = dl.index + 1, 0
    end
    nextFile()
end)

addEventHandler("onClientDownloadCancel", root, function()
    if not dl or dl.cancelled then return end
    dl.cancelled = true
    finish()
end)

--- Downloads the not current files of a "manual" category. Returns true when it started.
function downloadModels(catName)
    catName = catName or "vehicles"
    local cat = modloaderCategory(catName)
    if dl or not Mods or not cat or cat.download ~= "manual" or isVerifying() then return false end
    local queue, bytes = pendingFiles(catName)
    if #queue == 0 then
        notify(L("v_modloader.download.up_to_date"))
        return false
    end
    local status = getModelStatus(catName)
    dl = {
        cat = catName, queue = queue, index = 1, tries = 0, doneBytes = 0, totalBytes = bytes,
        files = 0, failed = 0, cancelled = false, models = status.new + status.outdated,
    }
    -- the panel hides first, then the download screen comes up
    triggerEvent("onClientModelDownloadStart", localPlayer, catName)
    uiDownload("beginExternal", L("v_modloader.download.title_" .. catName), true)
    nextFile()
    return true
end

function isModelDownloadActive()
    return dl ~= nil
end

local function runAutoUpdate()
    autoWaiting = false
    if getElementData(localPlayer, "loaded") == true then return end -- only between the login and the spawn
    for _, cat in ipairs(MODLOADER.categories) do
        if cat.download == "manual" and #pendingFiles(cat.name) > 0 then
            downloadModels(cat.name)
            return
        end
    end
end

--- acc_menu calls it once the account menu is up: with Auto-update on, the new / changed
--- "manual" models are downloaded right away (once per connection).
function autoUpdate()
    if autoChecked then return false end
    if not optionValue(MODLOADER.AUTOUPDATE_SETTING) then return false end
    autoChecked = true
    if not Mods or isVerifying() then
        autoWaiting = true    -- onVerifyDone runs it
        return true
    end
    runAutoUpdate()
    return true
end

-- state.lua hook: the manifest is checked against this PC
function onVerifyDone()
    if autoWaiting then runAutoUpdate() end
end

addEventHandler("onClientResourceStop", resourceRoot, function()
    if not dl then return end
    uiDownload("endExternal")
    -- the hidden panel comes back
    triggerEvent("onClientModelDownloadFinish", localPlayer, dl.cat, dl.files, dl.failed, true)
end)
