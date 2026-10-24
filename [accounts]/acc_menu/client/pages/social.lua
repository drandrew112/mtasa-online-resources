if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- SOCIAL: friends, requests, crew, messages, player search - through the
-- v_socialpanel Social API (c_api.lua there), nothing of the panel itself.

Social = { snapshot = nil, profile = nil, search = {}, searchNote = nil, thread = {}, conv = nil }

function isSocialRunning()
    local res = getResourceFromName("v_socialpanel")
    return res and getResourceState(res) == "running"
end

local function sp(fn, ...)
    if not isSocialRunning() then return notify(L("acc_menu.social.unavailable")) end
    return exports.v_socialpanel[fn](exports.v_socialpanel, ...)
end

local searchField = TextField.new{ max = 30 }
local msgField = TextField.new{ max = 200 }
local crewName = TextField.new{ max = 24 }
local crewTag = TextField.new{ max = 5 }

for ev, fn in pairs({
    ["v_socialpanel:onClientSnapshot"] = function(snap) if type(snap) == "table" then Social.snapshot = snap end end,
    ["v_socialpanel:onClientProfile"] = function(profile, name)
        if profile then
            Social.profile = profile
            if Menu.open then Menu.openView("player", { name = profile.display or profile.name }) end
        elseif Menu.open then
            notify(L("acc_menu.social.no_such_player", { name = tostring(name) }))
        end
    end,
    ["v_socialpanel:onClientSearchResults"] = function(list, note)
        Social.search = type(list) == "table" and list or {}
        Social.searchNote = note
    end,
    ["v_socialpanel:onClientThread"] = function(kind, with, msgs)
        local c = Social.conv
        if c and c.kind == kind and c.with:lower() == tostring(with):lower() then
            Social.thread = type(msgs) == "table" and msgs or {}
            Social.threadScroll = 1e9
        end
    end,
    ["v_socialpanel:onClientInfo"] = function(msg) if Menu.open then notify(msg) end end,
}) do
    addEvent(ev)
    addEventHandler(ev, localPlayer, fn)
end

local function snap() return Social.snapshot or {} end

-- shown name of an account: its display name (snapshot.names), else the account
-- name; the account name stays the key in every call
local function dn(account)
    local names = snap().names
    return (names and names[tostring(account):lower()]) or account
end

local function openThread(kind, with)
    Social.conv = { kind = kind, with = with }
    Social.thread = {}
    sp("spOpenThread", kind, with)
end

PAGES.defs.social = {
    label = "acc_menu.page.social",
    onMenuOpen = function()
        Social.snapshot, Social.conv, Social.thread = nil, nil, {}
        if isSocialRunning() then exports.v_socialpanel:spRequestSnapshot() end
    end,
    draw = function(x, y, w, h)
        local at = Grid(x, y, w, h, 5, 1)
        local s = snap()
        local big = function(str, cx, cy, cw, ch, color) text(str, cx, cy + ch - S(96), cw, S(48), color or C.white, 1, FONT.big) end

        local online = 0
        for _, f in ipairs(s.friends or {}) do if f.online then online = online + 1 end end
        local tx, ty, tw, th = at(1, 1)
        tile("page", "soc_friends", tx, ty, tw, th, L("acc_menu.social.friends"), L("acc_menu.social.friends_sub"), function(cx, cy, cw, ch)
            big(tostring(#(s.friends or {})), cx, cy, cw, ch)
            text(L("acc_menu.social.online", { count = online }), cx, cy + ch - S(36), cw, S(26), C.dim, 0.9)
        end, function() Menu.openView("friends") end)

        tx, ty, tw, th = at(2, 1)
        local req = #(s.requests or {})
        tile("page", "soc_requests", tx, ty, tw, th, L("acc_menu.social.requests"), L("acc_menu.social.requests_sub"), function(cx, cy, cw, ch)
            big(tostring(req), cx, cy, cw, ch, req > 0 and C.xp or C.white)
            text(req > 0 and L("acc_menu.social.waiting") or L("acc_menu.social.no_requests"), cx, cy + ch - S(36), cw, S(26), C.dim, 0.9)
        end, function() Menu.openView("requests") end)

        tx, ty, tw, th = at(3, 1)
        local crew = s.crew
        tile("page", "soc_crew", tx, ty, tw, th, L("acc_menu.social.crew"), L("acc_menu.social.crew_sub"), function(cx, cy, cw, ch)
            if crew then
                local col = crew.color or { 255, 255, 255 }
                big("[" .. tostring(crew.tag) .. "]", cx, cy, cw, ch, tocolor(col[1] or 255, col[2] or 255, col[3] or 255, 255))
                text(L("acc_menu.social.crew_members", { name = crew.name, count = #(crew.members or {}) }), cx, cy + ch - S(36), cw, S(26), C.dim, 0.9)
            else
                text(L("acc_menu.social.no_crew"), cx, cy + ch - S(36), cw, S(26), C.dim, 0.9)
            end
        end, function() Menu.openView("crew") end)

        tx, ty, tw, th = at(4, 1)
        local unread = 0
        for _, c in ipairs(s.conversations or {}) do unread = unread + (c.unread or 0) end
        tile("page", "soc_messages", tx, ty, tw, th, L("acc_menu.social.messages"), L("acc_menu.social.messages_sub"), function(cx, cy, cw, ch)
            big(tostring(unread), cx, cy, cw, ch)
            text(L("acc_menu.home.unread"), cx, cy + ch - S(36), cw, S(26), C.dim, 0.9)
        end, function() Menu.openView("messages") end)

        tx, ty, tw, th = at(5, 1)
        tile("page", "soc_find", tx, ty, tw, th, L("acc_menu.social.find"), L("acc_menu.social.find_sub"), nil, function() Menu.openView("find") end)
    end,
}

--------------------------------------------------------------------------------
-- shared: a person row with buttons on the right
--------------------------------------------------------------------------------

local function personRow(prefix, i, x, y, w, h, p, buttons)
    row("view", prefix .. i, x, y, w, h, { activate = buttons[1] and buttons[1].fn })
    dxDrawRectangle(x + S(16), y + h / 2 - S(5), S(10), S(10), p.online and C.money or tocolor(90, 90, 90, 255))
    text(p.display or dn(p.name), x + S(38), y, w * 0.3, h, C.white, 1.0, FONT.rowB)
    if p.level or p.playtime then
        text(L("acc_menu.social.level_played", { level = tostring(p.level or "-"), played = tostring(p.playtime or "-") }),
            x + w * 0.3, y, w * 0.3, h, C.dim, 0.9)
    end
    local bw, bx = S(130), x + w - S(10)
    for b = #buttons, 1, -1 do
        bx = bx - bw
        button("view", prefix .. i .. "_" .. b, bx, y + S(6), bw - S(8), h - S(12), buttons[b].label, buttons[b].fn, buttons[b].style or "ghost")
    end
end

local function listArea(viewId, x, y, w, h, count, rowH)
    local visible = math.max(1, math.floor(h / rowH))
    local v = VIEWS[viewId]
    v.scroll = math.max(0, math.min(v.scroll or 0, count - visible))
    Menu.wheel(x, y, w, h, function(d) v.scroll = (v.scroll or 0) + d end)
    return v.scroll, visible
end

--------------------------------------------------------------------------------
-- views
--------------------------------------------------------------------------------

VIEWS.friends = {
    title = function() return L("acc_menu.social.friends") end,
    draw = function(x, y, w, h)
        local list = snap().friends or {}
        if #list == 0 then
            panelBox(x, y, w, S(80))
            return text(L("acc_menu.social.no_friends"), x + S(24), y, w, S(80), C.dim, 1.05)
        end
        local rh = S(52)
        local scroll, visible = listArea("friends", x, y, w, h, #list, rh)
        for i = scroll + 1, math.min(#list, scroll + visible) do
            local f = list[i]
            personRow("fr_", i, x, y + (i - scroll - 1) * rh, w, rh - S(4), f, {
                { label = L("acc_menu.social.profile"), fn = function() sp("spViewProfile", f.name) end },
                { label = L("acc_menu.social.message"), fn = function() openThread("dm", f.name) Menu.goto("social", "messages") end },
                { label = L("acc_menu.social.remove"), fn = function() sp("spFriendRemove", f.name) end, style = "danger" },
            })
        end
    end,
}

VIEWS.requests = {
    title = function() return L("acc_menu.social.requests") end,
    draw = function(x, y, w, h)
        local list = snap().requests or {}
        if #list == 0 then
            panelBox(x, y, w, S(80))
            return text(L("acc_menu.social.no_requests"), x + S(24), y, w, S(80), C.dim, 1.05)
        end
        local rh = S(52)
        local scroll, visible = listArea("requests", x, y, w, h, #list, rh)
        for i = scroll + 1, math.min(#list, scroll + visible) do
            local name = type(list[i]) == "table" and list[i].name or tostring(list[i])
            personRow("rq_", i, x, y + (i - scroll - 1) * rh, w, rh - S(4), { name = name }, {
                { label = L("acc_menu.social.accept"), fn = function() sp("spFriendAccept", name) end, style = "primary" },
                { label = L("acc_menu.social.decline"), fn = function() sp("spFriendDecline", name) end },
            })
        end
    end,
}

VIEWS.crew = {
    title = function() return L("acc_menu.social.crew") end,
    onOpen = function() crewName:setText("") crewTag:setText("") end,
    draw = function(x, y, w, h)
        local s = snap()
        local crew = s.crew
        if crew then
            local lw = math.floor(w * 0.34)
            panelBox(x, y, lw, S(240))
            local cx, cw = x + S(24), lw - S(48)
            local col = crew.color or { 255, 255, 255 }
            text("[" .. tostring(crew.tag) .. "]", cx, y + S(18), cw, S(48), tocolor(col[1] or 255, col[2] or 255, col[3] or 255, 255), 1, FONT.big)
            text(crew.name, cx, y + S(72), cw, S(30), C.white, 1.2, FONT.head)
            text(L("acc_menu.social.founder", { name = dn(crew.founder) }), cx, y + S(106), cw, S(24), C.dim, 0.95)
            if crew.desc and crew.desc ~= "" then
                text(crew.desc, cx, y + S(134), cw, S(50), C.text, 0.92, FONT.row, "left", "top", true, true)
            end
            button("view", "crew_leave", cx, y + S(186), S(200), S(40), L("acc_menu.social.leave_crew"), function() sp("spCrewLeave") end, "danger")
            local rx, rw = x + lw + S(14), w - lw - S(14)
            local members = crew.members or {}
            local rh = S(52)
            local scroll, visible = listArea("crew", rx, y, rw, h, #members, rh)
            for i = scroll + 1, math.min(#members, scroll + visible) do
                local m = members[i]
                local buttons = { { label = L("acc_menu.social.profile"), fn = function() sp("spViewProfile", m.name) end } }
                if crew.isFounder and not m.isFounder then
                    buttons[2] = { label = L("acc_menu.social.kick"), fn = function() sp("spCrewKick", m.name) end, style = "danger" }
                end
                personRow("cm_", i, rx, y + (i - scroll - 1) * rh, rw, rh - S(4), m, buttons)
            end
            return
        end

        -- no crew: create one, or join one from the directory
        local lw = math.floor(w * 0.34)
        panelBox(x, y, lw, S(300))
        local cx, cw = x + S(24), lw - S(48)
        heading(L("acc_menu.social.create_crew"), cx, y + S(18), cw)
        text(L("acc_menu.social.crew_name"), cx, y + S(60), cw, S(20), C.dim, 0.85, FONT.rowB)
        local function create()
            sp("spCrewCreate", crewName:getText(), crewTag:getText(), 64, 156, 180)
        end
        field("view", "crew_name", cx, y + S(82), cw, S(42), crewName, "", create)
        text(L("acc_menu.social.crew_tag"), cx, y + S(136), cw, S(20), C.dim, 0.85, FONT.rowB)
        field("view", "crew_tag", cx, y + S(158), cw, S(42), crewTag, "", create)
        button("view", "crew_create", cx, y + S(220), S(200), S(42), L("acc_menu.social.create"), create)

        local rx, rw = x + lw + S(14), w - lw - S(14)
        local dir = s.crews or {}
        if #dir == 0 then
            panelBox(rx, y, rw, S(80))
            return text(L("acc_menu.social.no_crews"), rx + S(24), y, rw, S(80), C.dim, 1.05)
        end
        local rh = S(52)
        local scroll, visible = listArea("crew", rx, y, rw, h, #dir, rh)
        for i = scroll + 1, math.min(#dir, scroll + visible) do
            local c = dir[i]
            local ry = y + (i - scroll - 1) * rh
            row("view", "cd_" .. i, rx, ry, rw - S(150), rh - S(4), {})
            local col = c.color or { 255, 255, 255 }
            text("[" .. tostring(c.tag) .. "]", rx + S(16), ry, S(80), rh - S(4), tocolor(col[1] or 255, col[2] or 255, col[3] or 255, 255), 1.0, FONT.rowB)
            text(c.name, rx + S(100), ry, rw * 0.4, rh - S(4), C.white, 1.0, FONT.rowB)
            text(L("acc_menu.social.crew_count", { count = c.members or 0 }), rx + rw * 0.5, ry, rw * 0.2, rh - S(4), C.dim, 0.9)
            button("view", "cd_" .. i .. "_join", rx + rw - S(140), ry + S(6), S(130), rh - S(16), L("acc_menu.social.join"), function() sp("spCrewJoin", c.name) end)
        end
    end,
}

VIEWS.messages = {
    title = function() return L("acc_menu.social.messages") end,
    onOpen = function() msgField:setText("") end,
    onBack = function()
        -- first Backspace / Esc closes the open conversation
        if Social.conv then Social.conv = nil return true end
    end,
    draw = function(x, y, w, h)
        local convs = snap().conversations or {}
        local lw = math.floor(w * 0.32)
        panelBox(x, y, lw, h)
        if #convs == 0 then
            text(L("acc_menu.social.no_conversations"), x + S(18), y + S(10), lw - S(36), S(30), C.dim)
        end
        local rh = S(62)
        local visible = math.floor(h / rh)
        for i = 1, math.min(#convs, visible) do
            local c = convs[i]
            local ry = y + (i - 1) * rh
            local isOpen = Social.conv and Social.conv.kind == c.kind and Social.conv.with:lower() == tostring(c.with):lower()
            row("view", "cv_" .. i, x, ry, lw, rh - S(2), { activate = function() openThread(c.kind, c.with) end })
            if isOpen then dxDrawRectangle(x, ry, S(3), rh - S(2), C.white) end
            local title = c.kind == "crew" and ("[" .. tostring(c.crewTag or "") .. "] " .. tostring(c.with)) or tostring(dn(c.with))
            text(title, x + S(18), ry + S(8), lw - S(80), S(24), C.white, 1.0, FONT.rowB)
            text(L.resolve(c.last) or "", x + S(18), ry + S(32), lw - S(36), S(22), C.dim, 0.85)
            if (c.unread or 0) > 0 then chip(tostring(c.unread), x + lw - S(50), ry + S(10), C.money, tocolor(110, 220, 130, 40)) end
        end

        local rx, rw = x + lw + S(14), w - lw - S(14)
        panelBox(rx, y, rw, h)
        local conv = Social.conv
        if not conv then
            return text(L("acc_menu.social.pick_conversation"), rx + S(24), y + S(10), rw - S(48), S(40), C.dim)
        end
        text(conv.kind == "crew" and L("acc_menu.social.crew_chat", { name = conv.with }) or dn(conv.with), rx + S(20), y + S(10), rw - S(40), S(30), C.white, 1.15, FONT.head)

        local msgs = Social.thread or {}
        local top, bottom = y + S(50), y + h - S(70)
        local lineH = S(46)
        local visibleMsgs = math.max(1, math.floor((bottom - top) / lineH))
        local maxScroll = math.max(0, #msgs - visibleMsgs)
        Social.threadScroll = math.max(0, math.min(Social.threadScroll or maxScroll, maxScroll))
        Menu.wheel(rx, top, rw, bottom - top, function(d) Social.threadScroll = (Social.threadScroll or 0) + d end)
        for i = Social.threadScroll + 1, math.min(#msgs, Social.threadScroll + visibleMsgs) do
            local m = msgs[i]
            local my = top + (i - Social.threadScroll - 1) * lineH
            local bw = math.min(rw * 0.7, textW(m.text, 0.95) + S(28))
            local bx = m.mine and (rx + rw - S(20) - bw) or (rx + S(20))
            dxDrawRectangle(bx, my, bw, lineH - S(8), m.mine and tocolor(36, 86, 106, 255) or tocolor(35, 42, 51, 255))
            if conv.kind == "crew" and not m.mine then
                text(dn(m.from), bx + S(10), my + S(2), bw - S(20), S(16), C.dim, 0.75, FONT.rowB)
                text(m.text, bx + S(10), my + S(16), bw - S(20), lineH - S(26), C.text, 0.95)
            else
                text(m.text, bx + S(14), my, bw - S(28), lineH - S(8), C.text, 0.95)
            end
        end

        local function send()
            local t = msgField:getText()
            if t:gsub("%s", "") == "" then return end
            sp("spSendMessage", conv.kind, conv.with, t)
            msgField:setText("")
        end
        field("view", "msg_field", rx + S(20), y + h - S(58), rw - S(180), S(42), msgField, L("acc_menu.social.type_message"), send)
        button("view", "msg_send", rx + rw - S(150), y + h - S(58), S(130), S(42), L("acc_menu.social.send"), send)
    end,
}

VIEWS.find = {
    title = function() return L("acc_menu.social.find") end,
    onOpen = function() searchField:setText("") Social.search, Social.searchNote = {}, nil end,
    draw = function(x, y, w, h)
        local function search() sp("spSearch", searchField:getText()) end
        field("view", "find_field", x, y, w - S(170), S(46), searchField, L("acc_menu.social.search_placeholder"), search)
        button("view", "find_go", x + w - S(160), y, S(160), S(46), L("acc_menu.social.search"), search)
        local ly = y + S(62)
        if Social.searchNote then
            text(L.resolve(Social.searchNote), x, ly, w, S(28), C.dim)
            ly = ly + S(34)
        end
        local list = Social.search or {}
        local friends = {}
        for _, f in ipairs(snap().friends or {}) do friends[f.name:lower()] = true end
        local rh = S(52)
        local scroll, visible = listArea("find", x, ly, w, y + h - ly, #list, rh)
        for i = scroll + 1, math.min(#list, scroll + visible) do
            local p = list[i]
            local buttons = { { label = L("acc_menu.social.profile"), fn = function() sp("spViewProfile", p.name) end } }
            if not friends[p.name:lower()] and p.name:lower() ~= tostring(getElementData(localPlayer, "accName")):lower() then
                buttons[2] = { label = L("acc_menu.social.add_friend"), fn = function() sp("spFriendAdd", p.name) end, style = "primary" }
            end
            personRow("fd_", i, x, ly + (i - scroll - 1) * rh, w, rh - S(4), p, buttons)
        end
    end,
}

-- another player's profile (from a friend / member / search row)
VIEWS.player = {
    title = function(args) return tostring(args.name or "") end,
    draw = function(x, y, w, h)
        local p = Social.profile
        if not p then return end
        local pw = math.min(w, S(620))
        panelBox(x, y, pw, S(300))
        local cx, cw = x + S(28), pw - S(56)
        text(p.display or p.name, cx, y + S(20), cw, S(48), C.white, 1, FONT.big)
        chip(p.online and L("acc_menu.social.online_now") or L("acc_menu.social.offline"), cx, y + S(76),
            p.online and C.money or C.dim, p.online and tocolor(110, 220, 130, 40) or nil)
        local yy = y + S(116)
        local function line(label, value)
            text(label, cx, yy, cw, S(30), C.dim)
            text(value, cx, yy, cw, S(30), C.white, 1.0, FONT.rowB, "right")
            yy = yy + S(34)
        end
        line(L("acc_menu.stats.level"), tostring(p.level or "-"))
        line(L("acc_menu.stats.played"), tostring(p.playtime or "-"))
        line(L("acc_menu.social.crew"), p.crew and ("[" .. tostring(p.crewTag) .. "] " .. p.crew) or "-")
        if not p.isSelf then
            local bx = cx
            if not p.isFriend then
                button("view", "pl_add", bx, y + S(240), S(170), S(42), L("acc_menu.social.add_friend"), function() sp("spFriendAdd", p.name) end)
                bx = bx + S(182)
            end
            button("view", "pl_msg", bx, y + S(240), S(170), S(42), L("acc_menu.social.message"), function()
                openThread("dm", p.name)
                Menu.goto("social", "messages")
            end, "ghost")
        end
    end,
}
