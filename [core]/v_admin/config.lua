if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
L.config(function()  -- texts are refreshed once the player is loaded (v_locals L.config)
-- ============================================================
--  v_admin / config.lua
--  Shared configuration, available on both sides.
-- ============================================================

ADMIN = {}

-- Displayed admin rank labels (admin level -> coloured text).
ADMIN.titles = {
    [1] = "#000000[#00BAFFTRIAL MOD#000000]#FF0000",
    [2] = "#000000[#00BAFFMOD#000000]#FF0000",
    [3] = "#000000[#BAFFBAADMIN#000000]#FF0000",
    [4] = "#000000[#fc1f17SUPERADMIN#000000]#FF0000",
    [5] = "#000000[#FFBB00DEV#000000]#FFFFFF",
    [6] = "#000000[#FF4400OWNER#000000]#FFFFFF",
}

-- 0 = Player
-- 1 = Trial Mod
-- 2 = Mod
-- 3 = Admin
-- 4 = SuperAdmin
-- 5 = Dev
-- 6 = Owner

ADMIN.maxLevel = 6

-- Plain rank names (admin panel, no colours / brackets).
ADMIN.rankNames = {
    [0] = L.text("v_admin.config.player"),
    [1] = L.text("v_admin.config.trial_mod"),
    [2] = L.text("v_admin.config.mod"),
    [3] = L.text("v_admin.config.admin"),
    [4] = L.text("v_admin.config.superadmin"),
    [5] = L.text("v_admin.config.dev"),
    [6] = L.text("v_admin.config.owner"),
}

-- Minimum admin levels required by each command / panel action, in ONE place.
ADMIN.perms = {
    panel        = 1,   -- O key admin panel           (Trial Mod)
    adminCall    = 2,   -- /af, /adminannounce        (Mod)
    reports      = 1,   -- /reports                   (Trial Mod)
    teleport     = 1,   -- /goto, /gethere            (Trial Mod)
    vehicle      = 2,   -- /fixveh, /flipveh, /getout (Mod)
    heal         = 1,   -- /heal                      (Trial Mod)
    skin         = 2,   -- /setskin                   (Mod)
    noclip       = 2,   -- /fly + N key               (Mod)
    spectate     = 1,   -- /spec, /specoff, Online players page (Trial Mod)
    jail         = 2,   -- /ajail, /ajailout          (Mod)
    mute         = 1,   -- /mute, /unmute             (Trial Mod)
    kick         = 3,   -- /kick                      (Admin)
    ban          = 3,   -- /ban, /unban (account)     (Admin)
    setLevel     = 4,   -- /setadminlevel             (SuperAdmin)
    money        = 4,   -- /money                     (SuperAdmin)
    listAccounts = 5,   -- /listacc                   (Dev)

    -- admin panel pages (v_admin 3.0)
    accounts     = 1,   -- Accounts page: list + details (Trial Mod)
    fullEmail    = 5,   -- unmasked e-mail addresses   (Dev)
    accountEdit  = 4,   -- money / level / XP / work level of an account, online or offline (SuperAdmin)
    vehicles     = 4,   -- give / delete / restore an owned vehicle (SuperAdmin)
    achievements = 4,   -- give / reset achievements   (SuperAdmin)
    notes        = 1,   -- admin notes on an account   (Trial Mod)
    passwordReset = 3,  -- mail a password reset code to the account's own e-mail (Admin)
    email        = 5,   -- set / remove the e-mail address of an account (Dev)
    adminLog     = 1,   -- Admin log page              (Trial Mod)
    weekly       = 4,   -- Weekly page, /weekly        (SuperAdmin)
    news         = 5,   -- News page, /news            (Dev)
    mail         = 5,   -- Mail page, /mail            (Dev)
    resources    = 5,   -- Resources page             (Dev)
}

-- Admin panel (O key). Data is never hidden: every admin who can open the
-- panel sees every field; only the ACTIONS are gated by ADMIN.perms.
-- (Exception: e-mail addresses are masked below ADMIN.perms.fullEmail.)
ADMIN.panel = {
    key     = "o",
    refresh = 3000,     -- ms between player-list refreshes while the panel is open
    fontScale = 1.5,    -- text size relative to the layout (effective text: size * fontScale ~ 1.25x)
    sideWidth = 300,    -- left menu width (1080p pixels, scaled)
}

-- Left menu categories, top to bottom. Pages name their category (AP.addPage).
ADMIN.categories = {
    { id = "overview", label = L.text("v_admin.page.cat_overview") },
    { id = "players",  label = L.text("v_admin.page.cat_players") },
    { id = "server",   label = L.text("v_admin.page.cat_server") },
    { id = "content",  label = L.text("v_admin.page.cat_content") },
    { id = "help",     label = L.text("v_admin.page.cat_help") },
}

-- Commands of other resources that now open a page of this panel
-- (the resources' own panels were removed in v_admin 3.0).
ADMIN.pageCommands = {
    weekly = "weekly",
    news   = "news",
    mail   = "mail",
}

-- Accounts page.
ADMIN.accounts = {
    pageSize  = 50,     -- rows per page
    cacheTime = 30,     -- s: the account list is re-read from MySQL at most this often
    notesMax  = 300,    -- characters of one admin note
    notesKey  = "admin_notes", -- accData key (JSON list of { t, admin, text })
    exportMax = 5000,   -- rows of one CSV export
    filtersKey = "admin_filters", -- accData key of the ADMIN's account: saved filters (JSON list of { name, filter })
}

-- Admin log page (MySQL `admin_log`).
ADMIN.log = {
    table    = "admin_log",
    pageSize = 60,
}

-- Players online on every server instance (MySQL `online_players`, server/instance.lua).
ADMIN.instances = {
    table      = "online_players",
    heartbeat  = 30,    -- s: this instance refreshes its rows + re-reads the others this often
    staleAfter = 120,   -- s: rows of an instance not refreshed for this long are ignored (crashed server)
}

-- Command reference shown on the panel's "Commands" tab.
-- perm = key in ADMIN.perms (the level shown is read from there); false = everyone.
ADMIN.commands = {
    { cmd = "O key",                              perm = "panel",        desc = L.text("v_admin.config.open_close_admin_panel") },
    { cmd = "/reports",                           perm = "reports",      desc = L.text("v_admin.config.opens_admin_panel_on_reports_tab") },
    { cmd = "/weekly",                            perm = "weekly",       desc = L.text("v_admin.config.opens_weekly_page") },
    { cmd = "/news",                              perm = "news",         desc = L.text("v_admin.config.opens_news_page") },
    { cmd = "/mail",                              perm = "mail",         desc = L.text("v_admin.config.opens_mail_page") },
    { cmd = "/goto <ID>",                         perm = "teleport",     desc = L.text("v_admin.config.teleport_to_player_interior_dimension_too") },
    { cmd = "/gethere <ID>",                      perm = "teleport",     desc = L.text("v_admin.config.bring_player_to_you_with_their") },
    { cmd = "/spec <ID>",                         perm = "spectate",     desc = L.text("v_admin.config.spectate_player") },
    { cmd = "/specoff",                           perm = "spectate",     desc = L.text("v_admin.config.stop_spectating") },
    { cmd = "/heal <ID>",                         perm = "heal",         desc = L.text("v_admin.config.restore_player_s_health_and_armour") },
    { cmd = "/setskin <ID> <skin>",               perm = "skin",         desc = L.text("v_admin.config.change_player_s_skin") },
    { cmd = "/mute <ID> <minutes> <reason>",      perm = "mute",         desc = L.text("v_admin.config.chat_mute_survives_relog_expires_on") },
    { cmd = "/unmute <ID>",                       perm = "mute",         desc = L.text("v_admin.config.lift_chat_mute_early") },
    { cmd = "/af <message>",                      perm = "adminCall",    desc = L.text("v_admin.config.admin_announcement_to_whole_server_adminannounce") },
    { cmd = "/fixveh [ID]",                       perm = "vehicle",      desc = L.text("v_admin.config.repair_vehicle_yours_without_id") },
    { cmd = "/flipveh [ID]",                      perm = "vehicle",      desc = L.text("v_admin.config.flip_vehicle_back_on_its_wheels") },
    { cmd = "/getout <ID>",                       perm = "vehicle",      desc = L.text("v_admin.config.pull_player_out_of_their_vehicle") },
    { cmd = "/fly  or  N key",                     perm = "noclip",       desc = L.text("v_admin.config.noclip_on_off_flyspd_0_1") },
    { cmd = "/ajail <ID> <minutes> <reason>",     perm = "jail",         desc = L.text("v_admin.config.put_player_in_admin_jail") },
    { cmd = "/ajailout <ID>",                     perm = "jail",         desc = L.text("v_admin.config.release_player_from_admin_jail") },
    { cmd = "/kick <ID> <reason>",                perm = "kick",         desc = L.text("v_admin.config.kick_player_from_server") },
    { cmd = "/ban <account> <reason>",            perm = "ban",          desc = L.text("v_admin.config.account_ban_v_accounts_never_expires") },
    { cmd = "/unban <account>",                   perm = "ban",          desc = L.text("v_admin.config.lift_account_ban") },
    { cmd = "/setadminlevel <ID> <0-6>",          perm = "setLevel",     desc = L.text("v_admin.config.set_admin_level_only_below_your") },
    { cmd = "/money",                             perm = "money",        desc = L.text("v_admin.config.test_money_2000_for_yourself") },
    { cmd = "/listacc",                           perm = "listAccounts", desc = L.text("v_admin.config.write_every_account_name_to_server") },
    { cmd = "/getid <name>",                      perm = false,          desc = L.text("v_admin.config.player_s_id_from_name_fragment") },
    { cmd = "/myid",                              perm = false,          desc = L.text("v_admin.config.your_own_id") },
}

-- Admin jail location (interior 6).
ADMIN.jail = {
    interior  = 6,
    inside    = { x = 264.4140625,    y = 77.5673828125,   z = 1001.0390625 },
    release   = { x = 1540.279296875, y = -1675.322265625, z = 13.550283432007 },
    colOrigin = { x = 262, y = 75, z = 1000 },
    colSize   = 5,
}

-- Event names (server <-> client).
ADMIN.events = {
    alert         = "v_admin:alert",          -- server -> client: ui_core Alert
    toggleNoclip  = "v_admin:toggleNoclip",    -- server -> client: /fly noclip on/off

    -- Report system
    reportNotify  = "v_admin:reportNotify",    -- server -> client: sound ping (new message / report)

    reportOpen    = "v_admin:reportOpen",      -- server -> client: open the player panel (+ state / false)
    reportSync    = "v_admin:reportSync",      -- server -> client: state of the player's own report (table / false)
    reportAdminList = "v_admin:reportAdminList", -- server -> client: refresh the admin list

    reportCreate  = "v_admin:reportCreate",    -- client -> server: new report (text)
    reportMsg     = "v_admin:reportMsg",       -- client -> server: chat message (id, text)
    reportClaim   = "v_admin:reportClaim",     -- client -> server: claim a report (id)
    reportClose   = "v_admin:reportClose",     -- client -> server: close a report (id)
    reportTP      = "v_admin:reportTP",        -- client -> server: teleport to the player (id)

    reportWantActive = "v_admin:reportWantActive", -- client -> server: resend the active list
    reportLogList = "v_admin:reportLogList",   -- request (C->S) / result (S->C): saved log list
    reportLogOpen = "v_admin:reportLogOpen",   -- client -> server: request one log file (file name)
    reportLogData = "v_admin:reportLogData",   -- server -> client: contents of one log

    -- Admin panel (O key)
    panelRequest  = "v_admin:panelRequest",    -- client -> server: open / refresh the panel
    panelData     = "v_admin:panelData",       -- server -> client: (players, myLevel, isRefresh, tab) / false = denied
    panelAction   = "v_admin:panelAction",     -- client -> server: (action, targetId, args...)

    -- Admin panel pages (server/pages.lua)
    pageCall      = "v_admin:pageCall",        -- client -> server: (requestId, page, action, args)
    pageReply     = "v_admin:pageReply",       -- server -> client: (requestId, result | false, message | false)
}

-- Report limits.
ADMIN.report = {
    minLength = 3,      -- minimum characters in a report / message
    maxLength = 300,    -- maximum characters (truncated)
    maxHistory = 60,    -- messages kept per report
    logDir     = "report_logs/",  -- JSON logs of closed reports (index.json + one file each)
}
end)
