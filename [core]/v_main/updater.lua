--[[
    updater.lua
    ---------------------------------------------------------------------------
    Server-wide update *checker*, based on the public GitHub repo:

        https://github.com/drandrew112/mtasa-online-resources

    It does NOT download or modify anything - it only reports which local
    files differ from the repo (or are missing locally), so you know what a
    "git pull" would change.

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
      - Files on the IGNORE list below are skipped. The list mirrors
        resources/.gitignore (runtime data + credentials).
      - core.autocrlf is "true" on this checkout, so text files have CRLF in
        the working tree but LF in the git blob. We therefore accept a file
        as up to date if either the raw bytes OR the CRLF->LF normalised
        bytes hash to the repo's blob SHA-1.

    Triggers:
      - Automatically on v_main start, unless the "enableUpdateChecker"
        setting (meta.xml) is [false].
      - Manually from the server console:   checkupdates

    Uses the GitHub updater library under lib/updater/ (classes.lua + the
    Updater class) for the repo config and the event/logging plumbing.
]]

local REPO_USER   = "drandrew112"
local REPO_NAME   = "mtasa-online-resources"
local REPO_BRANCH = "main"

local API_TREE_URL = ("https://api.github.com/repos/%s/%s/git/trees/%s?recursive=1")
    :format(REPO_USER, REPO_NAME, REPO_BRANCH)

-- ---------------------------------------------------------------------------
-- IGNORE list - repo-relative paths we never compare (see resources/.gitignore)
-- ---------------------------------------------------------------------------
local IGNORE_PREFIX = {
    "[tiktok]/",
    "[core]/v_modloader/",
}
local IGNORE_EXACT = {
    ["[core]/v_accounts/bans.xml"]                      = true,
    ["[player_interaction]/v_socialpanel/crews.xml"]    = true,
    ["[player_interaction]/v_socialpanel/messages.xml"] = true,
    ["[core]/v_mysql/config.lua"]                       = true,
}
local IGNORE_SUFFIX   = { ".old", ".bak", ".orig", "~" }
local IGNORE_BASENAME = { ["Thumbs.db"] = true, ["desktop.ini"] = true }

local function log(msg)
    outputServerLog("[v_main:updater] " .. tostring(msg))
end

-- ---------------------------------------------------------------------------
-- lib/updater - reuse the Updater class for repo config + event plumbing
-- ---------------------------------------------------------------------------
local checker
if type(updater) == "table" and type(load) == "function" then
    checker = load(updater)
    checker:setDetails({ user = REPO_USER, repo = REPO_NAME, branch = REPO_BRANCH, private = false })
    checker:setDebug(true) -- silence the built-in "progress" print path
    checker:on("status",   function(m) log(m) end)
    checker:on("error",    function(e) log("ERROR: " .. tostring(e)) end)
    checker:on("outdated", function(p) log("outdated : " .. p) end)
    checker:on("missing",  function(p) log("missing  : " .. p .. "   (in repo, not found locally)") end)
    checker:on("complete", function(m) log(m) end)
else
    log("WARNING: lib/updater not loaded - falling back to plain logging.")
end

local function emit(event, text)
    if checker and checker.events[event] then
        checker:pushEvent(event, text)
    else
        log(text)
    end
end

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------

-- git blob SHA-1:  sha1("blob " .. bytelength .. "\0" .. content)
local function gitBlobSha(content)
    return hash("sha1", "blob " .. #content .. "\0" .. content)
end

local function basename(path)
    return path:match("([^/]+)$") or path
end

local function isIgnored(repoPath)
    if IGNORE_EXACT[repoPath] then return true end
    if IGNORE_BASENAME[basename(repoPath)] then return true end
    for _, p in ipairs(IGNORE_PREFIX) do
        if repoPath:sub(1, #p) == p then return true end
    end
    for _, s in ipairs(IGNORE_SUFFIX) do
        if repoPath:sub(-#s) == s then return true end
    end
    return false
end

local function readLocalFile(mtaPath)
    if not fileExists(mtaPath) then return nil end
    local f = fileOpen(mtaPath, true)
    if not f then return nil end
    local size = fileGetSize(f)
    local data = (size and size > 0) and fileRead(f, size) or ""
    fileClose(f)
    return data
end

local function localMatches(data, repoSha)
    if gitBlobSha(data) == repoSha then return true end
    if data:find("\r\n", 1, true) and gitBlobSha((data:gsub("\r\n", "\n"))) == repoSha then
        return true
    end
    return false
end

-- Resource roots = directories that directly contain a meta.xml.
-- Returned longest-first so the most specific root wins.
local function buildResourceRoots(tree)
    local roots = {}
    for _, entry in ipairs(tree) do
        if entry.type == "blob" and entry.path then
            local dir = entry.path:match("^(.+)/meta%.xml$")
            if dir then
                roots[#roots + 1] = { dir = dir, name = basename(dir) }
            end
        end
    end
    table.sort(roots, function(a, b) return #a.dir > #b.dir end)
    return roots
end

-- repoPath -> (resourceName, subPathInsideResource) or nil
local function mapToResource(repoPath, roots)
    for _, r in ipairs(roots) do
        local prefix = r.dir .. "/"
        if repoPath:sub(1, #prefix) == prefix then
            return r.name, repoPath:sub(#prefix + 1)
        end
    end
    return nil
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
        :format(triggeredBy, REPO_USER, REPO_NAME, REPO_BRANCH))

    fetchRemote(API_TREE_URL,
        {
            headers = {
                ["User-Agent"] = "mtasa-online-updater",
                ["Accept"]     = "application/vnd.github+json",
            },
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

            local roots = buildResourceRoots(parsed.tree)

            local checked, outdated, missing, ignored, notInstalled = 0, 0, 0, 0, 0

            for _, entry in ipairs(parsed.tree) do
                if entry.type == "blob" and entry.path and entry.sha then
                    local repoPath = entry.path

                    if isIgnored(repoPath) then
                        ignored = ignored + 1
                    else
                        local resName, subPath = mapToResource(repoPath, roots)
                        if not resName or not getResourceFromName(resName) then
                            notInstalled = notInstalled + 1
                        else
                            local localData = readLocalFile(":" .. resName .. "/" .. subPath)
                            if not localData then
                                missing = missing + 1
                                emit("missing", repoPath)
                            else
                                checked = checked + 1
                                if not localMatches(localData, entry.sha) then
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
                emit("status", "Run 'git pull' in the resources folder to bring the files above up to date.")
            end
        end
    )
end

-- ---------------------------------------------------------------------------
-- sanity check: MTA's hash() must produce git-compatible blob hashes
-- ---------------------------------------------------------------------------
if hash("sha1", "blob 0\0") ~= "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391" then
    log("WARNING: hash('sha1', ...) is not git-blob compatible on this build - results may be unreliable.")
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
