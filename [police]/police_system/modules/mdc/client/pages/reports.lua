-- police_system / modules/mdc/client/pages/reports.lua
-- Reports: own (drafts first: they block the sign-off), the unit's; the editor (title, language, text) with Save and
-- Submit; a manual report (Other, no pay). One language per report, always shown.

local MDC = POL.mdc
local C = POL.colors
local S = { scope = "mine", edit = nil }   -- edit = { id | "new", lang, readonly, status }

function MDC.openReport(id, readonly)
    S.edit = { id = id, readonly = readonly }
    MDC.data.report = nil
    MDC.go("reports", { report = id })
end

local function loadLangs()
    if MDC.data.warrantMeta then return end
    MDC.call("warrantReasons", {}, function(d) if d then MDC.data.warrantMeta = d end end)
end

MDC.pages.reports = {
    load = function()
        loadLangs()
        if S.edit and S.edit.id ~= "new" then
            MDC.call("report", { id = S.edit.id }, function(r)
                if not r then S.edit = nil return end
                MDC.data.report = r
                S.edit.lang = r.lang
                S.edit.readonly = S.edit.readonly or r.status ~= "draft"
                W.fieldOf("rp:title", { max = 160 }):setText(r.title or "")
                W.fieldOf("rp:body", { max = 8000, multiline = true }):setText(r.body or "")
            end)
            return
        end
        MDC.call("reports", { scope = S.scope }, function(d) MDC.data.reports = d or {} end)
    end,
    draw = function(x, y, w, h)
        if S.edit then return MDC.pages.reports.drawEditor(x, y, w, h) end
        W.text(L("police_system.mdc.menu_reports"), x, y, w, POL.px(30), C.white, 15, true)
        -- without a unit only the own reports; the sign-in window (no MDC computer) only submits drafts
        if not POL.onDuty() then S.scope = "mine" end
        W.button("rp:mine", x, y + POL.px(36), POL.px(130), POL.px(28), L("police_system.mdc.reports_mine"),
            function() S.scope = "mine"; MDC.load() end, S.scope == "mine" and "active" or nil)
        if POL.onDuty() then
            W.button("rp:unit", x + POL.px(134), y + POL.px(36), POL.px(130), POL.px(28), L("police_system.mdc.reports_unit"),
                function() S.scope = "unit"; MDC.load() end, S.scope == "unit" and "active" or nil)
        end
        if MDC.full() then
            W.button("rp:new", x + w - POL.px(170), y + POL.px(36), POL.px(170), POL.px(28), L("police_system.mdc.new_report"), function()
                S.edit = { id = "new", lang = (MDC.data.warrantMeta or {}).lang or L.lang() }
                W.fieldOf("rp:title", { max = 160 }):setText("")
                W.fieldOf("rp:body", { max = 8000, multiline = true }):setText("")
            end, "primary")
        end
        local rows = {}
        for _, r in ipairs(MDC.data.reports or {}) do
            rows[#rows + 1] = { cells = { r.status == "draft" and "DRAFT" or "", r.title, (r.unit or "") .. " " .. tostring(r.author or ""),
                L.upper(r.lang or ""), POL.date(r.at) }, colors = { C.orange, r.status == "draft" and C.white or C.text, C.dim, C.dim, C.dim }, id = r.id }
        end
        local ty = y + POL.px(76)
        W.table("reports", x, ty, w, y + h - ty, { { "", 0.8 }, { L("police_system.mdc.col_title"), 5 }, { L("police_system.mdc.col_author"), 1.6 },
            { L("police_system.mdc.col_lang"), 0.6 }, { L("police_system.mdc.col_date"), 1.4 } }, rows, function(r) MDC.openReport(r.id) end, POL.px(30))
    end,
    drawEditor = function(x, y, w, h)
        local e = S.edit
        local r = MDC.data.report
        W.button("rp:back", x, y, POL.px(100), POL.px(28), "‹ " .. L("police_system.mdc.back"), function()
            S.edit = nil
            MDC.go("reports")
        end)
        if e.id ~= "new" and not r then W.text(L("police_system.mdc.loading"), x, y + POL.px(40), w, POL.px(30), C.dim, 11) return end
        local cy = y + POL.px(40)
        local opts = {}
        for _, l in ipairs((MDC.data.warrantMeta or {}).languages or {}) do opts[#opts + 1] = { l.value, l.label } end
        if #opts == 0 then opts = { { "en", "English" } } end
        if e.readonly then
            W.text(r and r.title or "", x, cy, w - POL.px(120), POL.px(30), C.white, 13, true)
            W.badge(L.upper(r and r.lang or ""), x + w - POL.px(60), cy + POL.px(6), C.accentDim)
            dxDrawRectangle(x, cy + POL.px(40), w, h - POL.px(80), C.panel)
            W.text(r and r.body or "", x + POL.px(14), cy + POL.px(52), w - POL.px(28), h - POL.px(104), C.text, 10, false, "left", "top", true, true)
            return
        end
        W.field("rp:title", x, cy, w - POL.px(220), POL.px(32), L("police_system.mdc.report_title"), { max = 160 })
        W.select("rp:lang", x + w - POL.px(200), cy, POL.px(200), POL.px(32), opts, e.lang, function(v) e.lang = v end)
        W.field("rp:body", x, cy + POL.px(42), w, h - POL.px(130), L("police_system.mdc.report_body"), { max = 8000, multiline = true })
        local by = y + h - POL.px(36)
        local function save(submit)
            local title, body = W.fields["rp:title"]:getText(), W.fields["rp:body"]:getText()
            if e.id == "new" then
                MDC.call("reportManual", { title = title, body = body, lang = e.lang }, function(ok) if ok then S.edit = nil; MDC.go("reports") end end)
            else
                MDC.call("reportSave", { id = e.id, title = title, body = body, lang = e.lang, submit = submit }, function(ok)
                    if ok and submit then S.edit = nil; MDC.go("reports") end
                end)
            end
        end
        if e.id ~= "new" then W.button("rp:save", x, by, POL.px(160), POL.px(32), L("police_system.mdc.save"), function() save(false) end) end
        W.button("rp:submit", x + w - POL.px(180), by, POL.px(180), POL.px(32), L("police_system.mdc.submit"), function() save(true) end, "primary")
    end,
}
