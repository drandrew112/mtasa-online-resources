-- Web console (web/index.html, http://<server>:<httpport>/v_scenemanager/): the browser
-- twin of /scenesummon + /scenelist + /sceneclear, plus Flag scene and the Issues panel. Login with the v_accounts
-- account (httpLogin); VSM.MIN_ADMIN_LEVEL is re-checked on every call. English + Hungarian: the page asks
-- vsmWebTexts(lang) for its texts (v_locals keys v_scenemanager.web.*).

local SESSION_TIMEOUT = 15 * 60
local LEVEL_CACHE = 10          -- seconds an admin level lookup is reused
local MAX_FAILS, FAIL_WINDOW = 5, 60

local sessions = {}             -- [token] = { account, lastSeen, level, levelAt }
local fails = {}                -- [client] = { timestamps }
local DENIED = { ok = false, error = "unauthorized" }

local function now() return getRealTime().timestamp end

local function accountsRunning()
    local res = getResourceFromName("v_accounts")
    return res and getResourceState(res) == "running"
end

local function adminLevelOf(account)
    if accountsRunning() then
        for _, p in ipairs(getElementsByType("player")) do
            if exports.v_accounts:getName(p) == account then
                return tonumber(exports.v_mysql:getAccData(p, "admin_level")) or 0
            end
        end
    end
    local rows = exports.v_mysql:mysqlQuerySync("SELECT admin_level FROM `accounts` WHERE account_name = ? LIMIT 1", account)
    return rows and rows[1] and tonumber(rows[1].admin_level) or 0
end

local function displayNameOf(account)
    for _, p in ipairs(getElementsByType("player")) do
        if getElementData(p, "accName") == account then return vsmPlayerName(p), p end
    end
    return account
end

local function callerId()
    return exports.web_api:getCallerId(hostname)
end

local function tooManyFails(id)
    local t, keep = now(), {}
    for _, ts in ipairs(fails[id] or {}) do
        if t - ts < FAIL_WINDOW then keep[#keep + 1] = ts end
    end
    fails[id] = keep
    return #keep >= MAX_FAILS
end

local function newToken(account)
    return hash("sha256", table.concat({
        tostring(getTickCount()), tostring(now()), account,
        tostring(math.random(1, 2 ^ 30)), tostring(math.random(1, 2 ^ 30)),
    }, ":"))
end

local function check(token)
    local s = type(token) == "string" and sessions[token]
    if not s then return nil end
    local t = now()
    if t - s.lastSeen > SESSION_TIMEOUT then
        sessions[token] = nil
        return nil
    end
    s.lastSeen = t
    if t - s.levelAt > LEVEL_CACHE then
        s.level, s.levelAt = adminLevelOf(s.account), t
    end
    if s.level < VSM.MIN_ADMIN_LEVEL then
        sessions[token] = nil
        return nil
    end
    return s
end

setTimer(function()
    local t = now()
    for token, s in pairs(sessions) do
        if t - s.lastSeen > SESSION_TIMEOUT then sessions[token] = nil end
    end
end, 60000, 0)

local function lang(code)
    for _, l in ipairs(VSM.LANGS) do
        if l == code then return l end
    end
    return VSM.DEFAULT_LANG
end

local function text(code, key, params)
    return tostring(L.forLang(lang(code), key, params))
end

---------------------------------------------------------------- texts

-- every key of the page (web/js/scenes.js T("..."))
local WEB_KEYS = {
    "title", "subtitle", "sign_in_hint", "username", "password", "sign_in", "sign_out", "login_failed", "unreachable",
    "too_many", "no_accounts", "need_admin", "auto_on", "auto_off", "search", "all_places", "all_categories",
    "all_agencies", "agency_ems", "agency_pd", "has_issues", "scenes_count", "scenes_more", "no_match", "spawn",
    "active", "interior", "active_scenes", "issues", "remove", "remove_all", "remove_all_confirm", "remove_all_yes",
    "no_active", "task_closed", "no_task", "units", "patients", "flag", "flagged", "flag_title", "flag_placeholder",
    "flag_send", "cancel", "flag_saved", "flag_exists", "flag_short", "open", "resolved", "resolve", "copy_name",
    "copied", "no_issues", "issue_meta", "instance", "source_command", "source_web", "stats", "erm_down",
    "status_unassigned", "status_prioritized", "status_assigned", "status_closed", "not_safe", "safe", "late",
    "invalid", "spawned", "request_failed", "need_short_0", "need_short_1", "need_short_2", "ped_veh", "resolved_by",
}

-- vsmWebTexts(lang) -> { ok, lang, texts = { [short key] = text } } (no login needed: the login form uses it too)
function vsmWebTexts(code)
    local out = {}
    for _, k in ipairs(WEB_KEYS) do out[k] = text(code, "v_scenemanager.web." .. k) end
    return { ok = true, lang = lang(code), langs = VSM.LANGS, texts = out }
end

---------------------------------------------------------------- http exports

function vsmWebLogin(_, username, password, code)
    local id = callerId()
    if tooManyFails(id) then return { ok = false, error = text(code, "v_scenemanager.web.too_many") } end
    if not accountsRunning() then return { ok = false, error = text(code, "v_scenemanager.web.no_accounts") } end

    local ok, account = exports.v_accounts:httpLogin(username, password)
    local level = ok and adminLevelOf(account) or 0
    if not ok or level < VSM.MIN_ADMIN_LEVEL then
        table.insert(fails[id], now())
        vsmLog("failed web login from %s", id)
        return { ok = false, error = ok and text(code, "v_scenemanager.web.need_admin", { level = VSM.MIN_ADMIN_LEVEL }) or tostring(account) }
    end

    local token = newToken(account)
    sessions[token] = { account = account, lastSeen = now(), level = level, levelAt = now() }
    vsmLog("web login: %s (%s)", account, id)
    local name, player = displayNameOf(account)
    local playerLang = player and L.lang and L.lang(player) or nil
    return { ok = true, token = token, account = account, name = name, level = level, lang = playerLang }
end

function vsmWebLogout(token)
    sessions[token] = nil
    return { ok = true }
end

-- every scene as a compact row (the browser filters them itself):
-- { name, location, category, title en, priority, peds, vehicles, enabled, interior, title hu, ems need, pd need,
--   safe, valid, open issue comment | false }
function vsmWebScenes(token)
    if not check(token) then return DENIED end
    local open = Issues.openMap()
    local rows = {}
    for _, s in ipairs(Storage.list()) do
        local issue = open[s.name]
        rows[#rows + 1] = {
            s.name, s.location or "", s.category or "", Storage.title(s, "en"), s.priority or 0,
            s.peds or 0, s.vehicles or 0, s.enabled ~= false, (s.interior or 0) ~= 0, Storage.title(s, "hu"),
            s.needs.ems or 0, s.needs.pd or 0, s.safe ~= false, s.valid ~= false,
            issue and { issue.comment, issue.byName, issue.at } or false,
        }
    end
    return { ok = true, scenes = rows }
end

local function ermRunning()
    local res = getResourceFromName(VSM.ERM)
    return res and getResourceState(res) == "running"
end

-- live scenes + generator state; polled by the page
function vsmWebState(token)
    if not check(token) then return DENIED end
    local free = Auto.freeCounts()
    local out = { ok = true, time = now(), scenes = {}, erm = ermRunning() and true or false, free = free.ems or 0,
                  freePd = free.pd or 0, auto = Auto.enabled, issues = #Issues.query("open") }
    for _, scene in pairs(Live.scenes) do
        local pub = Live.public(scene)
        local s = Storage.summary[scene.name]
        pub.title = s and Storage.title(s, "en") or ""
        pub.titleHu = s and Storage.title(s, "hu") or ""
        pub.ageSec = math.floor((getTickCount() - scene.createdAt) / 1000)
        local ems = scene.tasks.ems
        if ems and out.erm then
            local task = Agencies.call(VSM.ERM, "getTask", ems.id)
            if task then
                pub.taskStatus = task.status
                pub.units = type(task.units) == "table" and #task.units or 0
            end
        end
        local pd = scene.tasks.pd
        if pd then
            local call = Agencies.call(VSM.POLICE, "getCall", pd.id)
            if call then
                pub.callStatus = call.status
                pub.callUnits = #(call.units or {})
            end
        end
        out.scenes[#out.scenes + 1] = pub
    end
    table.sort(out.scenes, function(a, b) return a.id < b.id end)
    return out
end

function vsmWebSpawn(token, name)
    local s = check(token)
    if not s then return DENIED end
    local id, err = Live.spawn(tostring(name), "web:" .. s.account)
    if not id then return { ok = false, error = tostring(err) } end
    return { ok = true, id = id, warning = err and tostring(err) or nil }
end

function vsmWebRemove(token, id)
    local s = check(token)
    if not s then return DENIED end
    if id == "all" then
        local ids = {}
        for sid in pairs(Live.scenes) do ids[#ids + 1] = sid end
        for _, sid in ipairs(ids) do Live.remove(sid, "web: " .. s.account) end
        return { ok = true, removed = #ids }
    end
    if not Live.remove(tonumber(id), "web: " .. s.account) then
        return { ok = false, error = "not_found" }
    end
    return { ok = true, removed = 1 }
end

function vsmWebAuto(token, on)
    local s = check(token)
    if not s then return DENIED end
    Auto.setEnabled(on == true, "web " .. s.account)
    return { ok = true, auto = Auto.enabled }
end

---------------------------------------------------------------- issues

-- vsmWebFlag(token, scene, comment, lang) -> { ok, id } | { ok = false, error, existing }
function vsmWebFlag(token, name, comment, code)
    local s = check(token)
    if not s then return DENIED end
    local live
    for _, scene in pairs(Live.scenes) do
        if scene.name == tostring(name) then live = scene end
    end
    local issue, err, open = Issues.add(tostring(name), comment, {
        source = "web", by = s.account, byName = (displayNameOf(s.account)), lang = lang(code),
        instance = live and live.id or false,
    })
    if not issue then
        return { ok = false, error = text(code, err, { min = VSM.FLAG.MIN_LEN, max = VSM.FLAG.MAX_LEN, comment = open and open.comment or "", name = tostring(name) }),
                 existing = open and { open.comment, open.byName, open.at } or false }
    end
    return { ok = true, id = issue.id }
end

-- vsmWebIssues(token, status) -> { ok, issues = { { id, scene, comment, byName, at, source, instance, status, resolvedBy, resolvedAt } } }
function vsmWebIssues(token, status)
    if not check(token) then return DENIED end
    local out = {}
    for _, i in ipairs(Issues.query(status == "resolved" and "resolved" or "open")) do
        out[#out + 1] = { id = i.id, scene = i.scene, comment = i.comment, byName = i.byName, at = i.at, source = i.source,
                          instance = i.instance or false, status = i.status, resolvedBy = i.resolvedBy or "", resolvedAt = i.resolvedAt or 0 }
        if #out >= 200 then break end
    end
    return { ok = true, issues = out, open = #Issues.query("open"), resolved = #Issues.query("resolved") }
end

function vsmWebResolveIssue(token, id)
    local s = check(token)
    if not s then return DENIED end
    if not Issues.resolve(id, s.account) then return { ok = false, error = "not_found" } end
    return { ok = true }
end
