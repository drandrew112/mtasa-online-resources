--[[
    updateResources.lua
    ---------------------------------------------------------------------------
    /updateresources

    Downloads every file that differs from the public GitHub repo, verifies
    each download against the git blob SHA-1 from the repo tree, writes it
    into place, then refreshes + reloads the affected resources in dependency
    order (via v_main's loadResources.lua).

    This is a FORCE OVERWRITE, not a merge: local uncommitted edits to tracked
    files are lost, exactly like "git reset --hard origin/<branch>" would do.
    Files that are not in the repo are left untouched - nothing is deleted.
    A brand-new resource (in the repo, not installed here) is created with
    createResource() in the same category folder as in the repo, its files
    are downloaded into it, and the loader then starts it like any other.
    (createResource needs the Admin ACL group - v_main is in it.)

    Repo config + shared helpers: lib/repoSync.lua (RepoSync).
    Read-only companion: updater.lua ("checkupdates").

    Access: server console, or an in-game player with admin_level >= 5.
    See commandAuth.lua.
]]

local MAX_PARALLEL = 4        -- simultaneous raw downloads
local RELOAD_DELAY = 2000     -- ms between stopping affected resources and reloading

local busy = false

local function log(msg)
    outputServerLog("[v_main:update] " .. tostring(msg))
end

-- ---------------------------------------------------------------------------
-- Step 3: apply results - reload the affected resources
-- ---------------------------------------------------------------------------
local function finalizeUpdate(player, written, failed, affected, created)
    commandFeedback(player, "update",
        ("Download done - written: %d, failed: %d."):format(#written, #failed))

    if #created > 0 then
        commandFeedback(player, "update", "New resources installed: " .. table.concat(created, ", "))
    end

    for _, path in ipairs(written) do log("  ok   " .. path) end
    for _, path in ipairs(failed) do log("  FAIL " .. path) end

    local names = {}
    for name in pairs(affected) do names[#names + 1] = name end
    table.sort(names)

    if #names == 0 then
        commandFeedback(player, "update", "No files were changed.")
        busy = false
        return
    end

    commandFeedback(player, "update", "Changed resources: " .. table.concat(names, ", "))

    -- v_main / v_mysql cannot cleanly restart themselves from inside this
    -- handler (this script is running, and the DB layer backs the auth check).
    local selfHit, toReload = {}, {}
    for _, name in ipairs(names) do
        if name == "v_main" or name == "v_mysql" then
            selfHit[#selfHit + 1] = name
        else
            toReload[#toReload + 1] = name
        end
    end

    if #selfHit > 0 then
        commandFeedback(player, "update", "NOTE: " .. table.concat(selfHit, ", ")
            .. " changed - restart from the server console manually.")
    end

    if #toReload == 0 then
        busy = false
        return
    end

    -- Stop the affected resources, then let v_main's dependency-ordered
    -- loader bring them (and anything that went down with them) back up.
    for _, name in ipairs(toReload) do
        local res = getResourceFromName(name)
        if res and getResourceState(res) == "running" then
            stopResource(res)
        end
    end

    commandFeedback(player, "update",
        ("Reloading %d resource(s) in dependency order..."):format(#toReload))

    setTimer(function()
        refreshResources(false)
        if type(loadAllResources) == "function" then
            loadAllResources()
        else
            log("ERROR: loadAllResources() unavailable - is loadResources.lua loaded?")
        end
        busy = false
    end, RELOAD_DELAY, 1)
end

-- ---------------------------------------------------------------------------
-- Step 2: download the queue, verify, write
-- ---------------------------------------------------------------------------
local function downloadAndApply(player, todo, created)
    local total    = #todo
    local nextIdx  = 0
    local finished = 0

    local written, failed = {}, {}
    local affected = {}

    local startNext  -- forward declaration

    local function onOne()
        finished = finished + 1
        if finished >= total then
            finalizeUpdate(player, written, failed, affected, created)
        else
            startNext()
        end
    end

    startNext = function()
        nextIdx = nextIdx + 1
        local item = todo[nextIdx]
        if not item then return end

        local url = RepoSync.RAW_BASE_URL .. RepoSync.encodePath(item.repoPath)

        local ok = fetchRemote(url,
            { headers = RepoSync.RAW_HEADERS, connectionAttempts = 2, connectTimeout = 30000 },
            function(data, info)
                local httpOk = (type(info) == "table" and info.success and info.statusCode == 200)
                            or (type(info) == "number" and info == 0)

                if not httpOk then
                    local code = (type(info) == "table") and tostring(info.statusCode) or tostring(info)
                    failed[#failed + 1] = item.repoPath .. "  (download failed, HTTP " .. code .. ")"
                elseif not RepoSync.contentMatches(data, item.sha) then
                    -- The bytes we got do not hash to the SHA the repo tree
                    -- promised. Never write a file we cannot verify.
                    failed[#failed + 1] = item.repoPath .. "  (SHA mismatch - NOT written)"
                else
                    local path = ":" .. item.resName .. "/" .. item.subPath
                    if fileExists(path) then fileDelete(path) end
                    local fh = fileCreate(path)   -- creates intermediate folders
                    if not fh then
                        failed[#failed + 1] = item.repoPath .. "  (could not write file)"
                    else
                        fileWrite(fh, data)
                        fileClose(fh)
                        written[#written + 1] = item.repoPath
                        affected[item.resName] = true
                    end
                end

                onOne()
            end)

        if not ok then
            failed[#failed + 1] = item.repoPath .. "  (could not start download)"
            onOne()
        end
    end

    for _ = 1, math.min(MAX_PARALLEL, total) do
        startNext()
    end
end

-- ---------------------------------------------------------------------------
-- Step 1: fetch the repo tree, work out what needs updating
-- ---------------------------------------------------------------------------
local function runUpdate(triggeredBy, player)
    if busy then
        commandFeedback(player, "update", "An update is already running - ignoring this request.")
        return
    end
    busy = true

    commandFeedback(player, "update", ("Update started (%s). Repo: %s/%s @ %s")
        :format(triggeredBy, RepoSync.USER, RepoSync.NAME, RepoSync.BRANCH))

    fetchRemote(RepoSync.API_TREE_URL,
        { headers = RepoSync.API_HEADERS, connectionAttempts = 2, connectTimeout = 20000 },
        function(data, info)
            local httpOk = (type(info) == "table" and info.success and info.statusCode == 200)
                        or (type(info) == "number" and info == 0)
            if not httpOk then
                local code = (type(info) == "table") and tostring(info.statusCode) or tostring(info)
                commandFeedback(player, "update", "Could not fetch the repo tree from GitHub (HTTP " .. code .. ").")
                busy = false
                return
            end

            local parsed = fromJSON(data)
            if type(parsed) ~= "table" or type(parsed.tree) ~= "table" then
                commandFeedback(player, "update", "Could not parse the GitHub tree response.")
                busy = false
                return
            end
            if parsed.truncated then
                commandFeedback(player, "update",
                    "WARNING: GitHub returned a TRUNCATED tree - some files will be missed.")
            end

            local roots = RepoSync.buildResourceRoots(parsed.tree)

            -- Create every repo resource that is not installed here yet, in
            -- the same category folder ("[core]", "[a]/[b]", ...) as in the
            -- repo. createResource writes a blank meta.xml, which then gets
            -- overwritten by the download below like any outdated file.
            local created, createFailed = {}, {}
            for _, r in ipairs(roots) do
                if not getResourceFromName(r.name)
                    and not RepoSync.isIgnored(r.dir .. "/meta.xml") then
                    local orgDir = r.dir:match("^(.+)/[^/]+$")
                    if createResource(r.name, orgDir) then
                        created[#created + 1] = r.name
                        log("created new resource " .. r.name .. " in " .. tostring(orgDir or "resources root"))
                    else
                        createFailed[#createFailed + 1] = r.name
                    end
                end
            end
            if #createFailed > 0 then
                commandFeedback(player, "update", "Could not create new resource(s): "
                    .. table.concat(createFailed, ", ")
                    .. " - the folder may already exist with a broken meta.xml; check it, then 'refresh'.")
            end

            local todo         = {}
            local notInstalled = 0

            for _, entry in ipairs(parsed.tree) do
                if entry.type == "blob" and entry.path and entry.sha then
                    local repoPath = entry.path

                    if not RepoSync.isIgnored(repoPath) then
                        local resName, subPath = RepoSync.mapToResource(repoPath, roots)

                        if resName and not getResourceFromName(resName) then
                            notInstalled = notInstalled + 1
                        elseif resName then
                            local localData = RepoSync.readLocalFile(":" .. resName .. "/" .. subPath)
                            if not localData or not RepoSync.contentMatches(localData, entry.sha) then
                                todo[#todo + 1] = {
                                    repoPath = repoPath,
                                    resName  = resName,
                                    subPath  = subPath,
                                    sha      = entry.sha,
                                }
                            end
                        end
                    end
                end
            end

            if notInstalled > 0 then
                commandFeedback(player, "update", notInstalled
                    .. " repo file(s) belong to resources that could not be installed here (skipped).")
            end

            if #todo == 0 then
                commandFeedback(player, "update", "Everything is already up to date with the repo.")
                busy = false
                return
            end

            commandFeedback(player, "update", ("%d file(s) to download and apply..."):format(#todo))
            downloadAndApply(player, todo, created)
        end)
end

-- ---------------------------------------------------------------------------
-- command
-- ---------------------------------------------------------------------------
addCommandHandler("updateresources", function(player)
    if not canRunAdminCommand(player) then
        return denyAdminCommand(player, "updateresources")
    end

    local who = isElement(player)
        and ("player " .. getPlayerName(player) .. " (#" .. tostring(getElementData(player, "ID")) .. ")")
        or  "console"

    runUpdate(who, player)
end, false, false)
