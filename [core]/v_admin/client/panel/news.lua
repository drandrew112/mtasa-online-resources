if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ============================================================
--  v_admin / client/panel/news.lua
--  News page (was the /news editor of v_news): every article on the
--  left (scheduled ones marked), the editor on the right. Saving and
--  deleting go through server/pages/news.lua -> v_news exports, which
--  check the texts (v_news NEWS.TITLE_MAX / BODY_MAX).
-- ============================================================

local S, F, C = AP.S, AP.F, AP.C

local TITLE_MAX, BODY_MAX = 120, 4000   -- the v_news limits (checked again there)

local st = { data = nil, selected = nil }

local function fill(a)
    st.selected = a and a.id or nil
    AP.setField("nw_date", a and a.dateText or (st.data and st.data.nowDate or ""))
    AP.setField("nw_time", a and a.timeText or (st.data and st.data.nowTime or ""))
    AP.setField("nw_title", a and a.title or "")
    AP.setField("nw_body", a and a.body or "")
end

local function article(id)
    for _, a in ipairs(st.data and st.data.list or {}) do
        if a.id == id then return a end
    end
end

local function setData(r)
    if not r then return end
    st.data = r
    if r.selected then fill(article(r.selected)) end
end

local function load()
    AP.call("news", "list", {}, function(r)
        setData(r)
        if r and not st.selected then fill(nil) end
    end)
end

local function save()
    AP.call("news", "save", {
        id = st.selected, dateText = AP.fieldText("nw_date"), timeText = AP.fieldText("nw_time"),
        title = AP.fieldText("nw_title"), body = AP.fieldText("nw_body"),
    }, function(r) setData(r) end)
end

AP.addPage({
    id = "news", category = "content", perm = "news", order = 310,
    label = function() return L("v_admin.page.news") end,
    onShow = load,
    draw = function(x, y, w, h)
        if not st.data then return AP.text(L("common.loading"), x, y, w, S(40), C.dim, 1.0) end

        -- list
        local lw = math.min(S(520), w * 0.38)
        AP.button(x, y, lw, S(44), L("v_news.panel.new_article"), function() fill(nil) end, st.selected and nil or "active")
        AP.table("nw_list", x, y + S(54), lw, h - S(54), {
            { key = "dateText", label = L("v_news.panel.date"), w = S(130),
              color = function(a) return a.scheduled and C.warn or C.dim end },
            { key = "title", label = L("v_news.panel.article_title"), bold = true,
              text = function(a) return (a.scheduled and ("[" .. L("v_news.panel.scheduled") .. "] ") or "") .. a.title end },
        }, st.data.list, { rowH = S(42), selected = function(a) return a.id == st.selected end,
            onClick = function(a) fill(a) end, empty = L("v_news.panel.no_articles") })

        -- editor
        local ex, ew = x + lw + S(24), w - lw - S(24)
        local colW = S(170)
        AP.text(L("v_news.panel.date"), ex, y, colW, S(26), C.dim, 0.85)
        AP.text(L("v_news.panel.time"), ex + colW + S(10), y, colW, S(26), C.dim, 0.85)
        AP.field("nw_date", ex, y + S(28), colW, S(44), { max = 10 })
        AP.field("nw_time", ex + colW + S(10), y + S(28), S(110), S(44), { max = 5 })
        AP.button(ex + colW + S(130), y + S(28), S(130), S(44), L("v_news.panel.now"), function()
            AP.setField("nw_date", st.data.nowDate)
            AP.setField("nw_time", st.data.nowTime)
        end)
        local a = article(st.selected)
        if a then
            AP.text(L("v_admin.news.author", { author = a.author ~= "" and a.author or "-", id = a.id }), ex + colW + S(280), y + S(28),
                ew - colW - S(280), S(44), C.dim, 0.8, "default", "right")
        end

        local ty = y + S(84)
        AP.text(L("v_news.panel.article_title"), ex, ty, ew, S(26), C.dim, 0.85)
        AP.field("nw_title", ex, ty + S(28), ew, S(44), { max = TITLE_MAX })
        local by = ty + S(84)
        AP.text(L("v_news.panel.text"), ex, by, ew, S(26), C.dim, 0.85)
        local footH = S(60)
        AP.field("nw_body", ex, by + S(28), ew, y + h - by - S(28) - footH, { max = BODY_MAX, multiline = true })

        local fy = y + h - footH + S(12)
        AP.text(L("v_news.panel.hint", { count = utf8.len(AP.fieldText("nw_body")) or 0, max = BODY_MAX }), ex, fy, ew - S(440), S(44),
            C.dim, 0.8, "default", "left", "center", true, true)
        AP.button(ex + ew - S(200), fy, S(200), S(44), L("v_news.panel.save"), save, "active")
        if st.selected then
            AP.confirmButton("nw_delete", ex + ew - S(420), fy, S(210), S(44), L("v_news.panel.delete"), L("v_news.panel.confirm_delete"),
                function()
                    local id = st.selected
                    AP.call("news", "delete", { id = id }, function(r)
                        setData(r)
                        fill(nil)
                    end)
                end)
        end
    end,
})
