-- police_system / modules/mdc/client/pages/warrants.lua
-- Warrants: the list (active / all), issue (citizen, reasons with checkboxes, short description, its language - any
-- v_locals language, the officer's by default), edit, revoke. Editing / revoking someone else's warrant: Hadnagy+.

local MDC = POL.mdc
local C = POL.colors
local S = { status = "active", page = 1, form = nil }   -- form = { id (edit), citizenId, citizenName, reasons = {}, lang }

local function reasonText(id)
    return id:find("%.") and L(btkKey(id)) or L(wantedReasonKey(id))
end

local function loadMeta(cb)
    if MDC.data.warrantMeta then return cb and cb() end
    MDC.call("warrantReasons", {}, function(d) if d then MDC.data.warrantMeta = d end; if cb then cb() end end)
end

-- open the form (from the list, or "Issue warrant" on a citizen profile)
function MDC.warrantForm(citizenId, citizenName, existing)
    loadMeta()
    S.form = { citizenId = citizenId, citizenName = citizenName, reasons = {}, lang = (MDC.data.warrantMeta or {}).lang or L.lang() }
    W.fieldOf("wf:desc", { max = 400, multiline = true }):setText("")
    W.fieldOf("wf:search", { max = 40 }):setText("")
    if existing then
        S.form.id = existing.id
        for _, r in ipairs(existing.reasons or {}) do S.form.reasons[r] = true end
        S.form.lang = existing.lang or S.form.lang
        W.fields["wf:desc"]:setText(existing.description or "")
    end
    MDC.go("warrants")
end

MDC.pages.warrants = {
    load = function()
        loadMeta()
        MDC.call("warrants", { status = S.status, page = S.page }, function(d) MDC.data.warrants = d end)
    end,
    draw = function(x, y, w, h)
        if S.form then return MDC.pages.warrants.drawForm(x, y, w, h) end
        W.text(L("police_system.mdc.menu_warrants"), x, y, w, POL.px(30), C.white, 15, true)
        W.button("wa:active", x, y + POL.px(36), POL.px(110), POL.px(28), L("police_system.mdc.active"),
            function() S.status = "active"; S.page = 1; MDC.load() end, S.status == "active" and "active" or nil)
        W.button("wa:all", x + POL.px(114), y + POL.px(36), POL.px(110), POL.px(28), L("police_system.mdc.all"),
            function() S.status = "all"; S.page = 1; MDC.load() end, S.status == "all" and "active" or nil)
        W.button("wa:new", x + w - POL.px(170), y + POL.px(36), POL.px(170), POL.px(28), L("police_system.mdc.new_warrant"),
            function() MDC.warrantForm(nil, nil) end, "primary")
        local d = MDC.data.warrants or { rows = {} }
        local canAll = (MDC.data.warrantMeta or {}).canEditAll
        local me = POL.nameOfLocal()
        local rows = {}
        for _, wr in ipairs(d.rows or {}) do
            local reasons = {}
            for _, r in ipairs(wr.reasons or {}) do reasons[#reasons + 1] = reasonText(r) end
            local editable = wr.status == "active" and (canAll or wr.issuer == me)
            rows[#rows + 1] = { cells = { "#" .. wr.id, wr.name .. (wr.kind == "npc" and "  (NPC)" or ""), table.concat(reasons, ", "),
                wr.description ~= "" and ('"' .. wr.description .. '"') or "", L.upper(wr.lang or ""), wr.issuer or "", POL.date(wr.at),
                function(bx, by, bw, bh)
                    if editable then
                        W.button("we" .. wr.id, bx, by + POL.px(3), bw * 0.48, bh - POL.px(6), L("police_system.mdc.edit"),
                            function() MDC.warrantForm(wr.citizenId, wr.name, wr) end)
                        W.button("wr" .. wr.id, bx + bw * 0.52, by + POL.px(3), bw * 0.48, bh - POL.px(6), L("police_system.mdc.revoke"),
                            function() MDC.call("warrantRevoke", { id = wr.id }, function() MDC.load() end) end, "danger")
                    else
                        W.text(L("police_system.mdc.status_" .. tostring(wr.status)), bx, by, bw, bh, C.dim, 9)
                    end
                end }, colors = { C.dim, nil, C.red } }
        end
        local ty = y + POL.px(76)
        W.table("warrants", x, ty, w, y + h - ty - POL.px(40), { { "#", 0.6 }, { L("police_system.mdc.col_name"), 2 },
            { L("police_system.mdc.col_reasons"), 3 }, { L("police_system.mdc.col_description"), 3 }, { L("police_system.mdc.col_lang"), 0.6 },
            { L("police_system.mdc.col_issuer"), 1.4 }, { L("police_system.mdc.col_date"), 1.6 }, { "", 1.8 } }, rows, nil, POL.px(34))
        local by = y + h - POL.px(32)
        if S.page > 1 then W.button("wa:prev", x, by, POL.px(100), POL.px(28), "‹ " .. L("police_system.mdc.prev"), function() S.page = S.page - 1; MDC.load() end) end
        if d.more then W.button("wa:next", x + w - POL.px(100), by, POL.px(100), POL.px(28), L("police_system.mdc.next") .. " ›", function() S.page = S.page + 1; MDC.load() end) end
    end,
    drawForm = function(x, y, w, h)
        local f = S.form
        local meta = MDC.data.warrantMeta or { reasons = {}, languages = {} }
        W.text(f.id and L("police_system.mdc.edit_warrant", { id = f.id }) or L("police_system.mdc.new_warrant"), x, y, w, POL.px(30), C.white, 15, true)
        local cy = y + POL.px(42)
        -- citizen
        W.text(L("police_system.mdc.citizen"), x, cy, POL.px(160), POL.px(30), C.dim, 10, true)
        if f.citizenId then
            W.text((f.citizenName or "?") .. "  #" .. f.citizenId, x + POL.px(160), cy, w * 0.5, POL.px(30), C.white, 11, true)
            if not f.id then W.button("wf:change", x + POL.px(160) + w * 0.5, cy, POL.px(120), POL.px(28), L("police_system.mdc.change"), function() f.citizenId = nil end) end
            cy = cy + POL.px(40)
        else
            W.field("wf:search", x + POL.px(160), cy, POL.px(300), POL.px(30), L("police_system.mdc.search_citizen"), { max = 40 })
            W.button("wf:find", x + POL.px(470), cy, POL.px(110), POL.px(30), L("police_system.mdc.search"), function()
                MDC.call("citizens", { filter = "all", q = W.fields["wf:search"]:getText(), page = 1 }, function(d) f.results = d and d.rows or {} end)
            end, "primary")
            cy = cy + POL.px(38)
            for i, r in ipairs(f.results or {}) do
                if i > 5 then break end
                W.button("wf:pick" .. i, x + POL.px(160), cy, POL.px(420), POL.px(26), r.name .. "  #" .. r.id .. (r.kind == "npc" and "  (NPC)" or ""),
                    function() f.citizenId, f.citizenName, f.results = r.id, r.name, nil end, "ghost")
                cy = cy + POL.px(28)
            end
            cy = cy + POL.px(8)
        end
        -- reasons
        W.text(L("police_system.mdc.col_reasons"), x, cy, POL.px(160), POL.px(24), C.dim, 10, true)
        local colW = (w - POL.px(160)) / 3
        local i = 0
        for _, r in ipairs(meta.reasons or {}) do
            local cx = x + POL.px(160) + (i % 3) * colW
            local ry = cy + math.floor(i / 3) * POL.px(24)
            W.check("wf:r:" .. r.id, cx, ry, f.reasons[r.id], reasonText(r.id) .. " (" .. r.minutes .. "')", function()
                f.reasons[r.id] = not f.reasons[r.id] or nil
            end)
            i = i + 1
        end
        cy = cy + math.ceil(i / 3) * POL.px(24) + POL.px(12)
        -- description + language
        W.text(L("police_system.mdc.col_description"), x, cy, POL.px(160), POL.px(24), C.dim, 10, true)
        local opts = {}
        for _, l in ipairs(meta.languages or {}) do opts[#opts + 1] = { l.value, l.label } end
        if #opts == 0 then opts = { { "en", "English" } } end
        W.select("wf:lang", x + w - POL.px(200), cy, POL.px(200), POL.px(28), opts, f.lang, function(v) f.lang = v end)
        W.field("wf:desc", x + POL.px(160), cy, w - POL.px(380), POL.px(110), L("police_system.mdc.description_hint"), { max = 400, multiline = true })
        cy = cy + POL.px(124)
        W.button("wf:cancel", x + POL.px(160), cy, POL.px(140), POL.px(32), L("police_system.mdc.cancel"), function() S.form = nil; MDC.load() end)
        local list = {}
        for id in pairs(f.reasons) do list[#list + 1] = id end
        W.button("wf:save", x + POL.px(310), cy, POL.px(180), POL.px(32), f.id and L("police_system.mdc.save") or L("police_system.mdc.issue"), function()
            local args = { citizenId = f.citizenId, id = f.id, reasons = list, description = W.fields["wf:desc"]:getText(), lang = f.lang }
            MDC.call(f.id and "warrantUpdate" or "warrantCreate", args, function(ok) if ok then S.form = nil; MDC.load() end end)
        end, "primary", not f.citizenId or #list == 0)
    end,
}
