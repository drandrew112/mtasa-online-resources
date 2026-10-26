-- Small server-side helpers shared by every module.

function now()
    return getRealTime().timestamp
end

function formatDateTime(ts)
    if not ts then return nil end
    local t = getRealTime(ts)
    return string.format("%04d-%02d-%02d %02d:%02d:%02d",
        t.year + 1900, t.month + 1, t.monthday, t.hour, t.minute, t.second)
end

function formatTime(ts)
    local t = getRealTime(ts)
    return string.format("%02d:%02d", t.hour, t.minute)
end

function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Strip control characters and cap length of user supplied text.
function cleanText(s, maxLen)
    s = trim(tostring(s or ""):gsub("%c", " "))
    return s:sub(1, maxLen or 200)
end

function removeValue(list, value)
    for i = #list, 1, -1 do
        if list[i] == value then table.remove(list, i) return true end
    end
    return false
end

function hasValue(list, value)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

local function accountsRunning()
    local res = getResourceFromName("v_accounts")
    return res and getResourceState(res) == "running"
end

-- Account name of a player (v_accounts), falling back to the nick.
function accountName(player)
    if accountsRunning() then
        local name = exports.v_accounts:getName(player)
        if name then return name end
    end
    return getPlayerName(player)
end

function isAccountLoggedIn(player)
    if accountsRunning() then
        return exports.v_accounts:isLoggedIn(player) and true or false
    end
    return true
end

function zoneLabel(x, y, z)
    local zone = getZoneName(x, y, z or 0)
    local city = getZoneName(x, y, z or 0, true)
    if zone == city or city == "Unknown" then return zone end
    return zone .. ", " .. city
end
