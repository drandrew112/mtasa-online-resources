if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
--[[
    v_socialpanel / c_ui.lua
    Social panel rendering. Pure DX, immediate-mode (see c_controls.lua / UI).

    Views (content_id):
      1 = HOME     3 = ACHIEVEMENTS     4 = SOCIAL     5 = PROFILE     6 = ACCOUNT (settings of the own profile)
      (2 was HELP, it moved to its own panel)
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

local TABS = {}
local TAB_LEFT = { 1, 3, 4 }   -- view ids shown on the left; PROFILE sits on the right
local function build_TABS()
TABS = { [1] = L("v_socialpanel.ui.home"), [3] = L("v_socialpanel.ui.achievements"), [4] = L("v_socialpanel.ui.social"), [5] = L("v_socialpanel.ui.profile") }
end

--------------------------------------------------------------------------------
-- SOCIAL sub-tabs
--------------------------------------------------------------------------------

local SOCIAL_TABS = {}
local function build_SOCIAL_TABS()
SOCIAL_TABS = { L("v_socialpanel.ui.friends"), L("v_socialpanel.ui.requests"), L("v_socialpanel.ui.find_player"), L("v_socialpanel.ui.messages"), L("v_socialpanel.ui.my_crew"), L("v_socialpanel.ui.find_crew") }
end
local social_tab = 1

--------------------------------------------------------------------------------
-- ACHIEVEMENTS (data from v_achievements via the server, see sp:ach:data)
--------------------------------------------------------------------------------

local achData = nil   -- nil = not loaded yet; { available, categories, list, summary }
local ach_tab = 1     -- 1 = ALL, 2.. = achData.categories[ach_tab - 1]

--------------------------------------------------------------------------------
-- Client-side state (from the server)
--------------------------------------------------------------------------------

local snapshot = { account = nil, friends = {}, requests = {}, crew = nil, crews = {}, conversations = {} }
-- shown name of an account: its display name when it has one (snapshot.names);
-- the account name stays the key in every event
local function dn(account)
    local names = snapshot.names
    return (names and names[tostring(account):lower()]) or account
end
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
        content_id = 5
    else
        outputChatBox(L("v_socialpanel.ui.social_no_such_player", { wanted_name = tostring(wantedName) }), 255, 255, 255, true)
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
        or (L("v_socialpanel.ui.uj_uzenet", { from = from }))
    local preview = tostring(text or "")
    if utf8.len(preview) and utf8.len(preview) > 60 then
        preview = utf8.sub(preview, 1, 57) .. "..."
    end
    pcall(function() exports.ui_core:addNotification(title, preview) end)
end)

addEvent("sp:ach:data", true)
addEventHandler("sp:ach:data", root, function(data)
    if type(data) ~= "table" then return end
    achData = data
    if ach_tab > #(data.categories or {}) + 1 then ach_tab = 1 end
end)

-- Fresh unlock while the tab is open -> reload it (v_achievements fires this).
addEvent("ach:unlocked", true)
addEventHandler("ach:unlocked", localPlayer, function()
    if show_socialpanel and content_id == 3 then
        triggerServerEvent("sp:ach:pull", localPlayer)
    end
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
            for _, row in ipairs(L.wrap(ln, w, size, font)) do
                dxDrawText(row, x, yy, x + w, yy + lineH, tocolor(40, 40, 40, 255), size, font, "left", "top")
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
    return L.fit(str, maxW, size, font)
end

local function openConversation(kind, with)
    openConv = { kind = kind, with = with }
    thread = {}
    content_id = 4
    social_tab = 4
    triggerServerEvent("sp:msg:open", localPlayer, kind, with)
end

--------------------------------------------------------------------------------
-- Main render
--------------------------------------------------------------------------------

-- "low" prioritas: minden mas onClientRender utan fut le, igy a social panel
-- mindig a legfelso reteg (pl. a nyitva hagyott pause menu folott).
local function renderSocialPanel()
    UI.beginFrame()

    dxDrawRectangle(0, 0, sw, sh, C.shade)
    dxDrawRectangle(0, 0, sw, TOPBAR, C.bar)
    dxDrawRectangle(0, TOPBAR, sw, 4, C.accent)

    -- "FREE V" branding exiled to the very top-left corner.
    dxDrawText("FreeV", 12, 0, 12, TOPBAR, tocolor(255, 200, 0, 120), 1.0, "pricedown", "left", "center")

    -- Panel title where the branding used to be.
    dxDrawText(L("v_socialpanel.ui.social_panel"), X, 0, X, TOPBAR, C.white, 1.5, "default-bold", "left", "center")

    local tabX = X + L.width(L("v_socialpanel.ui.social_panel"), 1.5, "default-bold") + 55
    for _, id in ipairs(TAB_LEFT) do
        local label = TABS[id]
        local tw = L.width(label, 1.4, "default-bold") + 30
        if UI.button(tabX, 0, tw, TOPBAR, label, {
            font = "default-bold", bg = C.bar, txt = C.white,
            hoverBg = C.bar, hoverTxt = C.accent,
            selected = (id == content_id), selTxt = C.accent,
        }) then
            content_id = id
            if id == 3 then triggerServerEvent("sp:ach:pull", localPlayer) end
        end
        tabX = tabX + tw
    end

    -- PROFILE on the right edge, the display name next to it
    local pLabel = TABS[5]
    local pw = L.width(pLabel, 1.4, "default-bold") + 30
    local px = X + W - pw
    local nameText = ellipsis(snapshot.displayName or snapshot.account or getPlayerName(localPlayer), 1.2, "default", 220)
    dxDrawText(nameText, px - 230, 0, px - 8, TOPBAR, tocolor(200, 200, 200, 255), 1.2, "default", "right", "center")
    if UI.button(px, 0, pw, TOPBAR, pLabel, {
        font = "default-bold", bg = C.bar, txt = C.white,
        hoverBg = C.bar, hoverTxt = C.accent,
        selected = (content_id == 5 or content_id == 6) and viewedProfile == nil, selTxt = C.accent,
    }) then
        content_id = 5
        viewedProfile = nil
    end

    dxDrawRectangle(X, Y, W, H, C.bg)

    if content_id == 1 then renderHome()
    elseif content_id == 3 then renderAchievements()
    elseif content_id == 4 then renderSocial()
    elseif content_id == 5 then renderProfile()
    elseif content_id == 6 then renderAccount() end

    dxDrawText(L("v_socialpanel.ui.esc_close"), X, Y + H + 6, X + W, Y + H + 26, C.white, 1.3, "default-bold", "right", "top")
end

-- attached only while the panel is open (setSocialPanel in c_controls.lua calls this)
local panelRendering = false
function syncSocialPanelRender()
    local on = show_socialpanel and true or false
    if on == panelRendering then return end
    panelRendering = on
    if on then
        addEventHandler("onClientRender", root, renderSocialPanel, false, "low")
    else
        removeEventHandler("onClientRender", root, renderSocialPanel)
    end
end

--------------------------------------------------------------------------------
-- HOME
--------------------------------------------------------------------------------

function renderHome()
    local leftW = W * 0.58

    -- Left grey strip: KEPT EMPTY (weekly-update images will go here later).
    dxDrawRectangle(X, Y, leftW, H, C.grey)
    dxDrawText(L("v_socialpanel.ui.weekly_updates"), X, Y + H / 2 - 30, X + leftW, Y + H / 2 - 30,
        tocolor(255, 255, 255, 60), 2.2, "default-bold", "center", "top")
    dxDrawText(L("v_socialpanel.ui.images_coming_soon"), X, Y + H / 2 + 6, X + leftW, Y + H / 2 + 6,
        tocolor(255, 255, 255, 45), 1.3, "default", "center", "top")

    local rx = X + leftW + 14
    local rw = W - leftW - 28
    local online = {}
    for _, f in ipairs(snapshot.friends or {}) do
        if f.online then online[#online + 1] = f end
    end

    dxDrawText(L("v_socialpanel.ui.friends_online", { online = #online }), rx, Y + 14, rx + rw, Y + 40,
        C.dark, 1.7, "default-bold", "left", "top")

    if #online == 0 then
        dxDrawText(L("v_socialpanel.ui.no_friends_online"), rx, Y + 70, rx + rw, Y + 90, C.sub, 1.3, "default", "left", "top")
        return
    end

    local listY, rowH, areaH = Y + 52, 58, H - 66
    local off = UI.beginScroll("home_online", rx, listY, rw, areaH, #online * (rowH + 6))
    for i, f in ipairs(online) do
        local ry = listY + (i - 1) * (rowH + 6) - off
        if ry + rowH > listY and ry < listY + areaH then
            dxDrawRectangle(rx, ry, rw, rowH, C.panel)
            dxDrawRectangle(rx, ry, 4, rowH, C.green)
            dxDrawText(dn(f.name), rx + 14, ry + 8, rx + rw, ry + 28, C.dark, 1.4, "default-bold", "left", "top")
            dxDrawText(L("v_socialpanel.ui.level", { level = f.level, playtime = f.playtime }), rx + 14, ry + 30, rx + rw, ry + 48,
                C.sub, 1.15, "default", "left", "top")
            if UI.button(rx + rw - 92, ry + 12, 84, rowH - 24, L("v_socialpanel.ui.profile_2"), { size = 1.2, bg = C.bg }) then
                triggerServerEvent("sp:profile:view", localPlayer, f.name)
            end
        end
    end
    UI.endScroll()
end

--------------------------------------------------------------------------------
-- ACHIEVEMENTS
--------------------------------------------------------------------------------

local function achCount(list, catId)
    local done, total = 0, 0
    for _, a in ipairs(list) do
        if not catId or a.category == catId then
            total = total + 1
            if a.done then done = done + 1 end
        end
    end
    return done, total
end

local function fmtNum(n)
    n = tonumber(n) or 0
    if n == math.floor(n) then return tostring(n) end
    return ("%.1f"):format(n)
end

local function achDate(ts)
    local t = getRealTime(tonumber(ts) or 0)
    return ("%04d.%02d.%02d"):format(t.year + 1900, t.month + 1, t.monthday)
end

function renderAchievements()
    if not achData or not achData.available then
        dxDrawText(achData and L("v_socialpanel.ui.achievements_are_not_available_right_now") or L("common.loading"),
            X, Y, X + W, Y + H, C.sub, 1.5, "default-bold", "center", "center")
        return
    end

    local list, cats = achData.list or {}, achData.categories or {}

    -- Sidebar: ALL + categories, with done/total counters
    local sideW = W * 0.26
    local tabs = { { name = L("v_socialpanel.ui.all") } }
    for _, c in ipairs(cats) do tabs[#tabs + 1] = { id = c.id, name = L.upper(c.name) } end
    local rowH = math.min(H / #tabs, 90)
    for i, t in ipairs(tabs) do
        local d, n = achCount(list, t.id)
        if UI.button(X, Y + (i - 1) * rowH, sideW, rowH, ("%s  (%d/%d)"):format(t.name, d, n), {
            bg = C.grey, txt = C.dark, hoverBg = C.white,
            selected = (i == ach_tab), selBg = C.white, selTxt = C.dark, size = 1.3,
        }) then
            ach_tab = i
        end
        if i == ach_tab then
            dxDrawRectangle(X + sideW - 4, Y + (i - 1) * rowH, 4, rowH, C.accent)
        end
    end
    if Y + #tabs * rowH < Y + H then
        dxDrawRectangle(X, Y + #tabs * rowH, sideW, H - #tabs * rowH, C.grey)
    end

    local cx, cw, cy = X + sideW + 20, W - sideW - 40, Y + 16

    -- Header + overall progress
    local s = achData.summary
    dxDrawText(tabs[ach_tab].name, cx, cy, cx + cw, cy + 28, C.dark, 1.8, "default-bold", "left", "top")
    if s then
        dxDrawText(L("v_socialpanel.ui.unlocked_xp", { done = s.done, total = s.total, xp = s.xp, max_xp = s.maxXp }),
            cx, cy + 4, cx + cw, cy + 28, C.sub, 1.2, "default", "right", "top")
        local frac = s.total > 0 and s.done / s.total or 0
        dxDrawRectangle(cx, cy + 34, cw, 6, C.grey)
        dxDrawRectangle(cx, cy + 34, cw * frac, 6, C.accent)
    end

    local shown = {}
    local catId = tabs[ach_tab].id
    for _, a in ipairs(list) do
        if not catId or a.category == catId then shown[#shown + 1] = a end
    end

    local listY = cy + 52
    if #shown == 0 then
        dxDrawText(L("v_socialpanel.ui.no_achievements_here_yet"), cx, listY, cx + cw, listY + 24, C.sub, 1.25, "default", "left", "top")
        return
    end

    local rH, gap, areaH = 66, 6, Y + H - 10 - listY
    local off = UI.beginScroll("ach_list", cx, listY, cw, areaH, #shown * (rH + gap))
    for i, a in ipairs(shown) do
        local ry = listY + (i - 1) * (rH + gap) - off
        if ry + rH > listY and ry < listY + areaH then
            dxDrawRectangle(cx, ry, cw, rH, C.panel)
            dxDrawRectangle(cx, ry, 4, rH, a.done and C.green or C.grey)

            local rightW = 150
            dxDrawText(a.name, cx + 14, ry + 7, cx + cw - rightW, ry + 27,
                a.done and C.dark or C.sub, 1.35, "default-bold", "left", "top")
            dxDrawText(ellipsis(a.desc or "", 1.1, "default", cw - rightW - 20), cx + 14, ry + 29, cx + cw - rightW, ry + 45,
                C.sub, 1.1, "default", "left", "top")

            if (a.xp or 0) > 0 then
                dxDrawText(L("v_socialpanel.ui.xp", { xp = a.xp }), cx, ry + 7, cx + cw - 12, ry + 27,
                    a.done and C.green or C.dark, 1.3, "default-bold", "right", "top")
            end

            if a.done then
                dxDrawText(a.unlockedAt and (L("v_socialpanel.ui.unlocked", { unlocked_at = achDate(a.unlockedAt) })) or L("v_socialpanel.ui.unlocked_2"),
                    cx, ry + 30, cx + cw - 12, ry + 46, C.green, 1.1, "default-bold", "right", "top")
            elseif a.isProgress and not a.hidden then
                local goal = math.max(tonumber(a.goal) or 1, 1)
                local frac = math.min((tonumber(a.progress) or 0) / goal, 1)
                local bx, bw, by = cx + 14, cw - rightW - 20, ry + rH - 14
                dxDrawRectangle(bx, by, bw, 6, C.bg)
                dxDrawRectangle(bx, by, bw * frac, 6, C.accent)
                local label = fmtNum(a.progress) .. " / " .. fmtNum(goal) .. (a.unit and (" " .. a.unit) or "")
                dxDrawText(label, cx, ry + 30, cx + cw - 12, ry + 46, C.dark, 1.1, "default-bold", "right", "top")
            else
                dxDrawText(L("v_socialpanel.ui.locked"), cx, ry + 30, cx + cw - 12, ry + 46, C.sub, 1.1, "default", "right", "top")
            end
        end
    end
    UI.endScroll()
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
    dxDrawText(L("v_socialpanel.ui.friends_2", { friends = #friends }), cx, cy, cx + cw, cy + 26, C.dark, 1.7, "default-bold", "left", "top")
    if #friends == 0 then
        dxDrawText(L("v_socialpanel.ui.no_friends_yet_add_players_on"),
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
            dxDrawText(dn(f.name), cx + 14, ry + 7, cx + cw, ry + 27, C.dark, 1.4, "default-bold", "left", "top")
            dxDrawText(L("v_socialpanel.ui.level_2", { online = f.online and L("v_socialpanel.ui.online") or L("v_socialpanel.ui.offline"), level = f.level, playtime = f.playtime }),
                cx + 14, ry + 29, cx + cw, ry + 47, C.sub, 1.1, "default", "left", "top")
            if UI.button(cx + cw - 270, ry + 12, 82, rowH - 24, L("v_socialpanel.ui.profile_2"), { size = 1.15, bg = C.bg }) then
                triggerServerEvent("sp:profile:view", localPlayer, f.name)
            end
            if UI.button(cx + cw - 182, ry + 12, 88, rowH - 24, L("v_socialpanel.ui.message"), { size = 1.15, bg = C.bg, hoverBg = C.blue, hoverTxt = C.white }) then
                openConversation("dm", f.name)
            end
            if UI.button(cx + cw - 88, ry + 12, 80, rowH - 24, L("v_socialpanel.ui.remove"), { size = 1.15, bg = C.bg, hoverBg = C.red, hoverTxt = C.white }) then
                triggerServerEvent("sp:friend:remove", localPlayer, f.name)
            end
        end
    end
    UI.endScroll()
end

function socialRequests(cx, cy, cw)
    local reqs = snapshot.requests or {}
    dxDrawText(L("v_socialpanel.ui.friend_requests", { reqs = #reqs }), cx, cy, cx + cw, cy + 26, C.dark, 1.7, "default-bold", "left", "top")
    if #reqs == 0 then
        dxDrawText(L("v_socialpanel.ui.no_pending_friend_requests"), cx, cy + 40, cx + cw, cy + 70, C.sub, 1.25, "default", "left", "top")
        return
    end
    local listY, rowH, gap = cy + 40, 52, 6
    for i, name in ipairs(reqs) do
        local ry = listY + (i - 1) * (rowH + gap)
        dxDrawRectangle(cx, ry, cw, rowH, C.panel)
        dxDrawText(dn(name), cx + 14, ry, cx + cw, ry + rowH, C.dark, 1.4, "default-bold", "left", "center")
        if UI.button(cx + cw - 200, ry + 10, 92, rowH - 20, L("v_socialpanel.ui.accept"), { size = 1.2, bg = C.bg, hoverBg = C.green, hoverTxt = C.white }) then
            triggerServerEvent("sp:friend:accept", localPlayer, name)
        end
        if UI.button(cx + cw - 100, ry + 10, 92, rowH - 20, L("v_socialpanel.ui.decline"), { size = 1.2, bg = C.bg, hoverBg = C.red, hoverTxt = C.white }) then
            triggerServerEvent("sp:friend:decline", localPlayer, name)
        end
    end
end

function socialFindPlayer(cx, cy, cw)
    dxDrawText(L("v_socialpanel.ui.find_player_2"), cx, cy, cx + cw, cy + 26, C.dark, 1.7, "default-bold", "left", "top")
    dxDrawText(L("v_socialpanel.ui.searches_online_and_offline_registered_players"), cx, cy + 26, cx + cw, cy + 46,
        C.sub, 1.1, "default", "left", "top")
    local q, entered = UI.input("find_player", cx, cy + 50, cw - 110, 34, { placeholder = L("v_socialpanel.ui.player_name") })
    local doSearch = entered
    if UI.button(cx + cw - 100, cy + 50, 100, 34, L("v_socialpanel.ui.search"), { size = 1.25, bg = C.dark, txt = C.white }) then
        doSearch = true
    end
    if doSearch and q ~= "" then
        triggerServerEvent("sp:search", localPlayer, q)
    end

    if searchNote then
        dxDrawText(searchNote, cx, cy + 94, cx + cw, cy + 112, C.red, 1.15, "default", "left", "top")
    else
        dxDrawText(L("v_socialpanel.ui.result_s", { search_results = #searchResults }), cx, cy + 94, cx + cw, cy + 112, C.sub, 1.15, "default", "left", "top")
    end

    local listY, rowH, gap, areaH = cy + 116, 54, 6, H - 134
    local off = UI.beginScroll("fp_list", cx, listY, cw, areaH, #searchResults * (rowH + gap))
    for i, r in ipairs(searchResults) do
        local ry = listY + (i - 1) * (rowH + gap) - off
        if ry + rowH > listY and ry < listY + areaH then
            dxDrawRectangle(cx, ry, cw, rowH, C.panel)
            dxDrawRectangle(cx, ry, 4, rowH, r.online and C.green or C.grey)
            dxDrawText(r.display or r.name, cx + 14, ry + 6, cx + cw, ry + 26, C.dark, 1.35, "default-bold", "left", "top")
            dxDrawText(L("v_socialpanel.ui.level_2", { online = r.online and L("v_socialpanel.ui.online") or L("v_socialpanel.ui.offline"), level = r.level, playtime = r.playtime }),
                cx + 14, ry + 28, cx + cw, ry + 46, C.sub, 1.1, "default", "left", "top")
            if UI.button(cx + cw - 270, ry + 11, 82, rowH - 22, L("v_socialpanel.ui.profile_2"), { size = 1.1, bg = C.bg }) then
                triggerServerEvent("sp:profile:view", localPlayer, r.name)
            end
            if UI.button(cx + cw - 182, ry + 11, 88, rowH - 22, L("v_socialpanel.ui.message"), { size = 1.1, bg = C.bg, hoverBg = C.blue, hoverTxt = C.white }) then
                openConversation("dm", r.name)
            end
            if UI.button(cx + cw - 88, ry + 11, 80, rowH - 22, L("v_socialpanel.ui.add"), { size = 1.1, bg = C.bg, hoverBg = C.green, hoverTxt = C.white }) then
                triggerServerEvent("sp:friend:add", localPlayer, r.name)
            end
        end
    end
    UI.endScroll()
end

--------------------------------------------------------------------------------
-- MESSAGES
--------------------------------------------------------------------------------

function socialMessages(cx, cy, cw)
    local convW = math.floor(cw * 0.36)
    local convos = snapshot.conversations or {}

    -- Conversation list
    dxDrawText(L("v_socialpanel.ui.chats"), cx, cy, cx + convW, cy + 24, C.dark, 1.6, "default-bold", "left", "top")
    local listY, rowH, gap, areaH = cy + 30, 54, 5, H - 50
    if #convos == 0 then
        dxDrawText(L("v_socialpanel.ui.no_chats_yet_open_profile_or"),
            cx, listY + 6, cx + convW, listY + 80, C.sub, 1.1, "default", "left", "top", false, true)
    end
    local off = UI.beginScroll("msg_convos", cx, listY, convW, areaH, #convos * (rowH + gap))
    for i, c in ipairs(convos) do
        local ry = listY + (i - 1) * (rowH + gap) - off
        if ry + rowH > listY and ry < listY + areaH then
            local isOpen = openConv and openConv.kind == c.kind and openConv.with:lower() == c.with:lower()
            dxDrawRectangle(cx, ry, convW - 6, rowH, C.panel)
            if isOpen then dxDrawRectangle(cx, ry, 3, rowH, C.accent) end
            local title = (c.kind == "crew") and ("[" .. (c.crewTag or L("v_socialpanel.ui.crew")) .. "] " .. c.with) or dn(c.with)
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
    UI.endScroll()

    -- Thread
    local tx = cx + convW + 12
    local tw = cw - convW - 12
    dxDrawRectangle(tx, cy, tw, H - 20, C.panel)

    if not openConv then
        dxDrawText(L("v_socialpanel.ui.select_chat_on_left"), tx, cy, tx + tw, cy + H - 20, C.sub, 1.3, "default", "center", "center")
        return
    end

    local header = (openConv.kind == "crew") and (L("v_socialpanel.ui.crew_chat", { with = openConv.with })) or (L("v_socialpanel.ui.chat_with", { with = dn(openConv.with) }))
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
        local lines = #L.wrap(m.text or "", bubbleW - 16, size, font)
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
            dxDrawText((mine and L("v_socialpanel.ui.you") or dn(m.from)) .. "  " .. clock(m.time), bx + 8, yy + 4, bx + bw - 8, yy + 18,
                C.sub, 1.0, "default", mine and "right" or "left", "top")
            dxDrawText(m.text or "", bx + 8, yy + 18, bx + bw - 8, yy + hgt - 4, C.dark, size, font,
                "left", "top", false, true)
        end
        yy = yy + hgt + 4
    end
    UI.endScroll()
    if #thread == 0 then
        dxDrawText(L("v_socialpanel.ui.no_messages_yet_say_hi"), tx + 12, areaTop + 10, tx + tw - 12, areaTop + 30, C.sub, 1.15, "default", "left", "top")
    end

    -- Input
    local iy = cy + H - 20 - inputH - 4
    local msg, sent = UI.input("msg_input", tx + 12, iy, tw - 120, inputH, { placeholder = L("v_socialpanel.ui.type_message") })
    local send = sent
    if UI.button(tx + tw - 100, iy, 88, inputH, L("common.send"), { size = 1.3, bg = C.dark, txt = C.white, hoverBg = C.green }) then
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
        dxDrawText(L("v_socialpanel.ui.you_have_no_crew"), cx, cy, cx + cw, cy + 26, C.dark, 1.7, "default-bold", "left", "top")
        dxDrawText(L("v_socialpanel.ui.create_one_below_or_join_existing"),
            cx, cy + 34, cx + cw, cy + 60, C.sub, 1.2, "default", "left", "top")

        dxDrawText(L("v_socialpanel.ui.create_new_crew"), cx, cy + 74, cx + cw, cy + 98, C.dark, 1.5, "default-bold", "left", "top")
        local name = UI.input("crew_name", cx, cy + 104, cw - 160, 34, { placeholder = L("v_socialpanel.ui.crew_name_3_24_chars") })
        local tag = UI.input("crew_tag", cx + cw - 150, cy + 104, 150, 34, { placeholder = L("v_socialpanel.ui.tag") })

        dxDrawText(L("v_socialpanel.ui.colour"), cx, cy + 150, cx + 70, cy + 174, C.sub, 1.2, "default", "left", "top")
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

        if UI.button(cx, cy + 190, 200, 40, L("v_socialpanel.ui.create_crew"), { size = 1.4, bg = C.dark, txt = C.white, hoverBg = C.green }) then
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
    dxDrawText(L("v_socialpanel.ui.founder_members", { founder = dn(crew.founder), members = #crew.members, value = 30 }),
        cx + cw - 340, cy + 8, cx + cw - 10, cy + 28, C.sub, 1.15, "default", "right", "top")
    if UI.button(cx + cw - 210, cy + 28, 100, 26, L("v_socialpanel.ui.crew_chat_2"), { size = 1.1, bg = C.bg, hoverBg = C.blue, hoverTxt = C.white }) then
        openConversation("crew", crew.name)
    end
    if UI.button(cx + cw - 104, cy + 28, 96, 26, L("v_socialpanel.ui.leave"), { size = 1.1, bg = C.bg, hoverBg = C.red, hoverTxt = C.white }) then
        triggerServerEvent("sp:crew:leave", localPlayer)
    end

    if crew.desc and crew.desc ~= "" then
        dxDrawText(crew.desc, cx, cy + 68, cx + cw, cy + 108, C.sub, 1.15, "default", "left", "top", false, true)
    end

    local listY = cy + 116
    local isFounder = crew.isFounder
    dxDrawText(L("v_socialpanel.ui.members"), cx, listY - 24, cx + cw, listY, C.dark, 1.4, "default-bold", "left", "top")
    local rowH, gap = 44, 5
    local half = isFounder and (H * 0.46) or (H - 150)
    local off = UI.beginScroll("crew_members", cx, listY, cw, half, #crew.members * (rowH + gap))
    for i, m in ipairs(crew.members) do
        local ry = listY + (i - 1) * (rowH + gap) - off
        if ry + rowH > listY and ry < listY + half then
            dxDrawRectangle(cx, ry, cw, rowH, C.panel)
            dxDrawRectangle(cx, ry, 4, rowH, m.online and C.green or C.grey)
            dxDrawText((m.isFounder and "* " or "") .. dn(m.name), cx + 14, ry, cx + 210, ry + rowH,
                C.dark, 1.3, "default-bold", "left", "center")
            dxDrawText(L("v_socialpanel.ui.level", { level = m.level, playtime = m.playtime }), cx + 220, ry, cx + cw - 160, ry + rowH,
                C.sub, 1.05, "default", "left", "center")
            if UI.button(cx + cw - 150, ry + 8, 70, rowH - 16, L("v_socialpanel.ui.profile_2"), { size = 1.05, bg = C.bg }) then
                triggerServerEvent("sp:profile:view", localPlayer, m.name)
            end
            if isFounder and not m.isFounder then
                if UI.button(cx + cw - 74, ry + 8, 66, rowH - 16, L("v_socialpanel.ui.kick"), { size = 1.05, bg = C.bg, hoverBg = C.red, hoverTxt = C.white }) then
                    triggerServerEvent("sp:crew:kick", localPlayer, m.name)
                end
            end
        end
    end
    UI.endScroll()

    if isFounder then
        local fy = listY + half + 12
        dxDrawText(L("v_socialpanel.ui.customise_founder_only"), cx, fy, cx + cw, fy + 22, C.dark, 1.35, "default-bold", "left", "top")
        UI.fields["cz_tag"] = UI.fields["cz_tag"] or { text = crew.tag }
        UI.fields["cz_desc"] = UI.fields["cz_desc"] or { text = crew.desc or "" }
        local tag = UI.input("cz_tag", cx, fy + 28, 120, 32, { placeholder = L("v_socialpanel.ui.tag") })
        local desc = UI.input("cz_desc", cx + 132, fy + 28, cw - 132, 32, { placeholder = L("v_socialpanel.ui.description") })
        local presets = { { 255, 200, 0 }, { 220, 60, 60 }, { 60, 140, 220 }, { 80, 200, 100 }, { 170, 90, 220 }, { 240, 240, 240 } }
        for i, pc in ipairs(presets) do
            local bx = cx + (i - 1) * 44
            dxDrawRectangle(bx, fy + 68, 34, 26, tocolor(pc[1], pc[2], pc[3], 255))
            if UI.clickedIn(bx, fy + 68, 34, 26) then czColor = pc end
        end
        if UI.button(cx + cw - 150, fy + 66, 150, 32, L("common.save"), { size = 1.25, bg = C.dark, txt = C.white, hoverBg = C.green }) then
            local c = czColor
            triggerServerEvent("sp:crew:customize", localPlayer, tag, desc,
                c and c[1] or nil, c and c[2] or nil, c and c[3] or nil)
        end
    end
end

function socialFindCrew(cx, cy, cw)
    local list = snapshot.crews or {}
    dxDrawText(L("v_socialpanel.ui.find_crew_2", { list = #list }), cx, cy, cx + cw, cy + 26, C.dark, 1.7, "default-bold", "left", "top")
    local hasCrew = snapshot.crew ~= nil
    if #list == 0 then
        dxDrawText(L("v_socialpanel.ui.no_crews_exist_yet_be_first"), cx, cy + 40, cx + cw, cy + 70,
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
            dxDrawText(L("v_socialpanel.ui.founder_members_30", { founder = dn(cr.founder), members = cr.members }),
                cx + 14, ry + 29, cx + cw, ry + 47, C.sub, 1.1, "default", "left", "top")
            if UI.button(cx + cw - 130, ry + 12, 120, rowH - 24, hasCrew and L("v_socialpanel.ui.in_crew") or L("v_socialpanel.ui.join"),
                { size = 1.2, bg = C.bg, hoverBg = C.green, hoverTxt = C.white, disabled = hasCrew }) then
                triggerServerEvent("sp:crew:join", localPlayer, cr.name)
            end
        end
    end
    UI.endScroll()
end

--------------------------------------------------------------------------------
-- PROFILE
--------------------------------------------------------------------------------

function renderProfile()
    local p = viewedProfile
    local isOwn = (p == nil)
    local name, level, playtime, online, crewName, crewTag, crewCol, isFriend, isSelf

    if isOwn then
        name = snapshot.displayName or snapshot.account or getPlayerName(localPlayer)
        level = getElementData(localPlayer, "level") or "n/a"
        playtime = getElementData(localPlayer, "Játékidő") or "n/a"
        online = true
        if snapshot.crew then
            crewName, crewTag, crewCol = snapshot.crew.name, snapshot.crew.tag, snapshot.crew.color
        end
        isSelf = true
    else
        name, level, playtime, online = p.display or p.name, p.level, p.playtime, p.online
        crewName, crewTag, crewCol = p.crew, p.crewTag, p.crewColor
        isFriend, isSelf = p.isFriend, p.isSelf
    end

    local headH = 150
    dxDrawRectangle(X, Y, W, headH, C.accent)
    dxDrawRectangle(X + 24, Y + 28, 94, 94, C.dark)
    dxDrawText(L.upper(L.sub(name, 1, 1)), X + 24, Y + 28, X + 118, Y + 122, C.accent, 3, "default-bold", "center", "center")
    dxDrawText(name, X + 140, Y + 30, X + W - 20, Y + 66, C.dark, 2.4, "default-bold", "left", "top")
    dxDrawText(online and L("v_socialpanel.ui.online_2") or L("v_socialpanel.ui.offline_2"), X + 140, Y + 78, X + W - 20, Y + 100,
        online and tocolor(0, 120, 0, 255) or tocolor(150, 40, 40, 255), 1.4, "default-bold", "left", "top")

    if isOwn then
        if UI.button(X + W - 170, Y + 20, 150, 34, L("v_socialpanel.ui.account"), { size = 1.3, bg = C.dark, txt = C.white, hoverBg = C.panel, hoverTxt = C.dark }) then
            openAccount()
        end
    else
        if UI.button(X + W - 130, Y + 20, 110, 30, L("common.back"), { size = 1.3, bg = C.panel }) then
            viewedProfile = nil
            content_id = 4
        end
        if not isSelf then
            local function refetch()
                setTimer(function()
                    if show_socialpanel then triggerServerEvent("sp:profile:view", localPlayer, name) end
                end, 400, 1)
            end
            if UI.button(X + W - 320, Y + 62, 150, 34, L("v_socialpanel.ui.message"), { size = 1.3, bg = C.panel, hoverBg = C.blue, hoverTxt = C.white }) then
                openConversation("dm", name)
            end
            if isFriend then
                if UI.button(X + W - 162, Y + 62, 150, 34, L("v_socialpanel.ui.remove_friend"),
                    { size = 1.3, bg = C.panel, hoverBg = C.red, hoverTxt = C.white }) then
                    triggerServerEvent("sp:friend:remove", localPlayer, name)
                    refetch()
                end
            else
                if UI.button(X + W - 162, Y + 62, 150, 34, L("v_socialpanel.ui.add_friend"),
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
        dxDrawText(L.upper(label), bx, sy + 12, bx + bw, sy + 32, C.sub, 1.2, "default-bold", "center", "top")
        dxDrawText(tostring(value), bx, sy + 34, bx + bw, sy + 80, valColor or C.dark, 2, "default-bold", "center", "top")
    end
    stat(1, L("common.level"), level)
    stat(2, L("common.played_time"), playtime)
    stat(3, L("v_socialpanel.ui.crew_2"), crewName and ("[" .. (crewTag or "?") .. "]") or "-", crewName and crewColor(crewCol) or C.sub)

    if crewName then
        dxDrawText(L("v_socialpanel.ui.crew_3", { crew_name = crewName }), X + 30, sy + 110, X + W - 30, sy + 134, C.dark, 1.4, "default-bold", "left", "top")
    end

    if isOwn then
        dxDrawText(L("v_socialpanel.ui.this_is_your_public_profile_this"),
            X + 30, Y + H - 40, X + W - 30, Y + H - 16, C.sub, 1.15, "default", "left", "top")
    end
end

--------------------------------------------------------------------------------
-- ACCOUNT (settings of the own profile): display name, email, password.
-- The account name itself can never be changed. Email and password go to
-- acc_auth (it checks the current password), the display name to the server
-- of this resource.
--------------------------------------------------------------------------------

local accEmail = { masked = false, has = false }
local accStatus = nil      -- { text, ok }

local function setAccStatus(text, ok)
    accStatus = { text = tostring(text or ""), ok = ok }
end

function openAccount()
    content_id = 6
    accStatus = nil
    UI.setInput("acc_display", snapshot.displayName or snapshot.account or "")
    for _, id in ipairs({ "acc_email", "acc_email_pw", "acc_pw_cur", "acc_pw_new", "acc_pw_new2" }) do
        UI.clearInput(id)
    end
    exports.acc_auth:requestEmail()
end

addEvent("acc_auth:onClientEmail", true)
addEventHandler("acc_auth:onClientEmail", localPlayer, function(masked, has, notice)
    accEmail.masked, accEmail.has = masked, has and true or false
    if notice and content_id == 6 then
        setAccStatus(notice, true)
        UI.clearInput("acc_email"); UI.clearInput("acc_email_pw")
    end
end)

addEvent("acc_auth:onClientSettings", true)
addEventHandler("acc_auth:onClientSettings", localPlayer, function(kind, ok, text)
    if content_id ~= 6 then return end
    setAccStatus(text, ok)
    if ok and kind == "password" then
        UI.clearInput("acc_pw_cur"); UI.clearInput("acc_pw_new"); UI.clearInput("acc_pw_new2")
    end
end)

addEvent("acc_auth:onClientAuthError", true)
addEventHandler("acc_auth:onClientAuthError", localPlayer, function(msg)
    if content_id == 6 then setAccStatus(msg, false) end
end)

addEvent("sp:display:result", true)
addEventHandler("sp:display:result", localPlayer, function(ok, msg)
    if content_id == 6 then setAccStatus(L.resolve(msg), ok) end
end)

function renderAccount()
    local leftW = W * 0.4
    dxDrawRectangle(X, Y, leftW, H, C.grey)

    local lx, lw = X + 20, leftW - 40
    dxDrawText(L("v_socialpanel.ui.account_settings"), lx, Y + 16, lx + lw, Y + 44, C.dark, 1.7, "default-bold", "left", "top")
    dxDrawText(L("v_socialpanel.ui.account_settings_intro"), lx, Y + 52, lx + lw, Y + 120, C.sub, 1.15, "default", "left", "top", false, true)

    dxDrawText(L("v_socialpanel.ui.account_name"), lx, Y + 140, lx + lw, Y + 160, C.sub, 1.15, "default", "left", "top")
    dxDrawRectangle(lx, Y + 164, lw, 34, tocolor(228, 228, 228, 255))
    dxDrawText(snapshot.account or getPlayerName(localPlayer), lx + 8, Y + 164, lx + lw - 8, Y + 198, C.sub, 1.3, "default", "left", "center")
    dxDrawText(L("v_socialpanel.ui.account_name_locked"), lx, Y + 204, lx + lw, Y + 224, C.sub, 1.05, "default", "left", "top")

    if UI.button(lx, Y + H - 56, 120, 34, L("v_socialpanel.ui.back_to_profile"), { size = 1.25, bg = C.panel }) then
        content_id = 5
    end

    local rx, rw = X + leftW + 20, W - leftW - 40
    local bw = 100
    local function head(txt, y) dxDrawText(txt, rx, Y + y, rx + rw, Y + y + 24, C.dark, 1.5, "default-bold", "left", "top") end

    -- display name
    head(L("v_socialpanel.ui.display_name"), 14)
    local display = UI.input("acc_display", rx, Y + 42, rw - bw - 8, 34, { max = 72 })
    if UI.button(rx + rw - bw, Y + 42, bw, 34, L("v_socialpanel.ui.save"), { size = 1.2, bg = C.accent, hoverBg = C.dark, hoverTxt = C.white }) then
        triggerServerEvent("sp:display:set", localPlayer, display)
    end
    dxDrawText(L("v_socialpanel.ui.display_name_hint"), rx, Y + 82, rx + rw, Y + 100, C.sub, 1.05, "default", "left", "top")

    -- email
    head(L("v_socialpanel.ui.email_address"), 120)
    dxDrawText(accEmail.has and accEmail.masked or L("v_socialpanel.ui.no_email_set"), rx, Y + 148, rx + rw, Y + 168,
        accEmail.has and C.dark or C.sub, 1.2, "default", "left", "top")
    local mail = UI.input("acc_email", rx, Y + 174, rw - bw - 8, 34, { placeholder = L("v_socialpanel.ui.new_email"), max = 120 })
    local mailPw = ""
    if accEmail.has then
        mailPw = UI.input("acc_email_pw", rx, Y + 214, rw, 34, { placeholder = L("v_socialpanel.ui.email_password_needed"), mask = true, max = 128 })
    end
    if UI.button(rx + rw - bw, Y + 174, bw, 34, L("v_socialpanel.ui.save"), { size = 1.2, bg = C.accent, hoverBg = C.dark, hoverTxt = C.white }) then
        if mail ~= "" then exports.acc_auth:setEmail(mail, mailPw) end
    end

    -- password
    head(L("v_socialpanel.ui.change_password"), 268)
    local cur  = UI.input("acc_pw_cur", rx, Y + 296, rw, 34, { placeholder = L("v_socialpanel.ui.current_password"), mask = true, max = 128 })
    local half = (rw - 8) / 2
    local new1 = UI.input("acc_pw_new", rx, Y + 336, half, 34, { placeholder = L("v_socialpanel.ui.new_password"), mask = true, max = 128 })
    local new2 = UI.input("acc_pw_new2", rx + half + 8, Y + 336, half, 34, { placeholder = L("v_socialpanel.ui.new_password_again"), mask = true, max = 128 })
    if UI.button(rx, Y + 380, 140, 36, L("v_socialpanel.ui.save"), { size = 1.25, bg = C.accent, hoverBg = C.dark, hoverTxt = C.white }) then
        if cur == "" or new1 == "" then
            -- nothing to send
        elseif new1 ~= new2 then
            setAccStatus(L("v_socialpanel.ui.passwords_do_not_match"), false)
        else
            triggerServerEvent("acc_auth:changePassword", localPlayer, cur, new1)
        end
    end

    if accStatus then
        dxDrawText(accStatus.text, rx, Y + 432, rx + rw, Y + 490, accStatus.ok and C.green or C.red, 1.2, "default-bold", "left", "top", false, true)
    end
end

-- Texts load only once the player is loaded (acc_loading gate).
local textsLoaded = false
local function loadTexts()
    if textsLoaded then return end
    textsLoaded = true
    build_TABS()
    build_SOCIAL_TABS()
    exports.acc_loading:resourceReady()
end
addEvent("onClientLoadingStarted", true)
addEventHandler("onClientLoadingStarted", root, loadTexts)
addEventHandler("onClientResourceStart", resourceRoot, function()
    if getElementData(localPlayer, "loaded") then loadTexts() end
end)
