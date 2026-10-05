-- /medscenesummon - pick an exact scene from a menu (ui_inac temp menu, same folder
-- tree as "Load scene" in the editor) and spawn it immediately. Unlike /medscenerandom
-- [name], nothing needs typing: it works like the scene editor's load list.

addEvent("msm:summonPick", true)

local function playerName(player)
    return isElement(player) and getPlayerName(player) or "console"
end

local function sceneList()
    local list = {}
    for _, s in ipairs(Storage.list()) do
        list[#list + 1] = {
            name = s.name, path = s.path, title = s.title,
            peds = s.peds, vehicles = s.vehicles,
            active = Live.isActive(s.name),
        }
    end
    return list
end

addCommandHandler(MSM.CMD_SUMMON, function(player)
    if not msmIsAllowed(player) then return end
    triggerClientEvent(player, "msm:summonOpen", resourceRoot, sceneList())
end)

addEventHandler("msm:summonPick", resourceRoot, function(name)
    local player = client
    if not msmIsAllowed(player) or type(name) ~= "string" then return end
    if not Storage.exists(name) then
        msmSay(player, "Unknown scene: #ffd24a" .. name)
        return
    end
    local id, err = Live.spawn(name, "command:" .. playerName(player))
    if id then
        msmSay(player, ("Scene #ffd24a%s#ffffff spawned (#%d).%s"):format(name, id, err and (" #ff9a3c" .. err) or ""))
    else
        msmSay(player, "Could not spawn: " .. tostring(err))
    end
end)
