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
    [0] = "Player",
    [1] = "Trial Mod",
    [2] = "Mod",
    [3] = "Admin",
    [4] = "SuperAdmin",
    [5] = "Dev",
    [6] = "Owner",
}

-- Minimum admin levels required by each command / panel action, in ONE place.
ADMIN.perms = {
    panel        = 1,   -- O key admin panel           (Trial Mod)
    adminCall    = 2,   -- /af, /adminannounce        (Mod)
    reports      = 1,   -- /reports                   (Trial Mod)
    teleport     = 1,   -- /goto, /gethere            (Trial Mod)
    vehicle      = 2,   -- /fixveh, /flipveh, /getout (Mod)
    heal         = 1,   -- /heal                      (Trial Mod)
    noclip       = 2,   -- /fly + N key               (Mod)
    jail         = 2,   -- /ajail, /ajailout          (Mod)
    mute         = 1,   -- /mute, /unmute             (Trial Mod)
    kick         = 3,   -- /kick                      (Admin)
    ban          = 3,   -- /ban, /unban (account)     (Admin)
    setLevel     = 4,   -- /setadminlevel             (SuperAdmin)
    money        = 4,   -- /money                     (SuperAdmin)
    listAccounts = 5,   -- /listacc                   (Dev)
}

-- Admin panel (O key). Data is never hidden: every admin who can open the
-- panel sees every field; only the ACTIONS are gated by ADMIN.perms.
ADMIN.panel = {
    key     = "o",
    refresh = 3000,     -- ms between player-list refreshes while the panel is open
    size      = 0.83,   -- whole panel size multiplier (on top of the ui_core screen scale)
    fontScale = 1.5,    -- text size relative to the layout (effective text: size * fontScale ~ 1.25x)
}

-- Command reference shown on the panel's "Commands" tab.
-- perm = key in ADMIN.perms (the level shown is read from there); false = everyone.
ADMIN.commands = {
    { cmd = "O key",                              perm = "panel",        desc = "Open / close the admin panel." },
    { cmd = "/reports",                           perm = "reports",      desc = "Opens the admin panel on the Reports tab: active cases, claim, chat, logs." },
    { cmd = "/goto <ID>",                         perm = "teleport",     desc = "Teleport to a player (interior / dimension too)." },
    { cmd = "/gethere <ID>",                      perm = "teleport",     desc = "Bring a player to you (with their vehicle)." },
    { cmd = "/heal <ID>",                         perm = "heal",         desc = "Restore a player's health and armour." },
    { cmd = "/mute <ID> <minutes> <reason>",      perm = "mute",         desc = "Chat mute. Survives a relog, expires on its own." },
    { cmd = "/unmute <ID>",                       perm = "mute",         desc = "Lift a chat mute early." },
    { cmd = "/af <message>",                      perm = "adminCall",    desc = "Admin announcement to the whole server (/adminannounce). Also on the Server tab." },
    { cmd = "/fixveh [ID]",                       perm = "vehicle",      desc = "Repair a vehicle (yours without an ID)." },
    { cmd = "/flipveh [ID]",                      perm = "vehicle",      desc = "Flip a vehicle back on its wheels." },
    { cmd = "/getout <ID>",                       perm = "vehicle",      desc = "Pull a player out of their vehicle." },
    { cmd = "/fly  or  N key",                     perm = "noclip",       desc = "NoClip on / off. /flyspd <0.1-20> sets the speed." },
    { cmd = "/ajail <ID> <minutes> <reason>",     perm = "jail",         desc = "Put a player in admin jail." },
    { cmd = "/ajailout <ID>",                     perm = "jail",         desc = "Release a player from admin jail." },
    { cmd = "/kick <ID> <reason>",                perm = "kick",         desc = "Kick a player from the server." },
    { cmd = "/ban <account> <reason>",            perm = "ban",          desc = "Account ban (v_accounts, never expires). Online player: serial too." },
    { cmd = "/unban <account>",                   perm = "ban",          desc = "Lift an account ban." },
    { cmd = "/setadminlevel <ID> <0-6>",          perm = "setLevel",     desc = "Set an admin level (only below your own)." },
    { cmd = "/money",                             perm = "money",        desc = "Test money (+€2000) for yourself." },
    { cmd = "/listacc",                           perm = "listAccounts", desc = "Write every account name to the server log." },
    { cmd = "/getid <name>",                      perm = false,          desc = "A player's ID from a name (fragment)." },
    { cmd = "/myid",                              perm = false,          desc = "Your own ID." },
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
}

-- Report limits.
ADMIN.report = {
    minLength = 3,      -- minimum characters in a report / message
    maxLength = 300,    -- maximum characters (truncated)
    maxHistory = 60,    -- messages kept per report
    logDir     = "report_logs/",  -- JSON logs of closed reports (index.json + one file each)
}
