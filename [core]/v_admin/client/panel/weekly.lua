if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ============================================================
--  v_admin / client/panel/weekly.lua
--  Weekly page (was the /weekly window of v_weekly): the upcoming weeks
--  on the left, Bonuses (Official Jobs / Community Jobs / Work multipliers),
--  time trial, login bonus and weekly news of the chosen week on the right. Every change goes to the server
--  (server/pages/weekly.lua), which answers with a fresh overview.
-- ============================================================

local S, F, C = AP.S, AP.F, AP.C

local st = { data = nil, week = 1, tab = "bonuses", sub = "official", loadedWeek = nil }

local function curWeek() return st.data and st.data.weeks[st.week] end

local function fillFields()
    local w = curWeek()
    if not w then return end
    local b = w.loginBonus or {}
    local n = w.news or {}
    AP.setField("wk_money", tostring(b.money or 0))
    AP.setField("wk_xp", tostring(b.xp or 0))
    AP.setField("wk_title", n.title or "")
    AP.setField("wk_body", n.body or "")
    st.loadedWeek = st.week
end

local function setData(data)
    if not data then return end
    st.data = data
    st.week = math.min(st.week, #data.weeks)
    fillFields()
end

local function load()
    AP.call("weekly", "overview", {}, function(r) setData(r) end)
end

local function edit(action, a, b, c)
    local w = curWeek()
    if not w then return end
    AP.call("weekly", "edit", { action = action, offset = w.offset, a = a, b = b, c = c }, function(r) setData(r) end)
end

local function weekLabel(w)
    if w.offset == 0 then return L("v_weekly.admin.this_week") end
    if w.offset == 1 then return L("v_weekly.admin.next_week") end
    return L("v_weekly.admin.in_weeks", { offset = w.offset })
end

--------------------------------------------------------------------------------
-- tabs
--------------------------------------------------------------------------------

-- Multiplier table of one list: official games (data.jobs), the player-made
-- community games (data.communityJobs, with their creator) or the work_core
-- works (data.works, kind = "work").
local function drawJobList(id, list, empty, community, x, y, w, h, kind)
    local data, week = st.data, curWeek()
    if #list == 0 then
        return AP.text(empty, x, y, w, S(40), C.dim, 1.0)
    end
    local bw, bh = S(54), S(30)
    local cols = {
        { key = "name", label = kind == "work" and L("v_admin.weekly.work") or L("v_weekly.admin.job"), bold = true,
          text = function(j) return j.missing and L("v_admin.weekly.not_registered", { name = j.name }) or j.name end },
        { key = "money", label = L("v_weekly.admin.money"), w = (bw + S(6)) * #data.multipliers + S(20),
          text = function() return "" end },
        { key = "xp", label = L("v_weekly.admin.xp"), w = (bw + S(6)) * #data.multipliers + S(20),
          text = function() return "" end },
    }
    if community then
        table.insert(cols, 2, { key = "owner", label = L("v_admin.weekly.created_by"), w = S(200), color = function() return C.dim end })
    end
    AP.table(id, x, y, w, h, cols, list, { rowH = S(46) })
    -- multiplier buttons on top of the visible rows
    local first = AP.scroll[id] or 0
    local rowH = S(46)
    local ly = y + S(36)
    local visible = math.max(1, math.floor((y + h - ly) / rowH))
    local xpX = x + w - cols[#cols].w
    local moneyX = xpX - cols[#cols - 1].w
    for i = 1, visible do
        local j = list[first + i]
        if not j then break end
        local ry = ly + (i - 1) * rowH + (rowH - S(4) - bh) / 2
        local action = kind or "job"
        local m = (action == "work" and (week.works or {}) or week.jobs)[j.id]
        local curMoney, curXp = m and m.money or 1, m and m.xp or 1
        for k, mult in ipairs(data.multipliers) do
            AP.button(moneyX + S(10) + (k - 1) * (bw + S(6)), ry, bw, bh, mult .. "x",
                function() edit(action, j.id, mult, curXp) end, curMoney == mult and "active")
            AP.button(xpX + S(10) + (k - 1) * (bw + S(6)), ry, bw, bh, mult .. "x",
                function() edit(action, j.id, curMoney, mult) end, curXp == mult and "active")
        end
    end
end

local function drawJobs(x, y, w, h)
    drawJobList("wk_jobs", st.data.jobs, L("v_weekly.admin.v_jobmanager_has_no_official_jobs"), false, x, y, w, h)
end

local function drawCommunityJobs(x, y, w, h)
    AP.text(L("v_admin.weekly.community_hint"), x, y, w, S(30), C.dim, 0.85)
    drawJobList("wk_cjobs", st.data.communityJobs or {}, L("v_admin.weekly.no_community_jobs"), true, x, y + S(36), w, h - S(36))
end

local function drawWorks(x, y, w, h)
    AP.text(L("v_admin.weekly.work_hint"), x, y, w, S(30), C.dim, 0.85)
    drawJobList("wk_works", st.data.works or {}, L("v_admin.weekly.no_works"), false, x, y + S(36), w, h - S(36), "work")
end

-- Bonuses: Official Jobs / Community Jobs / Work submenu
local SUB = { official = drawJobs, community = drawCommunityJobs, work = drawWorks }

local function drawBonuses(x, y, w, h)
    local items = {
        { id = "official", label = L("v_weekly.category.official") },
        { id = "community", label = L("v_weekly.category.community") },
        { id = "work", label = L("v_weekly.category.work") },
    }
    local th = AP.tabs(x, y, w, items, st.sub, function(id) st.sub = id end)
    SUB[st.sub](x, y + th, w, h - th)
end

local function drawTrial(x, y, w, h)
    local data, week = st.data, curWeek()
    if #data.trials == 0 then
        return AP.text(L("v_weekly.admin.v_timetrial_is_not_running"), x, y, w, S(40), C.dim, 1.0)
    end
    local rows = {}
    for i, t in ipairs(data.trials) do rows[i] = { i = i, name = t.name, time = t.time, reward = t.reward } end
    AP.table("wk_trials", x, y, w, h, {
        { key = "name", label = L("v_weekly.admin.time_trial"), bold = true },
        { key = "time", label = L("v_admin.weekly.limit"), w = S(160), text = function(t) return L("v_weekly.admin.limit_s", { time = t.time or 0 }) end },
        { key = "reward", label = L("v_admin.weekly.reward"), w = S(160), align = "right",
          text = function(t) return "€" .. AP.fmtInt(t.reward) end, color = function() return C.good end },
        { key = "active", label = "", w = S(150), align = "center",
          text = function(t) return week.timetrial == t.i and L("v_weekly.admin.active") or L("v_weekly.admin.select") end,
          color = function(t) return week.timetrial == t.i and C.head or C.dim end },
    }, rows, { rowH = S(44), selected = function(t) return week.timetrial == t.i end,
        onClick = function(t) if week.timetrial ~= t.i then edit("trial", t.i) end end })
end

local function drawLogin(x, y, w, h)
    local data = st.data
    local fw = math.min(S(320), w / 2 - S(10))
    AP.text(L("v_weekly.admin.money_2"), x, y, fw, S(28), C.dim, 0.9)
    AP.text("XP", x + fw + S(20), y, fw, S(28), C.dim, 0.9)
    AP.field("wk_money", x, y + S(30), fw, S(44), { max = 8, numeric = true })
    AP.field("wk_xp", x + fw + S(20), y + S(30), fw, S(44), { max = 8, numeric = true })
    AP.button(x, y + S(90), S(200), S(44), L("v_admin.page.save"), function()
        edit("login", tonumber(AP.fieldText("wk_money")) or 0, tonumber(AP.fieldText("wk_xp")) or 0)
    end, "active")
    local lines = AP.wrap(L("v_weekly.admin.paid_once_per_to_every_player", { period = L("v_weekly.period." .. data.period),
        max_money = AP.fmtInt(data.maxMoney), max_xp = AP.fmtInt(data.maxXp) }), w, 0.9)
    for i, line in ipairs(lines) do
        AP.text(line, x, y + S(150) + (i - 1) * S(26), w, S(26), C.dim, 0.9)
    end
end

local function drawNews(x, y, w, h)
    AP.text(L("v_weekly.admin.title"), x, y, w, S(28), C.dim, 0.9)
    AP.field("wk_title", x, y + S(30), w, S(44), { max = 60 })
    AP.text(L("v_weekly.admin.text"), x, y + S(86), w, S(28), C.dim, 0.9)
    local bodyH = math.min(S(320), h - S(186))
    AP.field("wk_body", x, y + S(116), w, bodyH, { max = 600, multiline = true })
    AP.button(x, y + S(126) + bodyH, S(200), S(44), L("v_admin.page.save"), function()
        edit("news", AP.trim(AP.fieldText("wk_title")), AP.trim(AP.fieldText("wk_body")))
    end, "active")
end

local DRAW = { bonuses = drawBonuses, trial = drawTrial, login = drawLogin, news = drawNews }

--------------------------------------------------------------------------------
-- page
--------------------------------------------------------------------------------

AP.addPage({
    id = "weekly", category = "content", perm = "weekly", order = 300,
    label = function() return L("v_admin.page.weekly") end,
    onShow = load,
    draw = function(x, y, w, h)
        local data = st.data
        if not data then return AP.text(L("common.loading"), x, y, w, S(40), C.dim, 1.0) end
        if st.loadedWeek ~= st.week then fillFields() end

        -- weeks
        local lw = S(260)
        dxDrawRectangle(x, y, lw, h, C.side)
        AP.text(L("v_weekly.admin.next_change_utc", { next_change = data.nextChange }), x + S(14), y + S(8), lw - S(28), S(44),
            C.dim, 0.75, "default", "left", "center", true, true)
        local by = y + S(60)
        for i, wk in ipairs(data.weeks) do
            local sel = st.week == i
            local bh = S(62)
            dxDrawRectangle(x + S(10), by, lw - S(20), bh, sel and C.rowSel or (AP.hovered(x + S(10), by, lw - S(20), bh) and C.rowHot or C.row))
            if sel then dxDrawRectangle(x + S(10), by, S(3), bh, C.head) end
            AP.text(weekLabel(wk), x + S(24), by + S(6), lw - S(48), S(28), C.text, 1.0, "default-bold")
            AP.text(wk.from .. (wk.inherited and L("v_weekly.admin.inherited") or ""), x + S(24), by + S(32), lw - S(48), S(24),
                sel and C.text or C.dim, 0.78)
            AP.area(x + S(10), by, lw - S(20), bh, function() st.week = i end)
            by = by + bh + S(8)
        end
        AP.button(x + S(10), y + h - S(108), lw - S(20), S(44), L("v_weekly.admin.preview_panel"), function()
            AP.close()
            AP.call("weekly", "preview", {})
        end)
        AP.confirmButton("wk_reset", x + S(10), y + h - S(56), lw - S(20), S(44), L("v_weekly.admin.reset_week_inherit_previous"),
            L("v_admin.page.click_again"), function() edit("reset") end)

        -- tabs + content
        local cx, cw = x + lw + S(24), w - lw - S(24)
        local items = {
            { id = "bonuses", label = L("v_admin.weekly.bonuses") },
            { id = "trial", label = L("v_weekly.admin.time_trial") },
            { id = "login", label = L("v_weekly.admin.login_bonus") },
            { id = "news", label = L("v_weekly.admin.news") },
        }
        local th = AP.tabs(cx, y, cw, items, st.tab, function(id) st.tab = id; AP.setFocus(nil) end)
        DRAW[st.tab](cx, y + th, cw, h - th)
    end,
})
