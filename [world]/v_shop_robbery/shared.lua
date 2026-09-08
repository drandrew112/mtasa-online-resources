
shops = {
    {
        pos = { -- for blip
            x = 2319.2099609375,
            y = -1718.560546875,
            z = 13.546875
        },
        npc = {
            pos = {
                x = 2326.244140625,
                y = -1711.9420166016,
                z = 13.793982505798,
                rot_z = 90
            },
            skin = 15,
            pickup_distance = 1.2
        },
        cdTimer = nil,
        isAvail = true
    },
    {
        pos = { -- for blip
            x = 808.72027587891,
            y = -1351.1381835938,
            z = 13.541837692261
        },
        npc = {
            pos = {
                x = 812.07354736328,
                y = -1355.1883544922,
                z = 13.540577888489,
                rot_z = 0
            },
            skin = 12,
            pickup_distance = 2.5
        },
        cdTimer = nil,
        isAvail = true
    }
}


-- hasznos cuccok

function getPositionInFrontOfElement(theElement, distance)
    assert(isElement(theElement), "Bad argument @ 'getPositionInFrontOfElement' [Expected element at argument 1, got "..(type(theElement)).."]")

    local x, y, z = getElementPosition(theElement)
    local rz = ({getElementRotation(theElement)})[3]

    local rotationRad = math.rad(rz)

    local objX = x - distance * math.sin(rotationRad)
    local objY = y + distance * math.cos(rotationRad)
    local objZ = z

    return objX, objY, objZ
end
