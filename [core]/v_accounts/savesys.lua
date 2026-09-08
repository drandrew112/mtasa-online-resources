--------------------------------------------------------------------------------

function saveHealth(player)
    local account = getPlayerAccount(player)
    local health = getElementHealth(player)
    if not isGuestAccount(account) then
        setAccountData(account,"health",health)
    end
end

function loadHealth(player)
    local account = getPlayerAccount(player)
    local health = tonumber(getAccountData(account,"health"))
    if health and health > 0 then
        setElementHealth(player,health)
    end
end

--------------------------------------------------------------------------------

function saveArmor(player)
    local account = getPlayerAccount(player)
    local armor = getPedArmor(player)
    if not isGuestAccount(account) then
        setAccountData(account,"armor",armor)
    end
end

function loadArmor(player)
    local account = getPlayerAccount(player)
    local armor = getAccountData(account,"armor")
    if (armor) then
        setPedArmor(player,armor)
    end
end

--------------------------------------------------------------------------------

function saveMoney(player)
    local account = getPlayerAccount(player)
    local money = getPlayerMoney(player)
    if not isGuestAccount(account) then
        setAccountData(account,"money-BETA",money)
    end
end

function loadMoney(player)
    local account = getPlayerAccount(player)
    local money = getAccountData(account,"money-BETA")
    if (money) then
        setPlayerMoney(player,money)
    end
end

--------------------------------------------------------------------------------

function saveSkin(player)
    local account = getPlayerAccount(player)
    local skin = getElementModel(player)
    if not isGuestAccount(account) then
        setAccountData(account,"skin",skin)
    end
end

function loadSkin(player)
    local account = getPlayerAccount(player)
    local skin = getAccountData(account,"skin")
    if (skin) then
        setElementModel(player,skin)
    end
end

--------------------------------------------------------------------------------

function savePosition(player)
    local account = getPlayerAccount(player)
    local x,y,z = getElementPosition(player)
    if not isGuestAccount(account) then
        setAccountData(account,"x",x)
        setAccountData(account,"y",y)
        setAccountData(account,"z",z)
        setAccountData(account,"interior",getElementInterior(player))
        setAccountData(account,"dimension",getElementDimension(player))
    end
end

function loadPosition(player)
    local account = getPlayerAccount(player)
    local skin = tonumber(getAccountData(account,"skin")) or 295
    local int = tonumber(getAccountData(account,"interior")) or 0
    local dim = tonumber(getAccountData(account,"dimension")) or 0
    local x = tonumber(getAccountData(account,"x"))
    local y = tonumber(getAccountData(account,"y"))
    local z = tonumber(getAccountData(account,"z"))

    if x and y and z then
        spawnPlayer(player,x,y,z+1,0,skin,int,dim)
    else
        -- No saved position: use the default spawn point.
        spawnPlayer(player,1685.6845703125,-2330.2578125,-1.6796875,0,skin,int,dim)
    end

    setElementInterior(player,int)
    setElementDimension(player,dim)
    setCameraTarget(player,player)
    fadeCamera(player,true)
end

-------------------------------------------------------------------------------

function saveStats(player)
    local account = getPlayerAccount(player)
    local stat1 = getPedStat(player,21)
    local stat2 = getPedStat(player,23)
    local stat3 = getPedStat(player,24)
    local stat4 = getPedStat(player,77)
    local stat5 = getPedStat(player,71)
    local stat6 = getPedStat(player,78)
    local stat7 = getPedStat(player,76)
    local stat8 = getPedStat(player,69)
    local stat9 = getPedStat(player,73)
    local stat10 = getPedStat(player,72)
    local stat11 = getPedStat(player,70)
    local stat12 = getPedStat(player,79)
    local stat13 = getPedStat(player,74)
    local stat14 = getPedStat(player,75)
    if not isGuestAccount(account) then
        setAccountData(account,"stat1",stat1)
        setAccountData(account,"stat2",stat2)
        setAccountData(account,"stat3",stat3)
        setAccountData(account,"stat4",stat4)
        setAccountData(account,"stat5",stat5)
        setAccountData(account,"stat6",stat6)
        setAccountData(account,"stat7",stat7)
        setAccountData(account,"stat8",stat8)
        setAccountData(account,"stat9",stat9)
        setAccountData(account,"stat10",stat10)
        setAccountData(account,"stat11",stat11)
        setAccountData(account,"stat12",stat12)
        setAccountData(account,"stat13",stat13)
        setAccountData(account,"stat14",stat14)
    end
end

function loadStats(player)
    local account = getPlayerAccount(player)
    local stat1 = getAccountData(account,"stat1")
    local stat2 = getAccountData(account,"stat2")
    local stat3 = getAccountData(account,"stat3")
    if (stat1) and (stat2) and (stat3) then
        setPedStat(player,21,stat1)
        setPedStat(player,23,stat2)
        setPedStat(player,24,stat3)
    end
end

-------------------------------------------------------------------------------

-- Weapon skill stats (pistol, shotgun, SMG, AK47, M4, sniper, etc.). Always
-- maxed out on spawn, regardless of saved progress.
local WEAPON_STAT_IDS = {69,70,71,72,73,74,75,76,77,78,79}
local MAX_WEAPON_STAT = 1000

function maxWeaponStats(player)
    for _, statID in ipairs(WEAPON_STAT_IDS) do
        setPedStat(player,statID,MAX_WEAPON_STAT)
    end
end

addEventHandler("onPlayerSpawn", root, function()
    maxWeaponStats(source)
end)

-------------------------------------------------------------------------------

function saveWeapons(player)
    local account = getPlayerAccount(player)
    local weapon0 = getPedWeapon(player,0)
    local weapon1 = getPedWeapon(player,1)
    local weapon2 = getPedWeapon(player,2)
    local weapon3 = getPedWeapon(player,3)
    local weapon4 = getPedWeapon(player,4)
    local weapon5 = getPedWeapon(player,5)
    local weapon6 = getPedWeapon(player,6)
    local weapon7 = getPedWeapon(player,7)
    local weapon8 = getPedWeapon(player,8)
    local weapon9 = getPedWeapon(player,9)
    local weapon10 = getPedWeapon(player,10)
    local weapon11 = getPedWeapon(player,11)
    local weapon12 = getPedWeapon(player,12)
    local ammo0 = getPedTotalAmmo(player,0)
    local ammo1 = getPedTotalAmmo(player,1)
    local ammo2 = getPedTotalAmmo(player,2)
    local ammo3 = getPedTotalAmmo(player,3)
    local ammo4 = getPedTotalAmmo(player,4)
    local ammo5 = getPedTotalAmmo(player,5)
    local ammo6 = getPedTotalAmmo(player,6)
    local ammo7 = getPedTotalAmmo(player,7)
    local ammo8 = getPedTotalAmmo(player,8)
    local ammo9 = getPedTotalAmmo(player,9)
    local ammo10 = getPedTotalAmmo(player,10)
    local ammo11 = getPedTotalAmmo(player,11)
    local ammo12 = getPedTotalAmmo(player,12)
    if not isGuestAccount(account) then
        setAccountData(account,"weapon0",weapon0)
        setAccountData(account,"weapon1",weapon1)
        setAccountData(account,"weapon2",weapon2)
        setAccountData(account,"weapon3",weapon3)
        setAccountData(account,"weapon4",weapon4)
        setAccountData(account,"weapon5",weapon5)
        setAccountData(account,"weapon6",weapon6)
        setAccountData(account,"weapon7",weapon7)
        setAccountData(account,"weapon8",weapon8)
        setAccountData(account,"weapon9",weapon9)
        setAccountData(account,"weapon10",weapon10)
        setAccountData(account,"weapon11",weapon11)
        setAccountData(account,"weapon12",weapon12)
        setAccountData(account,"ammo0",ammo0)
        setAccountData(account,"ammo1",ammo1)
        setAccountData(account,"ammo2",ammo2)
        setAccountData(account,"ammo3",ammo3)
        setAccountData(account,"ammo4",ammo4)
        setAccountData(account,"ammo5",ammo5)
        setAccountData(account,"ammo6",ammo6)
        setAccountData(account,"ammo7",ammo7)
        setAccountData(account,"ammo8",ammo8)
        setAccountData(account,"ammo9",ammo9)
        setAccountData(account,"ammo10",ammo10)
        setAccountData(account,"ammo11",ammo11)
        setAccountData(account,"ammo12",ammo12)
    end
end

function loadWeapons(player)
    local account = getPlayerAccount(player)
    local weapon0 = getAccountData(account,"weapon0")
    local weapon1 = getAccountData(account,"weapon1")
    local weapon2 = getAccountData(account,"weapon2")
    local weapon3 = getAccountData(account,"weapon3")
    local weapon4 = getAccountData(account,"weapon4")
    local weapon5 = getAccountData(account,"weapon5")
    local weapon6 = getAccountData(account,"weapon6")
    local weapon7 = getAccountData(account,"weapon7")
    local weapon8 = getAccountData(account,"weapon8")
    local weapon9 = getAccountData(account,"weapon9")
    local weapon10 = getAccountData(account,"weapon10")
    local weapon11 = getAccountData(account,"weapon11")
    local weapon12 = getAccountData(account,"weapon12")
    local ammo0 = getAccountData(account,"ammo0")
    local ammo1 = getAccountData(account,"ammo1")
    local ammo2 = getAccountData(account,"ammo2")
    local ammo3 = getAccountData(account,"ammo3")
    local ammo4 = getAccountData(account,"ammo4")
    local ammo5 = getAccountData(account,"ammo5")
    local ammo6 = getAccountData(account,"ammo6")
    local ammo7 = getAccountData(account,"ammo7")
    local ammo8 = getAccountData(account,"ammo8")
    local ammo9 = getAccountData(account,"ammo9")
    local ammo10 = getAccountData(account,"ammo10")
    local ammo11 = getAccountData(account,"ammo11")
    local ammo12 = getAccountData(account,"ammo12")
    if (weapon0) and (weapon1) and (weapon2) and (weapon3) and (weapon4) and (weapon5) and (weapon6) and (weapon7) and (weapon8) and (weapon9) and (weapon10) and (weapon11) and (weapon12) and
    (ammo0) and (ammo1) and (ammo2) and (ammo3) and (ammo4) and (ammo5) and (ammo6) and (ammo7) and (ammo8) and (ammo9) and (ammo10) and (ammo11) and (ammo12) then
        giveWeapon(player,weapon0,ammo0)
        giveWeapon(player,weapon1,ammo1)
        giveWeapon(player,weapon2,ammo2)
        giveWeapon(player,weapon3,ammo3)
        giveWeapon(player,weapon4,ammo4)
        giveWeapon(player,weapon5,ammo5)
        giveWeapon(player,weapon6,ammo6)
        giveWeapon(player,weapon7,ammo7)
        giveWeapon(player,weapon8,ammo8)
        giveWeapon(player,weapon9,ammo9)
        giveWeapon(player,weapon10,ammo10)
        giveWeapon(player,weapon11,ammo11)
        giveWeapon(player,weapon12,ammo12)
    end
end

-------------------------------------------------------------------------------

function save_all(player)
    saveHealth(player)
    saveArmor(player)
    saveMoney(player)
    saveSkin(player)
    savePosition(player)
    saveStats(player)
    saveWeapons(player)

    -- Mirror the freshly-written account data into the shared MySQL store so the
    -- localhost and the hosted server stay in sync. No-op when v_mysql is down.
    local mysqlRes = getResourceFromName("v_mysql")
    if mysqlRes and getResourceState(mysqlRes) == "running" then
        exports.v_mysql:updateAccountData(player)
    end
end
