if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
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
    DISPLAY_MIN      = 3,
    DISPLAY_MAX      = 24,
    MSG_MAX_LEN      = 200,
    MSG_HISTORY      = 200,   -- messages kept per conversation
    SEARCH_MIN       = 2,     -- min query length for player search
    SEARCH_LIMIT     = 60,    -- max search results

    -- Account data keys. Friends, friend requests, crews and messages live in
    -- their own MySQL tables (see db.lua).
    KEY_FRIENDS   = "socialpanel:friends",    -- OLD friend list, only read by SPDB.migrateFriends
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
-- Accented letters are allowed: Latin-1 letters (U+00C0-U+00FF without x and /) plus the Hungarian o/u double acute.
local function isAccentLetter(cp)
    return (cp >= 0xC0 and cp <= 0xFF and cp ~= 0xD7 and cp ~= 0xF7)
        or cp == 0x150 or cp == 0x151 or cp == 0x170 or cp == 0x171
end

-- Every character must be ASCII (matching asciiPattern) or an accented letter. Returns the character count or nil.
local function countCrewChars(s, asciiPattern)
    local len = utf8.len(s)
    if not len or #s > 96 then return nil end
    for _, cp in ipairs({ utf8.codepoint(s, 1, -1) }) do
        if cp < 0x80 then
            if not utf8.char(cp):find(asciiPattern) then return nil end
        elseif not isAccentLetter(cp) then
            return nil
        end
    end
    return len
end

local function upperAccented(s)
    local out = {}
    for _, cp in ipairs({ utf8.codepoint(s, 1, -1) }) do
        if cp < 0x80 then out[#out + 1] = utf8.char(cp):upper()
        elseif cp >= 0xE0 and cp <= 0xFE and cp ~= 0xF7 then out[#out + 1] = utf8.char(cp - 32)
        elseif cp == 0x151 or cp == 0x171 then out[#out + 1] = utf8.char(cp - 1)
        else out[#out + 1] = utf8.char(cp) end
    end
    return table.concat(out)
end

function SP.validateCrewName(name)
    if type(name) ~= "string" then return false, L.text("v_socialpanel.shared.invalid_name") end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    local len = countCrewChars(name, "^[%w _%-%.]$")
    if not len and utf8.len(name) and #name <= 96 then
        return false, L.text("v_socialpanel.shared.crew_name_may_only_contain_letters")
    end
    if not len or len < SP.CREW_NAME_MIN or len > SP.CREW_NAME_MAX then
        return false, L.text("v_socialpanel.shared.crew_name_must_be_characters", { crew_name_min = SP.CREW_NAME_MIN, crew_name_max = SP.CREW_NAME_MAX })
    end
    return true, name
end

function SP.validateCrewTag(tag)
    if type(tag) ~= "string" then return false, L.text("v_socialpanel.shared.invalid_tag") end
    tag = tag:gsub("^%s+", ""):gsub("%s+$", "")
    local len = countCrewChars(tag, "^%w$")
    if not len and utf8.len(tag) and #tag <= 96 then
        return false, L.text("v_socialpanel.shared.tag_may_only_contain_letters_and")
    end
    if not len or len < SP.CREW_TAG_MIN or len > SP.CREW_TAG_MAX then
        return false, L.text("v_socialpanel.shared.tag_must_be_characters", { crew_tag_min = SP.CREW_TAG_MIN, crew_tag_max = SP.CREW_TAG_MAX })
    end
    return true, upperAccented(tag)
end

-- Display name validation. Returns true, cleanValue  OR  false, errorMessage.
function SP.validateDisplayName(name)
    if type(name) ~= "string" then return false, L.text("v_socialpanel.shared.invalid_display_name") end
    name = name:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    local len = utf8.len(name)
    if not len or len < SP.DISPLAY_MIN or len > SP.DISPLAY_MAX or name:find("[%z\1-\31#]") then
        return false, L.text("v_socialpanel.shared.display_name_must_be_characters", { display_min = SP.DISPLAY_MIN, display_max = SP.DISPLAY_MAX })
    end
    return true, name
end

-- Trims and length-caps a chat message. Returns cleanText or nil.
function SP.cleanMessage(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("^%s+", ""):gsub("%s+$", ""):gsub("[%z\1-\8\11\12\14-\31]", "")
    if text == "" then return nil end
    return text:sub(1, SP.MSG_MAX_LEN)
end
