--[[
    v_phone / server/apps/invites.lua

    Pending lobby invites. Other resources push them in through the exports
    below; the jobmanager is expected to be the main producer.

      exports.v_phone:phoneAddInvite(player, id, title, subtitle, cbRes, cbFn)
        cbRes/cbFn (optional): on accept the phone calls
        call(getResourceFromName(cbRes), cbFn, player, id)
        -- e.g. v_jobmanager / jobmanagerAcceptInvite
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

function phoneAddInvite(player, id, title, subtitle, cbRes, cbFn)
    if not isElement(player) or getElementType(player) ~= "player" or id == nil then return false end
    id = tostring(id)

    invites[player] = invites[player] or {}
    for _, inv in ipairs(invites[player]) do
        if inv.id == id then
            inv.title    = tostring(title or inv.title)
            inv.subtitle = tostring(subtitle or "")
            inv.cbRes, inv.cbFn = cbRes, cbFn
            push(player)
            return true
        end
    end

    table.insert(invites[player], {
        id = id,
        title = tostring(title or "Lobby invite"),
        subtitle = tostring(subtitle or ""),
        cbRes = cbRes, cbFn = cbFn,
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
    phoneRemoveInvite(player, id)
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
