-- Public API (see README.md).

local function isPatientType(element)
    local t = isElement(element) and getElementType(element)
    return t == "player" or t == "ped"
end

-- Turns the forced animation off on an element (true) or back on (false), e.g. while another
-- script carries / seats the patient. The stretcher and vehicles are excepted without this.
function setAnimationBlocked(element, blocked)
    if not isPatientType(element) then return false end
    if blocked then
        setElementData(element, MEDFX.DATA_BLOCK, true)
    else
        removeElementData(element, MEDFX.DATA_BLOCK)
    end
    return true
end

function isAnimationBlocked(element)
    return isPatientType(element) and getElementData(element, MEDFX.DATA_BLOCK) == true
end

-- Key of the animation the element has to play (MEDFX_ANIMS: "down", "dazed_ped"), or false
function getForcedAnimation(element)
    if not isPatientType(element) then return false end
    return getElementData(element, MEDFX.DATA_ANIM) or false
end
