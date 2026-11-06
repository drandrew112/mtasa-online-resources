-- BNO (Hungarian ICD-10) database: bno/bno.db (SQLite, built offline by bno/build_bno.py from
-- [medical]/source/BNOTORZS.DBF + the WHO ICD-10 2019 XML). Read only: loaded into memory at start.
--
-- exports: searchBNO(query, lang, limit, filter) -> { { code, fmt, name, flag } }
--          getBNO(code) -> { code, fmt, hu, en, src, flag, sex, ageMin, ageMax, validTo, chapter } | false
--          checkDiagnosis(code, list, sex, age) -> true | false, reasonKey
-- client:  bno:search (query, lang) -> bno:results ; bno:names (codes) -> bno:names

BNO = { rows = {}, list = {}, ready = false }

local TODAY = (function()
    local t = getRealTime()
    return ("%04d%02d%02d"):format(t.year + 1900, t.month + 1, t.monthday)
end)()

-- accent-free lower case (the same as build_bno.py's search columns)
local FOLD = { ["á"] = "a", ["é"] = "e", ["í"] = "i", ["ó"] = "o", ["ö"] = "o", ["ő"] = "o", ["ú"] = "u", ["ü"] = "u", ["ű"] = "u",
    ["Á"] = "a", ["É"] = "e", ["Í"] = "i", ["Ó"] = "o", ["Ö"] = "o", ["Ő"] = "o", ["Ú"] = "u", ["Ü"] = "u", ["Ű"] = "u" }
function bnoFold(s)
    s = tostring(s or ""):gsub("[\195\197][\128-\191]", function(c) return FOLD[c] or c end)
    return s:lower()
end

local function load()
    local db = dbConnect("sqlite", "bno/bno.db")
    if not db then return outputDebugString("[med_docs] bno/bno.db missing (run bno/build_bno.py)", 1) end
    local q = dbQuery(db, "SELECT * FROM bno")
    local rows = q and dbPoll(q, -1) or {}
    destroyElement(db)
    BNO.rows, BNO.list = {}, {}
    for _, r in ipairs(rows) do
        local e = { code = r.code, fmt = r.code_fmt, hu = r.name_hu, en = r.name_en, src = r.en_source, flag = r.flag or "",
                    sex = r.sex or "", ageMin = tonumber(r.age_min) or 0, ageMax = tonumber(r.age_max) or 0,
                    validTo = tostring(r.valid_to or ""), chapter = r.chapter or "",
                    shu = r.search_hu or "", sen = r.search_en or "" }
        e.expired = e.validTo ~= "" and e.validTo < TODAY
        BNO.rows[e.code] = e
        BNO.list[#BNO.list + 1] = e
    end
    table.sort(BNO.list, function(a, b) return a.code < b.code end)
    BNO.ready = #BNO.list > 0
    outputDebugString(("[med_docs] BNO: %d codes"):format(#BNO.list))
end
addEventHandler("onResourceStart", resourceRoot, load)

function getBNO(code)
    local e = BNO.rows[tostring(code or "")]
    if not e then return false end
    return { code = e.code, fmt = e.fmt, hu = e.hu, en = e.en, src = e.src, flag = e.flag, sex = e.sex,
             ageMin = e.ageMin, ageMax = e.ageMax, validTo = e.validTo, chapter = e.chapter, expired = e.expired }
end

-- every word of the query must be in the code / name; code prefix matches come first; expired codes
-- are hidden (K37). filter = { sex = "m" | "f", age = n } hides codes that do not fit the patient.
function searchBNO(query, lang, limit, filter)
    limit = math.min(tonumber(limit) or 30, 100)
    local words = {}
    for w in bnoFold(query):gmatch("[^%s%.,]+") do words[#words + 1] = w end
    if #words == 0 then return {} end
    local en = lang == "en"
    local head, rest = {}, {}
    local codeQ = tostring(query or ""):upper():gsub("[%s%.]", "")
    for _, e in ipairs(BNO.list) do
        if not e.expired then
            local hay = en and e.sen or e.shu
            local ok = true
            for _, w in ipairs(words) do
                if not hay:find(w, 1, true) then ok = false break end
            end
            if ok and filter then
                if filter.sex and e.sex ~= "" and e.sex ~= filter.sex then ok = false end
                if filter.age and e.ageMax > 0 and (filter.age < e.ageMin or filter.age > e.ageMax) then ok = false end
            end
            if ok then
                local item = { code = e.code, fmt = e.fmt, name = en and e.en or e.hu, flag = e.flag }
                if codeQ ~= "" and e.code:sub(1, #codeQ) == codeQ then head[#head + 1] = item else rest[#rest + 1] = item end
                if #head >= limit then break end
            end
        end
    end
    local out = head
    for _, item in ipairs(rest) do
        if #out >= limit then break end
        out[#out + 1] = item
    end
    return out
end

-- Can the code be added to the diagnoses? list = the codes already there (max 5, no main one, K38).
-- A "*" (asterisk) code only next to a "+" (dagger) code (K36). -> true | false, reason key
function checkDiagnosis(code, list, sex, age)
    local e = BNO.rows[tostring(code or "")]
    if not e then return false, "bno_unknown" end
    if e.expired then return false, "bno_expired" end
    list = list or {}
    if #list >= 5 then return false, "bno_max" end
    for _, c in ipairs(list) do if c == code then return false, "bno_duplicate" end end
    if sex and e.sex ~= "" and e.sex ~= sex then return false, "bno_sex" end
    if age and e.ageMax > 0 and (age < e.ageMin or age > e.ageMax) then return false, "bno_age" end
    if e.flag == "*" then
        local dagger = false
        for _, c in ipairs(list) do local o = BNO.rows[c] if o and o.flag == "+" then dagger = true end end
        if not dagger then return false, "bno_asterisk" end
    end
    return true
end

-- the name of a code in a language (server side, e.g. documents written for a player)
function getBNOName(code, lang)
    local e = BNO.rows[tostring(code or "")]
    if not e then return tostring(code or "") end
    return lang == "en" and e.en or e.hu
end

---------------------------------------------------------------- client requests

addEvent("bno:search", true)
addEventHandler("bno:search", resourceRoot, function(query, lang, token, filter)
    if type(query) ~= "string" or #query > 60 then return end
    triggerClientEvent(client, "bno:results", resourceRoot, token, searchBNO(query, lang, 40, type(filter) == "table" and filter or nil))
end)

addEvent("bno:names", true)
addEventHandler("bno:names", resourceRoot, function(codes)
    if type(codes) ~= "table" then return end
    local out, n = {}, 0
    for _, code in ipairs(codes) do
        n = n + 1
        if n > 200 then break end
        local e = BNO.rows[tostring(code)]
        out[tostring(code)] = e and { e.hu, e.en, e.fmt, e.flag } or false
    end
    triggerClientEvent(client, "bno:names", resourceRoot, out)
end)
