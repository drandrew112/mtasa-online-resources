--[[
    ui_phone / shared/config.lua
    Values the client UI and the server logic both need.
]]

PHONE_CONFIG = {
    -- Key that opens / closes the phone.
    openKey = "b",

    -- Phone body geometry, in 1920x1080 reference pixels (scaled at runtime).
    width    = 340,
    height   = 690,
    radius   = 30,
    bezel    = 7,
    statusH  = 30,
    headerH  = 46,
    rowH     = 48,

    -- Ring time before a contact call opens its action menu.
    callRingMs = 2000,
}

--------------------------------------------------------------------------------
-- Wallpapers (Settings app). `color = false` -> use the player's crew colour.
--------------------------------------------------------------------------------

PHONE_CONFIG.wallpapers = {
    { key = "graphite", name = "Graphite",    color = { 18, 20, 26 } },
    { key = "ocean",    name = "Ocean",       color = { 12, 38, 60 } },
    { key = "violet",   name = "Violet",      color = { 34, 18, 52 } },
    { key = "forest",   name = "Forest",      color = { 14, 40, 26 } },
    { key = "crimson",  name = "Crimson",     color = { 52, 16, 22 } },
    { key = "sunset",   name = "Sunset",      color = { 58, 32, 14 } },
    { key = "crew",     name = "Crew colour", color = false          },
}
PHONE_CONFIG.defaultWallpaper = "graphite"

function PHONE_CONFIG.wallpaperByKey(key)
    for _, w in ipairs(PHONE_CONFIG.wallpapers) do
        if w.key == key then return w end
    end
    return PHONE_CONFIG.wallpapers[1]
end

--------------------------------------------------------------------------------
-- Contacts (Contacts app). The client draws the labels; the server owns the
-- effects and the prices.
--------------------------------------------------------------------------------

PHONE_CONFIG.contacts = {
    {
        key = "julia", name = "Julia", photo = "img/contacts/julia.png",
        actions = {
            { key = "heal",  label = "Heal  -  $200",          cost = 200 },
            { key = "armor", label = "Refill armour  -  $500", cost = 500 },
        },
    },
    {
        key = "markus", name = "Markus", photo = "img/contacts/markus.png",
        actions = {
            { key = "arena", label = "Join Arena War" },
            { key = "job",   label = "Request Job"   },
        },
    },
    {
        -- Vehicle insurance. The action list is built per call from the caller's
        -- destroyed vehicles (server/apps/contacts.lua); each claim clears the
        -- v_ownveh isDestroyed flag for `claimCost`. With nothing to claim the
        -- call rings out and drops back to the contact list
        -- (client/apps/contacts.lua) - `dynamic` is the channel both sides use.
        key = "insurance", name = "Insurance", photo = "img/contacts/insurance.png",
        dynamic   = "insurance",
        claimCost = 1000,
    },
}

function PHONE_CONFIG.contactByKey(key)
    for _, c in ipairs(PHONE_CONFIG.contacts) do
        if c.key == key then return c end
    end
    return nil
end

function PHONE_CONFIG.contactActionByKey(contactKey, actionKey)
    local c = PHONE_CONFIG.contactByKey(contactKey)
    if not c then return nil end
    for _, a in ipairs(c.actions or {}) do
        if a.key == actionKey then return a end
    end
    return nil
end
