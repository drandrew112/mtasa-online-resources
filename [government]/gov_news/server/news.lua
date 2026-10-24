-- gov_news / server/news.lua
-- Government news: a minister (or admin) writes one in every language the page offers (at least
-- one; a reader without its language gets the fallback like in v_news). Posting sends it as a
-- phone mail (ui_phone sendPhoneMail, kind "gov_news") to every account; deleting the news takes
-- the mails back too (deletePhoneMailGroup).
--
-- gov_news  one row per news; texts = JSON { [lang] = { title, body } }, mail_group = the
--           ui_phone group key of the sent mails

loadstring(exports.gov_core:importLib())()

local SCHEMA = {
    [[CREATE TABLE IF NOT EXISTS gov_news (
        id INT UNSIGNED NOT NULL AUTO_INCREMENT,
        texts MEDIUMTEXT NOT NULL,
        created_by VARCHAR(64) NOT NULL DEFAULT '',
        created_at INT UNSIGNED NOT NULL DEFAULT 0,
        mail_group VARCHAR(64) NOT NULL DEFAULT '',
        deleted_at INT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (id),
        KEY idx_list (deleted_at, id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

local function int(v) return DB.int(v) end

local TITLE_MAX = 120   -- = ui_phone SUBJECT_MAX
local BODY_MAX = 4000   -- = ui_phone BODY_MAX

addEvent("onGovNewsPosted", false)   -- (newsId, texts)

local function trim(s) return (tostring(s or ""):gsub("\r\n", "\n"):gsub("^%s+", ""):gsub("%s+$", "")) end

--- { { value = "en", label = "English" }, ... } the page asks a title + text for
function GOV.newsLanguages()
    local ok, list = pcall(function() return exports.v_locals:getLanguages() end)
    local out = {}
    for _, l in ipairs(ok and type(list) == "table" and list or {}) do
        if type(l) == "table" and type(l.value) == "string" then out[#out + 1] = { value = l.value, label = tostring(l.label or l.value) } end
    end
    if #out == 0 then out[1] = { value = "en", label = "English" } end
    return out
end

local function fromRow(r)
    local texts = fromJSON(tostring(r.texts or "")) or {}
    return { id = int(r.id), texts = type(texts) == "table" and texts or {}, createdBy = tostring(r.created_by or ""),
        createdAt = int(r.created_at), mailed = tostring(r.mail_group or "") ~= "" }
end

--- cb(list) newest first (deleted ones left out)
function GOV.newsList(cb)
    DB.query(function(rows)
        local list = {}
        for i, r in ipairs(rows or {}) do list[i] = fromRow(r) end
        cb(list)
    end, "SELECT id, texts, created_by, created_at, mail_group FROM gov_news WHERE deleted_at = 0 ORDER BY id DESC LIMIT 100")
end

local function sender(lang)
    local ok, s = pcall(function() return exports.v_locals:translate(lang, "gov_news.mail.sender") end)
    return ok and type(s) == "string" and s ~= "" and s ~= "gov_news.mail.sender" and s or "Government of San Andreas"
end

--- { texts = { [lang] = { title, body } } } -> cb(true) | cb(false, err)
function GOV.postNews(args, actor, cb)
    local texts, count = {}, 0
    local src = type(args.texts) == "table" and args.texts or {}
    for _, l in ipairs(GOV.newsLanguages()) do
        local t = type(src[l.value]) == "table" and src[l.value] or {}
        local title, body = trim(t.title), trim(t.body)
        if title ~= "" or body ~= "" then
            if title == "" or (utf8.len(title) or #title) > TITLE_MAX then return cb(false, "news_title") end
            if body == "" or (utf8.len(body) or #body) > BODY_MAX then return cb(false, "news_body") end
            texts[l.value] = { title = title, body = body }
            count = count + 1
        end
    end
    if count == 0 then return cb(false, "news_empty") end

    MYSQL.insert(function(id, err)
        id = tonumber(id)
        if not id then
            outputDebugString("[gov_news] news insert failed: " .. tostring(err), 1)
            return cb(false, "db")
        end
        local mail = { kind = "gov_news", sender = sender("en"), texts = {} }
        for code, t in pairs(texts) do mail.texts[code] = { subject = t.title, body = t.body, sender = sender(code) } end
        local sent, group = false, nil
        if isResourceRunning("ui_phone") then sent, group = exports.ui_phone:sendPhoneMail("all", mail) end
        if sent then
            DB.exec("UPDATE gov_news SET mail_group = ? WHERE id = ?", DB.clip(group, 64), id)
        else
            outputDebugString("[gov_news] news #" .. id .. " not mailed: " .. tostring(group or "ui_phone not running"), 2)
        end
        local first = texts.en or select(2, next(texts))
        GOV.log(actor, "news.post", { id = id, title = DB.clip(first.title, 80) })
        triggerEvent("onGovNewsPosted", resourceRoot, id, texts)
        cb(true)
    end, "INSERT INTO gov_news (texts, created_by, created_at) VALUES (?, ?, ?)", toJSON(texts, true), DB.clip(actor, 64), GOV.now())
end

--- hides the news and takes its phone mails back
function GOV.deleteNews(id, actor, cb)
    id = math.floor(tonumber(id) or 0)
    DB.query(function(rows)
        local r = rows and rows[1]
        if not r then return cb(false, "news_unknown") end
        DB.query(function(ok)
            if ok == false then return cb(false, "db") end
            local group = tostring(r.mail_group or "")
            if group ~= "" and isResourceRunning("ui_phone") then exports.ui_phone:deletePhoneMailGroup(group) end
            GOV.log(actor, "news.delete", { id = id })
            cb(true)
        end, "UPDATE gov_news SET deleted_at = ? WHERE id = ? AND deleted_at = 0", GOV.now(), id)
    end, "SELECT id, mail_group FROM gov_news WHERE id = ? AND deleted_at = 0", id)
end

addEventHandler("onResourceStart", resourceRoot, function()
    DB.start(SCHEMA)
end)
