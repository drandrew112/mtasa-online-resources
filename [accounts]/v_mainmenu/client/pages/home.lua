if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- HOME: Join game, profile, friends, news, this week, messages, collectibles, spawn location.

local function grid(x, y, w, h, cols, rows)
    local gap = S(14)
    local cw = (w - gap * (cols - 1)) / cols
    local rh = (h - gap * (rows - 1)) / rows
    return function(c, r, cs, rs)
        cs, rs = cs or 1, rs or 1
        return x + (c - 1) * (cw + gap), y + (r - 1) * (rh + gap), cw * cs + gap * (cs - 1), rh * rs + gap * (rs - 1)
    end
end
Grid = grid

local function spawnText()
    local prefs = (Menu.data.profile or {}).preferences or {}
    return prefs.spawnLocation == "random" and L("v_mainmenu.prefs.random") or L("v_mainmenu.prefs.last")
end

-- title, body of a v_news article in the current language (else the server's pick)
local function newsText(a)
    local t = type(a.texts) == "table" and a.texts[L.lang()]
    if t then return t.title, t.body end
    return a.title, a.body
end

local function bigNumber(str, x, y, w, color)
    text(str, x, y, w, S(48), color or C.white, 1, FONT.big, "left", "center")
end

PAGES.defs.home = {
    label = "v_mainmenu.page.home",
    draw = function(x, y, w, h)
        -- not downloaded custom models: a warning strip on top (pages/models.lua)
        local strip = drawModelsReminder(x, y, w)
        y, h = y + strip, h - strip
        local at = grid(x, y, w, h, 4, 3)
        local p = Menu.data.profile or {}

        -- Join game
        local jx, jy, jw, jh = at(1, 1, 2, 2)
        tile("page", "home_join", jx, jy, jw, jh, L("v_mainmenu.home.join"), nil, function(cx, cy, cw, ch)
            local pos = p.position
            local where = (p.preferences or {}).spawnLocation == "random" and L("v_mainmenu.home.spawn_random")
                or (pos and pos.zone and L("v_mainmenu.home.spawn_last", { zone = pos.zone })) or L("v_mainmenu.home.spawn_default")
            text(where, cx, cy + ch - S(30), cw, S(30), C.text, 1.05, FONT.row)
        end, Menu.join, "join")

        -- profile
        local px, py, pw, ph = at(3, 1)
        tile("page", "home_profile", px, py, pw, ph, L("v_mainmenu.home.profile"), nil, function(cx, cy, cw, ch)
            bigNumber(L("v_mainmenu.home.level", { level = p.level or 1 }), cx, cy + ch - S(92), cw)
            local frac = (p.nextXp and p.nextXp > 0) and (p.xp or 0) / p.nextXp or 0
            bar(cx, cy + ch - S(38), cw, S(6), frac, C.xp)
            text(L("v_mainmenu.home.xp_played", { xp = fmtInt(p.xp or 0), next = p.nextXp and fmtInt(p.nextXp) or "-", played = p.playtime or "-" }),
                cx, cy + ch - S(28), cw, S(26), C.dim, 0.9, FONT.row)
        end, function() Menu.goto("profile", "stats") end)

        -- friends
        local fx, fy, fw, fh = at(4, 1)
        local snap = Social.snapshot or {}
        local online, total, names = 0, #(snap.friends or {}), {}
        for _, f in ipairs(snap.friends or {}) do
            if f.online then online = online + 1; if #names < 4 then names[#names + 1] = f.name end end
        end
        tile("page", "home_friends", fx, fy, fw, fh, L("v_mainmenu.home.friends"), nil, function(cx, cy, cw, ch)
            bigNumber(L("v_mainmenu.home.online_of", { online = online, total = total }), cx, cy + ch - S(78), cw)
            text(#names > 0 and table.concat(names, ", ") or L("v_mainmenu.home.nobody_online"), cx, cy + ch - S(28), cw, S(26), C.dim, 0.9, FONT.row)
        end, function() Menu.goto("social", "friends") end)

        -- news
        local nx, ny, nw, nh = at(3, 2, 2, 1)
        local first = (Menu.data.news or {})[1]
        tile("page", "home_news", nx, ny, nw, nh, L("v_mainmenu.home.news"), nil, function(cx, cy, cw, ch)
            if first then
                local title, body = newsText(first)
                text(title, cx, cy + S(40), cw, S(28), C.white, 1.15, FONT.rowB)
                text(first.dateText .. "  ·  " .. body, cx, cy + S(72), cw, ch - S(72), C.dim, 0.95, FONT.row, "left", "top", true, true)
            else
                text(L("v_mainmenu.news.none"), cx, cy + S(40), cw, S(28), C.dim, 1.0, FONT.row)
            end
        end, function() Menu.openView("news", {}) end)

        -- this week
        local wx, wy, ww, wh = at(1, 3)
        local wk = Menu.data.weekly
        local best = 0
        local count = 0
        for _, c in ipairs(wk and wk.bonuses or {}) do
            for _, j in ipairs(c.items) do
                count = count + 1
                best = math.max(best, tonumber(j.money) or 0, tonumber(j.xp) or 0)
            end
        end
        tile("page", "home_weekly", wx, wy, ww, wh, L("v_mainmenu.home.weekly"), nil, function(cx, cy, cw, ch)
            if best > 1 then
                bigNumber(("%gx"):format(best), cx, cy + ch - S(78), cw, C.money)
                text(L("v_mainmenu.home.weekly_bonuses", { count = count }), cx, cy + ch - S(28), cw, S(26), C.dim, 0.9, FONT.row)
            else
                text(L("v_mainmenu.home.weekly_none"), cx, cy + ch - S(28), cw, S(26), C.dim, 0.9, FONT.row)
            end
        end, function() Menu.openView("weekly", {}) end)

        -- messages
        local mx, my, mw, mh = at(2, 3)
        local unread = 0
        for _, c in ipairs(snap.conversations or {}) do unread = unread + (c.unread or 0) end
        tile("page", "home_messages", mx, my, mw, mh, L("v_mainmenu.home.messages"), nil, function(cx, cy, cw, ch)
            bigNumber(tostring(unread), cx, cy + ch - S(78), cw)
            text(L("v_mainmenu.home.unread"), cx, cy + ch - S(28), cw, S(26), C.dim, 0.9, FONT.row)
        end, function() Menu.goto("social", "messages") end)

        -- collectibles
        local cx0, cy0, cw0, ch0 = at(3, 3)
        local found = 0
        for _, c in ipairs(Menu.data.collectibles or {}) do found = found + (c.count or 0) end
        tile("page", "home_collectibles", cx0, cy0, cw0, ch0, L("v_mainmenu.home.collectibles"), nil, function(cx, cy, cw, ch)
            bigNumber(tostring(found), cx, cy + ch - S(78), cw)
            text(L("v_mainmenu.home.found"), cx, cy + ch - S(28), cw, S(26), C.dim, 0.9, FONT.row)
        end, function() Menu.goto("profile", "collectibles") end)

        -- spawn location: Enter switches it right here
        local sx, sy, sw0, sh0 = at(4, 3)
        tile("page", "home_spawn", sx, sy, sw0, sh0, L("v_mainmenu.prefs.spawn_location"), nil, function(cx, cy, cw, ch)
            text("‹  " .. spawnText() .. "  ›", cx, cy + ch - S(78), cw, S(48), C.white, 1.3, FONT.head)
            text(L("v_mainmenu.home.spawn_hint"), cx, cy + ch - S(28), cw, S(26), C.dim, 0.9, FONT.row)
        end, function() togglePreference("spawnLocation") end)
    end,
}

-- last <-> random (v_accounts validates)
function togglePreference(id)
    local prefs = (Menu.data.profile or {}).preferences or {}
    if id == "spawnLocation" then
        local new = prefs.spawnLocation == "random" and "last" or "random"
        prefs.spawnLocation = new -- shown at once, the server answers with the saved profile
        triggerServerEvent("v_mainmenu:setPreference", localPlayer, id, new)
    end
end

--------------------------------------------------------------------------------
-- views reached from Home
--------------------------------------------------------------------------------

local newsSel = 1
VIEWS.news = {
    title = function() return L("v_mainmenu.home.news") end,
    onOpen = function() newsSel = 1 end,
    draw = function(x, y, w, h)
        local list = Menu.data.news or {}
        local lw = math.floor(w * 0.36)
        panelBox(x, y, lw, h)
        if #list == 0 then
            text(L("v_mainmenu.news.none"), x + S(18), y + S(14), lw, S(30), C.dim)
        end
        local rh = S(64)
        for i, a in ipairs(list) do
            local ry = y + (i - 1) * rh
            if ry + rh > y + h then break end
            local focused = row("view", "news_" .. i, x, ry, lw, rh - S(2), { activate = function() newsSel = i end })
            if focused then newsSel = i end
            text(a.dateText, x + S(16), ry + S(8), lw - S(32), S(20), C.dim, 0.85, FONT.row)
            text((newsText(a)), x + S(16), ry + S(28), lw - S(32), S(28), C.white, 1.05, FONT.rowB)
        end
        local a = list[newsSel]
        local rx, rw = x + lw + S(14), w - lw - S(14)
        panelBox(rx, y, rw, h)
        if a then
            local title, body = newsText(a)
            text(a.dateText, rx + S(24), y + S(20), rw - S(48), S(22), C.dim, 0.9, FONT.row)
            text(title, rx + S(24), y + S(44), rw - S(48), S(36), C.white, 1.5, FONT.head)
            text(body, rx + S(24), y + S(94), rw - S(48), h - S(110), C.text, 1.05, FONT.row, "left", "top", true, true)
        end
    end,
}

VIEWS.weekly = {
    title = function() return L("v_mainmenu.home.weekly") end,
    draw = function(x, y, w, h)
        local wk = Menu.data.weekly
        panelBox(x, y, w, h)
        local cx, cw = x + S(24), w - S(48)
        local yy = y + S(18)
        if not wk then
            return text(L("v_mainmenu.home.weekly_none"), cx, yy, cw, S(28), C.dim)
        end
        text(tostring(wk.from or "") .. "  -  " .. tostring(wk.to or ""), cx, yy, cw, S(24), C.dim, 0.95)
        yy = yy + S(40)
        heading(L("v_mainmenu.weekly.bonuses"), cx, yy, cw)
        yy = yy + S(32)
        local bonuses = wk.bonuses or {}
        if #bonuses == 0 then
            text(L("v_mainmenu.home.weekly_none"), cx, yy, cw, S(26), C.dim)
            yy = yy + S(30)
        end
        -- one block per category: Official Jobs, Community Jobs, Work
        local n = 0
        for _, c in ipairs(bonuses) do
            text(L("v_weekly.category." .. c.id), cx, yy, cw, S(28), C.dim, 0.95, FONT.rowB)
            yy = yy + S(30)
            for _, j in ipairs(c.items) do
                n = n + 1
                row("view", "wk_" .. n, cx, yy, cw, S(34), {})
                text(j.name, cx + S(14), yy, cw * 0.5, S(34), C.white, 1.0, FONT.rowB)
                text(L("v_mainmenu.weekly.money", { money = ("%g"):format(tonumber(j.money) or 1) }), cx + cw * 0.5, yy, cw * 0.25, S(34), C.money, 1.0, FONT.rowB, "right")
                if j.xp then text(L("v_mainmenu.weekly.xp", { xp = ("%g"):format(tonumber(j.xp) or 1) }), cx + cw * 0.75, yy, cw * 0.25 - S(14), S(34), C.xp, 1.0, FONT.rowB, "right") end
                yy = yy + S(38)
            end
            yy = yy + S(6)
        end
        local b = wk.loginBonus
        if b then
            yy = yy + S(16)
            heading(L("v_mainmenu.weekly.login_bonus"), cx, yy, cw)
            yy = yy + S(32)
            text(("€%s   ·   %s XP"):format(fmtInt(b.money or 0), fmtInt(b.xp or 0)), cx, yy, cw, S(28), C.money, 1.05, FONT.rowB)
            yy = yy + S(34)
        end
        local t = wk.timetrial
        if t then
            yy = yy + S(16)
            heading(L("v_mainmenu.weekly.time_trial"), cx, yy, cw)
            yy = yy + S(32)
            text(L("v_mainmenu.weekly.trial_line", { name = t.name or "", time = t.time or 0, reward = fmtInt(t.reward or 0) }), cx, yy, cw, S(28), C.text, 1.05, FONT.rowB)
        end
    end,
}
