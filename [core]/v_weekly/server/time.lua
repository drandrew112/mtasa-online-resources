-- Europe/Budapest week arithmetic. MTA has no tz database, so the EU DST rule
-- is computed by hand: CEST (UTC+2) from the last Sunday of March 01:00 UTC to
-- the last Sunday of October 01:00 UTC, CET (UTC+1) otherwise.

local DAY = 86400

-- days since 1970-01-01 for a civil date (Howard Hinnant's algorithm)
local function daysFromCivil(y, m, d)
    if m <= 2 then y = y - 1 end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local mp = (m + 9) % 12
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

-- 0 = Sunday
local function weekday(days) return (days + 4) % 7 end

local function lastSundayDays(y, m)
    local last = daysFromCivil(y, m, 31) -- March and October both have 31 days
    return last - weekday(last)
end

local function utcYear(ts) return os.date("!*t", ts).year end

-- Budapest UTC offset (seconds) at the UTC instant `ts`
function tzOffset(ts)
    local y = utcYear(ts)
    local dstStart = lastSundayDays(y, 3) * DAY + 3600
    local dstEnd   = lastSundayDays(y, 10) * DAY + 3600
    if ts >= dstStart and ts < dstEnd then return 7200 end
    return 3600
end

-- UTC start of the week containing `ts`
function weekStartFor(ts)
    local localNow = ts + tzOffset(ts)
    local days = math.floor(localNow / DAY)
    local secOfDay = localNow - days * DAY
    local back = (weekday(days) - WEEKLY.WEEK_DAY) % 7
    if back == 0 and secOfDay < WEEKLY.WEEK_HOUR * 3600 then back = 7 end
    local localStart = (days - back) * DAY + WEEKLY.WEEK_HOUR * 3600
    return localStart - tzOffset(localStart - 7200)
end

-- offset 0 = week containing `now`, 1 = next week ... (can be negative)
function weekStartAt(offset, now)
    local cur = weekStartFor(now or getRealTime().timestamp)
    if offset == 0 then return cur end
    return weekStartFor(cur + offset * 7 * DAY + 3.5 * DAY)
end

function nextWeekStart(now)
    return weekStartAt(1, now)
end

-- "2026-10-13 10:00" in Budapest local time
function formatBudapest(ts)
    local t = os.date("!*t", ts + tzOffset(ts))
    return string.format("%04d-%02d-%02d %02d:%02d", t.year, t.month, t.day, t.hour, t.min)
end
