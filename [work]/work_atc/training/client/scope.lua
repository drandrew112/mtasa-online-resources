-- SCOPE - the radar scope (SASF_TWR): a short tour of the scope, then the label and the command menu
-- of a departure at its stand (only shown), then Logout. The other modules take all this as known.
-- Texts: work_atc.trn.scope.*

TRN.modules.scope = {}

function TRN.modules.scope.onSpawn(H, role)
    H.focus(role, 2)
end

function TRN.modules.scope.build(H)
    local S = H.S

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
            -- the server moves on once the tutorial login is done
        },
        tour = {
            { text = S("tour_intro"), next = true, needScope = true },
            { text = S("tour_topbar"), next = true, needScope = true, rect = H.scopeRect("topBar") },
            { text = S("tour_tools"), next = true, needScope = true, rect = H.scopeRect("tools") },
            { text = S("tour_view"), next = true, needScope = true, rect = H.scopeRect("scaleBar") },
            { text = S("tour_list"), next = true, needScope = true, rect = H.scopeRect("list") },
            { text = S("tour_buttons"), next = true, needScope = true, rect = H.scopeRect("hide"), leave = H.serverNext },
        },
        menu = {
            { text = S("menu_wait"), needScope = true, fast = true, check = function() return H.ac("dep") ~= nil end },
            { text = S("menu_label"), next = true, needScope = true, rect = H.labelRect("dep"),
              enter = function() H.focus("dep", 2) end },
            { text = S("menu_open"), needScope = true, rect = H.labelRect("dep"),
              check = function() return H.menuOpenFor("dep") end },
            { text = S("menu_info"), next = true, needScope = true, rect = H.menuRect("dep"), leave = H.serverNext },
        },
        logout = {
            { text = S("logout"), needScope = true, rect = H.scopeRect("logout") },
            -- the server moves on at the logout (the receipt comes with it)
        },
    }
end
