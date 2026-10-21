if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- /news editor backend. Every request re-checks the admin level. Dates travel
-- as text in the server's local time ("YYYY.MM.DD", "HH:MM"), converted here.

addEvent("v_news:save", true)
addEvent("v_news:delete", true)
addEvent("v_news:close", true)

local editors = {}   -- [player] = true while the editor is open

local function isAdmin(player)
    if not isElement(player) or getElementData(player, "isLogged") ~= true then return false end
    return (tonumber(exports.v_mysql:getAccData(player, "admin_level")) or 0) >= NEWS.ADMIN_LEVEL
end

-- days since 1970-01-01 of a calendar date (proleptic Gregorian)
local function daysFromCivil(y, m, d)
    y = m <= 2 and y - 1 or y
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local doy = math.floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

local function fieldsToSeconds(t)
    return daysFromCivil(t.year + 1900, t.month + 1, t.monthday) * 86400 + t.hour * 3600 + t.minute * 60 + t.second
end

-- seconds the server's local time is ahead of UTC (getRealTime is local time)
local function utcOffset()
    local ts = getRealTime().timestamp
    return fieldsToSeconds(getRealTime(ts)) - ts
end

local function formatDate(ts)
    local t = getRealTime(ts)
    return ("%04d.%02d.%02d"):format(t.year + 1900, t.month + 1, t.monthday), ("%02d:%02d"):format(t.hour, t.minute)
end

-- "YYYY.MM.DD", "HH:MM" (local) -> unix timestamp or nil
local function parseDate(dateText, timeText)
    local y, mo, d = tostring(dateText or ""):match("^%s*(%d%d%d%d)[%.%-/](%d%d?)[%.%-/](%d%d?)%.?%s*$")
    local h, mi = tostring(timeText or ""):match("^%s*(%d%d?):(%d%d)%s*$")
    y, mo, d, h, mi = tonumber(y), tonumber(mo), tonumber(d), tonumber(h), tonumber(mi)
    if not (y and mo and d and h and mi) then return nil end
    if y < 2000 or y > 2100 or mo < 1 or mo > 12 or d < 1 or d > 31 or h > 23 or mi > 59 then return nil end
    local days = daysFromCivil(y, mo, d)
    -- reject e.g. 2026.02.31: the day must stay inside the month
    local nextMonth = mo == 12 and daysFromCivil(y + 1, 1, 1) or daysFromCivil(y, mo + 1, 1)
    if days >= nextMonth then return nil end
    return days * 86400 + h * 3600 + mi * 60 - utcOffset()
end

local function listFor()
    local t, out = getRealTime().timestamp, {}
    for i, a in ipairs(STORE.all()) do
        local dateText, timeText = formatDate(a.date)
        out[i] = { id = a.id, dateText = dateText, timeText = timeText, title = a.title, body = a.body,
                   author = a.author, scheduled = a.date > t }
    end
    return out
end

local function push(player, selectId)
    local nowDate, nowTime = formatDate(getRealTime().timestamp)
    triggerClientEvent(player, "v_news:data", player, listFor(), nowDate, nowTime, selectId)
end

local function reply(player, ok, key, params)
    triggerClientEvent(player, "v_news:result", player, ok, L.msg(key, params))
end

addCommandHandler(NEWS.COMMAND, function(player)
    if not isAdmin(player) then return end
    if not STORE.isLoaded() and not STORE.load() then
        return reply(player, false, "v_news.server.not_ready")
    end
    editors[player] = true
    triggerClientEvent(player, "v_news:open", player)
    push(player)
end)

addEventHandler("v_news:save", root, function(id, dateText, timeText, title, body)
    local player = client
    if not isAdmin(player) or not editors[player] then return end
    id = tonumber(id)
    title = tostring(title or ""):gsub("[\r\n\t]", " "):gsub("^%s+", ""):gsub("%s+$", "")
    body = tostring(body or ""):gsub("\r\n?", "\n"):gsub("^%s+", ""):gsub("%s+$", "")

    if title == "" then return reply(player, false, "v_news.server.title_missing") end
    if (utf8.len(title) or #title) > NEWS.TITLE_MAX then
        return reply(player, false, "v_news.server.title_too_long", { max = NEWS.TITLE_MAX })
    end
    if body == "" then return reply(player, false, "v_news.server.text_missing") end
    if (utf8.len(body) or #body) > NEWS.BODY_MAX then
        return reply(player, false, "v_news.server.text_too_long", { max = NEWS.BODY_MAX })
    end
    local date = parseDate(dateText, timeText)
    if not date then return reply(player, false, "v_news.server.bad_date") end

    local saved = STORE.save(id, date, title, body, getPlayerName(player))
    if not saved then return reply(player, false, "v_news.server.save_failed") end
    outputServerLog(("[v_news] %s %s article #%d '%s'"):format(getPlayerName(player), id and "edited" or "added", saved, title))
    reply(player, true, "v_news.server.saved")
    for p in pairs(editors) do push(p, p == player and saved or nil) end
end)

addEventHandler("v_news:delete", root, function(id)
    local player = client
    if not isAdmin(player) or not editors[player] then return end
    id = tonumber(id)
    if not id or not STORE.delete(id) then return reply(player, false, "v_news.server.delete_failed") end
    outputServerLog(("[v_news] %s deleted article #%d"):format(getPlayerName(player), id))
    reply(player, true, "v_news.server.deleted")
    for p in pairs(editors) do push(p) end
end)

addEventHandler("v_news:close", root, function()
    editors[client] = nil
end)

addEventHandler("onPlayerQuit", root, function()
    editors[source] = nil
end)
