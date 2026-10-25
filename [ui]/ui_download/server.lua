-- A beepitett MTA transfer box elrejtese (a sajat letolto kepernyonk rajzol helyette).
--
-- A setTransferBoxVisible csak a mar csatlakozott jatekosoknak kuldi ki az
-- allapotot, es ha az ertek nem valtozik, semmit sem kuld. Igy a szerver
-- inditasakor (meg nincs jatekos) beallitott "false" nem jut el a kesobb
-- belepokhoz, nekik a default box jelenne meg. Ezert minden belepeskor
-- ujra kikuldjuk (true -> false valtassal, hogy biztosan menjen packet);
-- az onPlayerJoin meg a resource-ok letoltese elott fut.

local function hideTransferBox()
    if isTransferBoxVisible() == false then
        setTransferBoxVisible(true)
    end
    setTransferBoxVisible(false)
end

addEventHandler("onResourceStart", resourceRoot, hideTransferBox)
addEventHandler("onPlayerJoin", root, hideTransferBox)

-- Csatlakozasi letoltes vege: a kliens nem a transfer box eltuneseibol talalgat
-- (MTA csoportonkent tolt, kozben a box tobbszor eltunik, a gap barmilyen hosszu
-- lehet), hanem megkapja azon futo resource-ok nevet, amelyek a kliensen is
-- elindulnak (kliens script / file / kliens config a meta.xml-ben), es akkor
-- jelez, amikor mind fut nala.

local clientSynced = nil -- cache: { [nev] = true }, resource start/stop torli
local waiting = {}       -- jatekosok, akiknek meg folyik a csatlakozasi letoltese

local function isClientSynced(res)
    local meta = xmlLoadFile(":" .. getResourceName(res) .. "/meta.xml", true)
    if not meta then return false end
    local synced = false
    for _, node in ipairs(xmlNodeGetChildren(meta)) do
        local tag = xmlNodeGetName(node)
        local t = xmlNodeGetAttribute(node, "type")
        if tag == "file"
            or (tag == "script" and (t == "client" or t == "shared"))
            or (tag == "config" and t == "client") then
            synced = true
            break
        end
    end
    xmlUnloadFile(meta)
    return synced
end

local function getClientSynced()
    if clientSynced then return clientSynced end
    clientSynced = {}
    for _, res in ipairs(getResources()) do
        local state = getResourceState(res)
        if (state == "running" or state == "starting") and isClientSynced(res) then
            clientSynced[getResourceName(res)] = true
        end
    end
    return clientSynced
end

local function notifyWaiting(event, name)
    for player in pairs(waiting) do
        if isElement(player) then triggerClientEvent(player, event, resourceRoot, name) end
    end
end

addEventHandler("onResourceStart", root, function(res)
    clientSynced = nil
    if res ~= resource and isClientSynced(res) then notifyWaiting("ui_download:expectAdd", getResourceName(res)) end
end)

addEventHandler("onResourceStop", root, function(res)
    clientSynced = nil
    notifyWaiting("ui_download:expectRemove", getResourceName(res))
end)

addEvent("ui_download:requestExpected", true)
addEventHandler("ui_download:requestExpected", resourceRoot, function()
    if not client then return end
    waiting[client] = true
    local names = {}
    for name in pairs(getClientSynced()) do names[#names + 1] = name end
    triggerClientEvent(client, "ui_download:expected", resourceRoot, names)
end)

addEvent("ui_download:joinDone", true)
addEventHandler("ui_download:joinDone", resourceRoot, function()
    if client then waiting[client] = nil end
end)

addEventHandler("onPlayerQuit", root, function() waiting[source] = nil end)
