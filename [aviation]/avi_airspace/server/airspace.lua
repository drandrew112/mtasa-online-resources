-- Airspaces (data/airspaces.json). Every airport has a CTR (tower) and a TMA (approach); one CTA
-- (radar / centre) covers San Andreas + 500 m. Altitudes are feet, floor / ceiling inclusive.
-- An aircraft belongs to the most specific airspace it is in: CTR > TMA > CTA.

local PRIORITY = { CTR = 1, TMA = 2, CTA = 3 }
local list, byId = {}, {}

local function load()
    local f = fileOpen("data/airspaces.json", true)
    if not f then
        outputDebugString("[avi_airspace] data/airspaces.json missing", 1)
        return
    end
    local data = fromJSON(fileRead(f, fileGetSize(f)))
    fileClose(f)
    list, byId = {}, {}
    for _, a in ipairs(data and data.airspaces or {}) do
        if a.id and a.polygon and #a.polygon >= 3 then
            a.floor = tonumber(a.floor) or 0
            a.ceiling = tonumber(a.ceiling) or 99999
            a.priority = PRIORITY[a.type] or 9
            list[#list + 1] = a
            byId[a.id] = a
        else
            outputDebugString("[avi_airspace] skipped airspace without id / polygon", 2)
        end
    end
    table.sort(list, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        return a.id < b.id
    end)
    outputDebugString(("[avi_airspace] %d airspaces loaded"):format(#list))
end
addEventHandler("onResourceStart", resourceRoot, load)

function getAirspaces()
    return list
end

function getAirspace(id)
    return byId[id]
end

-- every airspace containing the point, most specific first. altFt nil = ignore altitude
function getAirspacesAt(x, y, altFt)
    local out = {}
    for _, a in ipairs(list) do
        if (not altFt or (altFt >= a.floor and altFt <= a.ceiling)) and pointInPolygon(x, y, a.polygon) then
            out[#out + 1] = a
        end
    end
    return out
end

function getAirspaceAt(x, y, altFt)
    return getAirspacesAt(x, y, altFt)[1]
end
