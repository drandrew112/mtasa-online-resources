if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- PROFILE: Account, Statistics, Vehicles, Collectibles, Achievements - all behind tiles.

Account = { masked = false, has = false, asked = false }
local mailField = TextField.new{ max = 254 }
local passField = TextField.new{ max = 128 }

local achData = nil

local function sumCollectibles()
    local n = 0
    for _, c in ipairs(Menu.data.collectibles or {}) do n = n + (c.count or 0) end
    return n
end

local function statValue(def, v)
    v = tonumber(v) or 0
    if def.unit == "km" then return ("%.1f km"):format(v) end
    if def.unit == "s" then return fmtDuration(v) end
    return fmtInt(v)
end

local function statVal(id)
    return tonumber(((Menu.data.stats or {}).values or {})[id]) or 0
end

PAGES.defs.profile = {
    label = "acc_menu.page.profile",
    onMenuOpen = function()
        Account.asked = false
        achData = nil
    end,
    draw = function(x, y, w, h)
        local at = Grid(x, y, w, h, 5, 1)
        local big = function(str, cx, cy, cw, ch) text(str, cx, cy + ch - S(96), cw, S(48), C.white, 1, FONT.big) end

        local ax, ay, aw, ah = at(1, 1)
        tile("page", "prof_account", ax, ay, aw, ah, L("acc_menu.profile.account"), L("acc_menu.profile.account_sub"), function(cx, cy, cw, ch)
            text(Account.has and Account.masked or L("acc_menu.account.no_email"), cx, cy + ch - S(70), cw, S(30), C.white, 1.05, FONT.rowB)
            text(Account.has and L("acc_menu.account.change_email") or L("acc_menu.account.add_email"), cx, cy + ch - S(36), cw, S(26), C.dim, 0.9)
        end, function() Menu.openView("account") end)

        local sx, sy, sw0, sh0 = at(2, 1)
        tile("page", "prof_stats", sx, sy, sw0, sh0, L("acc_menu.profile.stats"), L("acc_menu.profile.stats_sub"), function(cx, cy, cw, ch)
            big(("%.0f km"):format(statVal("drive_km")), cx, cy, cw, ch)
            text(L("acc_menu.profile.driven"), cx, cy + ch - S(36), cw, S(26), C.dim, 0.9)
        end, function() Menu.openView("stats") end)

        local vx, vy, vw, vh = at(3, 1)
        local vehicles = Menu.data.vehicles or {}
        local destroyed = 0
        for _, v in ipairs(vehicles) do if v.isDestroyed then destroyed = destroyed + 1 end end
        tile("page", "prof_vehicles", vx, vy, vw, vh, L("acc_menu.profile.vehicles"), L("acc_menu.profile.vehicles_sub"), function(cx, cy, cw, ch)
            big(tostring(#vehicles), cx, cy, cw, ch)
            text(L("acc_menu.profile.owned", { destroyed = destroyed }), cx, cy + ch - S(36), cw, S(26), C.dim, 0.9)
        end, function() Menu.openView("vehicles") end)

        local cx0, cy0, cw0, ch0 = at(4, 1)
        tile("page", "prof_collectibles", cx0, cy0, cw0, ch0, L("acc_menu.profile.collectibles"), L("acc_menu.profile.collectibles_sub"), function(cx, cy, cw, ch)
            big(tostring(sumCollectibles()), cx, cy, cw, ch)
            text(L("acc_menu.home.found"), cx, cy + ch - S(36), cw, S(26), C.dim, 0.9)
        end, function() Menu.openView("collectibles") end)

        local hx, hy, hw, hh = at(5, 1)
        local summary = achData and achData.summary
        tile("page", "prof_achievements", hx, hy, hw, hh, L("acc_menu.profile.achievements"), L("acc_menu.profile.achievements_sub"), function(cx, cy, cw, ch)
            if summary and summary.total then
                big(("%d / %d"):format(summary.done or 0, summary.total), cx, cy, cw, ch)
                bar(cx, cy + ch - S(30), cw, S(6), (summary.done or 0) / math.max(1, summary.total))
            else
                text(L("acc_menu.profile.open_to_load"), cx, cy + ch - S(36), cw, S(26), C.dim, 0.9)
            end
        end, function() Menu.openView("achievements") end)

        if not Account.asked then
            Account.asked = true
            exports.acc_auth:requestEmail()
        end
        if achData == nil and isSocialRunning() then
            achData = false
            exports.v_socialpanel:spRequestAchievements()
        end
    end,
}

--------------------------------------------------------------------------------
-- Account (email)
--------------------------------------------------------------------------------

addEvent("acc_auth:onClientEmail", true)
addEventHandler("acc_auth:onClientEmail", localPlayer, function(masked, has, notice)
    Account.masked, Account.has = masked or false, has == true
    if notice then
        notify(notice)
        mailField:setText("")
        passField:setText("")
    end
end)

addEvent("acc_auth:onClientAuthError", true)
addEventHandler("acc_auth:onClientAuthError", localPlayer, function(msg)
    if Menu.open then notify(msg) end
end)

VIEWS.account = {
    title = function() return L("acc_menu.profile.account") end,
    onOpen = function()
        mailField:setText("")
        passField:setText("")
        exports.acc_auth:requestEmail()
    end,
    draw = function(x, y, w, h)
        local lw = math.floor(w * 0.38)
        panelBox(x, y, lw, S(230))
        local cx, cw = x + S(24), lw - S(48)
        heading(L("acc_menu.account.your_account"), cx, y + S(18), cw)
        local p = Menu.data.profile or {}
        local yy = y + S(64)
        local function line(label, value)
            text(label, cx, yy, cw, S(30), C.dim, 1.0)
            text(value, cx, yy, cw, S(30), C.white, 1.0, FONT.rowB, "right")
            yy = yy + S(36)
        end
        line(L("acc_menu.account.name"), tostring(p.account or ""))
        line(L("acc_menu.account.email"), Account.has and Account.masked or L("acc_menu.account.no_email"))
        line(L("acc_menu.account.played"), tostring(p.playtime or "-"))

        local rx, rw = x + lw + S(14), w - lw - S(14)
        panelBox(rx, y, rw, S(360))
        local fx, fw = rx + S(24), math.min(rw - S(48), S(560))
        heading(Account.has and L("acc_menu.account.change_email") or L("acc_menu.account.add_email"), fx, y + S(18), fw)
        text(Account.has and L("acc_menu.account.change_info") or L("acc_menu.account.add_info"), fx, y + S(50), fw, S(44), C.dim, 0.95, FONT.row, "left", "top", true, true)

        local function submit()
            if Account.has and passField:getText() == "" then
                return notify(L("acc_menu.account.password_needed"))
            end
            exports.acc_auth:setEmail(mailField:getText(), passField:getText())
        end

        local fy = y + S(104)
        text(L("acc_menu.account.new_email"), fx, fy, fw, S(20), C.dim, 0.85, FONT.rowB)
        field("view", "acc_mail", fx, fy + S(22), fw, S(42), mailField, "name@example.com", submit)
        fy = fy + S(76)
        if Account.has then
            text(L("acc_menu.account.current_password"), fx, fy, fw, S(20), C.dim, 0.85, FONT.rowB)
            field("view", "acc_pass", fx, fy + S(22), fw, S(42), passField, "", submit, true)
            fy = fy + S(76)
        end
        local bw = S(180)
        button("view", "acc_save", fx, fy + S(6), bw, S(42), L("acc_menu.account.save_email"), submit)
        if Account.has then
            button("view", "acc_remove", fx + bw + S(12), fy + S(6), bw, S(42), L("acc_menu.account.remove_email"), function()
                if passField:getText() == "" then return notify(L("acc_menu.account.password_needed")) end
                exports.acc_auth:setEmail("", passField:getText())
            end, "ghost")
        end
    end,
}

--------------------------------------------------------------------------------
-- Statistics: one tile per category (v_stats definitions + level / played time)
--------------------------------------------------------------------------------

local STAT_CATS = { "general", "distance", "vehicle_time", "combat", "work", "activities", "other" }

local function statCategories()
    local p = Menu.data.profile or {}
    local cats = {
        general = { { L("acc_menu.stats.level"), tostring(p.level or 1) },
                    { L("acc_menu.stats.total_xp"), fmtInt(p.xp or 0) },
                    { L("acc_menu.stats.to_next"), p.nextXp and fmtInt(math.max(0, p.nextXp - (p.xp or 0))) or "-" },
                    { L("acc_menu.stats.played"), tostring(p.playtime or "-") } },
    }
    local st = Menu.data.stats or {}
    for _, def in ipairs(st.defs or {}) do
        local cat = def.category or "other"
        cats[cat] = cats[cat] or {}
        table.insert(cats[cat], { L.resolve(def.name), statValue(def, (st.values or {})[def.id]) })
    end
    if cats.combat then
        local deaths = statVal("deaths")
        local kills = statVal("kills_players") + statVal("kills_peds")
        table.insert(cats.combat, { L("acc_menu.stats.kd"), ("%.2f"):format(kills / math.max(1, deaths)) })
    end
    local out = {}
    for _, id in ipairs(STAT_CATS) do
        if cats[id] then out[#out + 1] = { id = id, rows = cats[id] } end
    end
    return out
end

VIEWS.stats = {
    title = function() return L("acc_menu.profile.stats") end,
    draw = function(x, y, w, h)
        local cats = statCategories()
        local cols = math.min(4, #cats)
        local rows = math.ceil(#cats / cols)
        local at = Grid(x, y, w, h, cols, rows)
        for i, cat in ipairs(cats) do
            local c = (i - 1) % cols + 1
            local r = math.floor((i - 1) / cols) + 1
            local tx, ty, tw, th = at(c, r)
            tile("view", "stat_" .. cat.id, tx, ty, tw, th, L("acc_menu.statcat." .. cat.id), nil, function(cx, cy, cw, ch)
                local yy = cy + S(40)
                local lineH = math.min(S(30), (ch - S(40)) / math.max(1, #cat.rows))
                for _, rw in ipairs(cat.rows) do
                    if yy + lineH > cy + ch + S(4) then break end
                    text(rw[1], cx, yy, cw * 0.68, lineH, C.dim, 0.92, FONT.row)
                    text(rw[2], cx + cw * 0.6, yy, cw * 0.4, lineH, C.white, 0.95, FONT.rowB, "right")
                    yy = yy + lineH
                end
            end)
        end
    end,
}

--------------------------------------------------------------------------------
-- Vehicles
--------------------------------------------------------------------------------

VIEWS.vehicles = {
    title = function() return L("acc_menu.profile.vehicles") end,
    draw = function(x, y, w, h)
        local list = Menu.data.vehicles or {}
        if #list == 0 then
            panelBox(x, y, w, S(80))
            return text(L("acc_menu.vehicles.none"), x + S(24), y, w, S(80), C.dim, 1.05)
        end
        local cols = 4
        local tileH = S(170)
        local gap = S(14)
        local tw = (w - gap * (cols - 1)) / cols
        local scroll = VIEWS.vehicles.scroll or 0
        local rowsVisible = math.max(1, math.floor((h + gap) / (tileH + gap)))
        local totalRows = math.ceil(#list / cols)
        scroll = math.max(0, math.min(scroll, totalRows - rowsVisible))
        VIEWS.vehicles.scroll = scroll
        Menu.wheel(x, y, w, h, function(d) VIEWS.vehicles.scroll = (VIEWS.vehicles.scroll or 0) + d end)
        for i, v in ipairs(list) do
            local r = math.floor((i - 1) / cols) - scroll
            if r >= 0 and r < rowsVisible then
                local c = (i - 1) % cols
                local tx, ty = x + c * (tw + gap), y + r * (tileH + gap)
                local focused = tile("view", "veh_" .. tostring(v.id), tx, ty, tw, tileH, v.name, v.plate and L("acc_menu.vehicles.plate", { plate = v.plate }) or nil,
                    function(cx, cy, cw, ch)
                        local status, color = L("acc_menu.vehicles.stored"), C.dim
                        if v.isDestroyed then status, color = L("acc_menu.vehicles.destroyed"), C.bad
                        elseif v.spawned then status, color = L("acc_menu.vehicles.spawned"), C.money end
                        chip(status, cx, cy + ch - S(24), color)
                    end)
                if focused then
                    -- keep the focused tile on screen
                    if r == rowsVisible - 1 and r + scroll < totalRows - 1 then VIEWS.vehicles.scroll = scroll + 1 end
                    if r == 0 and scroll > 0 then VIEWS.vehicles.scroll = scroll - 1 end
                end
            end
        end
    end,
}

--------------------------------------------------------------------------------
-- Collectibles
--------------------------------------------------------------------------------

VIEWS.collectibles = {
    title = function() return L("acc_menu.profile.collectibles") end,
    draw = function(x, y, w, h)
        local list = Menu.data.collectibles or {}
        local at = Grid(x, y, w, math.min(h, S(320)), math.max(1, #list), 1)
        for i, c in ipairs(list) do
            local tx, ty, tw, th = at(i, 1)
            tile("view", "col_" .. c.id, tx, ty, tw, th, L(c.label), nil, function(cx, cy, cw, ch)
                local n = c.total and ("%d / %d"):format(c.count, c.total) or tostring(c.count)
                text(n, cx, cy + ch - S(96), cw, S(48), C.white, 1, FONT.big)
                if c.total then bar(cx, cy + ch - S(36), cw, S(6), c.count / math.max(1, c.total)) end
                text(L("acc_menu.collectibles.found"), cx, cy + ch - S(26), cw, S(24), C.dim, 0.9)
            end)
        end
    end,
}

--------------------------------------------------------------------------------
-- Achievements (through the Social API, like the social panel's tab)
--------------------------------------------------------------------------------

addEvent("v_socialpanel:onClientAchievements")
addEventHandler("v_socialpanel:onClientAchievements", localPlayer, function(data)
    if type(data) == "table" then achData = data end
end)

VIEWS.achievements = {
    title = function() return L("acc_menu.profile.achievements") end,
    onOpen = function()
        VIEWS.achievements.scroll = 0
        if isSocialRunning() then exports.v_socialpanel:spRequestAchievements() end
    end,
    draw = function(x, y, w, h)
        if not achData or not achData.available then
            panelBox(x, y, w, S(80))
            return text(L("acc_menu.achievements.unavailable"), x + S(24), y, w, S(80), C.dim, 1.05)
        end
        local list = achData.list or {}
        local rh = S(58)
        local visible = math.floor(h / rh)
        local scroll = math.max(0, math.min(VIEWS.achievements.scroll or 0, #list - visible))
        VIEWS.achievements.scroll = scroll
        Menu.wheel(x, y, w, h, function(d) VIEWS.achievements.scroll = (VIEWS.achievements.scroll or 0) + d end)
        for i = scroll + 1, math.min(#list, scroll + visible) do
            local a = list[i]
            local ry = y + (i - scroll - 1) * rh
            local focused = row("view", "ach_" .. tostring(a.id), x, ry, w, rh - S(4), {})
            if focused then
                if i == scroll + visible and i < #list then VIEWS.achievements.scroll = scroll + 1 end
                if i == scroll + 1 and scroll > 0 then VIEWS.achievements.scroll = scroll - 1 end
            end
            text(L.resolve(a.name), x + S(18), ry + S(6), w * 0.5, S(24), a.done and C.white or C.text, 1.0, FONT.rowB)
            text(L.resolve(a.desc), x + S(18), ry + S(28), w * 0.6, S(22), C.dim, 0.85)
            if a.done then
                chip(L("acc_menu.achievements.unlocked"), x + w - S(150), ry + S(16), C.money, tocolor(110, 220, 130, 40))
            elseif a.isProgress then
                bar(x + w - S(260), ry + S(24), S(160), S(6), (a.progress or 0) / math.max(1, a.goal or 1))
                text(("%s / %s"):format(fmtInt(a.progress or 0), fmtInt(a.goal or 1)), x + w - S(90), ry, S(80), rh - S(4), C.dim, 0.85, FONT.row, "right")
            end
        end
    end,
}
