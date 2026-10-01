-- Small helpers shared by the server modules.

function msmLog(fmt, ...)
    outputServerLog("[med_scenemanager] " .. string.format(fmt, ...))
end

function msmSay(player, text)
    if not isElement(player) then
        msmLog("%s", (text:gsub("#%x%x%x%x%x%x", "")))
        return
    end
    outputChatBox("#ff5a5a[SCENE] #ffffff" .. text, player, 255, 255, 255, true)
end

-- ui_core notification on the player's screen
function msmNotify(player, title, text)
    if isElement(player) then
        triggerClientEvent(player, "msm:notify", resourceRoot, title, text)
    end
end

function msmResourceRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

-- admin_level comes from the account store (v_mysql), not from element data
function msmIsAllowed(player)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    if getElementData(player, "isLogged") ~= true then return false end
    if not msmResourceRunning("v_mysql") then return false end
    local level = tonumber(exports.v_mysql:getAccData(player, "admin_level")) or 0
    return level >= MSM.MIN_ADMIN_LEVEL
end

function msmRound(value, decimals)
    local m = 10 ^ (decimals or 3)
    return math.floor((tonumber(value) or 0) * m + 0.5) / m
end

function msmCopy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = msmCopy(v) end
    return out
end

function msmValidName(name)
    return type(name) == "string" and #name > 0 and #name <= MSM.NAME_MAX
        and name:match(MSM.NAME_PATTERN) ~= nil and name ~= "index"
end

---------------------------------------------------------------- files

function msmReadFile(path)
    if not fileExists(path) then return nil end
    local f = fileOpen(path, true)
    if not f then return nil end
    local content = fileRead(f, fileGetSize(f))
    fileClose(f)
    return content
end

function msmWriteFile(path, content)
    if fileExists(path) then fileDelete(path) end
    local f = fileCreate(path)
    if not f then return false end
    fileWrite(f, content)
    fileClose(f)
    return true
end

-- Accepts a plain JSON object / array (MTA's fromJSON wants a top level array)
function msmDecodeJSON(content)
    if type(content) ~= "string" then return nil end
    content = content:gsub("^\239\187\191", "") -- UTF-8 BOM
    local first = content:match("^%s*(.)")
    if first == "{" then content = "[" .. content .. "]" end
    local ok, value = pcall(fromJSON, content)
    if ok and type(value) == "table" then return value end
    return nil
end

-- Pretty JSON without MTA's outer [ ] wrapper
function msmEncodeJSON(value)
    local json = toJSON(value, false, "spaces")
    if not json then return nil end
    local inner = json:match("^%[%s*(.-)%s*%]%s*$")
    return (inner or json) .. "\n"
end
