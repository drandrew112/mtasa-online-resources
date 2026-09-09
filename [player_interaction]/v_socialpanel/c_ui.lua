--[[
    v_socialpanel / c_ui.lua
    Social panel rendering. Pure DX, immediate-mode (see c_controls.lua / UI).

    Views (content_id):
      1 = HOME     2 = HELP     3 = SOCIAL     4 = PROFILE
]]

show_socialpanel = false
content_id = 1

local sw, sh = guiGetScreenSize()
local W, H = 900, 620
local TOPBAR = 60
local X = sw / 2 - W / 2
local Y = TOPBAR + 20

local C = {
    shade  = tocolor(0, 0, 0, 150),
    bar    = tocolor(20, 20, 20, 255),
    accent = tocolor(255, 200, 0, 255),
    bg     = tocolor(240, 240, 240, 255),
    panel  = tocolor(255, 255, 255, 255),
    grey   = tocolor(200, 200, 200, 255),
    line   = tocolor(0, 0, 0, 25),
    dark   = tocolor(25, 25, 25, 255),
    white  = tocolor(255, 255, 255, 255),
    green  = tocolor(0, 190, 0, 255),
    red    = tocolor(210, 60, 60, 255),
    blue   = tocolor(70, 140, 210, 255),
    sub    = tocolor(110, 110, 110, 255),
}

local TABS = { "HOME", "HELP", "SOCIAL", "PROFILE" }

--------------------------------------------------------------------------------
-- HELP content
--------------------------------------------------------------------------------

local HELP_TABS = { "BASICS", "INAC MENU", "MINIGAMES", "VEHICLES", "RULES" }
local HELP_TEXT = {
    ["BASICS"] = {
        "Three menus run everything on the server:",
        "",
        "INAC menu  -  press  M",
        "Your personal hub: fast travel, spawn a vehicle, collectibles",
        "and your stats (level, played time).",
        "",
        "Social panel  -  press  HOME  or  NUM 7   (this panel)",
        "Friends, player profiles, crews and private / crew messaging.",
        "",
        "Pause menu  -  press  P",
        "The server pause menu: settings, player list, keybinds, quit.",
        "",
        "Close any panel with ESC.",
    },
    ["INAC MENU"] = {
        "Open it with  M .  Move with the arrow keys, confirm with Enter,",
        "go back with Backspace.",
        "",
        "What you can do here:",
        "- Fast Travel: jump to LS / LV / SF airport (not while in a vehicle).",
        "- Vehicle: spawn any game vehicle to mess around with. These are",
        "  temporary and CANNOT be tuned or modified.",
        "- Collectibles: track your stunt jumps and hidden UFO parts.",
        "- Stats: your current level and total played time.",
        "",
        "The INAC menu is about your character; the Social panel (HOME)",
        "is about other players.",
    },
    ["MINIGAMES"] = {
        "Game modes on the server:",
        "",
        "JOBS",
        "A GTA Online style lobby system. Pick a job, wait in the lobby,",
        "then everyone starts together. Two types:",
        "  Race  -  checkpoint racing to the finish line.",
        "  DM    -  deathmatch, last player / team standing wins.",
        "",
        "ARENA WAR",
        "Vehicle combat in a closed arena. Take a weaponised car, wreck the",
        "other players, respawn and keep fighting. Score counts your kills.",
        "",
        "TIME TRIAL",
        "Solo race against the clock. Only ONE track is active at a time and",
        "it rotates to a new one every so often. Beat the target time and",
        "your best lap is saved.",
    },
    ["VEHICLES"] = {
        "Two kinds of vehicles:",
        "",
        "Spawned vehicles (INAC menu)",
        "Any vehicle in the game can be pulled from the INAC menu, but those",
        "are throwaway - no tuning, no modifications, no saving.",
        "",
        "Owned vehicles (Phone)",
        "Buy your own vehicles with in-game money in the Phone. Once owned",
        "you can spawn them from the Phone and they persist.",
        "",
        "Tuning",
        "Only owned vehicles can be modified - drive into a tuning shop (mod",
        "garage) to change parts, paint and performance.",
        "",
        "Every vehicle has a working radio and a GPS.",
    },
    ["RULES"] = {
        "1. No cheating. Mods, trainers, scripts or any helper program that",
        "   gives an advantage is forbidden.",
        "",
        "2. Do not deliberately ruin other players' experience - for example",
        "   killing the same person again and again for no reason.",
        "",
        "3. No discrimination of any kind (gender, skin colour, religion,",
        "   nationality, orientation, ...).",
        "",
        "4. No advertising - other servers, sites, services, etc.",
        "",
        "Breaking the rules can get you banned. Appeal on Discord.",
    },
}
local help_tab = 1

--------------------------------------------------------------------------------
-- SOCIAL sub-tabs
--------------------------------------------------------------------------------

local SOCIAL_TABS = { "FRIENDS", "REQUESTS", "FIND PLAYER", "MESSAGES", "MY CREW", "FIND CREW" }
local social_tab = 1

--------------------------------------------------------------------------------
-- Client-side state (from the server)
--------------------------------------------------------------------------------

local snapshot = { account = nil, friends = {}, requests = {}, crew = nil, crews = {}, conversations = {} }
local viewedProfile = nil          -- nil = own profile; otherwise server data
local searchResults, searchNote = {}, nil
local openConv = nil               -- { kind = "dm"/"crew", with = name }
local thread = {}                  -- messages of the open conversation

--------------------------------------------------------------------------------
-- Server -> client
--------------------------------------------------------------------------------

addEvent("sp:push", true)
addEventHandler("sp:push", root, function(snap)
    if type(snap) ~= "table" then return end
    -- Keep the open conversation visually "read" (server syncs it on next open).
    if openConv then
        for _, c in ipairs(snap.conversations or {}) do
            if c.kind == openConv.kind and c.with:lower() == openConv.with:lower() then
                c.unread = 0
            end
        end
    end
    snapshot = snap
end)

addEvent("sp:profile:show", true)
addEventHandler("sp:profile:show", root, function(data, wantedName)
    if data then
        viewedProfile = data
        content_id = 4
    else
        outputChatBox("#f0c800[Social] #ffffffNo such player: " .. tostring(wantedName), 255, 255, 255, true)
    end
end)

addEvent("sp:search:results", true)
addEventHandler("sp:search:results", root, function(list, note)
    searchResults = type(list) == "table" and list or {}
    searchNote = note
end)

-- Minden bejovo uzenetrol ui_core ertesitest kap a jatekos, fuggetlenul attol,
-- hogy a social panel eppen nyitva van-e vagy melyik chatet nezi.
addEvent("sp:notify", true)
addEventHandler("sp:notify", root, function(kind, from, text, crewTag)
    from = tostring(from or "?")
    local title = (kind == "crew")
        and ("[" .. tostring(crewTag or "CREW") .. "] " .. from)
        or ("Uj uzenet - " .. from)
    local preview = tostring(text or "")
    if utf8.len(preview) and utf8.len(preview) > 60 then
        preview = utf8.sub(preview, 1, 57) .. "..."
    end
    pcall(function() exports.ui_core:addNotification(title, preview) end)
end)

addEvent("sp:msg:data", true)
addEventHandler("sp:msg:data", root, function(kind, with, msgs)
    if openConv and openConv.kind == kind and openConv.with:lower() == tostring(with):lower() then
        thread = type(msgs) == "table" and msgs or {}
        if UI and UI.scroll then UI.scroll["msg_thread"] = 1e9 end -- snap to newest
        for _, c in ipairs(snapshot.conversations or {}) do
            if c.kind == kind and c.with:lower() == openConv.with:lower() then c.unread = 0 end
        end
    end
end)

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

local function para(lines, x, y, w)
    local size, font = 1.25, "default"
    local lineH = dxGetFontHeight(size, font) + 3
    local yy = y
    for _, ln in ipairs(lines) do
        if ln == "" then
            yy = yy + lineH * 0.6
        else
            local cur = ""
            for word in ln:gmatch("%S+") do
                local test = (cur == "") and word or (cur .. " " .. word)
                if dxGetTextWidth(test, size, font) > w and cur ~= "" then
                    dxDrawText(cur, x, yy, x + w, yy + lineH, tocolor(40, 40, 40, 255), size, font, "left", "top")
                    yy = yy + lineH
                    cur = word
                else
                    cur = test
                end
            end
            if cur ~= "" then
                dxDrawText(cur, x, yy, x + w, yy + lineH, tocolor(40, 40, 40, 255), size, font, "left", "top")
                yy = yy + lineH
            end
        end
    end
end

local function crewColor(col)
    if type(col) == "table" then return tocolor(col[1], col[2], col[3], 255) end
    return C.accent
end

local function clock(ts)
    local t = getRealTime(tonumber(ts) or 0)
    return ("%02d:%02d"):format(t.hour, t.minute)
end

local function ellipsis(str, size, font, maxW)
    if dxGetTextWidth(str, size, font) <= maxW then return str end
    while #str > 1 and dxGetTextWidth(str .. "...", size, font) > maxW do
        str = str:sub(1, -2)
    end
    return str .. "..."
end

local function openConversation(kind, with)
    openConv = { kind = kind, with = with }
    thread = {}
    content_id = 3
    social_tab = 4
    triggerServerEvent("sp:msg:open", localPlayer, kind, with)
end

--------------------------------------------------------------------------------
-- Main render
--------------------------------------------------------------------------------

-- "low" prioritas: minden mas onClientRender utan fut le, igy a social panel
-- mindig a legfelso reteg (pl. a nyitva hagyott pause menu folott).
addEventHandler("onClientRender", root, function()
    if not show_socialpanel then return end
    UI.beginFrame()

    dxDrawRectangle(0, 0, sw, sh, C.shade)
    dxDrawRectangle(0, 0, sw, TOPBAR, C.bar)
    dxDrawRectangle(0, TOPBAR, sw, 4, C.accent)

    -- "FREE V" branding exiled to the very top-left corner.
    dxDrawText("FreeV", 12, 0, 12, TOPBAR, tocolor(255, 200, 0, 120), 1.0, "pricedown", "left", "center")

    -- Panel title where the branding used to be.
    dxDrawText("SOCIAL PANEL", X, 0, X, TOPBAR, C.white, 1.5, "default-bold", "left", "center")

    local tabX = X + dxGetTextWidth("SOCIAL PANEL", 1.5, "default-bold") + 55
    for i, name in ipairs(TABS) do
        local label = (name == "PROFILE") and (snapshot.account or getPlayerName(localPlayer)) or name
        local tw = dxGetTextWidth(label, 1.4, "default-bold") + 30
        if UI.button(tabX, 0, tw, TOPBAR, label, {
            font = "default-bold", bg = C.bar, txt = C.white,
            hoverBg = C.bar, hoverTxt = C.accent,
            selected = (i == content_id), selTxt = C.accent,
        }) then
            content_id = i
            if i == 4 then viewedProfile = nil end
        end
        tabX = tabX + tw
    end

    dxDrawRectangle(X, Y, W, H, C.bg)

    if content_id == 1 then renderHome()
    elseif content_id == 2 then renderHelp()
    elseif content_id == 3 then renderSocial()
    elseif content_id == 4 then renderProfile() end

    dxDrawText("[ESC] close", X, Y + H + 6, X + W, Y + H + 26, C.white, 1.3, "default-bold", "right", "top")
end, false, "low")

--------------------------------------------------------------------------------
-- HOME
--------------------------------------------------------------------------------

function renderHome()
    local leftW = W * 0.58

    -- Left grey strip: KEPT EMPTY (weekly-update images will go here later).
    dxDrawRectangle(X, Y, leftW, H, C.grey)
    dxDrawText("Weekly updates", X, Y + H / 2 - 30, X + leftW, Y + H / 2 - 30,
        tocolor(255, 255, 255, 60), 2.2, "default-bold", "center", "top")
    dxDrawText("images coming soon", X, Y + H / 2 + 6, X + leftW, Y + H / 2 + 6,
        tocolor(255, 255, 255, 45), 1.3, "default", "center", "top")

    local rx = X + leftW + 14
    local rw = W - leftW - 28
    local online = {}
    for _, f in ipairs(snapshot.friends or {}) do
        if f.online then online[#online + 1] = f end
    end

    dxDrawText("Friends online (" .. #online .. ")", rx, Y + 14, rx + rw, Y + 40,
        C.dark, 1.7, "default-bold", "left", "top")

    if #online == 0 then
        dxDrawText("No friends online.", rx, Y + 70, rx + rw, Y + 90, C.sub, 1.3, "default", "left", "top")
        return
    end

    local listY, rowH, areaH = Y + 52, 58, H - 66
    local off = UI.beginScroll("home_online", rx, listY, rw, areaH, #online * (rowH + 6))
    for i, f in ipairs(online) do
        local ry = listY + (i - 1) * (rowH + 6) - off
        if ry + rowH > listY and ry < listY + areaH then
            dxDrawRectangle(rx, ry, rw, rowH, C.panel)
            dxDrawRectangle(rx, ry, 4, rowH, C.green)
            dxDrawText(f.name, rx + 14, ry + 8, rx + rw, ry + 28, C.dark, 1.4, "default-bold", "left", "top")
            dxDrawText(("Level %s  |  %s"):format(f.level, f.playtime), rx + 14, ry + 30, rx + rw, ry + 48,
                C.sub, 1.15, "default", "left", "top")
            if UI.button(rx + rw - 92, ry + 12, 84, rowH - 24, "Profile", { size = 1.2, bg = C.bg }) then
                triggerServerEvent("sp:profile:view", localPlayer, f.name)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- HELP
--------------------------------------------------------------------------------

function renderHelp()
    local sideW = W * 0.26
    local rowH = H / #HELP_TABS
    for i, name in ipairs(HELP_TABS) do
        if UI.button(X, Y + (i - 1) * rowH, sideW, rowH, name, {
            bg = C.grey, txt = C.dark, hoverBg = C.white,
            selected = (i == help_tab), selBg = C.white, selTxt = C.dark,
        }) then
            help_tab = i
        end
        if i == help_tab then
            dxDrawRectangle(X + sideW - 4, Y + (i - 1) * rowH, 4, rowH, C.accent)
        end
    end

    local cx, cw = X + sideW + 24, W - sideW - 48
    local name = HELP_TABS[help_tab]
    dxDrawText(name, cx, Y + 18, cx + cw, Y + 50, C.dark, 2.1, "default-bold", "left", "top")
    dxDrawRectangle(cx, Y + 54, cw, 2, C.line)
    para(HELP_TEXT[name] or { "..." }, cx, Y + 70, cw)
end

--------------------------------------------------------------------------------
-- SOCIAL
--------------------------------------------------------------------------------

function renderSocial()
    local sideW = W * 0.26
    local rowH = H / #SOCIAL_TABS
    for i, name in ipairs(SOCIAL_TABS) do
        local badge
        if i == 2 and #(snapshot.requests or {}) > 0 then badge = #snapshot.requests end
        if i == 4 then
            local u = 0
            for _, c in ipairs(snapshot.conversations or {}) do u = u + (c.unread or 0) end
            if u > 0 then badge = u end
        end
        if UI.button(X, Y + (i - 1) * rowH, sideW, rowH, badge and (name .. "  (" .. badge .. ")") or name, {
            bg = C.grey, txt = C.dark, hoverBg = C.white,
            selected = (i == social_tab), selBg = C.white, selTxt = C.dark, size = 1.3,
        }) then
            social_tab = i
        end
        if i == social_tab then
            dxDrawRectangle(X + sideW - 4, Y + (i - 1) * rowH, 4, rowH, C.accent)
        end
    end

    local cx, cw, cy = X + sideW + 20, W - sideW - 40, Y + 16

    if social_tab == 1 then socialFriends(cx, cy, cw)
    elseif social_tab == 2 then socialRequests(cx, cy, cw)
    elseif social_tab == 3 then socialFindPlayer(cx, cy, cw)
    elseif social_tab == 4 then socialMessages(cx, cy, cw)
    elseif social_tab == 5 then socialMyCrew(cx, cy, cw)
    elseif social_tab == 6 then socialFindCrew(cx, cy, cw) end
end

function socialFriends(cx, cy, cw)
    local friends = snapshot.friends or {}
    dxDrawText("Friends (" .. #friends .. ")", cx, cy, cx + cw, cy + 26, C.dark, 1.7, "default-bold", "left", "top")
    if #friends == 0 then
        dxDrawText("No friends yet. Add players on the FIND PLAYER tab.",
            cx, cy + 40, cx + cw, cy + 80, C.sub, 1.25, "default", "left", "top")
        return
    end
    local listY, rowH, gap, areaH = cy + 40, 56, 6, H - 60
    local off = UI.beginScroll("fr_list", cx, listY, cw, areaH, #friends * (rowH + gap))
    for i, f in ipairs(friends) do
        local ry = listY + (i - 1) * (rowH + gap) - off
        if ry + rowH > listY and ry < listY + areaH then
            dxDrawRectangle(cx, ry, cw, rowH, C.panel)
            dxDrawRectangle(cx, ry, 4, rowH, f.online and C.green or C.grey)
            dxDrawText(f.name, cx + 14, ry + 7, cx + cw, ry + 27, C.dark, 1.4, "default-bold", "left", "top")
            dxDrawText(("%s  |  Level %s  |  %s"):format(f.online and "Online" or "Offline", f.level, f.playtime),
                cx + 14, ry + 29, cx + cw, ry + 47, C.sub, 1.1, "default", "left", "top")
            if UI.button(cx + cw - 270, ry + 12, 82, rowH - 24, "Profile", { size = 1.15, bg = C.bg }) then
                triggerServerEvent("sp:profile:view", localPlayer, f.name)
            end
            if UI.button(cx + cw - 182, ry + 12, 88, rowH - 24, "Message", { size = 1.15, bg = C.bg, hoverBg = C.blue, hoverTxt = C.white }) then
                openConversation("dm", f.name)
            end
            if UI.button(cx + cw - 88, ry + 12, 80, rowH - 24, "Remove", { size = 1.15, bg = C.bg, hoverBg = C.red, hoverTxt = C.white }) then
                triggerServerEvent("sp:friend:remove", localPlayer, f.name)
            end
        end
    end
end

function socialRequests(cx, cy, cw)
    local reqs = snapshot.requests or {}
    dxDrawText("Friend requests (" .. #reqs .. ")", cx, cy, cx + cw, cy + 26, C.dark, 1.7, "default-bold", "left", "top")
    if #reqs == 0 then
        dxDrawText("No pending friend requests.", cx, cy + 40, cx + cw, cy + 70, C.sub, 1.25, "default", "left", "top")
        return
    end
    local listY, rowH, gap = cy + 40, 52, 6
    for i, name in ipairs(reqs) do
        local ry = listY + (i - 1) * (rowH + gap)
        dxDrawRectangle(cx, ry, cw, rowH, C.panel)
        dxDrawText(name, cx + 14, ry, cx + cw, ry + rowH, C.dark, 1.4, "default-bold", "left", "center")
        if UI.button(cx + cw - 200, ry + 10, 92, rowH - 20, "Accept", { size = 1.2, bg = C.bg, hoverBg = C.green, hoverTxt = C.white }) then
            triggerServerEvent("sp:friend:accept", localPlayer, name)
        end
        if UI.button(cx + cw - 100, ry + 10, 92, rowH - 20, "Decline", { size = 1.2, bg = C.bg, hoverBg = C.red, hoverTxt = C.white }) then
            triggerServerEvent("sp:friend:decline", localPlayer, name)
        end
    end
end

function socialFindPlayer(cx, cy, cw)
    dxDrawText("Find player", cx, cy, cx + cw, cy + 26, C.dark, 1.7, "default-bold", "left", "top")
    dxDrawText("Searches online and offline (registered) players.", cx, cy + 26, cx + cw, cy + 46,
        C.sub, 1.1, "default", "left", "top")
    local q, entered = UI.input("find_player", cx, cy + 50, cw - 110, 34, { placeholder = "Player name..." })
    local doSearch = entered
    if UI.button(cx + cw - 100, cy + 50, 100, 34, "Search", { size = 1.25, bg = C.dark, txt = C.white }) then
        doSearch = true
    end
    if doSearch and q ~= "" then
        triggerServerEvent("sp:search", localPlayer, q)
    end

    if searchNote then
        dxDrawText(searchNote, cx, cy + 94, cx + cw, cy + 112, C.red, 1.15, "default", "left", "top")
    else
        dxDrawText(#searchResults .. " result(s)", cx, cy + 94, cx + cw, cy + 112, C.sub, 1.15, "default", "left", "top")
    end

    local listY, rowH, gap, areaH = cy + 116, 54, 6, H - 134
    local off = UI.beginScroll("fp_list", cx, listY, cw, areaH, #searchResults * (rowH + gap))
    for i, r in ipairs(searchResults) do
        local ry = listY + (i - 1) * (rowH + gap) - off
        if ry + rowH > listY and ry < listY + areaH then
            dxDrawRectangle(cx, ry, cw, rowH, C.panel)
            dxDrawRectangle(cx, ry, 4, rowH, r.online and C.green or C.grey)
            dxDrawText(r.name, cx + 14, ry + 6, cx + cw, ry + 26, C.dark, 1.35, "default-bold", "left", "top")
            dxDrawText(("%s  |  Level %s  |  %s"):format(r.online and "Online" or "Offline", r.level, r.playtime),
                cx + 14, ry + 28, cx + cw, ry + 46, C.sub, 1.1, "default", "left", "top")
            if UI.button(cx + cw - 270, ry + 11, 82, rowH - 22, "Profile", { size = 1.1, bg = C.bg }) then
                triggerServerEvent("sp:profile:view", localPlayer, r.name)
            end
            if UI.button(cx + cw - 182, ry + 11, 88, rowH - 22, "Message", { size = 1.1, bg = C.bg, hoverBg = C.blue, hoverTxt = C.white }) then
                openConversation("dm", r.name)
            end
            if UI.button(cx + cw - 88, ry + 11, 80, rowH - 22, "Add", { size = 1.1, bg = C.bg, hoverBg = C.green, hoverTxt = C.white }) then
                triggerServerEvent("sp:friend:add", localPlayer, r.name)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- MESSAGES
--------------------------------------------------------------------------------

function socialMessages(cx, cy, cw)
    local convW = math.floor(cw * 0.36)
    local convos = snapshot.conversations or {}

    -- Conversation list
    dxDrawText("Chats", cx, cy, cx + convW, cy + 24, C.dark, 1.6, "default-bold", "left", "top")
    local listY, rowH, gap, areaH = cy + 30, 54, 5, H - 50
    if #convos == 0 then
        dxDrawText("No chats yet.\nOpen a profile or a friend and press Message.",
            cx, listY + 6, cx + convW, listY + 80, C.sub, 1.1, "default", "left", "top", false, true)
    end
    local off = UI.beginScroll("msg_convos", cx, listY, convW, areaH, #convos * (rowH + gap))
    for i, c in ipairs(convos) do
        local ry = listY + (i - 1) * (rowH + gap) - off
        if ry + rowH > listY and ry < listY + areaH then
            local isOpen = openConv and openConv.kind == c.kind and openConv.with:lower() == c.with:lower()
            dxDrawRectangle(cx, ry, convW - 6, rowH, C.panel)
            if isOpen then dxDrawRectangle(cx, ry, 3, rowH, C.accent) end
            local title = (c.kind == "crew") and ("[" .. (c.crewTag or "CREW") .. "] " .. c.with) or c.with
            dxDrawText(ellipsis(title, 1.25, "default-bold", convW - 60), cx + 10, ry + 6, cx + convW, ry + 24,
                isOpen and C.accent or C.dark, 1.25, "default-bold", "left", "top")
            dxDrawText(ellipsis(c.last or "", 1.0, "default", convW - 24), cx + 10, ry + 26, cx + convW, ry + 44,
                C.sub, 1.0, "default", "left", "top")
            if (c.unread or 0) > 0 and not isOpen then
                dxDrawRectangle(cx + convW - 30, ry + 8, 20, 20, C.red)
                dxDrawText(tostring(c.unread), cx + convW - 30, ry + 8, cx + convW - 10, ry + 28, C.white, 1.0, "default-bold", "center", "center")
            end
            if UI.clickedIn(cx, ry, convW - 6, rowH) then
                openConv = { kind = c.kind, with = c.with }
                thread = {}
                if UI.scroll then UI.scroll["msg_thread"] = 1e9 end
                triggerServerEvent("sp:msg:open", localPlayer, c.kind, c.with)
            end
        end
    end

    -- Thread
    local tx = cx + convW + 12
    local tw = cw - convW - 12
    dxDrawRectangle(tx, cy, tw, H - 20, C.panel)

    if not openConv then
        dxDrawText("Select a chat on the left.", tx, cy, tx + tw, cy + H - 20, C.sub, 1.3, "default", "center", "center")
        return
    end

    local header = (openConv.kind == "crew") and ("Crew chat: " .. openConv.with) or ("Chat with " .. openConv.with)
    dxDrawText(header, tx + 12, cy + 10, tx + tw - 12, cy + 34, C.dark, 1.5, "default-bold", "left", "top")
    dxDrawRectangle(tx + 12, cy + 38, tw - 24, 2, C.line)

    local areaTop = cy + 46
    local inputH = 40
    local areaBot = cy + H - 20 - inputH - 10
    local msgAreaH = areaBot - areaTop

    -- Measure total height
    local size, font = 1.15, "default"
    local lineH = dxGetFontHeight(size, font) + 2
    local bubbleW = tw - 40
    local heights = {}
    local total = 6
    for i, m in ipairs(thread) do
        local lines = 1
        local cur = ""
        for word in (m.text or ""):gmatch("%S+") do
            local test = cur == "" and word or cur .. " " .. word
            if dxGetTextWidth(test, size, font) > bubbleW - 16 and cur ~= "" then
                lines = lines + 1; cur = word
            else cur = test end
        end
        local hgt = lineH * lines + 16 + 14 -- text + padding + meta line
        heights[i] = hgt
        total = total + hgt + 4
    end

    local off2 = UI.beginScroll("msg_thread", tx + 6, areaTop, tw - 12, msgAreaH, total)
    local yy = areaTop + 6 - off2
    for i, m in ipairs(thread) do
        local hgt = heights[i]
        if yy + hgt > areaTop and yy < areaBot then
            local mine = m.mine
            local bx = mine and (tx + tw - 20 - bubbleW * 0.82) or (tx + 20)
            local bw = bubbleW * 0.82
            dxDrawRectangle(bx, yy, bw, hgt, mine and tocolor(255, 235, 170, 255) or C.bg)
            dxDrawText((mine and "You" or m.from) .. "  " .. clock(m.time), bx + 8, yy + 4, bx + bw - 8, yy + 18,
                C.sub, 1.0, "default", mine and "right" or "left", "top")
            dxDrawText(m.text or "", bx + 8, yy + 18, bx + bw - 8, yy + hgt - 4, C.dark, size, font,
                "left", "top", false, true)
        end
        yy = yy + hgt + 4
    end
    if #thread == 0 then
        dxDrawText("No messages yet. Say hi!", tx + 12, areaTop + 10, tx + tw - 12, areaTop + 30, C.sub, 1.15, "default", "left", "top")
    end

    -- Input
    local iy = cy + H - 20 - inputH - 4
    local msg, sent = UI.input("msg_input", tx + 12, iy, tw - 120, inputH, { placeholder = "Type a message..." })
    local send = sent
    if UI.button(tx + tw - 100, iy, 88, inputH, "Send", { size = 1.3, bg = C.dark, txt = C.white, hoverBg = C.green }) then
        send = true
    end
    if send then
        local clean = msg:gsub("^%s+", ""):gsub("%s+$", "")
        if clean ~= "" then
            triggerServerEvent("sp:msg:send", localPlayer, openConv.kind, openConv.with, clean)
            UI.clearInput("msg_input")
        end
    end
end

--------------------------------------------------------------------------------
-- MY CREW
--------------------------------------------------------------------------------

function socialMyCrew(cx, cy, cw)
    local crew = snapshot.crew
    if not crew then
        dxDrawText("You have no crew", cx, cy, cx + cw, cy + 26, C.dark, 1.7, "default-bold", "left", "top")
        dxDrawText("Create one below, or join an existing crew on the FIND CREW tab.",
            cx, cy + 34, cx + cw, cy + 60, C.sub, 1.2, "default", "left", "top")

        dxDrawText("Create a new crew", cx, cy + 74, cx + cw, cy + 98, C.dark, 1.5, "default-bold", "left", "top")
        local name = UI.input("crew_name", cx, cy + 104, cw - 160, 34, { placeholder = "Crew name (3-24 chars)" })
        local tag = UI.input("crew_tag", cx + cw - 150, cy + 104, 150, 34, { placeholder = "TAG" })

        dxDrawText("Colour:", cx, cy + 150, cx + 70, cy + 174, C.sub, 1.2, "default", "left", "top")
        local presets = {
            { 255, 200, 0 }, { 220, 60, 60 }, { 60, 140, 220 },
            { 80, 200, 100 }, { 170, 90, 220 }, { 240, 240, 240 },
        }
        for i, col in ipairs(presets) do
            local bx = cx + 70 + (i - 1) * 44
            dxDrawRectangle(bx, cy + 148, 34, 28, tocolor(col[1], col[2], col[3], 255))
            if UI.clickedIn(bx, cy + 148, 34, 28) then crewCreateColor = col end
            if crewCreateColor == col then dxDrawRectangle(bx, cy + 148, 34, 3, C.dark) end
        end
        crewCreateColor = crewCreateColor or presets[1]

        if UI.button(cx, cy + 190, 200, 40, "Create crew", { size = 1.4, bg = C.dark, txt = C.white, hoverBg = C.green }) then
            if name ~= "" and tag ~= "" then
                triggerServerEvent("sp:crew:create", localPlayer, name, tag,
                    crewCreateColor[1], crewCreateColor[2], crewCreateColor[3])
            end
        end
        return
    end

    local col = crewColor(crew.color)
    dxDrawRectangle(cx, cy, cw, 60, C.panel)
    dxDrawRectangle(cx, cy, 6, 60, col)
    dxDrawText(crew.name, cx + 18, cy + 6, cx + cw, cy + 32, C.dark, 1.8, "default-bold", "left", "top")
    dxDrawText("[" .. crew.tag .. "]", cx + 18, cy + 34, cx + cw, cy + 54, col, 1.3, "default-bold", "left", "top")
    dxDrawText(("Founder: %s  |  Members: %d/%d"):format(crew.founder, #crew.members, 30),
        cx + cw - 340, cy + 8, cx + cw - 10, cy + 28, C.sub, 1.15, "default", "right", "top")
    if UI.button(cx + cw - 210, cy + 28, 100, 26, "Crew chat", { size = 1.1, bg = C.bg, hoverBg = C.blue, hoverTxt = C.white }) then
        openConversation("crew", crew.name)
    end
    if UI.button(cx + cw - 104, cy + 28, 96, 26, "Leave", { size = 1.1, bg = C.bg, hoverBg = C.red, hoverTxt = C.white }) then
        triggerServerEvent("sp:crew:leave", localPlayer)
    end

    if crew.desc and crew.desc ~= "" then
        dxDrawText(crew.desc, cx, cy + 68, cx + cw, cy + 108, C.sub, 1.15, "default", "left", "top", false, true)
    end

    local listY = cy + 116
    local isFounder = crew.isFounder
    dxDrawText("Members", cx, listY - 24, cx + cw, listY, C.dark, 1.4, "default-bold", "left", "top")
    local rowH, gap = 44, 5
    local half = isFounder and (H * 0.46) or (H - 150)
    local off = UI.beginScroll("crew_members", cx, listY, cw, half, #crew.members * (rowH + gap))
    for i, m in ipairs(crew.members) do
        local ry = listY + (i - 1) * (rowH + gap) - off
        if ry + rowH > listY and ry < listY + half then
            dxDrawRectangle(cx, ry, cw, rowH, C.panel)
            dxDrawRectangle(cx, ry, 4, rowH, m.online and C.green or C.grey)
            dxDrawText((m.isFounder and "* " or "") .. m.name, cx + 14, ry, cx + 210, ry + rowH,
                C.dark, 1.3, "default-bold", "left", "center")
            dxDrawText(("Level %s  |  %s"):format(m.level, m.playtime), cx + 220, ry, cx + cw - 160, ry + rowH,
                C.sub, 1.05, "default", "left", "center")
            if UI.button(cx + cw - 150, ry + 8, 70, rowH - 16, "Profile", { size = 1.05, bg = C.bg }) then
                triggerServerEvent("sp:profile:view", localPlayer, m.name)
            end
            if isFounder and not m.isFounder then
                if UI.button(cx + cw - 74, ry + 8, 66, rowH - 16, "Kick", { size = 1.05, bg = C.bg, hoverBg = C.red, hoverTxt = C.white }) then
                    triggerServerEvent("sp:crew:kick", localPlayer, m.name)
                end
            end
        end
    end

    if isFounder then
        local fy = listY + half + 12
        dxDrawText("Customise (founder only)", cx, fy, cx + cw, fy + 22, C.dark, 1.35, "default-bold", "left", "top")
        UI.fields["cz_tag"] = UI.fields["cz_tag"] or { text = crew.tag }
        UI.fields["cz_desc"] = UI.fields["cz_desc"] or { text = crew.desc or "" }
        local tag = UI.input("cz_tag", cx, fy + 28, 120, 32, { placeholder = "TAG" })
        local desc = UI.input("cz_desc", cx + 132, fy + 28, cw - 132, 32, { placeholder = "Description..." })
        local presets = { { 255, 200, 0 }, { 220, 60, 60 }, { 60, 140, 220 }, { 80, 200, 100 }, { 170, 90, 220 }, { 240, 240, 240 } }
        for i, pc in ipairs(presets) do
            local bx = cx + (i - 1) * 44
            dxDrawRectangle(bx, fy + 68, 34, 26, tocolor(pc[1], pc[2], pc[3], 255))
            if UI.clickedIn(bx, fy + 68, 34, 26) then czColor = pc end
        end
        if UI.button(cx + cw - 150, fy + 66, 150, 32, "Save", { size = 1.25, bg = C.dark, txt = C.white, hoverBg = C.green }) then
            local c = czColor
            triggerServerEvent("sp:crew:customize", localPlayer, tag, desc,
                c and c[1] or nil, c and c[2] or nil, c and c[3] or nil)
        end
    end
end

function socialFindCrew(cx, cy, cw)
    local list = snapshot.crews or {}
    dxDrawText("Find crew (" .. #list .. ")", cx, cy, cx + cw, cy + 26, C.dark, 1.7, "default-bold", "left", "top")
    local hasCrew = snapshot.crew ~= nil
    if #list == 0 then
        dxDrawText("No crews exist yet. Be the first to make one!", cx, cy + 40, cx + cw, cy + 70,
            C.sub, 1.25, "default", "left", "top")
        return
    end
    local listY, rowH, gap, areaH = cy + 40, 54, 6, H - 60
    local off = UI.beginScroll("crew_dir", cx, listY, cw, areaH, #list * (rowH + gap))
    for i, cr in ipairs(list) do
        local ry = listY + (i - 1) * (rowH + gap) - off
        if ry + rowH > listY and ry < listY + areaH then
            local col = crewColor(cr.color)
            dxDrawRectangle(cx, ry, cw, rowH, C.panel)
            dxDrawRectangle(cx, ry, 4, rowH, col)
            dxDrawText(cr.name .. "  [" .. cr.tag .. "]", cx + 14, ry + 7, cx + cw, ry + 27, C.dark, 1.35, "default-bold", "left", "top")
            dxDrawText(("Founder: %s  |  Members: %d/30"):format(cr.founder, cr.members),
                cx + 14, ry + 29, cx + cw, ry + 47, C.sub, 1.1, "default", "left", "top")
            if UI.button(cx + cw - 130, ry + 12, 120, rowH - 24, hasCrew and "In a crew" or "Join",
                { size = 1.2, bg = C.bg, hoverBg = C.green, hoverTxt = C.white, disabled = hasCrew }) then
                triggerServerEvent("sp:crew:join", localPlayer, cr.name)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- PROFILE
--------------------------------------------------------------------------------

function renderProfile()
    local p = viewedProfile
    local isOwn = (p == nil)
    local name, level, playtime, online, crewName, crewTag, crewCol, isFriend, isSelf

    if isOwn then
        name = snapshot.account or getPlayerName(localPlayer)
        level = getElementData(localPlayer, "level") or "n/a"
        playtime = getElementData(localPlayer, "Játékidő") or "n/a"
        online = true
        if snapshot.crew then
            crewName, crewTag, crewCol = snapshot.crew.name, snapshot.crew.tag, snapshot.crew.color
        end
        isSelf = true
    else
        name, level, playtime, online = p.name, p.level, p.playtime, p.online
        crewName, crewTag, crewCol = p.crew, p.crewTag, p.crewColor
        isFriend, isSelf = p.isFriend, p.isSelf
    end

    local headH = 150
    dxDrawRectangle(X, Y, W, headH, C.accent)
    dxDrawRectangle(X + 24, Y + 28, 94, 94, C.dark)
    dxDrawText(name:sub(1, 1):upper(), X + 24, Y + 28, X + 118, Y + 122, C.accent, 3, "default-bold", "center", "center")
    dxDrawText(name, X + 140, Y + 30, X + W - 20, Y + 66, C.dark, 2.4, "default-bold", "left", "top")
    dxDrawText(online and "ONLINE" or "OFFLINE", X + 140, Y + 78, X + W - 20, Y + 100,
        online and tocolor(0, 120, 0, 255) or tocolor(150, 40, 40, 255), 1.4, "default-bold", "left", "top")

    if not isOwn then
        if UI.button(X + W - 130, Y + 20, 110, 30, "Back", { size = 1.3, bg = C.panel }) then
            viewedProfile = nil
            content_id = 3
        end
        if not isSelf then
            local function refetch()
                setTimer(function()
                    if show_socialpanel then triggerServerEvent("sp:profile:view", localPlayer, name) end
                end, 400, 1)
            end
            if UI.button(X + W - 320, Y + 62, 150, 34, "Message", { size = 1.3, bg = C.panel, hoverBg = C.blue, hoverTxt = C.white }) then
                openConversation("dm", name)
            end
            if isFriend then
                if UI.button(X + W - 162, Y + 62, 150, 34, "Remove friend",
                    { size = 1.3, bg = C.panel, hoverBg = C.red, hoverTxt = C.white }) then
                    triggerServerEvent("sp:friend:remove", localPlayer, name)
                    refetch()
                end
            else
                if UI.button(X + W - 162, Y + 62, 150, 34, "Add friend",
                    { size = 1.3, bg = C.panel, hoverBg = C.green, hoverTxt = C.white }) then
                    triggerServerEvent("sp:friend:add", localPlayer, name)
                    refetch()
                end
            end
        end
    end

    local sy = Y + headH + 30
    local function stat(i, label, value, valColor)
        local bw = (W - 80) / 3
        local bx = X + 30 + (i - 1) * (bw + 10)
        dxDrawRectangle(bx, sy, bw, 90, C.panel)
        dxDrawText(label:upper(), bx, sy + 12, bx + bw, sy + 32, C.sub, 1.2, "default-bold", "center", "top")
        dxDrawText(tostring(value), bx, sy + 34, bx + bw, sy + 80, valColor or C.dark, 2, "default-bold", "center", "top")
    end
    stat(1, "Level", level)
    stat(2, "Played time", playtime)
    stat(3, "Crew", crewName and ("[" .. (crewTag or "?") .. "]") or "-", crewName and crewColor(crewCol) or C.sub)

    if crewName then
        dxDrawText("Crew: " .. crewName, X + 30, sy + 110, X + W - 30, sy + 134, C.dark, 1.4, "default-bold", "left", "top")
    end

    if isOwn then
        dxDrawText("This is your public profile - this is how others see you.",
            X + 30, Y + H - 40, X + W - 30, Y + H - 16, C.sub, 1.15, "default", "left", "top")
    end
end
