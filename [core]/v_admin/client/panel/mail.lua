if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ============================================================
--  v_admin / client/panel/mail.lua
--  Mail page (was the /mail panel of v_mail), three tabs:
--    Compose  - recipients (account names only; the server never sends
--               addresses) + subject / text per v_locals language
--    History  - every mail the server sent (`mails` table), by group
--    Updates  - queue + weekly update mail state, and a test of the weekly
--               update mail to the admin's own e-mail address
--  Server side: server/pages/mail.lua -> v_mail mailAdmin* exports.
-- ============================================================

local S, F, C = AP.S, AP.F, AP.C

local SUBJECT_MAX, BODY_MAX = 150, 8000   -- v_mail MAILER limits (checked again there)

local st = {
    tab = "compose",
    names = nil, configured = true,
    chosen = {}, chosenCount = 0, mode = "all",
    languages = {}, lang = nil,
    filtered = {}, filterKey = nil,
    hist = { page = 0, groups = nil, more = false, group = nil, mails = nil, mailId = nil },
    status = nil, testLang = nil,
}

local function langs()
    if #st.languages == 0 then
        local ok, list = pcall(function() return exports.v_locals:getLanguages() end)
        st.languages = ok and type(list) == "table" and list or { { value = "en", label = "English" } }
        st.lang = st.lang or (st.languages[1] and st.languages[1].value) or "en"
        st.testLang = st.testLang or L.lang()
    end
    return st.languages
end

local function loadRecipients()
    st.names = nil
    AP.call("mail", "recipients", {}, function(r)
        if not r then return end
        st.names, st.configured = r.names or {}, r.configured ~= false
        -- chosen names without an email any more drop out
        local valid = {}
        for _, n in ipairs(st.names) do valid[n] = true end
        st.chosenCount = 0
        for n in pairs(st.chosen) do
            if valid[n] then st.chosenCount = st.chosenCount + 1 else st.chosen[n] = nil end
        end
    end, true)
end

local function loadHistory(page)
    local h = st.hist
    h.page, h.groups, h.more = page, nil, false
    AP.call("mail", "history", { page = page }, function(r)
        if r then h.groups, h.more = r.groups or {}, r.more end
    end, true)
end

local function openGroup(key)
    local h = st.hist
    h.group, h.mails, h.mailId = key, nil, nil
    AP.setField("ml_view", "")
    AP.call("mail", "group", { key = key }, function(r)
        if r and h.group == key then h.mails = r.mails or {} end
    end, true)
end

local function openMail(id)
    st.hist.mailId = id
    AP.call("mail", "mail", { id = id }, function(r)
        if not r or st.hist.mailId ~= id then return end
        local m = r.mail
        AP.setField("ml_view", m.subject .. "\n\n" .. (m.body or "") .. (m.error and ("\n\n[" .. m.error .. "]") or ""))
    end, true)
end

local function loadStatus()
    AP.call("mail", "status", {}, function(r) if r then st.status = r end end, true)
end

local function texts()
    local out = {}
    for _, l in ipairs(langs()) do
        out[l.value] = { subject = AP.fieldText("ml_subj_" .. l.value), body = AP.fieldText("ml_body_" .. l.value) }
    end
    return out
end

local function send(mode)
    local list
    if mode == "selected" then
        list = {}
        for n in pairs(st.chosen) do list[#list + 1] = n end
    end
    AP.call("mail", "send", { mode = mode, names = list, texts = texts() })
end

local function langState(code)
    local subject, body = AP.trim(AP.fieldText("ml_subj_" .. code)), AP.trim(AP.fieldText("ml_body_" .. code))
    if subject ~= "" and body ~= "" then return "done" end
    if subject ~= "" or body ~= "" then return "partial" end
    return "empty"
end

local function visibleNames()
    local needle = AP.trim(AP.fieldText("ml_search")):lower()
    local key = needle .. "|" .. tostring(st.names and #st.names)
    if key ~= st.filterKey then
        st.filterKey, st.filtered = key, {}
        for _, n in ipairs(st.names or {}) do
            if needle == "" or n:lower():find(needle, 1, true) then st.filtered[#st.filtered + 1] = { name = n } end
        end
    end
    return st.filtered
end

--------------------------------------------------------------------------------
-- compose
--------------------------------------------------------------------------------

local function drawCompose(x, y, w, h)
    -- recipients
    local lw = math.min(S(440), w * 0.34)
    dxDrawRectangle(x, y, lw, h, C.side)
    local pad = S(14)
    local ix, iw = x + pad, lw - pad * 2
    local half = (iw - S(8)) / 2
    AP.text(L("v_mail.panel.recipients"):upper(), ix, y + S(8), iw, S(26), C.head, 0.8, "default-bold")
    AP.button(ix, y + S(38), half, S(40), L("v_mail.panel.mode_all", { count = st.names and #st.names or 0 }),
        function() st.mode = "all" end, st.mode == "all" and "active" or nil)
    AP.button(ix + half + S(8), y + S(38), half, S(40), L("v_mail.panel.mode_selected", { count = st.chosenCount }),
        function() st.mode = "selected" end, st.mode == "selected" and "active" or nil)
    AP.field("ml_search", ix, y + S(88), iw, S(40), { placeholder = L("v_mail.panel.search"), max = 40 })
    local shown = visibleNames()
    local footH = S(56)
    AP.table("ml_names", ix, y + S(136), iw, h - S(136) - footH, {
        { key = "name", label = L("v_admin.mail.account"),
          text = function(r) return ((st.mode == "all" or st.chosen[r.name]) and "[x]  " or "[  ]  ") .. r.name end,
          color = function(r) return (st.mode == "all" or st.chosen[r.name]) and C.text or C.dim end },
    }, shown, { rowH = S(34), empty = st.names and L("v_mail.panel.no_accounts") or L("v_mail.panel.loading"),
        onClick = function(r)
            if st.chosen[r.name] then
                st.chosen[r.name], st.chosenCount = nil, st.chosenCount - 1
            else
                st.chosen[r.name], st.chosenCount = true, st.chosenCount + 1
            end
            st.mode = "selected"
        end })
    local fy = y + h - footH + S(8)
    AP.button(ix, fy, half, S(40), L("v_mail.panel.select_shown"), function()
        for _, r in ipairs(shown) do
            if not st.chosen[r.name] then st.chosen[r.name], st.chosenCount = true, st.chosenCount + 1 end
        end
        st.mode = "selected"
    end)
    AP.button(ix + half + S(8), fy, half, S(40), L("v_mail.panel.clear"), function() st.chosen, st.chosenCount = {}, 0 end)

    -- texts
    local ex, ew = x + lw + S(24), w - lw - S(24)
    local tx = ex
    for _, l in ipairs(langs()) do
        local label = l.label .. " (" .. l.value:upper() .. ")"
        local tw = L.width(label, F(0.95), "default-bold") + S(30)
        AP.button(tx, y, tw, S(40), label, function() st.lang = l.value end, st.lang == l.value and "active" or nil)
        local state = langState(l.value)
        if state ~= "empty" then dxDrawRectangle(tx, y + S(37), tw, S(3), state == "done" and C.good or C.warn) end
        tx = tx + tw + S(8)
    end
    local lang = st.lang
    local sy = y + S(54)
    AP.text(L("v_mail.panel.subject", { lang = lang:upper() }), ex, sy, ew, S(26), C.dim, 0.85)
    AP.field("ml_subj_" .. lang, ex, sy + S(28), ew, S(44), { max = SUBJECT_MAX })
    local by = sy + S(84)
    AP.text(L("v_mail.panel.text", { lang = lang:upper() }), ex, by, ew, S(26), C.dim, 0.85)
    local footY = y + h - S(100)
    AP.field("ml_body_" .. lang, ex, by + S(28), ew, footY - by - S(36), { max = BODY_MAX, multiline = true })
    AP.text(L("v_mail.panel.hint", { tag = "{name}", count = utf8.len(AP.fieldText("ml_body_" .. lang)) or 0, max = BODY_MAX }),
        ex, footY, ew, S(30), C.dim, 0.8, "default", "left", "center", true)
    local fy2 = y + h - S(52)
    AP.text(st.configured and L("v_mail.panel.fallback_hint") or L("v_mail.panel.not_configured"), ex, fy2, ew - S(470), S(48),
        st.configured and C.dim or C.warn, 0.8, "default", "left", "center", true, true)
    local count = st.mode == "all" and (st.names and #st.names or 0) or st.chosenCount
    AP.button(ex + ew - S(460), fy2, S(220), S(48), L("v_mail.panel.send_test"), function() send("test") end)
    AP.confirmButton("ml_send", ex + ew - S(230), fy2, S(230), S(48), L("v_mail.panel.send", { count = count }),
        L("v_mail.panel.confirm_send", { count = count }), function() send(st.mode) end, "active")
end

--------------------------------------------------------------------------------
-- history
--------------------------------------------------------------------------------

local function drawHistory(x, y, w, h)
    local hs = st.hist
    local gw = w * 0.42
    local pagerH = S(48)
    AP.table("ml_groups", x, y, gw, h - pagerH, {
        { key = "date", label = L("v_admin.mail.date"), w = S(150) },
        { key = "kind", label = L("v_admin.mail.kind"), w = S(110) },
        { key = "subject", label = L("v_admin.mail.subject") },
        { key = "total", label = L("v_admin.mail.sent"), w = S(110), align = "right",
          text = function(g) return g.sent .. " / " .. g.total end,
          color = function(g) return g.failed > 0 and C.bad or (g.waiting > 0 and C.warn or C.good) end },
    }, hs.groups or {}, { rowH = S(38), selected = function(g) return hs.group == g.key end,
        onClick = function(g) openGroup(g.key) end, empty = hs.groups and L("v_admin.page.no_rows") or L("common.loading") })
    local py = y + h - pagerH + S(8)
    AP.button(x, py, S(44), S(36), "<", function() loadHistory(hs.page - 1) end, hs.page > 0 and nil or "off")
    AP.text(L("v_admin.accounts.page", { page = hs.page + 1, pages = hs.more and "..." or hs.page + 1 }), x + S(50), py, S(160), S(36), C.dim, 0.9, "default", "center")
    AP.button(x + S(216), py, S(44), S(36), ">", function() loadHistory(hs.page + 1) end, hs.more and nil or "off")
    AP.button(x + gw - S(120), py, S(120), S(36), L("v_admin.accounts.reload"), function() loadHistory(hs.page) end)

    local mx, mw = x + gw + S(20), w - gw - S(20)
    if not hs.group then return AP.text(L("v_admin.mail.pick_group"), mx, y, mw, S(40), C.dim, 1.0) end
    local listH = h * 0.42
    AP.table("ml_mails", mx, y, mw, listH, {
        { key = "account", label = L("v_admin.mail.account"), bold = true },
        { key = "language", label = L("v_admin.mail.lang"), w = S(70) },
        { key = "date", label = L("v_admin.mail.date"), w = S(150) },
        { key = "status", label = L("v_admin.mail.status"), w = S(100),
          color = function(m) return m.status == "sent" and C.good or (m.status == "failed" and C.bad or C.warn) end },
    }, hs.mails or {}, { rowH = S(34), selected = function(m) return hs.mailId == m.id end,
        onClick = function(m) openMail(m.id) end, empty = hs.mails and L("v_admin.page.no_rows") or L("common.loading") })
    AP.field("ml_view", mx, y + listH + S(12), mw, h - listH - S(12), { multiline = true, readonly = true, max = 100000,
        placeholder = L("v_admin.mail.pick_mail") })
end

--------------------------------------------------------------------------------
-- updates
--------------------------------------------------------------------------------

local function drawUpdates(x, y, w, h)
    local s = st.status
    if not s then return AP.text(L("common.loading"), x, y, w, S(40), C.dim, 1.0) end
    local cw = math.min(w, S(1100))
    local tw, th, gap = (cw - S(20)) / 3, S(64), S(10)
    local last = s.lastRun
    local tiles = {
        { L("v_admin.mail.brevo"), s.configured and L("v_admin.mail.configured") or L("v_admin.mail.not_configured"), s.configured and C.good or C.bad },
        { L("v_admin.mail.queue"), AP.fmtInt(s.queued) },
        { L("v_admin.mail.instance"), L("v_admin.mail.instance_text", { id = s.instance, sender = s.sendingInstance }),
          s.isSender and C.good or C.warn },
        { L("v_admin.mail.next_run"), AP.fmtDate(s.nextRun) },
        { L("v_admin.mail.pending"), AP.fmtInt(s.pending), s.pending > 0 and C.warn or nil },
        { L("v_admin.mail.sent_24h"), L("v_admin.mail.of_limit", { n = s.sent24h, limit = s.dailyLimit }), nil },
        { L("v_admin.mail.failed_24h"), AP.fmtInt(s.failed24h), s.failed24h > 0 and C.bad or nil },
        { L("v_admin.mail.last_run"), last and L("v_admin.mail.last_run_text", { sent = last.sent, total = last.total, failed = last.failed,
          waiting = last.waiting, skipped = last.skipped }) or "-" },
    }
    for i, t in ipairs(tiles) do
        AP.kv(x + ((i - 1) % 3) * (tw + gap), y + math.floor((i - 1) / 3) * (th + gap), tw, th, t[1], t[2], t[3])
    end
    local cy = y + math.ceil(#tiles / 3) * (th + gap) + S(20)

    local ix, iy, iw = AP.card(x, cy, cw, S(250), L("v_admin.mail.test_update"), "mail")
    for _, line in ipairs(AP.wrap(L("v_admin.mail.test_update_desc"), iw, 0.9)) do
        AP.text(line, ix, iy, iw, S(26), C.dim, 0.9)
        iy = iy + S(26)
    end
    iy = iy + S(12)
    local bx = ix
    for _, l in ipairs(langs()) do
        local label = l.label .. " (" .. l.value:upper() .. ")"
        local bw = L.width(label, F(0.95), "default-bold") + S(30)
        AP.button(bx, iy, bw, S(40), label, function() st.testLang = l.value end, st.testLang == l.value and "active" or nil)
        bx = bx + bw + S(8)
    end
    AP.button(ix + iw - S(320), iy, S(320), S(40), L("v_admin.mail.send_test_update"), function()
        AP.call("mail", "updatetest", { lang = st.testLang }, function() loadStatus() end)
    end, "active")
    AP.button(x + cw - S(130), cy + S(250) + S(14), S(130), S(36), L("v_admin.accounts.reload"), loadStatus)
end

--------------------------------------------------------------------------------
-- page
--------------------------------------------------------------------------------

local function setTab(id)
    st.tab = id
    AP.setFocus(nil)
    if id == "history" then loadHistory(0) elseif id == "updates" then loadStatus() end
end

AP.addPage({
    id = "mail", category = "content", perm = "mail", order = 320,
    label = function() return L("v_admin.page.mail") end,
    onShow = function(arg)
        langs()
        loadRecipients()
        if type(arg) == "table" and type(arg.recipients) == "table" then
            st.chosen, st.chosenCount = {}, 0
            for _, n in ipairs(arg.recipients) do
                st.chosen[n], st.chosenCount = true, st.chosenCount + 1
            end
            st.mode = "selected"
            st.tab = "compose"
        end
        if st.tab ~= "compose" then setTab(st.tab) end
    end,
    onRefresh = function() if st.tab == "updates" then loadStatus() end end,
    draw = function(x, y, w, h)
        local th = AP.tabs(x, y, w, {
            { id = "compose", label = L("v_admin.mail.compose") },
            { id = "history", label = L("v_admin.mail.history") },
            { id = "updates", label = L("v_admin.mail.updates") },
        }, st.tab, setTab)
        y, h = y + th, h - th
        if st.tab == "compose" then drawCompose(x, y, w, h)
        elseif st.tab == "history" then drawHistory(x, y, w, h)
        else drawUpdates(x, y, w, h) end
    end,
})
