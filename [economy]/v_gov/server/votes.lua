-- v_gov / server/votes.lua
-- State votes: a minister (or admin) opens one with a title, a description, 2..VOTE_MAX_OPTIONS
-- options and a length in hours. Every logged-in player can vote once per vote with /vote (the
-- vote may be changed until it closes). Results are shown in /gov (Votes page) and on gov_web
-- once the vote is closed - while it is open only the number of voters is public.
--
-- gov_votes        one row per vote; status open | closed | cancelled
-- gov_vote_ballots one row per (vote, account)

local function int(v) return DB.int(v) end

addEvent("onGovVoteOpened", false)   -- (title)
addEvent("onGovVoteClosed", false)   -- (voteId); a vote that ran out may be announced by both instances

local function fromRow(r)
    local options = fromJSON(tostring(r.options or "")) or {}
    return { id = int(r.id), title = tostring(r.title), description = tostring(r.description or ""),
        options = type(options) == "table" and options or {}, createdBy = tostring(r.created_by or ""),
        createdAt = int(r.created_at), endsAt = int(r.ends_at), status = tostring(r.status), closedAt = int(r.closed_at),
        voters = int(r.voters) }
end

local COLS = "v.id, v.title, v.description, v.options, v.created_by, v.created_at, v.ends_at, v.status, v.closed_at, "
    .. "(SELECT COUNT(*) FROM gov_vote_ballots b WHERE b.vote_id = v.id) AS voters"

--- adds .results = { count per option index } (closed votes only, or every vote when `all`)
local function withResults(list, all, cb)
    local ids, byId = {}, {}
    for _, v in ipairs(list) do
        if all or v.status == "closed" then
            ids[#ids + 1] = v.id
            byId[v.id] = v
            v.results = {}
            for i = 1, #v.options do v.results[i] = 0 end
        end
    end
    if #ids == 0 then return cb(list) end
    local marks = {}
    for i = 1, #ids do marks[i] = "?" end
    DB.query(function(rows)
        for _, r in ipairs(rows or {}) do
            local v, opt = byId[int(r.vote_id)], int(r.option_idx)
            if v and v.results[opt] then v.results[opt] = int(r.n) end
        end
        cb(list)
    end, "SELECT vote_id, option_idx, COUNT(*) AS n FROM gov_vote_ballots WHERE vote_id IN (" .. table.concat(marks, ",")
        .. ") GROUP BY vote_id, option_idx", unpack(ids))
end

--- cb(list) newest first; filter = "open" | "recent" (open + closed in HISTORY_DAYS) | "all"
function GOV.votes(filter, cb)
    local sql = "SELECT " .. COLS .. " FROM gov_votes v"
    local args = {}
    if filter == "open" then
        sql = sql .. " WHERE v.status = 'open'"
    elseif filter == "recent" then
        sql = sql .. " WHERE v.status = 'open' OR (v.status = 'closed' AND v.closed_at >= ?)"
        args[1] = GOV.now() - GOV.HISTORY_DAYS * 86400
    end
    DB.query(function(rows)
        local list = {}
        for i, r in ipairs(rows or {}) do list[i] = fromRow(r) end
        withResults(list, false, cb)
    end, sql .. " ORDER BY v.id DESC LIMIT 100", unpack(args))
end

--- { title, description, options = { "...", ... }, hours } -> cb(true) | cb(false, err)
function GOV.openVote(args, actor, cb)
    local title = tostring(args.title or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local description = tostring(args.description or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local hours = math.floor(tonumber(args.hours) or 0)
    local options = {}
    for _, o in ipairs(type(args.options) == "table" and args.options or {}) do
        o = tostring(o or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if o ~= "" then options[#options + 1] = DB.clip(o, 80) end
    end
    if title == "" or #title > 120 then return cb(false, "bad_title") end
    if #description > 2000 then return cb(false, "bad_description") end
    if #options < 2 or #options > GOV.VOTE_MAX_OPTIONS then return cb(false, "bad_options") end
    if hours < 1 or hours > GOV.VOTE_MAX_HOURS then return cb(false, "bad_hours") end
    local now = GOV.now()
    DB.query(function(ok, err)
        if ok == false then
            outputDebugString("[v_gov] vote insert failed: " .. tostring(err), 1)
            return cb(false, "db")
        end
        GOV.log(actor, "vote.open", { title = DB.clip(title, 80), hours = hours })
        triggerEvent("onGovVoteOpened", resourceRoot, title)
        for _, p in ipairs(getElementsByType("player")) do
            if GOV.accountOf(p) then triggerClientEvent(p, "v_gov:voteOpened", resourceRoot, title) end
        end
        cb(true)
    end, "INSERT INTO gov_votes (title, description, options, created_by, created_at, ends_at, status) VALUES (?, ?, ?, ?, ?, ?, 'open')",
        title, description, toJSON(options, true), DB.clip(actor, 64), now, now + hours * 3600)
end

--- closes (status closed) or cancels (status cancelled) an open vote now
function GOV.endVote(id, status, actor, cb)
    id = math.floor(tonumber(id) or 0)
    DB.query(function(ok)
        if ok == false then return cb(false, "db") end
        GOV.log(actor, status == "cancelled" and "vote.cancel" or "vote.close", { id = id })
        if status == "closed" then triggerEvent("onGovVoteClosed", resourceRoot, id) end
        cb(true)
    end, "UPDATE gov_votes SET status = ?, closed_at = ?, ends_at = LEAST(ends_at, ?) WHERE id = ? AND status = 'open'",
        status == "cancelled" and "cancelled" or "closed", GOV.now(), GOV.now(), id)
end

--- a player's ballot: cb(true) | cb(false, err)
function GOV.castVote(account, id, option, cb)
    id, option = math.floor(tonumber(id) or 0), math.floor(tonumber(option) or 0)
    DB.query(function(rows)
        local r = rows and rows[1]
        if not r then return cb(false, "vote_unknown") end
        local v = fromRow(r)
        if v.status ~= "open" or v.endsAt <= GOV.now() then return cb(false, "vote_closed") end
        if option < 1 or option > #v.options then return cb(false, "bad_option") end
        DB.query(function(ok)
            if ok == false then return cb(false, "db") end
            cb(true)
        end, "INSERT INTO gov_vote_ballots (vote_id, account_name, option_idx, ts) VALUES (?, ?, ?, ?) "
            .. "ON DUPLICATE KEY UPDATE option_idx = VALUES(option_idx), ts = VALUES(ts)", id, account, option, GOV.now())
    end, "SELECT " .. COLS .. " FROM gov_votes v WHERE v.id = ?", id)
end

--- the open votes for /vote with the player's own choice: cb(list)
function GOV.openVotesFor(account, cb)
    GOV.votes("open", function(list)
        if #list == 0 then return cb(list) end
        DB.query(function(rows)
            local mine = {}
            for _, r in ipairs(rows or {}) do mine[int(r.vote_id)] = int(r.option_idx) end
            for _, v in ipairs(list) do v.mine = mine[v.id] or 0 end
            cb(list)
        end, "SELECT vote_id, option_idx FROM gov_vote_ballots WHERE account_name = ?", account)
    end)
end

-- votes past their end close by themselves (either instance)
local function closeExpired()
    if not DB.ready then return end
    DB.query(function(rows)
        for _, r in ipairs(rows or {}) do
            local id = int(r.id)
            DB.query(function(ok)
                if ok ~= false then triggerEvent("onGovVoteClosed", resourceRoot, id) end
            end, "UPDATE gov_votes SET status = 'closed', closed_at = ? WHERE id = ? AND status = 'open'", GOV.now(), id)
        end
    end, "SELECT id FROM gov_votes WHERE status = 'open' AND ends_at <= ?", GOV.now())
end

addEventHandler("v_gov:dbReady", resourceRoot, function()
    closeExpired()
    setTimer(closeExpired, GOV.VOTE_CHECK_MS, 0)
end)

addCommandHandler("vote", function(player)
    if not GOV.accountOf(player) then return end
    triggerClientEvent(player, "v_gov:openVote", resourceRoot)
end)
