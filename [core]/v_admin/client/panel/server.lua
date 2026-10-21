if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ============================================================
--  v_admin / client/panel/server.lua
--  Server page: admin announcement, unban by account name and a
--  quick server overview (players / admins online).
-- ============================================================

local S, F, C = AP.S, AP.F, AP.C

local ANNOUNCE_MAX = 200

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function sendAnnouncement()
    if not AP.can("adminCall") then return end
    local msg = trim(AP.fieldText("sv_announce"))
    if msg == "" then return AP.notify(L("v_admin.panel.write_announcement_first")) end
    AP.sendAction("announce", nil, msg)
    AP.setField("sv_announce", "")
end

local function sendUnban()
    if not AP.can("ban") then return end
    local acc = trim(AP.fieldText("sv_unban"))
    if acc == "" then return AP.notify(L("v_admin.panel.enter_account_name")) end
    AP.sendAction("unbanAccount", nil, acc)
    AP.setField("sv_unban", "")
end

local card = AP.card

local function drawAnnounce(x, y, w, h)
    local ix, iy, iw = card(x, y, w, h, L("v_admin.panel.admin_announcement"), "adminCall")
    local allowed = AP.can("adminCall")
    local lines = AP.wrap(L("v_admin.panel.sent_to_every_player_on_server"), iw, 0.9)
    for _, l in ipairs(lines) do
        AP.text(l, ix, iy, iw, S(26), C.dim, 0.9); iy = iy + S(26)
    end
    iy = iy + S(10)

    if allowed then
        AP.field("sv_announce", ix, iy, iw, S(48), { placeholder = L("v_admin.panel.announcement_text"), max = ANNOUNCE_MAX,
            onEnter = sendAnnouncement })
    else
        dxDrawRectangle(ix, iy, iw, S(48), C.btnOff)
        AP.text(L("v_admin.panel.you_need_level_for_announcements", { perm_level = AP.permLevel("adminCall") }), ix + S(10), iy, iw, S(48), C.off, 0.95)
    end
    iy = iy + S(58)

    local text = trim(AP.fieldText("sv_announce"))
    AP.text(("%d / %d"):format(utf8.len(AP.fieldText("sv_announce")) or 0, ANNOUNCE_MAX), ix, iy, iw, S(26), C.off, 0.8, "default", "right")
    AP.text(L("v_admin.panel.preview"), ix, iy, iw, S(26), C.dim, 0.9)
    iy = iy + S(30)
    dxDrawRectangle(ix, iy, iw, S(48), C.field)
    AP.text(L("v_admin.panel.announcement", { player = getPlayerName(localPlayer), text = (text ~= "" and text or "...") }),
        ix + S(12), iy, iw - S(24), S(48), C.text, 0.95, "default", "left", "center", true, false, true)
    iy = iy + S(60)

    AP.button(ix + iw - S(240), iy, S(240), S(50), L("v_admin.panel.send_announcement"), sendAnnouncement,
        (allowed and text ~= "") and "active" or "off")
end

local function drawUnban(x, y, w, h)
    local ix, iy, iw = card(x, y, w, h, L("v_admin.panel.unban_account"), "ban")
    local allowed = AP.can("ban")
    for _, l in ipairs(AP.wrap(L("v_admin.panel.lifts_v_accounts_ban_of_account"), iw, 0.9)) do
        AP.text(l, ix, iy, iw, S(26), C.dim, 0.9); iy = iy + S(26)
    end
    iy = iy + S(10)
    local bw = S(160)
    if allowed then
        AP.field("sv_unban", ix, iy, iw - bw - S(10), S(48), { placeholder = L("v_admin.panel.account_name"), max = 32, onEnter = sendUnban })
    else
        dxDrawRectangle(ix, iy, iw - bw - S(10), S(48), C.btnOff)
    end
    AP.button(ix + iw - bw, iy, bw, S(48), L("v_admin.panel.unban"), sendUnban,
        (allowed and trim(AP.fieldText("sv_unban")) ~= "") and "active" or "off")
end

local function drawOverview(x, y, w, h)
    local ix, iy, iw = card(x, y, w, h, L("v_admin.panel.server"))
    local t = getRealTime()
    local guests, muted, jailed = 0, 0, 0
    local admins = {}
    for _, p in ipairs(AP.players) do
        if not p.logged then guests = guests + 1 end
        if p.muted then muted = muted + 1 end
        if p.jailed then jailed = jailed + 1 end
        if p.adminLevel > 0 then admins[#admins + 1] = p end
    end
    table.sort(admins, function(a, b) return a.adminLevel > b.adminLevel end)

    local rows = {
        { L("v_admin.panel.time"), ("%04d.%02d.%02d  %02d:%02d"):format(t.year + 1900, t.month + 1, t.monthday, t.hour, t.minute) },
        { L("v_admin.panel.players_online"), L("v_admin.panel.not_logged_in", { players = #AP.players, guests = guests }) },
        { L("v_admin.panel.muted_jailed"), muted .. " / " .. jailed },
        { L("v_admin.panel.admins_online"), #admins },
    }
    for _, r in ipairs(rows) do
        AP.text(r[1], ix, iy, iw * 0.45, S(32), C.dim, 0.95)
        AP.text(tostring(r[2]), ix + iw * 0.45, iy, iw * 0.55, S(32), C.text, 0.95, "default-bold")
        iy = iy + S(32)
    end

    iy = iy + S(14)
    AP.text(L("v_admin.panel.admins_online_2"), ix, iy, iw, S(32), C.dim, 0.9, "default-bold")
    iy = iy + S(36)
    for _, p in ipairs(admins) do
        if iy + S(32) > y + h - S(10) then break end
        AP.text(L("v_admin.players.id_2", { name = p.name, id = p.id }), ix, iy, iw * 0.6, S(32), C.text, 0.95)
        AP.text(p.adminLevel .. "  " .. AP.rankName(p.adminLevel), ix + iw * 0.6, iy, iw * 0.4, S(32), C.head, 0.9, "default-bold", "right")
        iy = iy + S(32)
    end
end

AP.addPage({
    id = "server", category = "server", label = function() return L("v_admin.panel.server_2") end, perm = "panel", order = 100,
    draw = function(x, y, w, h)
        local gap = S(18)
        local leftW = (w - gap) * 0.6
        local rightW = w - leftW - gap
        drawAnnounce(x, y, leftW, S(470))
        drawUnban(x, y + S(470) + gap, leftW, S(230))
        drawOverview(x + leftW + gap, y, rightW, h)
    end,
})
