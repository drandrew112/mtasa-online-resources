-- ACC - Area Control Centre training (radar, SACC_CTR = the whole CTA): an overflight, a head-on
-- conflict pair and an arrival handed to approach. Every other position is closed. Texts:
-- work_atc.trn.acc.*

TRN.modules.acc = {}

function TRN.modules.acc.onSpawn(H, role)
    if role ~= "cfb" then H.focus(role) end
end

function TRN.modules.acc.build(H)
    local S, cmd = H.S, H.cmd

    local function arrived(role)
        return function() return H.mine(role) or H.handedOff(role) end
    end
    local function did(role, ...)
        local actions = { ... }
        return function() return cmd(role, unpack(actions)) or H.handedOff(role) end
    end
    local function gone(role)
        return function() return H.handedOff(role) end
    end

    -- the conflict pair: one of them got a new level or heading
    local function separated()
        return cmd("cfa", "cfl", "hdg") or cmd("cfb", "cfl", "hdg") or H.handedOff("cfa") or H.handedOff("cfb")
    end

    -- they passed each other (the same rule as the server's pairPassed)
    local function passed()
        local a, b = H.ac("cfa"), H.ac("cfb")
        if not a or not b then return H.handedOff("cfa") or H.handedOff("cfb") end
        local h = math.rad(a.hdg or 0)
        local along = (b.x - a.x) * math.sin(h) + (b.y - a.y) * math.cos(h)
        return along < 0 and getDistanceBetweenPoints2D(a.x, a.y, b.x, b.y) > 600
    end

    local function levels()
        local p = H.base()
        local a = H.ac("cfa")
        p.level = a and a.alt and ("FL%03d"):format(math.floor(a.alt / 100 + 0.5)) or "?"
        return p
    end

    return {
        console = {
            { text = S("console_walk"), check = function() return H.loginOpen() or H.scopeVisible() end },
            { text = S("console_login"),
              rect = function()
                  local lg = H.scope().login
                  return lg and lg.rows and lg.rows[TRN.T.info.position] or nil
              end,
              note = function()
                  if not H.loginOpen() then return H.note("note_open_console") end
              end },
        },
        -- the airspace of radar (the scope itself is known from the SCOPE module)
        airspace = {
            { text = S("airspace_intro"), next = true, needScope = true },
            { text = S("airspace_sectors"), next = true, needScope = true, rect = H.scopeRect("tools"), leave = H.serverNext },
        },
        overflight = {
            { text = S("ovf_wait"), needScope = true, fast = true, rect = H.labelRect("ovf"), check = arrived("ovf") },
            { text = S("ovf_level"), needScope = true, rect = H.menuItem("ovf", "Cleared altitude"),
              enter = function() H.focus("ovf") end, check = did("ovf", "cfl") },
            { text = S("ovf_direct"), needScope = true, rect = H.menuItem("ovf", "Direct to"), check = did("ovf", "dct") },
            { text = S("ovf_leave"), needScope = true, fast = true, rect = H.labelRect("ovf"), check = gone("ovf"),
              leave = H.serverNext },
        },
        conflict = {
            { text = S("cf_spot", levels), needScope = true, rect = H.labelRect("cfa"),
              enter = function() H.focus("cfa") end, check = separated },
            { text = S("cf_watch"), needScope = true, fast = true, rect = H.labelRect("cfb"), check = passed,
              leave = H.serverNext },
        },
        inbound = {
            { text = S("inb_wait"), needScope = true, fast = true, rect = H.labelRect("inb"), check = arrived("inb") },
            { text = S("inb_descend"), needScope = true, rect = H.menuItem("inb", "Cleared altitude"),
              enter = function() H.focus("inb") end, check = did("inb", "cfl") },
            { text = S("inb_star"), needScope = true, rect = H.menuItem("inb", "Arrival procedure"),
              check = did("inb", "star") },
            { text = S("inb_leave"), needScope = true, fast = true, rect = H.labelRect("inb"), check = gone("inb"),
              leave = H.serverNext },
        },
        alerts = {
            { text = S("alerts_list"), next = true, needScope = true },
            { text = S("alerts_fines", H.payParams), next = true, needScope = true },
            { text = S("alerts_pay", H.payParams), next = true, needScope = true },
            { text = S("alerts_logout"), needScope = true, rect = H.scopeRect("logout") },
        },
    }
end
