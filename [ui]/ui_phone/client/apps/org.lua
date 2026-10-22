if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
--[[
    ui_phone / client/apps/org.lua
    Organization app (biz_core temporary associates).

      root      your membership (+ Leave), invitations, and - for founders -
                your associates (Enter removes) and "Invite a player"
      invite    online players to invite (Enter sends the invitation)
      offer     one invitation: Accept / Decline
]]

local state = false   -- biz_core:getMembershipState(player)
local sub, offer = nil, nil

phoneOnServer("org:state", function(s)
    state = type(s) == "table" and s or false
    if sub == "offer" and offer then
        local still = false
        for _, inv in ipairs(state and state.invites or {}) do
            if inv.companyId == offer.companyId then still = true end
        end
        if not still then sub, offer = nil, nil end
    end
end)

local function list(t) return type(t) == "table" and t or {} end

PhoneApp.defer(function()
PhoneApp.register({
    id    = "org",
    name  = L("ui_phone.org.title"),
    order = 25,

    badge = function() return state and #list(state.invites) or 0 end,

    open  = function() sub, offer = nil, nil; phonePull() end,
    close = function() sub, offer = nil, nil end,

    headerTitle = function()
        if sub == "invite" then return L("ui_phone.org.invite_title") end
        if sub == "offer" and offer then return offer.name end
        return L("ui_phone.org.title")
    end,

    hint = function()
        if sub then return L("ui_phone.settings.enter_apply_backspace_back") end
        return L("ui_phone.myveh.enter_open")
    end,

    empty = L("ui_phone.org.empty"),

    items = function()
        local rows = {}
        if not state then return rows end

        if sub == "invite" then
            for _, c in ipairs(list(state.candidates)) do
                local right = c.invited and L("ui_phone.org.invited") or (c.busy and L("ui_phone.org.busy") or nil)
                rows[#rows + 1] = {
                    title = c.name, subtitle = L("ui_phone.org.distance", { m = c.distance }), right = right,
                    _invite = c.player,
                }
            end
            return rows
        end

        if sub == "offer" and offer then
            rows[#rows + 1] = { title = L("ui_phone.org.accept"), subtitle = L("ui_phone.org.accept_sub"), _accept = offer.companyId }
            rows[#rows + 1] = { title = L("ui_phone.org.decline"), _decline = offer.companyId }
            return rows
        end

        -- root
        if state.member then
            local m = state.member
            rows[#rows + 1] = {
                title = m.name, subtitle = L("ui_phone.org.member_sub", { founder = m.founder, share = math.floor((m.share or 0.8) * 100 + 0.5) }),
            }
            rows[#rows + 1] = { title = L("ui_phone.org.leave"), subtitle = L("ui_phone.org.leave_sub"), _leave = true }
        end
        for _, inv in ipairs(list(state.invites)) do
            rows[#rows + 1] = {
                title = L("ui_phone.org.invitation", { name = inv.name }),
                subtitle = L("ui_phone.org.invitation_sub", { founder = inv.founder, s = inv.expiresIn }),
                _offer = inv,
            }
        end
        if state.own then
            local own = state.own
            rows[#rows + 1] = {
                title = L("ui_phone.org.invite"), subtitle = L("ui_phone.org.slots", { count = #list(own.associates), max = state.max or 3 }),
                _open = "invite",
            }
            for _, a in ipairs(list(own.associates)) do
                rows[#rows + 1] = { title = a.name, subtitle = L("ui_phone.org.associate_sub"), right = L("ui_phone.org.remove"), _remove = a.player }
            end
        end
        return rows
    end,

    onSelect = function(_, row)
        if row._open then
            sub = row._open
            Phone.setSelected(1)
        elseif row._offer then
            sub, offer = "offer", row._offer
            Phone.setSelected(1)
        elseif row._invite then
            phoneRPC("org:invite", row._invite)
        elseif row._accept then
            phoneRPC("org:accept", row._accept)
            sub, offer = nil, nil
            Phone.setSelected(1)
        elseif row._decline then
            phoneRPC("org:decline", row._decline)
            sub, offer = nil, nil
            Phone.setSelected(1)
        elseif row._leave then
            phoneRPC("org:leave")
        elseif row._remove then
            if isElement(row._remove) then phoneRPC("org:remove", row._remove) end
        end
    end,

    key = function(_, key)
        if sub and key == "backspace" then
            sub, offer = nil, nil
            Phone.setSelected(1)
            PhoneSound.select()
            return true
        end
        return false
    end,
})
end)
