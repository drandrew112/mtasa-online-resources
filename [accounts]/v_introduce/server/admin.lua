if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Admin / test commands (players skip with the keys, see client/runner.lua).
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
            local kind = def.update and ("update" .. (def.expires and (L.msg("v_introduce.admin.expires", { expires = def.expires })) or "")) or "main"
            chat(player, L.msg("v_introduce.admin.order_v_xp", { id = def.id, kind = kind, order = def.order, version = def.version, xp = def.xp }))
        end
        return
    end

    if action == "reset" then
        if not target then return chat(player, L.msg("v_introduce.admin.intro_reset_player_account_xp")) end
        local p = findPlayer(target)
        local who = p or exports.v_accounts:accountNameExists(target)
        if not who then return chat(player, L.msg("v_introduce.admin.no_such_player_or_account")) end
        Progress.reset(who, extra == "xp")
        return chat(player, L.msg("v_introduce.admin.introduction_progress_reset_for", { who = (p and getPlayerName(p) or who) }))
    end

    local p = findPlayer(target)
    if not p then return chat(player, L.msg("v_introduce.admin.intro_start_stop_reset_player_intro")) end

    if action == "stop" then
        if Session.finish(p, "stopped") then chat(player, "Stopped.") else chat(player, L.msg("v_introduce.admin.not_in_introduction")) end
    elseif action == "start" then
        local list, mode
        if extra == "full" then
            list, mode = Intro.available("main"), "full"
        elseif extra == "updates" then
            list, mode = Intro.available("update"), "new"
        elseif extra then
            local def = Intro.get(extra)
            if not def then return chat(player, L.msg("v_introduce.admin.unknown_module", { extra = extra })) end
            list, mode = { def }, "preview"
        else
            list, mode = Session.pending(p)
        end
        local ok, err = Session.start(p, { modules = list, mode = mode })
        chat(player, ok and "Started." or err)
    else
        chat(player, L.msg("v_introduce.admin.intro_start_stop_reset_player_intro"))
    end
end)
