-- /scenesummon - pick an exact scene from a menu (ui_inac temp menu, same folder
-- tree as "Load scene" in the editor) and spawn it immediately. Unlike /scenerandom
-- [name], nothing needs typing: it works like the scene editor's load list.

addEvent("vsm:summonPick", true)

local function sceneList(player)
    local lang = L.lang and L.lang(player) or "en"
    local list = {}
    for _, s in ipairs(Storage.list()) do
        list[#list + 1] = {
            name = s.name, path = s.path, title = Storage.title(s, lang),
            peds = s.peds, vehicles = s.vehicles, needs = s.needs, valid = s.valid,
            active = Live.isActive(s.name),
        }
    end
    return list
end

addCommandHandler(VSM.CMD_SUMMON, function(player)
    if not vsmIsAllowed(player) then return end
    -- ~1900 scenes in one event arrived truncated on the client (categories missing), so the list
    -- goes out in chunks; the client builds the menu when the last one is in.
    local list = sceneList(player)
    local size = 150
    local chunks = math.max(1, math.ceil(#list / size))
    for c = 1, chunks do
        local part = {}
        for i = (c - 1) * size + 1, math.min(#list, c * size) do part[#part + 1] = list[i] end
        triggerClientEvent(player, "vsm:summonOpen", resourceRoot, part, c, chunks, #list)
    end
end)

addEventHandler("vsm:summonPick", resourceRoot, function(name)
    local player = client
    if not vsmIsAllowed(player) or type(name) ~= "string" then return end
    if not Storage.exists(name) then
        vsmSay(player, "v_scenemanager.err.unknown_scene", { name = name })
        return
    end
    local id, err = Live.spawn(name, "command:" .. vsmPlayerName(player))
    Auto.spawnReply(player, name, id, err)
end)
