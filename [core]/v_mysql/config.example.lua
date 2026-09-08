-- v_mysql :: configuration TEMPLATE
--
-- Copy this file to `config.lua` (same folder) and fill in your database
-- credentials. `config.lua` is git-ignored so the secrets never get committed.
--
-- Because this resource uses dbConnect() with mysql, the MTA server makes
-- config.lua unreadable to other resources and turns meta.xml read only
-- (see <database_credentials_protection> in mtaserver.conf).

-- Master switch. When false, v_mysql does NOT connect to any database:
--   * onPlayerLogin -> it answers "accountdata ready" immediately, so
--     v_accounts starts loading / spawning the player with no delay.
--   * updateAccountData() is a no-op.
-- Turn it off on servers that do not need the localhost <-> host sync.
MYSQL_ENABLE_SYNC = false

MYSQL_CONFIG = {
    host     = "",          -- e.g. "mysql8.example.eu"
    port     = 3306,
    database = "",          -- e.g. "s00000_myserver"
    username = "",
    password = "",
    charset  = "utf8mb4",
}

-- Extra verbose logging (every query / exec) into the server console.
MYSQL_DEBUG = false

-- How often to retry a failed connection, and how often to ping an idle one.
MYSQL_RECONNECT_INTERVAL = 15000
MYSQL_PING_INTERVAL      = 30000
