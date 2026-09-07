--autor: Emanuel 
--04/2021
--Cableway system :D

local easing =  "InOutQuad"
local speed = 50000 --move object speed --53000 normal original
local wait = 15000 --1000=1second  60000=1mins
local timeopendoor = speed

function createcableway ()
	--start cableway in mount chiliad to angel pine
	setTimer(cablewaytoangelpine2, wait, 1)
	--cable angel pine
	cablewayangelpine = createObject (5837, -2125.1318359375, -2549.2998046875, 43.035999298096, 0, 0, 98)
	cablewayangelpinedoor = createObject(3089, -2126.6999511719, -2548.1999511719, 43, 0, 0, 277.99255371094)
	attachElements(cablewayangelpinedoor, cablewayangelpine, 1.3072073464583, 1.3999543197823, -0.035999298096002, 0, 0, 180)--open door
	setObjectScale(cablewayangelpinedoor, 1.02999997)
	--wheels and metal
	angelAttach1 = createObject(2393, -2125.7998046875, -2548.7294921875, 48.5, 9.99755859375, 179.99450683594, 7.9925537109375)
	attachElements(angelAttach1, cablewayangelpine, 0.65764988417393, 0.58218143948329, 5.464000701904, 9.99755859375, 179.99450683594, -90)
	setObjectScale(angelAttach1, 2.49000000)
	angelAttach2 = createObject(2393, -2125.7998046875, -2548.7294921875, 48.299999237061, 349.99694824219, 179.99450683594, 7.998046875)
	attachElements(angelAttach2, cablewayangelpine, 0.65764988417393, 0.58218143948329, 5.2639999389645, -10.003051757812, 179.99450683594, -89.994506835938)
	setObjectScale(angelAttach2, 2.49000000)
	angelAttach3 = createObject(1025, -2125.7001953125, -2548.830078125, 48.544998168945, 0, 0, 188.7451171875)
	attachElements(angelAttach3, cablewayangelpine, 0.54419089761023, 0.497525566807, 5.5089988708493, 0, 0, 90.752563476562)
	angelAttach4 = createObject(1025, -2125.568359375, -2549.7900390625, 48.150001525879, 0, 0, 189.74487304688)
	attachElements(angelAttach4, cablewayangelpine, -0.42477617019382, 0.50044745893443, 5.1140022277829, 0, 0, 91.752319335937)
	angelAttach5 = createObject(1025, -2124.64453125, -2548.7001953125, 48.544998168945, 0, 0, 7.998046875)
	attachElements(angelAttach5, cablewayangelpine, 0.52602786903611, -0.56594340887115, 5.5089988708493, 0, 0, -89.994506835938)
	angelAttach6 = createObject(1025, -2124.509765625, -2549.6552734375, 48.150001525879, 0, 0, 7.998046875)
	attachElements(angelAttach6, cablewayangelpine, -0.43851117383511, -0.56660167343749, 5.1140022277829, 0, 0, -89.994506835938)
	--blip
	cablewayangelpineblip = createBlipAttachedTo(cablewayangelpine, 0, 0, 0, 0, 0)
	setBlipVisibleDistance(cablewayangelpineblip, 300)
	setBlipSize(cablewayangelpineblip, 0.5)
	-------------------------------
	--start cableway in angel pine to mount chiliad
	setTimer(cablewaytomountchiliad, wait, 1)
	--cableway mountchiliad
	cablewaymountchiliad = createObject (5837, -2265.6499023438, -1781.1999511719, 457.98498535156, 0, 0, 277.94860839844)
	--wheels and metal
	mountAttach1 = createObject(2393, -2266.2998046875, -1780.7001953125, 463.25, 349.99694824219, 179.99450683594, 7.9925537109375)
	attachElements(mountAttach1, cablewaymountchiliad, -0.58513540252747, -0.57499958764934, 5.26501464844, -10.003051757812, 179.99450683594, 90.043945312497)
	setObjectScale(mountAttach1, 2.49000000)
	mountAttach2 = createObject(2393, -2266.2998046875, -1780.7001953125, 463.44799804688, 9.99755859375, 179.99450683594, 7.9925537109375)
	attachElements(mountAttach2, cablewaymountchiliad, -0.58513540252747, -0.57499958764934, 5.463012695315, 9.99755859375, 179.99450683594, 90.043945312497)
	setObjectScale(mountAttach2, 2.49000000)
	mountAttach3 = createObject(1025, -2265, -1781.599609375, 463.25, 0, 0, 7.9925537109375)
	attachElements(mountAttach3, cablewaymountchiliad, 0.48538080044377, 0.58794191588632, 5.26501464844, 0, 0, 90.043945312497)
	mountAttach4 = createObject(1025, -2265.1201171875, -1780.650390625, 463.55001831055, 0, 0, 7.998046875)
	attachElements(mountAttach4, cablewaymountchiliad, -0.47132871620615, 0.60024129944649, 5.5650329589869, 0, 0, 90.04943847656)
	mountAttach5 = createObject(1025, -2266.0869140625, -1781.75, 463.25, 0, 0, 187.998046875)
	attachElements(mountAttach5, cablewaymountchiliad, 0.48402283068176, -0.50932636273394, 5.26501464844, 0, 0, -89.95056152344)
	mountAttach6 = createObject(1025, -2266.2099609375, -1780.7998046875, 463.55001831055, 0, 0, 187.998046875)
	attachElements(mountAttach6, cablewaymountchiliad, -0.474058997459, -0.49979347593614, 5.5650329589869, 0, 0, -89.95056152344)
	--door
	cablewaymountchiliaddoor = createObject(3089, -2264.1000976562, -1782.3000488281, 457.93499755859, 0, 0, 97.998046875)
	attachElements(cablewaymountchiliaddoor, cablewaymountchiliad, 1.3035336179581, 1.3823383049605, -0.049987792966249, 0, 0, -179.95056152344)--open door
    setObjectScale(cablewaymountchiliaddoor, 1.02999997)
	--blip
	cablewaymountchiliadblip = createBlipAttachedTo(cablewaymountchiliad, 0, 0, 0, 0, 0)
	setBlipVisibleDistance(cablewaymountchiliadblip, 300)
	setBlipSize(cablewaymountchiliadblip, 0.5) 
end
addEventHandler("onResourceStart", getResourceRootElement(getThisResource()), createcableway)

function cablewaytomountchiliad(source)
	moveObject(cablewayangelpine, speed, -2255.0498046875, -1779.7001953125, 458, 0, 0, 0, easing)
	attachElements(cablewayangelpinedoor, cablewayangelpine, -0.2799987856504, 1.4613305379074, -0.055999755859673, 0, 0, 180, easing)
	setTimer(cablewaytoangelpine, speed+wait, 1)
	setTimer(attachElements, timeopendoor, 1, cablewayangelpinedoor, cablewayangelpine, 1.3050919138052, 1.3822542574335, -0.05499267578125, 0, 0, -179.99450683594)
end

function cablewaytoangelpine()
	moveObject(cablewayangelpine, speed, -2125.1318359375, -2549.2998046875, 43.035999298096, 0, 0, 0, easing)
	setTimer(cablewaytomountchiliad, speed+wait, 1)
	attachElements(cablewayangelpinedoor, cablewayangelpine, -0.27916749488349, 1.4602276760422, -0.05499267578125, 0, 0, 180, easing)
	setTimer(attachElements, timeopendoor, 1, cablewayangelpinedoor, cablewayangelpine, 1.3072073464583, 1.3999543197823, -0.035999298096002, 0, 0, 180)
end

function cablewaytoangelpine2()
	moveObject(cablewaymountchiliad, speed, -2136.2001953125, -2550.8994140625, 42.974998474121, 0, 0, 0, easing)
	setTimer(cablewaytomountchiliad2, speed+wait, 1)
	attachElements(cablewaymountchiliaddoor, cablewaymountchiliad, -0.25235233809494, 1.4482243732163, -0.049987792966249, 0, 0, -179.95056152344, easing)
	setTimer(attachElements, timeopendoor, 1, cablewaymountchiliaddoor, cablewaymountchiliad, 1.3011526236902, 1.4417363716101, -0.059997558593658, 0, 0, -179.54675292969)
end
  
function cablewaytomountchiliad2()
	moveObject(cablewaymountchiliad, speed, -2265.6499023438, -1781.1999511719, 457.98498535156, 0, 0, 0, easing)
	attachElements(cablewaymountchiliaddoor, cablewaymountchiliad, -0.25661589538024, 1.4466086582694, -0.059997558593658, 0, 0, -179.54675292969, easing)
	setTimer(attachElements, timeopendoor, 1, cablewaymountchiliaddoor, cablewaymountchiliad, 1.3035336179581, 1.3823383049605, -0.049987792966249, 0, 0, -179.95056152344)
	setTimer(cablewaytoangelpine2, speed+wait, 1)
end