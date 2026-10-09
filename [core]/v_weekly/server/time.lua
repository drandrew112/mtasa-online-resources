-- Week arithmetic in plain UTC (no time zone, no DST). A week runs from
-- WEEKLY.WEEK_DAY at WEEKLY.WEEK_HOUR o'clock UTC to the same moment 7 days later.

local DAY = 86400
local WEEK = 7 * DAY

-- UTC start of the week containing `ts`. 1970-01-01 was a Thursday, so
-- weekday = (days + 4) % 7 with 0 = Sunday.
function weekStartFor(ts)
    local days = math.floor(ts / DAY)
    local secOfDay = ts - days * DAY
    local back = ((days + 4) % 7 - WEEKLY.WEEK_DAY) % 7
    if back == 0 and secOfDay < WEEKLY.WEEK_HOUR * 3600 then back = 7 end
    return (days - back) * DAY + WEEKLY.WEEK_HOUR * 3600
end

-- offset 0 = week containing `now`, 1 = next week ... (can be negative)
function weekStartAt(offset, now)
    return weekStartFor(now or getRealTime().timestamp) + offset * WEEK
end

function nextWeekStart(now)
    return weekStartAt(1, now)
end

-- UTC calendar day number (changes at 00:00 UTC)
function utcDay(ts)
    return math.floor((ts or getRealTime().timestamp) / DAY)
end

-- "2026-10-13 10:00 UTC"
function formatUtc(ts)
    local t = os.date("!*t", ts)
    return string.format("%04d-%02d-%02d %02d:%02d UTC", t.year, t.month, t.day, t.hour, t.min)
end
