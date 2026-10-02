-- Admin / test commands. Players cannot skip the introduction; these are for testing and support.
--   /intro start <player> [full | updates | <moduleId>]
--                                    pending modules / the main line / every update / one module
--   /intro stop <player>                          ends it without marking anything as seen
--   /intro reset <player | account> [xp]          forgets what was seen (xp: the rewards too)
--   /intro list                                   modules and whether they run now

local PREFIX = "#f2ab2f[Intro] #ffffff"

local function chat(player, text)
    outputChatBox(PREFIX .. text, player, 255, 255, 255, true)
end

local function isAdmin(player)
    if getElementData(player, "isLogged") ~= true then return false end
    return (tonumber(exports.v_mysql:getAccData(player, "admin_level")) or 0) >= INTRO.ADMIN_LEVEL
end

local function findPlayer(name)
    if not name then return nil end
    local exact = getPlayerFromName(name)
    if exact then return exact end
    local needle = name:lower()
    for _, p in ipairs(getElementsByType("player")) do
        if getPlayerName(p):lower():find(needle, 1, true) then return p end
    end
end

addCommandHandler("intro", function(player, _, action, target, extra)
    if not isAdmin(player) then return end

    if action == "list" then
        for _, def in ipairs(Intro.available()) do
            local kind = def.update and ("update" .. (def.expires and (", expires " .. def.expires) or "")) or "main"
            chat(player, ("%s  #aaaaaa(%s, order %d, v%d, %d XP)"):format(def.id, kind, def.order, def.version, def.xp))
        end
        return
    end

    if action == "reset" then
        if not target then return chat(player, "/intro reset <player | account> [xp]") end
        local p = findPlayer(target)
        local who = p or exports.v_accounts:accountNameExists(target)
        if not who then return chat(player, "No such player or account.") end
        Progress.reset(who, extra == "xp")
        return chat(player, "Introduction progress reset for " .. (p and getPlayerName(p) or who) .. ".")
    end

    local p = findPlayer(target)
    if not p then return chat(player, "/intro start|stop|reset <player>, /intro list") end

    if action == "stop" then
        if Session.finish(p, "stopped") then chat(player, "Stopped.") else chat(player, "Not in the introduction.") end
    elseif action == "start" then
        local list, mode
        if extra == "full" then
            list, mode = Intro.available("main"), "full"
        elseif extra == "updates" then
            list, mode = Intro.available("update"), "new"
        elseif extra then
            local def = Intro.get(extra)
            if not def then return chat(player, "Unknown module: " .. extra) end
            list, mode = { def }, "preview"
        else
            list, mode = Session.pending(p)
        end
        local ok, err = Session.start(p, { modules = list, mode = mode })
        chat(player, ok and "Started." or err)
    else
        chat(player, "/intro start|stop|reset <player>, /intro list")
    end
end)
