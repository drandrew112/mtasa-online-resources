-- Flagged scenes: scenes/issues.json next to index.json (written only here, by the own JSON writer).
--   /flagscene <reason...>  everyone, only within FLAG.RADIUS of a live scene (cleaned-up ones no longer count)
--   web Flag                the console (admins), any scene of the catalog
-- One open issue per scene: a second report is refused (and shows the open one). No admin notification; the editor's
-- "Check issues" menu and the web Issues panel list them, an admin marks them resolved.
--
-- issue = { id, scene, path, comment, lang, source = "command" | "web", by (account), byName, at, pos, instance,
--           server, status = "open" | "resolved", resolvedBy, resolvedAt }

Issues = { list = {}, seq = 0 }

local F = VSM.FLAG
local FORMAT = 1
local saveTimer
local lastFlag = {}   -- [player] = tick

addEvent("onSceneFlagged", false)

function Issues.load()
    Issues.list, Issues.seq = {}, 0
    local data = vsmDecodeJSON(vsmReadFile(VSM.ISSUES_FILE) or "")
    if not data then return end
    for _, i in ipairs(type(data.issues) == "table" and data.issues or {}) do
        if type(i) == "table" and tonumber(i.id) and type(i.scene) == "string" then
            i.id = math.floor(tonumber(i.id))
            i.status = i.status == "resolved" and "resolved" or "open"
            Issues.list[#Issues.list + 1] = i
            Issues.seq = math.max(Issues.seq, i.id)
        end
    end
    Issues.seq = math.max(Issues.seq, math.floor(tonumber(data.seq) or 0))
end

local function write()
    saveTimer = nil
    if not vsmWriteFile(VSM.ISSUES_FILE, vsmEncodeJSON({ format = FORMAT, seq = Issues.seq, issues = Issues.list })) then
        vsmLog("issues: could not write %s", VSM.ISSUES_FILE)
    end
end

local function save()
    if saveTimer and isTimer(saveTimer) then return end
    saveTimer = setTimer(write, F.SAVE_DELAY, 1)
end

-- the open issue of a scene | nil
function Issues.openFor(name)
    for _, i in ipairs(Issues.list) do
        if i.scene == name and i.status == "open" then return i end
    end
end

function Issues.get(id)
    id = tonumber(id)
    for _, i in ipairs(Issues.list) do
        if i.id == id then return i end
    end
end

-- status: "open" | "resolved" | nil (all); newest first
function Issues.query(status)
    local out = {}
    for _, i in ipairs(Issues.list) do
        if not status or i.status == status then out[#out + 1] = i end
    end
    table.sort(out, function(a, b) return a.id > b.id end)
    return out
end

-- open issue count per scene name
function Issues.openMap()
    local out = {}
    for _, i in ipairs(Issues.list) do
        if i.status == "open" then out[i.scene] = i end
    end
    return out
end

-- -> issue | false, error key, existing issue
function Issues.add(name, comment, info)
    if not Storage.exists(name) then return false, "v_scenemanager.err.unknown_scene" end
    comment = vsmCleanText(comment, F.MAX_LEN)
    if vsmTextLen(comment) < F.MIN_LEN then return false, "v_scenemanager.flag.too_short" end
    local open = Issues.openFor(name)
    if open then return false, "v_scenemanager.flag.already_open", open end
    Issues.seq = Issues.seq + 1
    local issue = {
        id = Issues.seq, scene = name, path = Storage.paths[name] or "", comment = comment, lang = info.lang or "en",
        source = info.source, by = info.by or "", byName = info.byName or "", at = vsmNow(),
        pos = info.pos or false, instance = info.instance or false,
        server = tostring(getServerName and getServerName() or "") .. ":" .. tostring(getServerPort and getServerPort() or ""),
        status = "open", resolvedBy = false, resolvedAt = false,
    }
    Issues.list[#Issues.list + 1] = issue
    save()
    vsmLog("scene '%s' flagged by %s (%s): %s", name, issue.byName, issue.source, comment)
    triggerEvent("onSceneFlagged", resourceRoot, issue)
    return issue
end

function Issues.resolve(id, by)
    local issue = Issues.get(id)
    if not issue or issue.status ~= "open" then return false end
    issue.status, issue.resolvedBy, issue.resolvedAt = "resolved", tostring(by or ""), vsmNow()
    save()
    vsmLog("issue #%d (%s) resolved by %s", issue.id, issue.scene, tostring(by))
    return true
end

-- every open issue of a scene resolved -> count
function Issues.resolveScene(name, by)
    local n = 0
    for _, i in ipairs(Issues.list) do
        if i.scene == name and i.status == "open" and Issues.resolve(i.id, by) then n = n + 1 end
    end
    return n
end

---------------------------------------------------------------- /flagscene

local function flagCommand(player, _, ...)
    if not isElement(player) or getElementType(player) ~= "player" then return end
    local comment = table.concat({ ... }, " ")
    if comment:gsub("%s", "") == "" then
        vsmNotify(player, "v_scenemanager.flag.title", "v_scenemanager.flag.usage", { cmd = VSM.CMD_FLAG })
        return
    end
    local last = lastFlag[player]
    if last and getTickCount() - last < F.COOLDOWN * 1000 then
        vsmNotify(player, "v_scenemanager.flag.title", "v_scenemanager.flag.wait",
            { seconds = math.ceil((F.COOLDOWN * 1000 - (getTickCount() - last)) / 1000) })
        return
    end
    local x, y, z = getElementPosition(player)
    local scene = Live.sceneAt(x, y, z, F.RADIUS, true)
    if not scene or getElementDimension(player) ~= scene.dimension then
        vsmNotify(player, "v_scenemanager.flag.title", "v_scenemanager.flag.no_scene", { radius = F.RADIUS })
        return
    end
    local issue, err, open = Issues.add(scene.name, comment, {
        source = "command", by = vsmAccount(player), byName = vsmPlayerName(player),
        pos = { vsmRound(x, 2), vsmRound(y, 2), vsmRound(z, 2) }, instance = scene.id,
        lang = L.lang and L.lang(player) or "en",
    })
    if not issue then
        vsmNotify(player, "v_scenemanager.flag.title", err, { comment = open and open.comment or "", min = F.MIN_LEN, max = F.MAX_LEN })
        return
    end
    lastFlag[player] = getTickCount()
    vsmNotify(player, "v_scenemanager.flag.title", "v_scenemanager.flag.saved", { name = scene.name })
end

addCommandHandler(VSM.CMD_FLAG, flagCommand)

addEventHandler("onPlayerQuit", root, function() lastFlag[source] = nil end)

---------------------------------------------------------------- v_chat command database

local function registerCommands()
    if not vsmResourceRunning("v_chat") then return end
    local ok, code = pcall(function() return exports.v_chat:importCommands() end)
    if not ok or type(code) ~= "string" then return end
    local fn = loadstring(code)
    if not fn then return end
    fn()
    CMD.register(VSM.CMD_FLAG, "<reason...>", 0, "v_scenemanager.cmd.desc_flagscene")
    local level = VSM.MIN_ADMIN_LEVEL
    CMD.register(VSM.CMD_EDITOR, "", level, "v_scenemanager.cmd.desc_editor")
    CMD.register(VSM.CMD_RANDOM, "[scene]", level, "v_scenemanager.cmd.desc_random")
    CMD.register(VSM.CMD_SUMMON, "", level, "v_scenemanager.cmd.desc_summon")
    CMD.register(VSM.CMD_AUTO, "[on|off]", level, "v_scenemanager.cmd.desc_auto")
    CMD.register(VSM.CMD_LIST, "", level, "v_scenemanager.cmd.desc_list")
    CMD.register(VSM.CMD_CLEAR, "[id|all]", level, "v_scenemanager.cmd.desc_clear")
    CMD.register(VSM.CMD_RELOAD, "", level, "v_scenemanager.cmd.desc_reload")
    CMD.register(VSM.CMD_VARIETY, "[sim [n]|clear]", level, "v_scenemanager.cmd.desc_variety")
end

addEventHandler("onResourceStart", resourceRoot, function()
    Issues.load()
    registerCommands()
end)

addEventHandler("onResourceStop", resourceRoot, function()
    if saveTimer and isTimer(saveTimer) then
        killTimer(saveTimer)
        write()
    end
end)
