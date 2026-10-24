-- gov_votes / client/vote.lua
-- /vote opens web/vote.html on gov_core's CEF relay (exports.gov_core:openGovPage); a new vote is
-- announced with a notification.

local function text(key)
    return L.has(key) and L.text(key) or key
end

addEvent("gov_votes:openVote", true)
addEventHandler("gov_votes:openVote", resourceRoot, function()
    pcall(function() exports.gov_core:openGovPage("gov_votes", "web/vote.html") end)
end)

addEvent("gov_votes:voteOpened", true)
addEventHandler("gov_votes:voteOpened", resourceRoot, function(title)
    pcall(function() exports.ui_core:addNotification(text("gov_votes.ui.vote_new"), tostring(title) .. "  -  /vote") end)
end)
