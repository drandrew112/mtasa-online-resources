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
