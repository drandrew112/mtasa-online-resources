

addCommandHandler("showrespawnpoints", function(plr)
    for i,v in ipairs(respawn_points) do
        local x,y,z = v[1], v[2], v[3]
        local marker = createMarker(x,y,z, "checkpoint", 4, 255,255,0,150, plr)
        createBlipAttachedTo(marker, 1, 1, 255,255,0, 255, 0, 3000, plr)
    end
end)

function getRespawnPoint(x, y)
    local temp = {} -- Define a table to store our data.
    local valid_points = {} -- Table to store points within the distance range.

    for index = 1, #respawn_points do -- Loop from 1 to the total items in "respawn_points" table.
        local dist = getDistanceBetweenPoints2D(x, y, respawn_points[index][1], respawn_points[index][2]) -- Get the distance between the respawn_points coordinates and the given coordinates.
        table.insert(temp, {index = index, dist = dist}) -- Insert it into our "temp" table.
        if dist >= 30 and dist <= 100 then
            table.insert(valid_points, {index = index, dist = dist}) -- Insert into valid_points if within the range.
        end
    end

    if #valid_points > 0 then
        -- If there are valid points, choose one randomly.
        local random_index = random(1, #valid_points)
        return unpack(respawn_points[valid_points[random_index].index])
    else
        -- If no points are within the range, sort the "temp" table by lowest distance.
        table.sort(
            temp,
            function(a, b)
                return ((a.dist or 0) < (b.dist or 0))
            end
        )
        return unpack(respawn_points[temp[1].index]) -- Return the X, Y and Z from the nearest respawn_point.
    end
end

local savedWeapons = {} -- Halálkor eltárolt fegyverek játékosonként.

function saveWeapons(player)
    local weapons = {}
    for slot = 0, 12 do
        local weapon = getPedWeapon(player, slot)
        local ammo = getPedTotalAmmo(player, slot)
        if weapon and weapon > 0 and ammo and ammo > 0 then
            weapons[#weapons + 1] = { weapon = weapon, ammo = ammo }
        end
    end
    savedWeapons[player] = weapons
end

function restoreWeapons(player)
    local weapons = savedWeapons[player]
    if not weapons then return end
    for _, data in ipairs(weapons) do
        giveWeapon(player, data.weapon, data.ammo, false)
    end
    savedWeapons[player] = nil
end

function Wasted ( )
    setElementData(source, "skin", getElementModel(source))
    saveWeapons(source)
    triggerClientEvent(source, "drawWasted", source)
end
addEventHandler("onPlayerWasted", getRootElement(), Wasted)

addEventHandler("onPlayerQuit", getRootElement(), function()
    savedWeapons[source] = nil
end)

addEvent("respawnAfterWasted", true)
addEventHandler("respawnAfterWasted", getRootElement(), function()
    local px,py,pz = getElementPosition(source)
    local x,y,z = getRespawnPoint(px,py)
	spawnPlayer(source, x,y,z, random(0,359), getElementData(source, "skin"), 0, 0, getPlayerTeam(source))
	restoreWeapons(source)
end)

function player_Spawn()
	setCameraTarget(source, source)
	setElementData(source, "halott", false)
end
addEventHandler ( "onPlayerSpawn", getRootElement(), player_Spawn )

addCommandHandler("spawnfix", function(source)
	spawnPlayer(source, 0,0,0)
end)

addCommandHandler("fixme",
	function (player, cmd)
		setElementDimension ( player, 0 )
		setElementInterior ( player, 0 )
	end
)

addEvent("pos:saveToFile", true)
addEventHandler("pos:saveToFile", resourceRoot, function(text)
    local filePath = "positions.txt"
    local file = fileOpen(filePath)
    if not file then
        file = fileCreate(filePath)
    else
        fileSetPos(file, fileGetSize(file)) -- a végére írunk
    end

    if file then
        fileWrite(file, text.."\n")
        fileClose(file)
    end
end)