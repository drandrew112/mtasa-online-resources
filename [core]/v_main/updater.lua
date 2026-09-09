--[[
    updater.lua
    ---------------------------------------------------------------------------
    Server-wide update *checker*, based on the public GitHub repo:

        https://github.com/drandrew112/mtasa-online-resources

    It does NOT download or modify anything - it only reports which local
    files differ from the repo (or are missing locally), so you know what a
    "git pull" would change. To actually apply the changes, use the
    "updateresources" command (updateResources.lua).

    How it works:
      1. Fetches the repo file tree from the GitHub API in a single request.
         That tree already contains the git blob SHA-1 of every file.
      2. For every repo file that belongs to a resource installed here, it
         computes the same git blob SHA-1 from the local copy and compares.
      3. Every mismatch (and every repo file missing locally) is logged to
         the server console.

    Rules:
      - Local files that are NOT in the repo are left alone (extra files are
        allowed). We only look at files that exist in the repo.
      - Files on the IGNORE list (lib/repoSync.lua) are skipped. That list
        mirrors resources/.gitignore (runtime data + credentials).
      - core.autocrlf is "true" on this checkout, so text files have CRLF in
        the working tree but LF in the git blob. We therefore accept a file
        as up to date if either the raw bytes OR the CRLF->LF normalised
        bytes hash to the repo's blob SHA-1.

    Triggers:
      - Automatically on v_main start, unless the "enableUpdateChecker"
        setting (meta.xml) is [false].
      - Manually from the server console:   checkupdates

    Repo config + all the shared helpers live in lib/repoSync.lua (RepoSync),
    so this checker and updateResources.lua can never disagree about which
    files are tracked. The GitHub updater library under lib/updater/ is still
    used for the event/logging plumbing.
]]

local function log(msg)
    outputServerLog("[v_main:updater] " .. tostring(msg))
end

-- ---------------------------------------------------------------------------
-- lib/updater - reuse the Updater class for the event plumbing
-- ---------------------------------------------------------------------------
local checker
if type(updater) == "table" and type(load) == "function" then
    checker = load(updater)
    checker:setDetails({ user = RepoSync.USER, repo = RepoSync.NAME, branch = RepoSync.BRANCH, private = false })
    checker:setDebug(true) -- silence the built-in "progress" print path
else
    log("WARNING: lib/updater not loaded - event forwarding disabled.")
end

-- Single logging path. Also forwards the raw event to the lib so external
-- listeners (checker:on(...)) keep working, but formatting lives here.
local EVENT_PREFIX = { error = "ERROR: ", outdated = "outdated : ", missing = "missing  : " }

local function emit(event, text)
    local line = (EVENT_PREFIX[event] or "") .. tostring(text)
    if event == "missing" then line = line .. "   (in repo, not found locally)" end
    log(line)
    if checker then checker:pushEvent(event, text) end
end

-- ---------------------------------------------------------------------------
-- the check
-- ---------------------------------------------------------------------------
local running = false

local function runCheck(triggeredBy)
    if running then
        emit("status", "A check is already running - ignoring this request.")
        return
    end
    running = true
    emit("status", ("Update check started (%s). Repo: %s/%s @ %s")
        :format(triggeredBy, RepoSync.USER, RepoSync.NAME, RepoSync.BRANCH))

    fetchRemote(RepoSync.API_TREE_URL,
        {
            headers            = RepoSync.API_HEADERS,
            connectionAttempts = 2,
            connectTimeout     = 20000,
        },
        function(data, info)
            running = false

            local httpOk = (type(info) == "table" and info.success and info.statusCode == 200)
                        or (type(info) == "number" and info == 0)
            if not httpOk then
                local code = (type(info) == "table") and tostring(info.statusCode) or tostring(info)
                emit("error", "Could not fetch the repo tree from GitHub (HTTP " .. code .. ").")
                return
            end

            local parsed = fromJSON(data)
            if type(parsed) ~= "table" or type(parsed.tree) ~= "table" then
                emit("error", "Could not parse the GitHub tree response.")
                return
            end
            if parsed.truncated then
                emit("status", "WARNING: GitHub returned a TRUNCATED tree - some files were not checked.")
            end

            local roots = RepoSync.buildResourceRoots(parsed.tree)

            local checked, outdated, missing, ignored, notInstalled = 0, 0, 0, 0, 0

            for _, entry in ipairs(parsed.tree) do
                if entry.type == "blob" and entry.path and entry.sha then
                    local repoPath = entry.path

                    if RepoSync.isIgnored(repoPath) then
                        ignored = ignored + 1
                    else
                        local resName, subPath = RepoSync.mapToResource(repoPath, roots)
                        if not resName or not getResourceFromName(resName) then
                            notInstalled = notInstalled + 1
                        else
                            local localData = RepoSync.readLocalFile(":" .. resName .. "/" .. subPath)
                            if not localData then
                                missing = missing + 1
                                emit("missing", repoPath)
                            else
                                checked = checked + 1
                                if not RepoSync.contentMatches(localData, entry.sha) then
                                    outdated = outdated + 1
                                    emit("outdated", repoPath)
                                end
                            end
                        end
                    end
                end
            end

            emit("complete", ("Done. checked: %d, outdated: %d, missing locally: %d, ignored: %d, not installed here: %d.")
                :format(checked, outdated, missing, ignored, notInstalled))

            if outdated == 0 and missing == 0 then
                emit("status", "All checked files are up to date with the repo.")
            else
                emit("status", "Run 'updateresources' (or 'git pull') to bring the files above up to date.")
            end
        end
    )
end

-- ---------------------------------------------------------------------------
-- triggers
-- ---------------------------------------------------------------------------
addEventHandler("onResourceStart", resourceRoot, function()
    local setting = get("enableUpdateChecker")
    if setting == false or setting == "false" then
        log("Update checker disabled via the enableUpdateChecker setting.")
        return
    end
    setTimer(function() runCheck("on start") end, 5000, 1)
end)

addCommandHandler("checkupdates", function(player)
    if player then return end -- console only
    runCheck("manual")
end, false, false)
