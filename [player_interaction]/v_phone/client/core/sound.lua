--[[
    v_phone / client/core/sound.lua
    Tiny UI sound helper.
      select        -> phone opens, Enter / activate
      click         -> moving the selection
      ring (looped) -> a contact call, until it is answered or cancelled
]]

PhoneSound = {}

local function play(file, looped)
    local s = playSound("sounds/" .. file .. ".wav", looped and true or false)
    if s then setSoundVolume(s, 0.5) end
    return s
end

function PhoneSound.select() play("select") end
function PhoneSound.click()  play("click")  end

--------------------------------------------------------------------------------
-- Looping ring
--------------------------------------------------------------------------------

local ringHandle

function PhoneSound.ringStart()
    if isElement(ringHandle) then return end
    ringHandle = play("ring", true)
end

function PhoneSound.ringStop()
    if isElement(ringHandle) then stopSound(ringHandle) end
    ringHandle = nil
end
