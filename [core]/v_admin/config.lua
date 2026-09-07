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

-- Minimum admin levels required by each command, in ONE place.
ADMIN.perms = {
    adminCall    = 2,   -- /af, /adminannounce        (Mod)
    reports      = 1,   -- /reports                   (Trial Mod)
    teleport     = 1,   -- /goto, /gethere            (Trial Mod)
    vehicle      = 2,   -- /fixveh, /flipveh, /getout (Mod)
    heal         = 1,   -- /heal                      (Trial Mod)
    noclip       = 2,   -- /fly + N key               (Mod)
    jail         = 2,   -- /ajail, /ajailout          (Mod)
    ban          = 2,   -- /ban, /unban               (Mod)
    mute         = 2,   -- /mute                      (Mod)
    setLevel     = 4,   -- /setadminlevel             (SuperAdmin)
    money        = 4,   -- /money                     (SuperAdmin)
    listAccounts = 5,   -- /listacc                   (Dev)
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
    reportAdminOpen = "v_admin:reportAdminOpen", -- server -> client: open the admin panel (+ list)
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
}

-- Report limits.
ADMIN.report = {
    minLength = 3,      -- minimum characters in a report / message
    maxLength = 300,    -- maximum characters (truncated)
    maxHistory = 60,    -- messages kept per report
    logDir     = "report_logs/",  -- JSON logs of closed reports (index.json + one file each)
}
