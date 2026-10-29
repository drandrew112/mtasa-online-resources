-- Country flags for any UI: flags/<iso 3166 code>.png (lowercase, plus gb-eng/gb-nir/gb-sct/gb-wls).
-- The files are download="false" in meta.xml: a flag is downloaded the first time a UI asks
-- for it, then kept as a texture. Until it arrives the draw exports simply draw nothing.
-- A player's country comes from the IP (server/flags.lua) in element data "country",
-- never from the chosen language.
local FLAG_CODES = {}
for _, code in ipairs({
    "ad", "ae", "af", "ag", "ai", "al", "am", "ao", "aq", "ar", "as", "at", "au", "aw", "ax", "az",
    "ba", "bb", "bd", "be", "bf", "bg", "bh", "bi", "bj", "bl", "bm", "bn", "bo", "bq", "br", "bs",
    "bt", "bv", "bw", "by", "bz", "ca", "cc", "cd", "cf", "cg", "ch", "ci", "ck", "cl", "cm", "cn",
    "co", "cr", "cu", "cv", "cw", "cx", "cy", "cz", "de", "dj", "dk", "dm", "do", "dz", "ec", "ee",
    "eg", "eh", "er", "es", "et", "fi", "fj", "fk", "fm", "fo", "fr", "ga", "gb", "gb-eng",
    "gb-nir", "gb-sct", "gb-wls", "gd", "ge", "gf", "gg", "gh", "gi", "gl", "gm", "gn", "gp", "gq",
    "gr", "gs", "gt", "gu", "gw", "gy", "hk", "hm", "hn", "hr", "ht", "hu", "id", "ie", "il", "im",
    "in", "io", "iq", "ir", "is", "it", "je", "jm", "jo", "jp", "ke", "kg", "kh", "ki", "km", "kn",
    "kp", "kr", "kw", "ky", "kz", "la", "lb", "lc", "li", "lk", "lr", "ls", "lt", "lu", "lv", "ly",
    "ma", "mc", "md", "me", "mf", "mg", "mh", "mk", "ml", "mm", "mn", "mo", "mp", "mq", "mr", "ms",
    "mt", "mu", "mv", "mw", "mx", "my", "mz", "na", "nc", "ne", "nf", "ng", "ni", "nl", "no", "np",
    "nr", "nu", "nz", "om", "pa", "pe", "pf", "pg", "ph", "pk", "pl", "pm", "pn", "pr", "ps", "pt",
    "pw", "py", "qa", "re", "ro", "rs", "ru", "rw", "sa", "sb", "sc", "sd", "se", "sg", "sh", "si",
    "sj", "sk", "sl", "sm", "sn", "so", "sr", "ss", "st", "sv", "sx", "sy", "sz", "tc", "td", "tf",
    "tg", "th", "tj", "tk", "tl", "tm", "tn", "to", "tr", "tt", "tv", "tw", "tz", "ua", "ug", "um",
    "us", "uy", "uz", "va", "vc", "ve", "vg", "vi", "vn", "vu", "wf", "ws", "xk", "ye", "yt", "za",
    "zm", "zw",
}) do FLAG_CODES[code] = true end
local ALIASES = { uk = "gb" }

local flags = {} -- code -> "loading" | { tex, ratio } | false

local function normalize(code)
    if type(code) ~= "string" then return nil end
    code = code:lower()
    code = ALIASES[code] or code
    return FLAG_CODES[code] and code or nil
end

-- starts the download on the first call; texture + width/height ratio once it is there
local function getFlag(code)
    code = normalize(code)
    if not code then return nil end
    local f = flags[code]
    if f == nil then
        flags[code] = "loading"
        if not downloadFile("flags/"..code..".png") then flags[code] = false end
        return nil
    end
    return type(f) == "table" and f or nil
end

addEventHandler("onClientFileDownloadComplete", resourceRoot, function(fileName, success)
    local code = fileName:match("^flags/([%w%-]+)%.png$")
    if not code or flags[code] ~= "loading" then return end
    -- the sources are large: compressed + mipmapped so they stay sharp and cheap when drawn small
    local tex = success and dxCreateTexture(fileName, "dxt5", true, "clamp")
    if not tex then
        flags[code] = false
        return
    end
    local w, h = dxGetMaterialSize(tex)
    flags[code] = { tex = tex, ratio = w/h }
end)

-- ===== exports =====

-- player's country code ("hu", "de", ...) or false (unknown / LAN)
function getPlayerCountry(player)
    if not isElement(player) then return false end
    return normalize(getElementData(player, "country")) or false
end

-- true when there is a flag file for the code (it may still have to download)
function hasFlag(code)
    return normalize(code) ~= nil
end

-- starts the download now, so the first draw already has it
function preloadFlag(code)
    getFlag(code)
    return hasFlag(code)
end

-- texture element of the flag, or false while downloading / no flag
function getFlagTexture(code)
    local f = getFlag(code)
    return f and f.tex or false
end

-- width / height of the flag image, or false while downloading / no flag
function getFlagRatio(code)
    local f = getFlag(code)
    return f and f.ratio or false
end

-- Draws the flag fitted into the w x h box (aspect kept, centred). h nil -> h from the ratio.
-- alpha 0-255 (default 255). Returns the drawn width, height or false while it is not ready.
function drawFlag(code, x, y, w, h, alpha, postGUI)
    local f = getFlag(code)
    if not f then return false end
    local dw, dh = w, h or w/f.ratio
    if dw/dh > f.ratio then dw = dh*f.ratio else dh = dw/f.ratio end
    dxDrawImage(x + (w - dw)/2, y + ((h or dh) - dh)/2, dw, dh, f.tex, 0, 0, 0, tocolor(255,255,255, alpha or 255), postGUI or false)
    return dw, dh
end

-- drawFlag with the player's country
function drawPlayerFlag(player, x, y, w, h, alpha, postGUI)
    local code = getPlayerCountry(player)
    if not code then return false end
    return drawFlag(code, x, y, w, h, alpha, postGUI)
end
