--autor: Emanuel
--04/2021
--Cableway system :D

-- Two cabins run between the Angel Pine and the Mount Chiliad station. One timer drives both:
-- every cycle the cabins swap stations, and the doors open when they arrive.

local EASING = "InOutQuad"
local TRAVEL_MS = 50000    -- one trip
local WAIT_MS = 15000      -- time spent in the station

local BODY_MODEL, DOOR_MODEL = 5837, 3089
local WHEEL_MODEL, HANGER_MODEL = 2393, 1025

-- { model, x, y, z, rx, ry, rz, scale } relative to the cabin body
local PARTS_A = {
    { WHEEL_MODEL, 0.65764988, 0.58218143, 5.46400070, 9.99755859, 179.9945, -90, 2.49 },
    { WHEEL_MODEL, 0.65764988, 0.58218143, 5.26399994, -10.0030518, 179.9945, -89.9945, 2.49 },
    { HANGER_MODEL, 0.54419090, 0.49752557, 5.50899887, 0, 0, 90.75256 },
    { HANGER_MODEL, -0.42477617, 0.50044745, 5.11400223, 0, 0, 91.75232 },
    { HANGER_MODEL, 0.52602787, -0.56594340, 5.50899887, 0, 0, -89.99451 },
    { HANGER_MODEL, -0.43851117, -0.56660167, 5.11400223, 0, 0, -89.99451 },
}
local PARTS_B = {
    { WHEEL_MODEL, -0.58513541, -0.57499959, 5.26501465, -10.0030518, 179.9945, 90.0439, 2.49 },
    { WHEEL_MODEL, -0.58513541, -0.57499959, 5.46301270, 9.99755859, 179.9945, 90.0439, 2.49 },
    { HANGER_MODEL, 0.48538080, 0.58794192, 5.26501465, 0, 0, 90.0439 },
    { HANGER_MODEL, -0.47132872, 0.60024130, 5.56503296, 0, 0, 90.04943848 },
    { HANGER_MODEL, 0.48402283, -0.50932636, 5.26501465, 0, 0, -89.95056 },
    { HANGER_MODEL, -0.47405900, -0.49979348, 5.56503296, 0, 0, -89.95056 },
}

-- Door offsets {x, y, z, rz}: shut while travelling, open at the station it arrives at.
-- Cabin A starts at the bottom (Angel Pine), cabin B at the top (Mount Chiliad).
local cabins = {
    {
        pos = { -2125.1318359375, -2549.2998046875, 43.035999298096 }, rotZ = 98,
        parts = PARTS_A,
        stations = {
            bottom = { -2125.1318359375, -2549.2998046875, 43.035999298096 },
            top = { -2255.0498046875, -1779.7001953125, 458 },
        },
        doorShut = { toTop = { -0.2799987856504, 1.4613305379074, -0.055999755859673, 180 },
                     toBottom = { -0.27916749488349, 1.4602276760422, -0.05499267578125, 180 } },
        doorOpen = { top = { 1.3050919138052, 1.3822542574335, -0.05499267578125, -179.99450683594 },
                     bottom = { 1.3072073464583, 1.3999543197823, -0.035999298096002, 180 } },
        at = "bottom",
    },
    {
        pos = { -2265.6499023438, -1781.1999511719, 457.98498535156 }, rotZ = 277.94860839844,
        parts = PARTS_B,
        stations = {
            bottom = { -2136.2001953125, -2550.8994140625, 42.974998474121 },
            top = { -2265.6499023438, -1781.1999511719, 457.98498535156 },
        },
        doorShut = { toBottom = { -0.25235233809494, 1.4482243732163, -0.049987792966249, -179.95056152344 },
                     toTop = { -0.25661589538024, 1.4466086582694, -0.059997558593658, -179.54675292969 } },
        doorOpen = { bottom = { 1.3011526236902, 1.4417363716101, -0.059997558593658, -179.54675292969 },
                     top = { 1.3035336179581, 1.3823383049605, -0.049987792966249, -179.95056152344 } },
        at = "top",
    },
}

local function attachDoor(cabin, o)
    attachElements(cabin.door, cabin.body, o[1], o[2], o[3], 0, 0, o[4])
end

local function createCabin(cabin)
    local p = cabin.pos
    cabin.body = createObject(BODY_MODEL, p[1], p[2], p[3], 0, 0, cabin.rotZ)
    cabin.door = createObject(DOOR_MODEL, p[1], p[2], p[3])
    setObjectScale(cabin.door, 1.03)
    attachDoor(cabin, cabin.doorOpen[cabin.at])

    for _, part in ipairs(cabin.parts) do
        local obj = createObject(part[1], p[1], p[2], p[3])
        attachElements(obj, cabin.body, part[2], part[3], part[4], part[5], part[6], part[7])
        if part[8] then setObjectScale(obj, part[8]) end
    end

    local blip = createBlipAttachedTo(cabin.body, 0, 0, 0, 0, 0)
    setBlipVisibleDistance(blip, 300)
    setBlipSize(blip, 0.5)
end

local function openDoor(cabin, station)
    attachDoor(cabin, cabin.doorOpen[station])
end

-- Sends the cabin to the other station: door shut now, open on arrival.
local function sendCabin(cabin)
    local dest = cabin.at == "bottom" and "top" or "bottom"
    local d = cabin.stations[dest]
    moveObject(cabin.body, TRAVEL_MS, d[1], d[2], d[3], 0, 0, 0, EASING)
    attachDoor(cabin, cabin.doorShut[dest == "top" and "toTop" or "toBottom"])
    cabin.at = dest
    setTimer(openDoor, TRAVEL_MS, 1, cabin, dest)
end

local function cycle()
    for _, cabin in ipairs(cabins) do
        sendCabin(cabin)
    end
    setTimer(cycle, TRAVEL_MS + WAIT_MS, 1)
end

addEventHandler("onResourceStart", resourceRoot, function()
    for _, cabin in ipairs(cabins) do
        createCabin(cabin)
    end
    setTimer(cycle, WAIT_MS, 1)
end)
