if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Menu music: plays "main_menu.mp3" on a loop while any account panel (or the
-- acc_menu, setMusicActive) is visible. The player can mute/unmute it from the
-- Settings card (or acc_menu Settings > Audio); the choice is kept in userdata.xml.

Music = {}

local SOUND_FILE = "audio/main_menu.mp3"
local VOLUME = 0.6

local sound = nil
local enabled = true
local btn = { x = 0, y = 0, w = 0, h = 0 }

--------------------------------------------------------------------------------
-- Playback
--------------------------------------------------------------------------------

local function startSound()
    if isElement(sound) then return end
    sound = playSound(SOUND_FILE, true) -- looped
    if isElement(sound) then
        setSoundVolume(sound, VOLUME)
    end
end

local function stopMusic()
    if isElement(sound) then
        stopSound(sound)
    end
    sound = nil
end

-- Keeps playback in sync with panel visibility and the player's preference.
local external = false -- acc_menu keeps the music on (setMusicActive)

function Music.update()
    if (UIState.active or external) and enabled then
        startSound()
    else
        stopMusic()
    end
end

function Music.toggle()
    enabled = not enabled
    UserData.set("music", enabled and "1" or "0")
    Music.update()
end

function Music.isEnabled()
    return enabled
end

--------------------------------------------------------------------------------
-- Toggle button
--
-- Drawn by settings.lua inside the Settings card (which hands over the rect)
-- and clicked via onClientClick, so it needs no DGS element.
--------------------------------------------------------------------------------

local function inButton(px, py)
    return px and btn.w > 0 and px >= btn.x and px <= btn.x + btn.w
       and py >= btn.y and py <= btn.y + btn.h
end

-- Called from settings.lua while a panel is visible.
function Music.drawToggle(x, y, w, h)
    btn.x, btn.y, btn.w, btn.h = x, y, w, h

    local cx, cy = getCursorPosition()
    local hover = false
    if cx then
        hover = inButton(cx * sw, cy * sh)
    end

    dxDrawRectangle(btn.x, btn.y, btn.w, btn.h, hover and Theme.accent or Theme.fieldBG)
    dxDrawRectangle(btn.x, btn.y, ui(3), btn.h, Theme.accent)
    dxDrawRectangle(btn.x + ui(15), btn.y + btn.h / 2 - ui(5), ui(10), ui(10),
        enabled and tocolor(90, 200, 120, 255) or tocolor(210, 90, 90, 255))
    dxDrawText(enabled and L("acc_ui.settings.on") or L("acc_ui.settings.off"),
        btn.x + ui(34), btn.y, btn.x + btn.w - ui(8), btn.y + btn.h,
        Theme.text, ui(1.15), "default-bold", "left", "center")
end

addEventHandler("onClientClick", root, function(mouseButton, state, absX, absY)
    if mouseButton ~= "left" or state ~= "down" then return end
    if not (UIState and UIState.active) then return end
    if inButton(absX, absY) then
        Music.toggle()
        uiSound("audio/ui_btn_click.mp3")
    end
end)

--------------------------------------------------------------------------------

-- exports (acc_menu)
function setMusicActive(on)
    external = on == true
    Music.update()
end

function isMusicEnabled()
    return enabled
end

function setMusicEnabled(on)
    if (on == true) ~= enabled then Music.toggle() end
end

function Music.init()
    enabled = (UserData.get("music") ~= "0") -- default: enabled
    Music.update()
end
