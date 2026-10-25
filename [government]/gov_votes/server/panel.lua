-- gov_votes / server/panel.lua
-- The Votes page of /gov, the /vote page actions and the registration with gov_core.

local A = GOV.A

function A.votes(p, args, reply)
    GOV.votes("all", function(list) reply({ list = list, maxOptions = GOV.VOTE_MAX_OPTIONS, maxHours = GOV.VOTE_MAX_HOURS }) end)
end

--- { title, description, options = {...}, hours }
function A.openVote(p, args, reply, actor)
    GOV.openVote(args, actor, function(ok, err)
        if not ok then return reply(false, err) end
        reply(true)
    end)
end

function A.closeVote(p, args, reply, actor)
    GOV.endVote(args.id, "closed", actor, function(ok, err) reply(ok or false, err) end)
end

function A.cancelVote(p, args, reply, actor)
    GOV.endVote(args.id, "cancelled", actor, function(ok, err) reply(ok or false, err) end)
end

-- /vote (any logged-in player)
function A.voteList(p, args, reply, actor)
    GOV.openVotesFor(actor, function(list)
        for _, v in ipairs(list) do v.createdBy = nil end
        reply({ list = list, now = GOV.now() })
    end)
end

function A.voteCast(p, args, reply, actor)
    GOV.castVote(actor, args.id, args.option, function(ok, err)
        if not ok then return reply(false, err) end
        reply(true)
    end)
end

GOV.module({
    perms = {
        { "votes.view",  "public", 0 },
        { "votes.open",  "public", 1 },
        { "votes.close", "public", 1 },
    },
    actions = {
        votes = "votes.view", openVote = "votes.open", closeVote = "votes.close", cancelVote = "votes.close",
        voteList = "public", voteCast = "public",
    },
    pages = {
        { id = "votes", category = "public", order = 10, script = "web/js/pages.js", need = "votes.view" },
    },
})
