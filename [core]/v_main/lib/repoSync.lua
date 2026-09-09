--[[
    lib/repoSync.lua
    ---------------------------------------------------------------------------
    Shared configuration + helper functions for comparing / syncing local
    resource files against the public GitHub repo.

    Used by:
      - updater.lua           read-only check   ("checkupdates" console command)
      - updateResources.lua   download + apply  ("updateresources" command)

    Keeping the repo config and the IGNORE lists in ONE place means the
    checker and the applier can never disagree about which files are tracked.
]]

RepoSync = {}

-- ---------------------------------------------------------------------------
-- Repo location
-- ---------------------------------------------------------------------------
RepoSync.USER   = "drandrew112"
RepoSync.NAME   = "mtasa-online-resources"
RepoSync.BRANCH = "main"

-- Whole file tree + git blob SHA-1 of every file, in one request.
RepoSync.API_TREE_URL = ("https://api.github.com/repos/%s/%s/git/trees/%s?recursive=1")
    :format(RepoSync.USER, RepoSync.NAME, RepoSync.BRANCH)

-- Raw file contents. Does NOT count against the GitHub API rate limit.
RepoSync.RAW_BASE_URL = ("https://raw.githubusercontent.com/%s/%s/%s/")
    :format(RepoSync.USER, RepoSync.NAME, RepoSync.BRANCH)

RepoSync.API_HEADERS = {
    ["User-Agent"] = "mtasa-online-updater",
    ["Accept"]     = "application/vnd.github+json",
}
RepoSync.RAW_HEADERS = {
    ["User-Agent"] = "mtasa-online-updater",
}

-- ---------------------------------------------------------------------------
-- IGNORE list - repo-relative paths we never compare and never write.
-- Mirrors resources/.gitignore (runtime data + credentials).
-- ---------------------------------------------------------------------------
local IGNORE_PREFIX = {
    "[tiktok]/",
    "[core]/v_modloader/",
    -- MTA's database-credentials protection blocks other resources from
    -- reading/writing v_mysql's files, so we cannot touch them from here.
    "[core]/v_mysql/",
}
local IGNORE_EXACT = {
    ["[core]/v_accounts/bans.xml"]                      = true,
    ["[player_interaction]/v_socialpanel/crews.xml"]    = true,
    ["[player_interaction]/v_socialpanel/messages.xml"] = true,
    ["[core]/v_mysql/config.lua"]                       = true,
    ["[vehicles]/v_ownveh/vehiclespawnpoints.txt"]      = true,
}
local IGNORE_SUFFIX   = { ".old", ".bak", ".orig", "~" }
local IGNORE_BASENAME = { ["Thumbs.db"] = true, ["desktop.ini"] = true }

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- git blob SHA-1:  sha1("blob " .. bytelength .. "\0" .. content)
function RepoSync.gitBlobSha(content)
    return hash("sha1", "blob " .. #content .. "\0" .. content)
end

function RepoSync.basename(path)
    return path:match("([^/]+)$") or path
end

function RepoSync.isIgnored(repoPath)
    if IGNORE_EXACT[repoPath] then return true end
    if IGNORE_BASENAME[RepoSync.basename(repoPath)] then return true end
    for _, p in ipairs(IGNORE_PREFIX) do
        if repoPath:sub(1, #p) == p then return true end
    end
    for _, s in ipairs(IGNORE_SUFFIX) do
        if repoPath:sub(-#s) == s then return true end
    end
    return false
end

-- Percent-encode a repo path for use in a raw.githubusercontent.com URL
-- (resource-category folders such as "[core]" contain URL-reserved chars).
function RepoSync.encodePath(path)
    return (path:gsub("[^%w%-%._~/]", function(c)
        return ("%%%02X"):format(c:byte())
    end))
end

function RepoSync.readLocalFile(mtaPath)
    if not fileExists(mtaPath) then return nil end
    local f = fileOpen(mtaPath, true)
    if not f then return nil end
    local size = fileGetSize(f)
    local data = (size and size > 0) and fileRead(f, size) or ""
    fileClose(f)
    return data
end

-- core.autocrlf is "true" on this checkout, so a text file has CRLF in the
-- working tree but LF in the git blob. Accept either form.
function RepoSync.contentMatches(data, repoSha)
    if RepoSync.gitBlobSha(data) == repoSha then return true end
    if data:find("\r\n", 1, true)
        and RepoSync.gitBlobSha((data:gsub("\r\n", "\n"))) == repoSha then
        return true
    end
    return false
end

-- Resource roots = directories that directly contain a meta.xml.
-- Returned longest-first so the most specific root wins.
function RepoSync.buildResourceRoots(tree)
    local roots = {}
    for _, entry in ipairs(tree) do
        if entry.type == "blob" and entry.path then
            local dir = entry.path:match("^(.+)/meta%.xml$")
            if dir then
                roots[#roots + 1] = { dir = dir, name = RepoSync.basename(dir) }
            end
        end
    end
    table.sort(roots, function(a, b) return #a.dir > #b.dir end)
    return roots
end

-- repoPath -> (resourceName, subPathInsideResource) or nil
function RepoSync.mapToResource(repoPath, roots)
    for _, r in ipairs(roots) do
        local prefix = r.dir .. "/"
        if repoPath:sub(1, #prefix) == prefix then
            return r.name, repoPath:sub(#prefix + 1)
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Sanity check: MTA's hash() must produce git-compatible blob hashes
-- ---------------------------------------------------------------------------
if hash("sha1", "blob 0\0") ~= "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391" then
    outputServerLog("[v_main:repoSync] WARNING: hash('sha1', ...) is not "
        .. "git-blob compatible on this build - update results may be unreliable.")
end
