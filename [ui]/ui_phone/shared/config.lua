if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
L.config(function()  -- texts are refreshed once the player is loaded (v_locals L.config)
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
    { key = "graphite", name = L.text("ui_phone.config.graphite"),    color = { 18, 20, 26 } },
    { key = "ocean",    name = L.text("ui_phone.config.ocean"),       color = { 12, 38, 60 } },
    { key = "violet",   name = L.text("ui_phone.config.violet"),      color = { 34, 18, 52 } },
    { key = "forest",   name = L.text("ui_phone.config.forest"),      color = { 14, 40, 26 } },
    { key = "crimson",  name = L.text("ui_phone.config.crimson"),     color = { 52, 16, 22 } },
    { key = "sunset",   name = L.text("ui_phone.config.sunset"),      color = { 58, 32, 14 } },
    { key = "crew",     name = L.text("ui_phone.config.crew_colour"), color = false          },
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
            { key = "heal",  label = L.text("ui_phone.config.heal_200"),          cost = 200 },
            { key = "armor", label = L.text("ui_phone.config.refill_armour_500"), cost = 500 },
        },
    },
    {
        key = "markus", name = "Markus", photo = "img/contacts/markus.png",
        actions = {
            { key = "arena", label = L.text("ui_phone.config.join_arena_war") },
            { key = "job",   label = L.text("ui_phone.config.request_job")   },
        },
    },
    {
        -- Vehicle insurance. The action list is built per call from the caller's
        -- destroyed vehicles (server/apps/contacts.lua); each claim clears the
        -- v_ownveh isDestroyed flag for `claimCost`. With nothing to claim the
        -- call rings out and drops back to the contact list
        -- (client/apps/contacts.lua) - `dynamic` is the channel both sides use.
        key = "insurance", name = L.text("ui_phone.config.insurance"), photo = "img/contacts/insurance.png",
        dynamic   = "insurance",
        claimCost = 1000,
    },
    {
        -- Emergency Services (server/apps/emergency.lua). Only EMS works for now:
        -- the caller types a title + description and a med_erm task is created at
        -- the caller's position. Refused while no ambulance unit is signed in, or
        -- at an open med_scenemanager scene (an ambulance is already on its way).
        key = "emergency", name = L.text("ui_phone.config.emergency_services"), photo = "img/contacts/emergency.png",
        actions = {
            { key = "ems", label = L.text("ui_phone.config.ambulance_ems")      },
            { key = "pd",  label = L.text("ui_phone.config.police_pd")          },
            { key = "fd",  label = L.text("ui_phone.config.fire_department_fd") },
        },
        titleMax = 60,     -- characters of the ERM task title
        descMax  = 200,    -- characters of the ERM task description
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
end)
