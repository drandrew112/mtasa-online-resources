if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
--[[
    ui_phone / server/apps/invites.lua

    Pending lobby invites. Other resources push them in through the exports
    below; the jobmanager is expected to be the main producer.

      exports.ui_phone:phoneAddInvite(player, id, title, subtitle, cbRes, cbFn, cbDeclineFn)
        cbRes/cbFn (optional): on accept the phone calls
        call(getResourceFromName(cbRes), cbFn, player, id)
        -- e.g. v_jobmanager / jobmanagerAcceptInvite
        cbDeclineFn (optional): the same call on decline (v_jobmanager / jobmanagerDeclineInvite)
]]

local invites = {}   -- invites[player] = { { id, title, subtitle, cbRes, cbFn }, ... }

local function push(player)
    if not isElement(player) then return end
    local out = {}
    for _, inv in ipairs(invites[player] or {}) do
        out[#out + 1] = { id = inv.id, title = inv.title, subtitle = inv.subtitle }
    end
    PhoneServer.push(player, "invites:list", out)
end

--------------------------------------------------------------------------------
-- Public exports
--------------------------------------------------------------------------------

function phoneAddInvite(player, id, title, subtitle, cbRes, cbFn, cbDeclineFn)
    if not isElement(player) or getElementType(player) ~= "player" or id == nil then return false end
    -- nobody can invite a player who is in the server introduction (v_introduce)
    if getElementData(player, "intro.active") then return false end
    id = tostring(id)

    invites[player] = invites[player] or {}
    for _, inv in ipairs(invites[player]) do
        if inv.id == id then
            inv.title    = tostring(title or inv.title)
            inv.subtitle = tostring(subtitle or "")
            inv.cbRes, inv.cbFn, inv.cbDeclineFn = cbRes, cbFn, cbDeclineFn
            push(player)
            return true
        end
    end

    table.insert(invites[player], {
        id = id,
        title = tostring(title or L.msg("ui_phone.invites.lobby_invite")),
        subtitle = tostring(subtitle or ""),
        cbRes = cbRes, cbFn = cbFn, cbDeclineFn = cbDeclineFn,
    })
    push(player)
    return true
end

function phoneRemoveInvite(player, id)
    local list = invites[player]
    if not list or id == nil then return false end
    id = tostring(id)
    for i, inv in ipairs(list) do
        if inv.id == id then
            table.remove(list, i)
            push(player)
            return true
        end
    end
    return false
end

function phoneClearInvites(player)
    if invites[player] then
        invites[player] = nil
        push(player)
    end
    return true
end

function phoneHasInvite(player, id)
    for _, inv in ipairs(invites[player] or {}) do
        if inv.id == tostring(id) then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- Phone hooks
--------------------------------------------------------------------------------

PhoneServer.onPull(function(player) push(player) end)

PhoneServer.on("invites:accept", function(player, id)
    local list = invites[player]
    if not list or id == nil then return end
    id = tostring(id)

    for i, inv in ipairs(list) do
        if inv.id == id then
            table.remove(list, i)
            push(player)
            PhoneServer.close(player)

            local cbResource = inv.cbRes and inv.cbFn and getResourceFromName(inv.cbRes)
            if cbResource then
                -- NOTE: exports[res][fn](...) drops its first argument (it is
                -- built for the `:` method-call form), which would silently eat
                -- `player`. call() passes every argument through untouched.
                local ok, err = pcall(call, cbResource, inv.cbFn, player, inv.id)
                if not ok then
                    outputDebugString("[phone] invite callback failed: " .. tostring(err), 2)
                end
            end
            return
        end
    end
end)

PhoneServer.on("invites:decline", function(player, id)
    local inv
    for _, entry in ipairs(invites[player] or {}) do
        if entry.id == tostring(id) then inv = entry break end
    end
    phoneRemoveInvite(player, id)
    local cbResource = inv and inv.cbRes and inv.cbDeclineFn and getResourceFromName(inv.cbRes)
    if cbResource then
        local ok, err = pcall(call, cbResource, inv.cbDeclineFn, player, inv.id)
        if not ok then
            outputDebugString("[phone] invite decline callback failed: " .. tostring(err), 2)
        end
    end
end)

addEventHandler("onPlayerQuit", root, function()
    invites[source] = nil
end)

--------------------------------------------------------------------------------
-- Dev helper
--------------------------------------------------------------------------------

addCommandHandler("phonetestinvite", function(player)
    phoneAddInvite(player, "test-" .. getTickCount(), "Race lobby", "LS Airport  -  waiting for players")
    PhoneServer.toast(player, "Test invite added.")
end)
