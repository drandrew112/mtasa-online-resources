--[[
    v_socialpanel / shared.lua
    Constants and pure helpers used by both the client and the server.
]]

SP = {
    -- Limits
    MAX_FRIENDS      = 100,
    MAX_CREW_MEMBERS = 30,
    CREW_NAME_MIN    = 3,
    CREW_NAME_MAX    = 24,
    CREW_TAG_MIN     = 2,
    CREW_TAG_MAX     = 5,
    CREW_DESC_MAX    = 140,
    MSG_MAX_LEN      = 200,
    MSG_HISTORY      = 200,   -- messages kept per conversation
    SEARCH_MIN       = 2,     -- min query length for player search
    SEARCH_LIMIT     = 60,    -- max search results

    -- Account data keys. Friend lists stay here; friend *requests*, crews and
    -- messages moved to their own MySQL tables (see db.lua).
    KEY_FRIENDS   = "socialpanel:friends",    -- \n separated account names
    KEY_CREW      = "socialpanel:crew",       -- the player's crew name, or ""
    KEY_CREW_SEEN = "socialpanel:crew_seen",  -- last-seen crew-chat timestamp
}

-- Splits a string into a list (separator: newline). Empty/nil input -> empty table.
function SP.split(raw)
    local list = {}
    if type(raw) == "string" and raw ~= "" then
        for item in raw:gmatch("[^\n]+") do
            item = item:gsub("^%s+", ""):gsub("%s+$", "")
            if item ~= "" then
                list[#list + 1] = item
            end
        end
    end
    return list
end

-- List -> string (separator: newline).
function SP.join(list)
    return table.concat(list or {}, "\n")
end

-- Case-insensitive membership test. Returns bool, exactValue.
function SP.contains(list, value)
    if not value then return false end
    local needle = tostring(value):lower()
    for _, item in ipairs(list) do
        if item:lower() == needle then
            return true, item
        end
    end
    return false
end

-- Removes a value from a list (case-insensitive). Returns a new list.
function SP.removeValue(list, value)
    local out, needle = {}, tostring(value):lower()
    for _, item in ipairs(list) do
        if item:lower() ~= needle then
            out[#out + 1] = item
        end
    end
    return out
end

-- "Xh Ym" played-time string from hours + minutes.
function SP.formatPlaytime(hours, minutes)
    hours = tonumber(hours) or 0
    minutes = tonumber(minutes) or 0
    return string.format("%dh %02dm", hours, minutes)
end

-- Stable key for a DM conversation between two account names (order independent).
function SP.pairKey(a, b)
    a, b = tostring(a):lower(), tostring(b):lower()
    if a <= b then return a .. "\1" .. b end
    return b .. "\1" .. a
end

-- Crew name / tag validation. Returns true, cleanValue  OR  false, errorMessage.
function SP.validateCrewName(name)
    if type(name) ~= "string" then return false, "Invalid name." end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if #name < SP.CREW_NAME_MIN or #name > SP.CREW_NAME_MAX then
        return false, ("Crew name must be %d-%d characters."):format(SP.CREW_NAME_MIN, SP.CREW_NAME_MAX)
    end
    if not name:find("^[%w _%-%.]+$") then
        return false, "Crew name may only contain letters, digits, space, - _ ."
    end
    return true, name
end

function SP.validateCrewTag(tag)
    if type(tag) ~= "string" then return false, "Invalid tag." end
    tag = tag:gsub("^%s+", ""):gsub("%s+$", "")
    if #tag < SP.CREW_TAG_MIN or #tag > SP.CREW_TAG_MAX then
        return false, ("Tag must be %d-%d characters."):format(SP.CREW_TAG_MIN, SP.CREW_TAG_MAX)
    end
    if not tag:find("^[%w]+$") then
        return false, "Tag may only contain letters and digits."
    end
    return true, tag:upper()
end

-- Trims and length-caps a chat message. Returns cleanText or nil.
function SP.cleanMessage(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("^%s+", ""):gsub("%s+$", ""):gsub("[%z\1-\8\11\12\14-\31]", "")
    if text == "" then return nil end
    return text:sub(1, SP.MSG_MAX_LEN)
end
