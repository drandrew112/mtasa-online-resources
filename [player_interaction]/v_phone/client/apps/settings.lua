--[[
    v_phone / client/apps/settings.lua
    Settings root menu. "Wallpaper" opens a sub-screen for picking the screen
    background colour (incl. a "Crew colour" option). The choice is persisted
    per account by server/apps/settings.lua.
]]

local currentKey = PHONE_CONFIG.defaultWallpaper
local sub = nil   -- nil = settings root  |  "wallpaper"

--------------------------------------------------------------------------------
-- Exposed to the shell so it can paint the screen background.
--------------------------------------------------------------------------------

PhoneWallpaper = {}

function PhoneWallpaper.rgb()
    local w = PHONE_CONFIG.wallpaperByKey(currentKey)
    if w.color then return w.color[1], w.color[2], w.color[3] end

    local c = getElementData(localPlayer, "crewColor")
    if type(c) == "table" and c[1] then
        -- darken so text stays readable on top
        return math.floor(c[1] * 0.35), math.floor(c[2] * 0.35), math.floor(c[3] * 0.35)
    end
    return 18, 20, 26
end

--------------------------------------------------------------------------------

phoneOnServer("settings:wallpaper", function(key)
    currentKey = PHONE_CONFIG.wallpaperByKey(key).key
end)

local function swatchRGB(w)
    if w.color then return w.color end
    local c = getElementData(localPlayer, "crewColor")
    if type(c) == "table" and c[1] then return c end
    return { 120, 120, 120 }
end

local function wallpaperIndex()
    for i, w in ipairs(PHONE_CONFIG.wallpapers) do
        if w.key == currentKey then return i end
    end
    return 1
end

--------------------------------------------------------------------------------

PhoneApp.register({
    id    = "settings",
    name  = "Settings",
    order = 50,

    open  = function() sub = nil end,
    close = function() sub = nil end,

    headerTitle = function()
        return sub == "wallpaper" and "Wallpaper" or "Settings"
    end,

    hint = function()
        if sub == "wallpaper" then return "[Enter] apply    [Backspace] back" end
        return "[Enter] open"
    end,

    items = function()
        if sub == "wallpaper" then
            local rows = {}
            for _, w in ipairs(PHONE_CONFIG.wallpapers) do
                rows[#rows + 1] = {
                    title  = w.name,
                    swatch = swatchRGB(w),
                    right  = (w.key == currentKey) and "Active" or nil,
                    _wp    = w.key,
                }
            end
            return rows
        end

        -- settings root
        return {
            {
                title    = "Wallpaper",
                subtitle = PHONE_CONFIG.wallpaperByKey(currentKey).name,
                _open    = "wallpaper",
            },
        }
    end,

    onSelect = function(_, row)
        if row._open then
            sub = row._open
            Phone.setSelected(wallpaperIndex())
        elseif row._wp then
            currentKey = row._wp                       -- optimistic
            phoneRPC("settings:setWallpaper", row._wp)
        end
    end,

    -- Backspace inside a sub-screen returns to the settings root instead of
    -- closing the app.
    key = function(_, key)
        if sub and key == "backspace" then
            sub = nil
            Phone.setSelected(1)
            PhoneSound.select()
            return true
        end
        return false
    end,
})
