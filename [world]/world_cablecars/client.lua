--autor: Emanuel 
--04/2021
--Cableway system :D

--CABLE WAY / Teleférico

local radius, x, y, z = 10000,0,0,0 

--remove rocks in mount chiliad
addEventHandler('onClientResourceStop', resourceRoot, 
function()
	restoreWorldModel(879,  radius, x, y, z)
	restoreWorldModel(880, radius, x, y, z )
end)

addEventHandler('onClientResourceStart', resourceRoot, 
function()
	removeWorldModel(879,  radius, x, y, z )
	removeWorldModel(880,  radius, x, y, z )
end)

function cableforcableway()
dxDrawLine3D(-2124.80688, -2552.63257, 46.5, -2255.23218, -1777.85, 464.6, tocolor(0,0,0,255), 10)
dxDrawLine3D(-2135.83423, -2554.47144, 46.5, -2265.81909, -1779.30981, 464.6, tocolor(0,0,0,255), 10)
end
addEventHandler("onClientRender", root, cableforcableway)

--show line in map not zoom bug xd
function cableforcablewayinmap()
if (isPlayerMapVisible()) then
	dxDrawLine(225, 617, 240, 709, tocolor(0, 0, 0, 255), 1, true)
end
end
addEventHandler("onClientRender", root, cableforcablewayinmap)