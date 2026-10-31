-- police_system / modules/web/server/stats.lua
-- Public data for police_web (one export, cached STATS_CACHE s) and the gov_web summary: officers / units on duty
-- now, active pursuits and wanted players, daily / weekly counters (pol_stats), the penal code with the current
-- amounts, the active warrants (public, the decision: name, reasons, date; no position), the ranks.

local WB = POL.module("web", { cache = nil, at = 0, todayStats = {} })

local function refreshDaily(cb)
    POL.db.query(function(rows)
        local days, today, week, month = {}, {}, {}, {}
        local now = POL.now()
        local todayKey = POL.db.day(now)
        for _, r in ipairs(type(rows) == "table" and rows or {}) do
            local day, stat, n = tostring(r.day):sub(1, 10), r.stat, tonumber(r.amount) or 0
            days[day] = days[day] or {}
            days[day][stat] = n
            month[stat] = (month[stat] or 0) + n
            if day == todayKey then today[stat] = n end
        end
        for i = 0, 6 do
            local d = days[POL.db.day(now - i * 86400)]
            if d then for k, v in pairs(d) do week[k] = (week[k] or 0) + v end end
        end
        local daily = {}
        for i = 13, 0, -1 do
            local key = POL.db.day(now - i * 86400)
            local d = days[key] or {}
            daily[#daily + 1] = { day = key, arrests = d.arrests or 0, fines = d.fines or 0, pursuits = d.pursuits or 0,
                                  evaded = d.evaded or 0, fine_amount = d.fine_amount or 0 }
        end
        WB.todayStats = today
        cb(today, week, month, daily)
    end, "SELECT day, stat, amount FROM pol_stats WHERE day >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)")
end

function WB.today(key) return WB.todayStats[key] or 0 end

local function build(cb)
    refreshDaily(function(today, week, month, daily)
        POL.warrants.list("active", 1, function(rows)
            local warrants = {}
            for _, w in ipairs(rows) do
                local reasons = {}
                for _, id in ipairs(w.reasons) do
                    reasons[#reasons + 1] = L.forLang("en", id:find("%.") and btkKey(id) or wantedReasonKey(id))
                end
                warrants[#warrants + 1] = { id = w.id, name = w.name, kind = w.kind, reasons = reasons, at = w.at,
                                            description = w.description, lang = w.lang }
            end
            local officers = #POL.units.onDuty()
            local units = 0
            for _ in pairs(POL.units.list) do units = units + 1 end
            local pursuits, wanted = 0, 0
            for _ in pairs(POL.chase.list) do pursuits = pursuits + 1 end
            for _ in pairs(POL.wanted.list) do wanted = wanted + 1 end
            -- the website is English: names resolved here
            local ranks = {}
            for i = 1, 15 do ranks[i] = L.forLang("en", "police_system.rank." .. i) end
            local penal = POL.btk.list()
            for _, c in ipairs(penal) do
                c.name = L.forLang("en", btkCategoryKey(c.id))
                for _, it in ipairs(c.items) do it.name = L.forLang("en", btkKey(it.id)) end
            end
            cb({
                updated = POL.now(), officers = officers, units = units, pursuits = pursuits, wanted = wanted,
                today = today, week = week, month = month, daily = daily, warrants = warrants,
                penal = penal, ranks = ranks,
                evadeRate = (week.pursuits or 0) > 0 and math.floor((week.evaded or 0) * 100 / week.pursuits + 0.5) or 0,
            })
        end)
    end)
end

-- export (police_web): the cached data; the first call (or after STATS_CACHE) starts a refresh
function getPublicStats()
    local now = POL.now()
    if not WB.loading and now - WB.at >= POLICE.STATS_CACHE and POL.db.ready then
        WB.loading = true
        build(function(data)
            WB.cache, WB.at, WB.loading = data, POL.now(), false
        end)
    end
    return WB.cache or false
end

-- gov_web: the police summary (fine income 30 days)
function getPublicPolice()
    local d = getPublicStats()
    if not d then return false end
    return { officers = d.officers, finesMonth = d.month.fine_amount or 0, arrestsMonth = d.month.arrests or 0 }
end

POL.on("db.ready", function() getPublicStats() end)
